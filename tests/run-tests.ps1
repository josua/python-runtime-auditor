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
    Assert (@($files | Where-Object { -not $_.CreationTimeUtc -or -not $_.LastWriteTimeUtc }).Count -eq 0) 'Scanner records UTC file creation and modification timestamps'
    Assert ((Get-Content -LiteralPath (Join-Path $scan.ReportDirectory 'python-executables.jsonl')).Count -eq 6) 'Incremental journal retains every discovered path'
    $audit=& (Join-Path $repo 'scripts/analyze-python-inventory.ps1') -ReportDirectory $scan.ReportDirectory -PassThru
    Assert ($audit.VirtualEnvironments -eq 1) 'python/pythonw pair produces one observed venv configuration'
    Assert ($audit.RuntimeFolders -eq 5) 'Executable variants group into candidate runtime folders'
    $classified=Read-Json (Join-Path $scan.ReportDirectory 'python-classification.json')
    . (Join-Path $repo 'scripts/file-dates.ps1')
    $dateFixture=Get-ExecutableDates -Path (Join-Path $base 'python.exe') -Registrations @([pscustomobject]@{Root=$base;Date='2026-10-20';Source='Synthetic registration';Name='Fixture Python'})
    Assert ($dateFixture.RegisteredInstallDate -eq '2026-10-20' -and $dateFixture.CreationTimeUtc) 'Installation date evidence stays separate from file creation metadata'
    $noRegistration=Get-ExecutableDates -Path (Join-Path $sibling 'python.exe') -Registrations @([pscustomobject]@{Root=$excluded;Date='2026-10-20';Source='Synthetic registration';Name='Fixture Python'})
    Assert ($null -eq $noRegistration.RegisteredInstallDate -and $noRegistration.FileDateSource -match 'analysis time') 'Old inventories gain file dates without guessing installation dates or matching sibling prefixes'
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
    Assert ([regex]::Matches($html,'<svg class="icon"').Count -ge 11 -and $html -notmatch '<!--ICON:') 'Report embeds all navigation and metric SVG icons inline'
    Assert ($html.Contains('Copyright (c) 2020-2026 Paweł Kuna') -and $html.Contains('aria-hidden="true"')) 'Inline SVGs retain their license and decorative accessibility state'
    $empty=Join-Path $fixture 'empty'
    $null=New-Item -ItemType Directory -Path $empty
    $emptyScan=& (Join-Path $repo 'scripts/list-python-executables.ps1') -Roots $empty -OutputDirectory (Join-Path $outputRoot 'empty-reports') -PassThru
    Assert ($emptyScan.Completed -and $emptyScan.ExecutablesFound -eq 0) 'Empty scans still produce a completed report'
    $emptyAudit=& (Join-Path $repo 'scripts/analyze-python-inventory.ps1') -ReportDirectory $emptyScan.ReportDirectory -PassThru
    & (Join-Path $repo 'scripts/new-audit-report.ps1') -ReportDirectory $emptyScan.ReportDirectory
    Assert ($emptyAudit.ExecutablePaths -eq 0 -and $emptyAudit.RuntimeFolders -eq 0) 'Empty inventory analysis is supported'
    . (Join-Path $repo 'scripts/report-browser.ps1')
    $browserReport=Join-Path $fixture 'report with spaces-é-#-100%.html'
    Copy-Item -LiteralPath (Join-Path $scan.ReportDirectory 'report.html') -Destination $browserReport
    $browserData=Join-Path $fixture 'browser data'
    $edge=[pscustomobject]@{Name='edge';DisplayName='Edge fixture';Path='C:\Test Browsers\msedge.exe';Mode='app';Priority=0}
    $chrome=[pscustomobject]@{Name='chrome';DisplayName='Chrome fixture';Path='C:\Test Browsers\chrome.exe';Mode='app';Priority=1}
    $firefox=[pscustomobject]@{Name='firefox';DisplayName='Firefox fixture';Path='C:\Test Browsers\firefox.exe';Mode='window';Priority=4}
    $plan=Get-ReportBrowserPlan -Candidate $edge -ReportPath $browserReport -BrowserDataDirectory $browserData
    Assert (([uri]$plan.Url).LocalPath -eq $browserReport) 'Report URI preserves Unicode, spaces, # and percent characters'
    Assert ($plan.Arguments -contains ('--app='+$plan.Url)) 'Chromium app launch targets the generated local report'
    Assert ($plan.ProfileDirectory.StartsWith($browserData+'\') -and $plan.CacheDirectory.StartsWith($browserData+'\')) 'Browser profile and cache use a dedicated location'
    Assert ($plan.Arguments -contains '--disk-cache-size=67108864') 'Report browser uses a modest disk-cache size hint'
    $otherEdge=[pscustomobject]@{Name='edge';Path='C:\Test Browsers\Beta\msedge.exe';Mode='app'}
    $otherPlan=Get-ReportBrowserPlan -Candidate $otherEdge -ReportPath $browserReport -BrowserDataDirectory $browserData
    Assert ($plan.ProfileDirectory -ne $otherPlan.ProfileDirectory) 'Separate browser installations get distinct profiles'
    $firefoxPlan=Get-ReportBrowserPlan -Candidate $firefox -ReportPath $browserReport -BrowserDataDirectory $browserData
    Assert ($firefoxPlan.Arguments[0] -eq '--new-window' -and $null -eq $firefoxPlan.ProfileDirectory) 'Firefox uses a documented new-window fallback without Chromium flags'
    Assert ((ConvertFrom-BrowserCommand '"C:\Test Browsers\chrome.exe" --ignored "%1"') -eq 'C:\Test Browsers\chrome.exe') 'Registered browser commands retain only the quoted executable path'
    $preview=Open-ReportBrowser -ReportPath $browserReport -BrowserDataDirectory $browserData -Candidates @($firefox,$chrome,$edge) -WhatIf
    Assert ($preview.Browser -eq 'edge' -and -not (Test-Path -LiteralPath $browserData)) 'WhatIf prefers app mode and creates no browser data'
    $preview=& (Join-Path $repo 'open-audit-report.ps1') -ReportPath $browserReport -BrowserDataDirectory $browserData -Browser default -WhatIf -PassThru
    Assert ($preview.Mode -eq 'default') 'Standalone report opener supports the ordinary default-application option'
    $nativeBrowserStarter=(Get-Item Function:\Start-ReportBrowserProcess).ScriptBlock
    $attempts=[Collections.Generic.List[string]]::new()
    try {
        function Start-ReportBrowserProcess {
            param($Plan)
            $attempts.Add($Plan.Browser)
            if ($Plan.Browser -eq 'edge') { throw 'Synthetic startup failure' }
            return 1234
        }
        $opened=Open-ReportBrowser -ReportPath $browserReport -BrowserDataDirectory $browserData -Candidates @($firefox,$chrome,$edge) -WarningAction SilentlyContinue
        Assert (($attempts -join ',') -eq 'edge,chrome' -and $opened.Browser -eq 'chrome') 'Automatic selection tries the next app browser after a startup failure'
        $attempts.Clear();$explicitFailure=$false
        try { $null=Open-ReportBrowser -ReportPath $browserReport -BrowserDataDirectory $browserData -Browser edge -Candidates @($edge,$chrome) } catch { $explicitFailure=$true }
        Assert ($explicitFailure -and ($attempts -join ',') -eq 'edge') 'An explicitly chosen browser fails clearly instead of silently changing the choice'
        $attempts.Clear();$missingFailure=$false
        try { $null=Open-ReportBrowser -ReportPath (Join-Path $fixture 'missing.html') -BrowserDataDirectory $browserData -Candidates @($edge) } catch { $missingFailure=$true }
        Assert ($missingFailure -and $attempts.Count -eq 0) 'A missing report fails before any browser launch'
        $missingBrowser=$false
        try { $null=Open-ReportBrowser -ReportPath $browserReport -BrowserDataDirectory $browserData -Browser brave -Candidates @($edge) } catch { $missingBrowser=$true }
        Assert ($missingBrowser -and $attempts.Count -eq 0) 'An unavailable explicit browser reports an actionable error'
    } finally { Set-Item Function:\Start-ReportBrowserProcess $nativeBrowserStarter }
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
