#requires -Version 7.2
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReportDirectory, [switch]$PassThru)
$ErrorActionPreference = 'Stop'
$report = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportDirectory)
$rows = @(Get-Content -LiteralPath (Join-Path $report 'python-executables.json') -Raw | ConvertFrom-Json)
$findings = [Collections.Generic.List[object]]::new()
function Write-Json([string]$Name, [object]$Value) {
    ConvertTo-Json -InputObject $Value -Depth 12 | Set-Content -LiteralPath (Join-Path $report $Name) -Encoding utf8
}
function Resolve-Directory([string]$Path) {
    if (-not $Path) { return $null }
    try {
        $directory = [IO.DirectoryInfo]::new($Path)
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            $target = $directory.ResolveLinkTarget($true)
            if ($target) { return [IO.Path]::TrimEndingDirectorySeparator($target.FullName) }
        }
        return [IO.Path]::TrimEndingDirectorySeparator($directory.FullName)
    } catch { return $Path }
}
$analysis = @(
    foreach ($row in $rows) {
        $path = [string]$row.Path
        $directory = [IO.Path]::GetDirectoryName($path)
        $config = $null; $baseHome = $null; $baseExists = $null
        if ([IO.Path]::GetFileName($directory) -eq 'Scripts') {
            $candidate = Join-Path ([IO.Directory]::GetParent($directory).FullName) 'pyvenv.cfg'
            if (Test-Path -LiteralPath $candidate -PathType Leaf -ErrorAction SilentlyContinue) {
                $config = $candidate
                try {
                    $homeLine = Get-Content -LiteralPath $candidate | Where-Object { $_ -match '^\s*home\s*=' } | Select-Object -First 1
                    if ($homeLine) { $baseHome = ($homeLine -split '=',2)[1].Trim() }
                } catch {
                    $findings.Add([pscustomobject]@{Code='unreadable-venv-config';Severity='review';Path=$candidate;Message=$_.Exception.Message})
                }
            }
        }
        $category = 'unclassified-runtime'; $evidence = 'Executable filename; ownership has not been established'
        $action = 'Identify the owning tool or project before changes'
        $runtimeRoot = $directory
        if ($path -match '\\Program Files(?: \(x86\))?\\|\\python_embeded\\|\\pythonsdk\\|\\python3kit\\|\\pico-sdk\\python\\|\\SteamLibrary\\steamapps\\common\\|\\\.cache\\codex-runtimes\\|\\AppData\\(?:Local|Roaming)\\(?:Arduino15|chaiNNer)\\|\\Programs\\Thonny\\|\\3DCoat\\python-') {
            $category='embedded-runtime';$evidence='Application bundle directory convention; ownership is inferred';$action='Keep with its application; verify ownership before changes'
        }
        if ($row.IsAlias) { $category='alias'; $action='Review command routing'; $evidence='Filesystem reparse-point metadata' }
        elseif ($path -match '\\Windows\\Installer\\') { $category='installer-cache'; $action='Keep: Windows repair/uninstall resources'; $evidence='Windows Installer directory' }
        elseif ($path -match '\\lib\\venv\\scripts\\nt\\') {
            $category='venv-template'; $action='Keep: venv launcher template'; $evidence='Standard-library venv template layout'
            $runtimeRoot=$path -replace '(?i)\\lib\\venv\\scripts\\nt\\[^\\]+$',''
        }
        elseif ($path -match '\\backups?\\|\\before-update-') { $category='backup'; $action='Review backup retention; usage has not been established'; $evidence='Backup-like directory name' }
        elseif ($path -match '\\chocolatey\\bin\\|\\AppData\\Local\\python\\bin\\|\\WindowsApps\\PythonSoftwareFoundation\.PythonManager_') { $category='launcher'; $action='Review routing; this may wrap another installation'; $evidence='Known manager launcher directory' }
        elseif (Test-Path -LiteralPath (Join-Path $directory 'conda-meta') -PathType Container -ErrorAction SilentlyContinue) { $category='conda-environment';$action='Review through the owning Conda manager';$evidence='conda-meta directory next to the executable' }
        elseif ($config) {
            $category='virtual-environment'; $action='Keep with its project and base Python'; $evidence='pyvenv.cfg found next to Scripts'
            $runtimeRoot=[IO.Path]::GetDirectoryName($config)
        }
        elseif ($path -match '\\AppData\\Roaming\\uv\\python\\|\\Local\\hermes\\tools\\python-') { $category='managed-runtime'; $action='Check dependent environments before uninstalling'; $evidence='Known manager installation directory' }
        elseif ($path -match '^[A-Z]:\\Python\d+\\|\\Programs\\Python\\Python\d+\\|\\Local\\python\\pythoncore-|\\WindowsApps\\PythonSoftwareFoundation\.Python\.\d') { $category='standalone-runtime'; $action='Check dependent environments and scripts before uninstalling'; $evidence='Conventional Python installation directory' }
        if ([IO.Path]::GetFileName($runtimeRoot) -eq 'bin' -and $category -in @('embedded-runtime','unclassified-runtime')) { $runtimeRoot=[IO.Path]::GetDirectoryName($runtimeRoot) }
        if ($baseHome) { $baseExists=Test-Path -LiteralPath $baseHome -PathType Container -ErrorAction SilentlyContinue }
        [pscustomobject][ordered]@{
            Path=$path;Category=$category;FileVersion=$row.FileVersion;RuntimeRoot=$runtimeRoot
            SuggestedAction=$action;Evidence=$evidence;VenvConfiguration=$config;BaseHome=$baseHome
            ResolvedBaseHome=(Resolve-Directory $baseHome);BaseDirectoryAccessible=$baseExists
        }
    }
)
$analysis | Export-Csv -LiteralPath (Join-Path $report 'python-classification.csv') -NoTypeInformation -Delimiter ';' -Encoding utf8BOM
Write-Json 'python-classification.json' $analysis
$categories = @($analysis | Group-Object Category | Sort-Object Name | ForEach-Object { [pscustomobject]@{ Category=$_.Name;Paths=$_.Count } })
Write-Json 'classification-summary.json' $categories
$dependencies = @($analysis | Where-Object BaseHome | Group-Object ResolvedBaseHome | ForEach-Object {
    [pscustomobject]@{
        ResolvedBaseHome=$_.Name;ConfiguredBaseHomes=@($_.Group.BaseHome | Sort-Object -Unique)
        Environments=@($_.Group.VenvConfiguration | Sort-Object -Unique)
        Accessible=(@($_.Group | Where-Object BaseDirectoryAccessible).Count -gt 0)
    }
})
foreach ($dependency in $dependencies) {
    if (-not $dependency.Accessible) {
        $findings.Add([pscustomobject]@{Code='base-directory-unavailable';Severity='review';Path=$dependency.ResolvedBaseHome;Message='Configured venv base directory is not accessible; verify before running or changing this environment.'})
    }
}
Write-Json 'base-runtime-dependencies.json' $dependencies
$runtimeCategories=@('standalone-runtime','managed-runtime','embedded-runtime','virtual-environment','conda-environment','unclassified-runtime')
$runtimes = @($analysis | Where-Object { $_.Category -in $runtimeCategories } | Group-Object RuntimeRoot | ForEach-Object {
    $group=$_.Group; $resolvedRoot=Resolve-Directory $_.Name
    $dependents=@($dependencies | Where-Object { $_.ResolvedBaseHome -eq $resolvedRoot } | ForEach-Object { $_.Environments } | Sort-Object -Unique)
    [pscustomobject]@{
        Root=$_.Name;Category=$group[0].Category;Paths=$group.Count
        FileVersions=@($group.FileVersion | Where-Object { $_ } | Sort-Object -Unique)
        Executables=@($group.Path);ObservedDependentEnvironments=$dependents
        CleanupVerdict='Not determined: no observed dependency does not prove that a runtime is unused'
    }
})
Write-Json 'runtime-folders.json' $runtimes
$commands = @(
    foreach ($name in @('python','python3','py','pip')) {
        $position=0
        foreach ($command in @(Get-Command -Name $name -All -ErrorAction SilentlyContinue)) {
            $position++; $source=$command.Source
            if ($command.CommandType -eq 'Alias') { $source=$command.Definition }
            $bytes=$null
            if ($command.CommandType -eq 'Application' -and (Test-Path -LiteralPath $source -PathType Leaf -ErrorAction SilentlyContinue)) {
                $bytes=(Get-Item -LiteralPath $source).Length
                if ($bytes -eq 0 -and [IO.Path]::GetExtension($source) -eq '') {
                    $findings.Add([pscustomobject]@{Code='empty-extensionless-command';Severity='warning';Path=$source;Message="An empty extensionless file participates in '$name' command resolution. Review this shadow file before changing PATH."})
                }
            }
            [pscustomobject]@{Command=$name;Priority=$position;Type=[string]$command.CommandType;Source=$source;Bytes=$bytes}
        }
    }
)
Write-Json 'command-resolution.json' $commands
Write-Json 'audit-findings.json' $findings.ToArray()
$summary=[pscustomobject]@{
    SchemaVersion=1;ExecutablePaths=$analysis.Count;RuntimeFolders=$runtimes.Count
    VirtualEnvironments=@($analysis.VenvConfiguration | Where-Object { $_ } | Sort-Object -Unique).Count
    BaseDependencyGroups=$dependencies.Count;Findings=$findings.Count;ReportDirectory=$report
    Mode='Read-only metadata audit; no interpreter execution, uninstall or PATH changes'
}
Write-Json 'audit-summary.json' $summary
$categories | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "Audit complete: $($summary.RuntimeFolders) candidate runtime folders, $($summary.VirtualEnvironments) venv configurations."
if ($PassThru) { Write-Output $summary }
