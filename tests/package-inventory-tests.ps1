# Invoked by run-tests.ps1 inside its owned fixture; no discovered code is executed.
$packageReport=Join-Path $fixture 'package-report'
$null=New-Item -ItemType Directory -Path $packageReport -Force
$first=Join-Path $fixture 'package-env-one';$second=Join-Path $fixture 'package-env-two'
$userSite=Join-Path $fixture 'user-package-site'
$sites=@((Join-Path $first 'Lib/site-packages'),(Join-Path $second 'Lib/site-packages'),$userSite)
foreach ($site in $sites) { $null=New-Item -ItemType Directory -Path $site -Force }
function New-PackageFixture([string]$Site,[string]$Directory,[string]$Metadata,[string]$Record) {
    $destination=Join-Path $Site $Directory
    $null=New-Item -ItemType Directory -Path $destination -Force
    $Metadata | Set-Content -LiteralPath (Join-Path $destination 'METADATA') -Encoding utf8
    if ($null -ne $Record -and $Record -ne '') { $Record | Set-Content -LiteralPath (Join-Path $destination 'RECORD') -Encoding utf8 }
    return $destination
}
$metadata="Metadata-Version: 2.4`nName: Shared-Package`nVersion: 1.0`nSummary: A folded`n description`nRequires-Dist: torch>=2; python_version >= '3.12'`nRequires-Dist: optional; extra == 'gpu'`n`nName: body-is-not-a-header"
$null=New-PackageFixture $sites[0] 'shared_package-1.0.dist-info' $metadata ('"module/file,quoted.py",,100'+"`n"+'Z:/does-not-exist/outside.py,,23')
$null=New-PackageFixture $sites[1] 'shared_package-2.0.dist-info' ($metadata.Replace('Version: 1.0','Version: 2.0')) 'module.py,,2048'
$null=New-PackageFixture $sites[1] 'shared_package-2.0-copy.dist-info' ($metadata.Replace('Version: 1.0','Version: 2.0')) 'module.py,,0'
$null=New-PackageFixture $sites[0] 'partial-1.dist-info' "Name: Partial`nVersion: 1`n" "a.py,,17`nb.py,,`na.py,,17`nc.py,,-1`nd.py,,9223372036854775808"
$null=New-PackageFixture $sites[0] 'unknown-1.dist-info' "Name: Unknown`nVersion: 1`n" ''
$null=New-PackageFixture $sites[0] 'zero-1.dist-info' "Name: Zero`nVersion: 1`n" 'zero.py,,0'
$null=New-PackageFixture $sites[0] 'broken-1.dist-info' 'Invalid header' ''
$attack="</script><script>globalThis.packageInjected=true</script>"
$null=New-PackageFixture $userSite 'open_webui-0.0.1.dist-info' "Name: open-webui`nVersion: 0.0.1`nSummary: $attack`n" ''
$legacy=Join-Path $sites[0] 'legacy.egg-info';$null=New-Item -ItemType Directory -Path $legacy
"Name: Legacy-Package`nVersion: 0.9`n" | Set-Content -LiteralPath (Join-Path $legacy 'PKG-INFO')
"Name: Legacy-File`nVersion: 0.8`n" | Set-Content -LiteralPath (Join-Path $sites[0] 'legacy-file.egg-info')
$oversized=New-PackageFixture $sites[0] 'oversized.dist-info' 'fixture' ''
$stream=[IO.File]::OpenWrite((Join-Path $oversized 'METADATA'));try {$stream.SetLength(4194305)}finally{$stream.Dispose()}
$linkedMetadata=Join-Path $sites[0] 'linked.dist-info'
$null=New-Item -ItemType Junction -Path $linkedMetadata -Target $oversized
$linkedLib=Join-Path $fixture 'package-env-linked';$null=New-Item -ItemType Directory -Path $linkedLib
$linkedLibPath=Join-Path $linkedLib 'Lib';$null=New-Item -ItemType Junction -Path $linkedLibPath -Target (Join-Path $first 'Lib')
$sentinel=Join-Path $fixture 'must-not-exist'
"import pathlib; pathlib.Path(r'$sentinel').touch()" | Set-Content -LiteralPath (Join-Path $sites[0] 'startup.pth')
$missing=Join-Path $fixture 'package-env-missing'
$runtimeData=@($first,$second,$linkedLib,$missing | ForEach-Object { @{Root=$_;Category='virtual-environment'} })
ConvertTo-Json -InputObject $runtimeData | Set-Content -LiteralPath (Join-Path $packageReport 'runtime-folders.json')
try {
    $result=& (Join-Path $repo 'scripts/inventory-python-packages.ps1') -ReportDirectory $packageReport -UserSiteRoots @($userSite) -PassThru
    $entries=Read-Json (Join-Path $packageReport 'python-packages.json')
    Assert ($entries.Count -eq 11) 'Package metadata remains per environment and retains same-name duplicates'
    $shared=@($entries | Where-Object Name -eq 'Shared-Package')
    Assert ($shared.Count -eq 3 -and @($shared.EnvironmentId | Sort-Object -Unique).Count -eq 2) 'Different package versions and duplicate metadata directories are not merged'
    $one=@($shared | Where-Object EnvironmentRoot -eq $first)[0]
    Assert ($one.EstimatedBytes -eq 123 -and $one.SizeCoverage -eq 'complete') 'Quoted CSV paths and external RECORD paths only contribute declared sizes'
    Assert ($one.Summary -eq 'A folded description' -and $one.RequiresDist.Count -eq 2 -and $one.Name -eq 'Shared-Package') 'Core metadata unfolds headers, retains markers and stops before the body'
    $partial=@($entries | Where-Object Name -eq 'Partial')[0]
    Assert ($partial.EstimatedBytes -eq 17 -and $partial.SizeCoverage -eq 'partial') 'Missing, duplicate, negative and overflowing sizes are handled explicitly'
    Assert ($null -eq @($entries | Where-Object Name -eq 'Unknown')[0].EstimatedBytes) 'Missing RECORD size remains unknown rather than zero'
    Assert (@($entries | Where-Object Name -eq 'Zero')[0].EstimatedBytes -eq 0) 'A declared zero-byte package remains a known zero'
    Assert (@($entries | Where-Object { $_.MetadataStatus -eq 'incomplete' -and -not $_.Name }).Count -eq 2) 'Malformed and oversized metadata remain visible without invented names'
    Assert (@($entries | Where-Object MetadataKind -eq 'egg-info').Count -eq 2) 'Legacy PKG-INFO directories and egg-info files are supported'
    $userPackage=@($entries | Where-Object Name -eq 'open-webui')[0]
    Assert ($userPackage.Scope -eq 'user-site' -and $userPackage.EnvironmentId -like 'user-site:*') 'Shared user packages have a distinct scope instead of being assigned to every runtime'
    $packageIssues=Read-Json (Join-Path $packageReport 'package-issues.json')
    Assert (@($packageIssues | Where-Object Reason -match 'Linked').Count -ge 2) 'Metadata junctions and linked package-location ancestors are reported and skipped'
    $packageLocations=Read-Json (Join-Path $packageReport 'package-locations.json')
    Assert (@($packageLocations | Where-Object Status -eq 'missing').Count -ge 2) 'Missing candidate package locations retain coverage evidence'
    Assert (-not (Test-Path -LiteralPath $sentinel)) 'Package startup hooks are never executed'
    Assert (@(Import-Csv -LiteralPath (Join-Path $packageReport 'python-packages.csv') -Delimiter ';').Count -eq $entries.Count) 'Package CSV and JSON keep matching entry counts'
    foreach ($name in @('scan-summary.json','audit-summary.json','python-classification.json','base-runtime-dependencies.json','command-resolution.json','audit-findings.json','scan-issues.json')) {
        Copy-Item -LiteralPath (Join-Path $scan.ReportDirectory $name) -Destination (Join-Path $packageReport $name)
    }
    & (Join-Path $repo 'scripts/new-audit-report.ps1') -ReportDirectory $packageReport
    $packageHtml=Get-Content -LiteralPath (Join-Path $packageReport 'report.html') -Raw
    Assert (-not $packageHtml.Contains($attack) -and $packageHtml.Contains('packageInjected')) 'Package metadata is escaped in the offline HTML payload'
    Assert ($result.Environments -eq 5 -and $result.Packages -eq 11) 'Package summary counts runtime and separate user-site scopes'
} finally {
    if (Test-Path -LiteralPath $linkedMetadata) { [IO.Directory]::Delete($linkedMetadata) }
    if (Test-Path -LiteralPath $linkedLibPath) { [IO.Directory]::Delete($linkedLibPath) }
}
$oldReport=Join-Path $fixture 'old-report';$null=New-Item -ItemType Directory -Path $oldReport
foreach ($name in @('scan-summary.json','audit-summary.json','python-classification.json','runtime-folders.json','base-runtime-dependencies.json','command-resolution.json','audit-findings.json','scan-issues.json')) { Copy-Item -LiteralPath (Join-Path $scan.ReportDirectory $name) -Destination (Join-Path $oldReport $name) }
& (Join-Path $repo 'scripts/new-audit-report.ps1') -ReportDirectory $oldReport
Assert ((Get-Content -LiteralPath (Join-Path $oldReport 'report.html') -Raw).Contains('"packageSummary":null')) 'Older reports without package inventory still generate successfully'
$storeReport=Join-Path $fixture 'store-report';$null=New-Item -ItemType Directory -Path $storeReport
$storePath=Join-Path $fixture 'WindowsApps/PythonSoftwareFoundation.Python.3.12_fixture/python3.12.exe'
ConvertTo-Json -InputObject @(@{Path=$storePath;IsAlias=$false;FileVersion='3.12.10'}) | Set-Content -LiteralPath (Join-Path $storeReport 'python-executables.json')
& (Join-Path $repo 'scripts/analyze-python-inventory.ps1') -ReportDirectory $storeReport -SkipUserSitePackages
$storeRuntimes=Read-Json (Join-Path $storeReport 'runtime-folders.json')
Assert ($storeRuntimes.Count -eq 1 -and $storeRuntimes[0].DisplayName -eq 'Python 3.12.10 · Microsoft Store') 'Store Python gets a readable label from observed package path and version metadata'
Assert ($null -eq $storeRuntimes[0].RegisteredInstallDate) 'Store labeling does not fabricate an installation date'
