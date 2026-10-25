#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ReportDirectory,
    [string[]]$UserSiteRoots,
    [switch]$SkipUserSitePackages,
    [switch]$PassThru
)
$ErrorActionPreference='Stop'
$report=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportDirectory)
$runtimes=@(Get-Content -LiteralPath (Join-Path $report 'runtime-folders.json') -Raw | ConvertFrom-Json)
$packages=[Collections.Generic.List[object]]::new()
$locations=[Collections.Generic.List[object]]::new()
$issues=[Collections.Generic.List[object]]::new()
$environments=[Collections.Generic.List[object]]::new()
$watch=[Diagnostics.Stopwatch]::StartNew()
function Add-PackageIssue([string]$Path,[string]$Operation,[string]$Reason) {
    $issues.Add([pscustomobject]@{Path=$Path;Operation=$Operation;Reason=$Reason})
}
function Read-PackageText([string]$Path,[long]$Limit=4194304) {
    $item=Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Linked or non-file metadata is not read' }
    # Bound both allocation and I/O; RECORD paths are never opened or resolved.
    $stream=[IO.File]::Open($item.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        if ($stream.Length -gt $Limit) { throw "Metadata exceeds the $Limit byte reading limit" }
        $buffer=[byte[]]::new([int]$stream.Length)
        $read=0
        while ($read -lt $buffer.Length) {
            $count=$stream.Read($buffer,$read,$buffer.Length-$read)
            if ($count -eq 0) { break }; $read+=$count
        }
        return [Text.Encoding]::UTF8.GetString($buffer,0,$read).TrimStart([char]0xfeff)
    } finally { $stream.Dispose() }
}
function Get-CoreHeaders([string]$Content) {
    $headers=@{}; $key=$null
    foreach ($line in ($Content -split '\r?\n')) {
        if ($line -eq '') { break }
        if ($line -match '^\s' -and $key) { $values=$headers[$key];$values[$values.Count-1]+=' '+$line.Trim();continue }
        if ($line -match '^([A-Za-z0-9-]+):\s*(.*)$') {
            $key=$Matches[1]
            if (-not $headers.ContainsKey($key)) { $headers[$key]=[Collections.Generic.List[string]]::new() }
            $headers[$key].Add($Matches[2].Trim())
        } else { $key=$null }
    }
    return $headers
}
function Get-RecordedSize([string]$MetadataDirectory) {
    $record=Join-Path $MetadataDirectory 'RECORD'
    $total=[long]0;$known=0;$count=0;$bad=$false
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    try {
        if (-not (Test-Path -LiteralPath $record)) { return [pscustomobject]@{Bytes=$null;Known=0;Count=0;Coverage='unavailable'} }
        $content=Read-PackageText $record 33554432
        foreach ($entry in @($content | ConvertFrom-Csv -Header 'Path','Hash','Size','Extra')) {
            if (-not $entry.Path -or $null -ne $entry.Extra) { $bad=$true;continue }
            if (-not $seen.Add($entry.Path.Replace('\','/'))) { $bad=$true;continue }
            $count++
            if ($entry.Size -eq '' -or $null -eq $entry.Size) { continue }
            $bytes=[long]0
            if ($entry.Size -notmatch '^\d+$' -or -not [long]::TryParse($entry.Size,[ref]$bytes) -or $bytes -gt ([long]::MaxValue-$total)) { $bad=$true;continue }
            $total+=$bytes; $known++
        }
        if ($bad) { Add-PackageIssue $record 'read-record' 'Malformed, duplicate or overflowing RECORD entries were excluded from the estimate' }
        $coverage=if ($known -eq 0) { 'unavailable' } elseif ($known -eq $count -and -not $bad) { 'complete' } else { 'partial' }
        return [pscustomobject]@{Bytes=$(if ($known -gt 0) {$total} else {$null});Known=$known;Count=$count;Coverage=$coverage}
    } catch {
        Add-PackageIssue $record 'read-record' $_.Exception.Message
        return [pscustomobject]@{Bytes=$null;Known=0;Count=0;Coverage='unavailable'}
    }
}
function Find-UserSites {
    # Bounded current-user locations, including Microsoft Store's redirected user site.
    $parents=[Collections.Generic.List[string]]::new()
    if ($env:APPDATA) { $parents.Add((Join-Path $env:APPDATA 'Python')) }
    if ($env:PYTHONUSERBASE) { $parents.Add($env:PYTHONUSERBASE) }
    if ($env:LOCALAPPDATA) {
        $store=Join-Path $env:LOCALAPPDATA 'Packages'
        if (Test-Path -LiteralPath $store) {
            try {
                foreach ($folder in Get-ChildItem -LiteralPath $store -Directory -Filter 'PythonSoftwareFoundation.Python.3.*' -Force) {
                    if ($folder.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                    $parents.Add((Join-Path $folder.FullName 'LocalCache/local-packages'))
                }
            } catch { Add-PackageIssue $store 'discover-user-sites' $_.Exception.Message }
        }
    }
    foreach ($parent in $parents | Sort-Object -Unique) {
        if (-not (Test-Path -LiteralPath $parent)) { continue }
        try {
            if ((Get-Item -LiteralPath $parent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked user-site parent is not followed' }
            foreach ($folder in Get-ChildItem -LiteralPath $parent -Directory -Filter 'Python3*' -Force) {
                if ($folder.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                $candidate=Join-Path $folder.FullName 'site-packages'
                if (Test-Path -LiteralPath $candidate) { $candidate }
            }
        } catch { Add-PackageIssue $parent 'discover-user-sites' $_.Exception.Message }
    }
}
$scopes=[Collections.Generic.List[object]]::new()
foreach ($runtime in $runtimes) {
    $scopes.Add([pscustomobject]@{Id=[string]$runtime.Root;Root=[string]$runtime.Root;Category=[string]$runtime.Category;Kind='runtime';Candidates=@()})
}
if (-not $SkipUserSitePackages) {
    $userSites=if ($PSBoundParameters.ContainsKey('UserSiteRoots')) { @($UserSiteRoots) } else { @(Find-UserSites) }
    foreach ($site in $userSites | Where-Object { $_ } | Sort-Object -Unique) {
        $full=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($site)
        $scopes.Add([pscustomobject]@{Id='user-site:'+$full;Root=$full;Category='shared-user-site';Kind='user-site';Candidates=@($full)})
    }
}
Write-Host "Reading package metadata in $($scopes.Count) scopes; no executable rescan."
$scopeIndex=0
foreach ($scope in $scopes) {
    $scopeIndex++
    Write-Progress -Activity 'Package metadata inventory' -Status "$scopeIndex of $($scopes.Count) scopes · $($packages.Count) entries" -CurrentOperation $scope.Root -PercentComplete ([int](100*($scopeIndex-1)/[math]::Max(1,$scopes.Count)))
    $before=$packages.Count;$beforeIssues=$issues.Count
    $candidates=[Collections.Generic.List[string]]::new()
    if ($scope.Kind -eq 'runtime') {
        $candidates.Add((Join-Path $scope.Root 'Lib/site-packages'))
        $candidates.Add((Join-Path $scope.Root 'site-packages'))
        $lib=Join-Path $scope.Root 'lib'
        if (Test-Path -LiteralPath $lib) {
            try {
                if ((Get-Item -LiteralPath $lib -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked library directory is not followed' }
                foreach ($folder in Get-ChildItem -LiteralPath $lib -Directory -Filter 'python3.*' -Force) {
                    if ($folder.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                    $candidates.Add((Join-Path $folder.FullName 'site-packages'))
                }
            } catch { Add-PackageIssue $lib 'discover-package-locations' $_.Exception.Message }
        }
    } else { foreach ($candidate in $scope.Candidates) { $candidates.Add($candidate) } }
    $statuses=[Collections.Generic.List[string]]::new()
    foreach ($candidate in $candidates | Sort-Object -Unique) {
        $status='missing';$found=0
        try {
            $directory=Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
            # Check ancestors up to the runtime root: no junction escape through Lib.
            for ($ancestor=$directory; $ancestor; $ancestor=$ancestor.Parent) {
                if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked package location or ancestor is not followed' }
                if ($ancestor.FullName -eq $scope.Root) { break }
            }
            if (-not $directory.PSIsContainer) { throw 'Package location is not a directory' }
            $status='scanned'
            foreach ($entry in Get-ChildItem -LiteralPath $candidate -Force) {
                if ($entry.Name -notmatch '\.(dist|egg)-info$') { continue }
                if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { Add-PackageIssue $entry.FullName 'read-package' 'Linked package metadata is not followed';continue }
                $kind=if ($entry.Name -match '\.dist-info$') {'dist-info'} else {'egg-info'}
                if ($kind -eq 'dist-info' -and -not $entry.PSIsContainer) { continue }
                $metadata=if (-not $entry.PSIsContainer) {$entry.FullName} elseif ($kind -eq 'dist-info') {Join-Path $entry.FullName 'METADATA'} else {Join-Path $entry.FullName 'PKG-INFO'}
                $headers=@{};$metadataStatus='read'
                try {
                    $headers=Get-CoreHeaders (Read-PackageText $metadata)
                    if (-not $headers['Name'] -or -not $headers['Version']) { throw 'Required Name or Version metadata is missing; values are not inferred from the directory name' }
                } catch { $metadataStatus='incomplete';Add-PackageIssue $metadata 'read-metadata' $_.Exception.Message }
                $size=if ($kind -eq 'dist-info') {Get-RecordedSize $entry.FullName} else {[pscustomobject]@{Bytes=$null;Known=0;Count=0;Coverage='unavailable'}}
                $packages.Add([pscustomobject][ordered]@{
                    EnvironmentId=$scope.Id;EnvironmentRoot=$scope.Root;Scope=$scope.Kind
                    Name=$(if ($headers['Name']) {$headers['Name'][0]} else {$null})
                    Version=$(if ($headers['Version']) {$headers['Version'][0]} else {$null})
                    Summary=$(if ($headers['Summary']) {$headers['Summary'][0]} else {$null})
                    RequiresDist=@($headers['Requires-Dist'] | Where-Object { $_ });SitePackages=$candidate;MetadataPath=$metadata
                    MetadataKind=$kind;MetadataStatus=$metadataStatus;EstimatedBytes=$size.Bytes
                    SizeCoverage=$size.Coverage;RecordedFiles=$size.Count;FilesWithDeclaredSize=$size.Known
                });$found++
            }
        } catch [System.Management.Automation.ItemNotFoundException] { $status='missing' }
        catch { $status='unavailable';Add-PackageIssue $candidate 'enumerate-packages' $_.Exception.Message }
        $statuses.Add($status)
        $locations.Add([pscustomobject]@{EnvironmentId=$scope.Id;Path=$candidate;Status=$status;Packages=$found})
    }
    $local=@($packages | Select-Object -Skip $before)
    $known=@($local | Where-Object { $null -ne $_.EstimatedBytes })
    $environments.Add([pscustomobject]@{
        Id=$scope.Id;Root=$scope.Root;Category=$scope.Category;Scope=$scope.Kind
        PackageCount=$local.Count;PackagesWithSize=$known.Count
        EstimatedBytes=$(if ($known.Count) {($known | Measure-Object EstimatedBytes -Sum).Sum} else {$null})
        LocationsScanned=@($statuses | Where-Object {$_ -eq 'scanned'}).Count
        Issues=$issues.Count-$beforeIssues
    })
}
Write-Progress -Activity 'Package metadata inventory' -Completed
$watch.Stop()
$summary=[pscustomobject][ordered]@{
    SchemaVersion=1;GeneratedAtUtc=[DateTime]::UtcNow.ToString('o');ElapsedSeconds=[math]::Round($watch.Elapsed.TotalSeconds,2)
    Environments=$environments.Count;Packages=$packages.Count;LocationsScanned=@($locations | Where-Object Status -eq 'scanned').Count
    Issues=$issues.Count;Mode='Static METADATA / PKG-INFO and RECORD audit; no interpreter execution'
    SizeBasis='Sum of declared RECORD sizes, not measured disk usage or reclaimable space'
    ScopeLimits='Known package locations only; user sites are separate candidates. Inherited packages, .pth/.start, PYTHONPATH, editable sources and archives are not resolved. Presence does not prove importability.'
}
foreach ($output in @(
    @{Name='python-packages.json';Data=$packages.ToArray()},@{Name='package-environments.json';Data=$environments.ToArray()},
    @{Name='package-locations.json';Data=$locations.ToArray()},@{Name='package-issues.json';Data=$issues.ToArray()},@{Name='package-summary.json';Data=$summary}
)) { ConvertTo-Json -InputObject $output.Data -Depth 12 | Set-Content -LiteralPath (Join-Path $report $output.Name) -Encoding utf8 }
$csv=Join-Path $report 'python-packages.csv'
if ($packages.Count) {
    $packages | Select-Object EnvironmentId,EnvironmentRoot,Scope,Name,Version,Summary,SitePackages,MetadataPath,MetadataKind,MetadataStatus,EstimatedBytes,SizeCoverage,RecordedFiles,FilesWithDeclaredSize,@{Name='RequiresDist';Expression={$_.RequiresDist -join ' | '}} | Export-Csv -LiteralPath $csv -NoTypeInformation -Delimiter ';' -Encoding utf8BOM
} else { '"EnvironmentId";"EnvironmentRoot";"Scope";"Name";"Version";"Summary";"SitePackages";"MetadataPath";"MetadataKind";"MetadataStatus";"EstimatedBytes";"SizeCoverage";"RecordedFiles";"FilesWithDeclaredSize";"RequiresDist"' | Set-Content -LiteralPath $csv -Encoding utf8BOM }
Write-Host "Package metadata: $($summary.Packages) entries in $($summary.Environments) environment scopes; $($summary.Issues) issues; $($summary.ElapsedSeconds) s."
if ($PassThru) { $summary }
