#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string[]]$Roots,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'reports'),
    [switch]$IncludeNetworkDrives,
    [string[]]$ExcludePaths = @(),
    [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
$started = Get-Date
$clock = [Diagnostics.Stopwatch]::StartNew()
$pathComparer = [StringComparer]::OrdinalIgnoreCase
$networkCache = [Collections.Generic.Dictionary[string,bool]]::new($pathComparer)
$exclusions = @($ExcludePaths | ForEach-Object { [IO.Path]::TrimEndingDirectorySeparator($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($_)) })
$excludedDirectories = 0
$visited = [Collections.Generic.HashSet[string]]::new($pathComparer)
$foundPaths = [Collections.Generic.HashSet[string]]::new($pathComparer)
$pending = [Collections.Generic.Stack[string]]::new()
$results = [Collections.Generic.List[object]]::new()
$issues = [Collections.Generic.List[object]]::new()
$links = [Collections.Generic.List[object]]::new()
$scanRoots = [Collections.Generic.List[string]]::new()
$skippedDrives = [Collections.Generic.List[object]]::new()
$options = [IO.EnumerationOptions]::new()
$options.RecurseSubdirectories = $false
$options.IgnoreInaccessible = $false
$options.AttributesToSkip = [IO.FileAttributes]0
$options.ReturnSpecialDirectories = $false
$executableName = '^(?:python(?:w)?(?:[0-9]+(?:\.[0-9]+)*[dt]?)?(?:_d)?|pypy(?:w)?(?:[0-9]+(?:\.[0-9]+)*)?)\.exe$'

function Add-ScanIssue([string]$Path, [string]$Operation, [Exception]$Exception) {
    $issues.Add([pscustomobject]@{ Path=$Path; Operation=$Operation; Reason=$Exception.Message })
}
function Test-NetworkPath([string]$Path) {
    if ($Path.StartsWith('\\')) { return $true }
    $driveRoot = [IO.Path]::GetPathRoot($Path)
    if ($networkCache.ContainsKey($driveRoot)) { return $networkCache[$driveRoot] }
    try {
        $networkCache[$driveRoot] = ([IO.DriveInfo]::new($driveRoot).DriveType -eq [IO.DriveType]::Network)
        return $networkCache[$driveRoot]
    }
    catch { return $false }
}
function Test-ExcludedPath([string]$Path) {
    foreach ($base in $exclusions) {
        if ($Path.Equals($base,[StringComparison]::OrdinalIgnoreCase) -or $Path.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

if (-not $Roots -or $Roots.Count -eq 0) {
    $Roots = @(
        foreach ($drive in [IO.DriveInfo]::GetDrives()) {
            if (-not $drive.IsReady) {
                $skippedDrives.Add([pscustomobject]@{ Path=$drive.Name; Reason='Drive not ready or no media' })
                continue
            }
            if ($drive.DriveType -in @([IO.DriveType]::Fixed, [IO.DriveType]::Removable) -or
                ($IncludeNetworkDrives -and $drive.DriveType -eq [IO.DriveType]::Network)) {
                $drive.RootDirectory.FullName
            } else {
                $skippedDrives.Add([pscustomobject]@{ Path=$drive.Name; Reason='Drive type excluded from local scan' })
            }
        }
    )
}
foreach ($root in $Roots) {
    $absolute = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($root)
    if (-not [IO.Directory]::Exists($absolute)) { throw "Directory or drive not found: $absolute" }
    if ((Test-NetworkPath $absolute) -and -not $IncludeNetworkDrives) {
        throw "Network path $absolute requires -IncludeNetworkDrives."
    }
    $scanRoots.Add($absolute)
    $pending.Push($absolute)
}
if ($scanRoots.Count -eq 0) { throw 'No accessible drives to scan.' }
$reportDirectory = Join-Path ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)) ($started.ToString('yyyyMMdd-HHmmss')+'-'+$PID)
$null = [IO.Directory]::CreateDirectory($reportDirectory)
$journalPath = Join-Path $reportDirectory 'python-executables.jsonl'
$journal = [IO.StreamWriter]::new($journalPath, $false, [Text.UTF8Encoding]::new($false))
$journal.AutoFlush = $true
$directories = 0
$lastProgress = -2.0
$completed = $false
Write-Host "Scanning executable paths: $($scanRoots -join ', ')" -ForegroundColor Cyan
Write-Host 'Hidden folders, caches, applications and virtual environments are included.'
Write-Host 'Directory links are resolved and visited once to avoid cycles.'
Write-Host "Reports: $reportDirectory"
try {
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        try {
            if (Test-ExcludedPath $directory) { $excludedDirectories++; continue }
            $directoryInfo = [IO.DirectoryInfo]::new($directory)
            if (($directoryInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $target = $directoryInfo.ResolveLinkTarget($true)
                if ($null -eq $target) { throw [IO.IOException]::new('Unresolved directory link target') }
                $links.Add([pscustomobject]@{ Path=$directory; Target=$target.FullName })
                $directory = $target.FullName
            }
            if (Test-ExcludedPath $directory) { $excludedDirectories++; continue }
            if ((Test-NetworkPath $directory) -and -not $IncludeNetworkDrives) {
                $issues.Add([pscustomobject]@{ Path=$directory; Operation='directory-link'; Reason='Network target excluded from local scan' })
                continue
            }
            if (-not $visited.Add([IO.Path]::TrimEndingDirectorySeparator($directory))) { continue }
            $directories++
            if ($clock.Elapsed.TotalSeconds - $lastProgress -ge 1) {
                $lastProgress = $clock.Elapsed.TotalSeconds
                Write-Progress -Activity 'Python Runtime Auditor' -Status "$directories directories · $($results.Count) executable paths · $([int]$clock.Elapsed.TotalSeconds) s" -CurrentOperation $directory
                [pscustomobject]@{Directories=$directories;Executables=$results.Count;CurrentDirectory=$directory;ElapsedSeconds=[int]$clock.Elapsed.TotalSeconds} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $reportDirectory 'scan-progress.json') -Encoding utf8
            }
            foreach ($filter in @('python*.exe','pypy*.exe')) {
                try {
                    foreach ($file in [IO.Directory]::EnumerateFiles($directory, $filter, $options)) {
                        if ([IO.Path]::GetFileName($file) -notmatch $executableName -or -not $foundPaths.Add($file)) { continue }
                        try {
                            $info = [IO.FileInfo]::new($file)
                            $targetPath = $file
                            $isAlias = ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
                            if ($isAlias) {
                                try { $resolved = $info.ResolveLinkTarget($true); if ($resolved) { $targetPath=$resolved.FullName } }
                                catch { Add-ScanIssue $file 'file-link' $_.Exception }
                            }
                            $version = $null
                            try { $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($file).FileVersion }
                            catch { Add-ScanIssue $file 'file-version' $_.Exception }
                            $kind = 'Name-matched executable candidate'
                            if ($file -match '[\\/](?:\.venv|venv|venvs|envs?)[\\/]') { $kind='Virtual environment candidate' }
                            if ($isAlias) { $kind='File alias or link' }
                            $row = [pscustomobject][ordered]@{
                                Path=$file; ResolvedPath=$targetPath; FileVersion=$version; Kind=$kind
                                IsAlias=$isAlias; Bytes=$info.Length
                                CreationTimeUtc=$info.CreationTimeUtc.ToString('o'); LastWriteTimeUtc=$info.LastWriteTimeUtc.ToString('o')
                            }
                            $results.Add($row)
                            $journal.WriteLine(($row | ConvertTo-Json -Compress))
                            Write-Host "[$($results.Count)] $file" -ForegroundColor Green
                        } catch { Add-ScanIssue $file 'file-metadata' $_.Exception }
                    }
                } catch { Add-ScanIssue $directory 'enumerate-executables' $_.Exception }
            }
            try {
                foreach ($child in [IO.Directory]::EnumerateDirectories($directory,'*',$options)) { $pending.Push($child) }
            } catch { Add-ScanIssue $directory 'enumerate-directories' $_.Exception }
        } catch { Add-ScanIssue $directory 'directory-access' $_.Exception }
    }
    $completed = $true
} finally {
    $journal.Dispose()
    Write-Progress -Activity 'Python Runtime Auditor' -Completed
    $sorted = @($results | Sort-Object Path)
    $csvPath = Join-Path $reportDirectory 'python-executables.csv'
    $jsonPath = Join-Path $reportDirectory 'python-executables.json'
    if ($sorted.Count -gt 0) { $sorted | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Delimiter ';' -Encoding utf8BOM }
    else { 'Path;ResolvedPath;FileVersion;Kind;IsAlias;Bytes;CreationTimeUtc;LastWriteTimeUtc' | Set-Content -LiteralPath $csvPath -Encoding utf8BOM }
    ConvertTo-Json -InputObject $sorted -Depth 5 | Set-Content -LiteralPath $jsonPath -Encoding utf8
    ConvertTo-Json -InputObject $issues.ToArray() -Depth 5 | Set-Content -LiteralPath (Join-Path $reportDirectory 'scan-issues.json') -Encoding utf8
    ConvertTo-Json -InputObject $links.ToArray() -Depth 5 | Set-Content -LiteralPath (Join-Path $reportDirectory 'directory-links.json') -Encoding utf8
    $summary = [pscustomobject][ordered]@{
        SchemaVersion=1; ReportDirectory=$reportDirectory
        StartedAt=$started.ToString('o'); FinishedAt=(Get-Date).ToString('o'); Completed=$completed
        Roots=$scanRoots.ToArray(); DirectoriesVisited=$directories; ExecutablesFound=$results.Count
        DirectoryLinks=$links.Count; Issues=$issues.Count; SkippedDrives=$skippedDrives.ToArray()
        ElapsedSeconds=[math]::Round($clock.Elapsed.TotalSeconds,1)
        ExcludePaths=$exclusions;ExcludedDirectories=$excludedDirectories
        Scope='Accessible Windows python*.exe/pypy*.exe paths; Linux/WSL interpreters are not included'
        Versions='File metadata only; discovered interpreters are never executed'
    }
    $summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reportDirectory 'scan-summary.json') -Encoding utf8
    Write-Host "`n$($results.Count) executable paths · $directories directories · $($issues.Count) access or metadata issues." -ForegroundColor Cyan
    Write-Host "CSV: $csvPath"
    Write-Host "JSON: $jsonPath"
    if (-not $completed) { Write-Warning 'Scan interrupted: results found so far have been retained.' }
    if ($PassThru) { Write-Output $summary }
}
