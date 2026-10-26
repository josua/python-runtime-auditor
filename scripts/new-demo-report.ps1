#requires -Version 7.2
[CmdletBinding()]
param([string]$OutputDirectory=(Join-Path (Split-Path $PSScriptRoot -Parent) 'output/demo'))
$ErrorActionPreference='Stop'
$destination=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$null=New-Item -ItemType Directory -Path $destination -Force
$fixture=Join-Path (Split-Path $PSScriptRoot -Parent) 'examples/demo-audit.json'
$payload=Get-Content -LiteralPath $fixture -Raw | ConvertFrom-Json -AsHashtable
if (-not $payload.scan.IsAnonymized) { throw 'The public demo requires the anonymized reference fixture.' }
$outputs=[ordered]@{
    scan='scan-summary.json';summary='audit-summary.json'
    files='python-classification.json';runtimes='runtime-folders.json'
    dependencies='base-runtime-dependencies.json';commands='command-resolution.json'
    findings='audit-findings.json';issues='scan-issues.json'
    packages='python-packages.json';packageSummary='package-summary.json'
    packageEnvironments='package-environments.json';packageLocations='package-locations.json'
    packageIssues='package-issues.json'
}
foreach ($item in $outputs.GetEnumerator()) {
    ConvertTo-Json -InputObject $payload[$item.Key] -Depth 20 |
        Set-Content -LiteralPath (Join-Path $destination $item.Value) -Encoding utf8
}
& (Join-Path $PSScriptRoot 'new-audit-report.ps1') -ReportDirectory $destination
