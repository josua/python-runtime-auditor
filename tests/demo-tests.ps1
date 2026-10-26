$demo=Read-Json (Join-Path $repo 'examples/demo-audit.json')
Assert ($demo.scan.IsAnonymized -and -not $demo.scan.IsSynthetic) 'Reference demo is explicitly anonymized instead of claiming synthetic values'
Assert ($demo.summary.ExecutablePaths -eq 173 -and @($demo.files).Count -eq 173 -and @($demo.files.Path | Sort-Object -Unique).Count -eq 173) 'All 173 demo executable paths are distinct data rows, not a cosmetic counter'
Assert ($demo.summary.RuntimeFolders -eq 60 -and @($demo.runtimes).Count -eq 60 -and @($demo.runtimes | Where-Object Category -eq 'virtual-environment').Count -eq 22) 'Demo retains 60 runtime groups including 22 virtual environments'
$missingPaths=@(foreach ($runtime in $demo.runtimes) { foreach ($path in $runtime.Executables) { if ($path -notin $demo.files.Path) { $path } } })
Assert ($missingPaths.Count -eq 0) 'Demo runtime drill-down paths refer to actual executable rows'
$countsMatch=@(foreach ($scope in $demo.packageEnvironments) {
    if (@($demo.packages | Where-Object EnvironmentId -eq $scope.Id).Count -ne $scope.PackageCount) { $scope.Id }
})
Assert ($demo.packageSummary.Packages -eq 2592 -and @($demo.packages).Count -eq 2592 -and $countsMatch.Count -eq 0) 'All 2592 package metadata rows agree with per-environment counts'
Assert (@($demo.packageEnvironments).Count -eq 62 -and @($demo.packageLocations | Where-Object Status -eq 'scanned').Count -eq 52 -and @($demo.packageIssues).Count -eq 13) 'Demo package coverage and issue totals retain their source relationships'
$serialized=Get-Content -LiteralPath (Join-Path $repo 'examples/demo-audit.json') -Raw
Assert ($serialized -notmatch '(?i)\\\\Users\\\\|https?://|[a-z]:\\\\(?!demo(?:\\\\|"))') 'Public demo fixture contains only demonstration paths and no source URLs or user profile folders'
$demoDestination=Join-Path $outputRoot 'reference-demo'
& (Join-Path $repo 'scripts/new-demo-report.ps1') -OutputDirectory $demoDestination
$generated=Read-Json (Join-Path $demoDestination 'audit-summary.json')
Assert ($generated.ExecutablePaths -eq 173 -and (Test-Path -LiteralPath (Join-Path $demoDestination 'report.html'))) 'Reference demo regenerates offline without a filesystem scan'
