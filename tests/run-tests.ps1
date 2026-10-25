#requires -Version 7.2
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$outputRoot=Join-Path $repo 'output/tests'
$null=New-Item -ItemType Directory -Path $outputRoot -Force
$fixture=Join-Path $outputRoot ('fixture-'+$PID)
$null=New-Item -ItemType Directory -Path $fixture -Force
$checks=0
function Assert([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:checks++; Write-Host "PASS: $Message"
}
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -NoEnumerate }
$originalPath=$env:PATH
$originalLocation=$PWD
$cycle=Join-Path $fixture 'cycle'
try {
    # Real PE files are copied only as inert filename fixtures. They are never invoked.
    $base=Join-Path $fixture 'base-python'
    $venv=Join-Path $fixture 'folder with spaces/.venv'
    $embedded=Join-Path $fixture 'embedded/bin'
    $excluded=Join-Path $fixture 'excluded'
    $sibling=Join-Path $fixture 'excluded-sibling'
    $shadow=Join-Path $fixture 'shadow-bin'
    $conda=Join-Path $fixture 'conda-environment'
    foreach ($directory in @($base,(Join-Path $venv 'Scripts'),$embedded,$excluded,$sibling,$shadow,(Join-Path $conda 'conda-meta'))) { $null=New-Item -ItemType Directory -Path $directory -Force }
    foreach ($path in @((Join-Path $base 'python.exe'),(Join-Path $venv 'Scripts/python.exe'),(Join-Path $venv 'Scripts/pythonw.exe'),(Join-Path $embedded 'python3.12.exe'),(Join-Path $excluded 'python.exe'),(Join-Path $sibling 'python.exe'),(Join-Path $conda 'python.exe'))) {
        Copy-Item -LiteralPath (Join-Path $PSHOME 'pwsh.exe') -Destination $path
    }
    "home = $base`nversion = 3.12.0" | Set-Content -LiteralPath (Join-Path $venv 'pyvenv.cfg') -Encoding utf8
    'inert installer fixture' | Set-Content -LiteralPath (Join-Path $fixture 'python-3.99-installer.exe')
    [IO.File]::WriteAllBytes((Join-Path $shadow 'py'),[byte[]]@())
    $null=New-Item -ItemType Junction -Path $cycle -Target $fixture
    $env:PATH=$shadow+';'+$originalPath
    Set-Location $outputRoot
    $relative='./'+[IO.Path]::GetFileName($fixture)
    $scan=& (Join-Path $repo 'scripts/list-python-executables.ps1') -Roots $relative,$base -ExcludePaths $excluded -OutputDirectory (Join-Path $outputRoot 'reports') -PassThru
    Assert $scan.Completed 'Scanner finishes through a directory junction cycle'
    Assert ($scan.ExecutablesFound -eq 6) 'Nested venv, Conda environment, runtime and sibling are found exactly once'
    Assert ($scan.DirectoryLinks -ge 1) 'Directory junctions are recorded'
    Assert ($scan.ExcludedDirectories -eq 1) 'Explicit exclusion is recorded without excluding a same-prefix sibling'
    Assert ($scan.Roots[0] -eq $fixture) 'Relative roots resolve against PowerShell location'
    $files=Read-Json (Join-Path $scan.ReportDirectory 'python-executables.json')
    Assert (@($files | Where-Object { $_.Path -match 'installer' }).Count -eq 0) 'Installer filenames are excluded'
    Assert (@($files | Where-Object { $_.Path -match 'pythonw.exe$' }).Count -eq 1) 'Windowed executable is retained as a separate path'
    $csv=@(Import-Csv -LiteralPath (Join-Path $scan.ReportDirectory 'python-executables.csv') -Delimiter ';')
    Assert ($csv.Count -eq 6) 'CSV and JSON counts agree'
    Assert ((Get-Content -LiteralPath (Join-Path $scan.ReportDirectory 'python-executables.jsonl')).Count -eq 6) 'Incremental journal retains every discovered path'
    $audit=& (Join-Path $repo 'scripts/analyze-python-inventory.ps1') -ReportDirectory $scan.ReportDirectory -PassThru
    Assert ($audit.VirtualEnvironments -eq 1) 'python/pythonw pair produces one observed venv configuration'
    Assert ($audit.RuntimeFolders -eq 5) 'Executable variants group into candidate runtime folders'
    $classified=Read-Json (Join-Path $scan.ReportDirectory 'python-classification.json')
    Assert (@($classified | Where-Object Category -eq 'conda-environment').Count -eq 1) 'Conda environments use conda-meta evidence'
    Assert (@($classified | Where-Object Category -eq 'unclassified-runtime').Count -ge 1) 'Unknown ownership stays unclassified'
    $dependencies=Read-Json (Join-Path $scan.ReportDirectory 'base-runtime-dependencies.json')
    Assert ($dependencies.Count -eq 1 -and $dependencies[0].ResolvedBaseHome -eq $base) 'Base dependency comes from pyvenv.cfg'
    Assert ($dependencies[0].Environments.Count -eq 1) 'Base dependency graph deduplicates the two venv executables'
    $runtimes=Read-Json (Join-Path $scan.ReportDirectory 'runtime-folders.json')
    $baseRuntime=@($runtimes | Where-Object Root -eq $base)[0]
    Assert ($baseRuntime.ObservedDependentEnvironments.Count -eq 1) 'Base runtime retains its dependent environment'
    Assert (@($runtimes | Where-Object { $_.CleanupVerdict -notmatch 'Not determined' }).Count -eq 0) 'No candidate is declared safe to delete'
    $findings=Read-Json (Join-Path $scan.ReportDirectory 'audit-findings.json')
    Assert (@($findings | Where-Object { $_.Code -eq 'empty-extensionless-command' -and $_.Path -eq (Join-Path $shadow 'py') }).Count -ge 1) 'Empty extensionless command shadow is diagnosed without execution'
    # Import an adversarial data string to verify that JSON cannot escape its HTML data element.
    $attack='</script><script>globalThis.auditInjected=true</script>'
    ConvertTo-Json -InputObject @([pscustomobject]@{Code='synthetic-data';Severity='review';Path='synthetic';Message=$attack}) | Set-Content -LiteralPath (Join-Path $scan.ReportDirectory 'audit-findings.json') -Encoding utf8
    & (Join-Path $repo 'scripts/new-audit-report.ps1') -ReportDirectory $scan.ReportDirectory
    $html=Get-Content -LiteralPath (Join-Path $scan.ReportDirectory 'report.html') -Raw
    Assert (-not $html.Contains($attack)) 'Imported data cannot close the HTML script element'
    Assert ($html.Contains('\u003c/script\u003e')) 'HTML delimiters are escaped inside embedded JSON'
    Assert ((Test-Path -LiteralPath (Join-Path $scan.ReportDirectory 'assets/report.js'))) 'Offline report contains its local JavaScript asset'
    Assert ($html.Contains('SolGPT 6.1') -and $html.Contains('Philippe Jos')) 'Report includes requested authorship and human project role'
    $empty=Join-Path $fixture 'empty'
    $null=New-Item -ItemType Directory -Path $empty
    $emptyScan=& (Join-Path $repo 'scripts/list-python-executables.ps1') -Roots $empty -OutputDirectory (Join-Path $outputRoot 'empty-reports') -PassThru
    Assert ($emptyScan.Completed -and $emptyScan.ExecutablesFound -eq 0) 'Empty scans still produce a completed report'
    $emptyAudit=& (Join-Path $repo 'scripts/analyze-python-inventory.ps1') -ReportDirectory $emptyScan.ReportDirectory -PassThru
    & (Join-Path $repo 'scripts/new-audit-report.ps1') -ReportDirectory $emptyScan.ReportDirectory
    Assert ($emptyAudit.ExecutablePaths -eq 0 -and $emptyAudit.RuntimeFolders -eq 0) 'Empty inventory analysis is supported'
    $parseFailures=@(
        foreach ($script in Get-ChildItem -LiteralPath $repo -Filter '*.ps1' -Recurse -File | Where-Object { $_.FullName -notlike '*\output\*' }) {
            $tokens=$null;$errors=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$errors)
            foreach ($error in $errors) { $error.Message }
        }
    )
    Assert ($parseFailures.Count -eq 0) 'All PowerShell entry points parse'
    [pscustomobject]@{Passed=$true;Checks=$checks;HtmlReport=(Join-Path $scan.ReportDirectory 'report.html')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outputRoot 'test-result.json') -Encoding utf8
    Write-Host "`n$checks checks passed." -ForegroundColor Green
} finally {
    $env:PATH=$originalPath
    Set-Location $originalLocation
    # Remove only the owned test fixture. Unlink the cycle before any recursive cleanup.
    if (Test-Path -LiteralPath $cycle) { [IO.Directory]::Delete($cycle) }
    $resolvedFixture=[IO.Path]::GetFullPath($fixture)
    $resolvedOutput=[IO.Path]::GetFullPath($outputRoot)
    if (-not $resolvedFixture.StartsWith($resolvedOutput+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path' }
    if (Test-Path -LiteralPath $resolvedFixture) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}
