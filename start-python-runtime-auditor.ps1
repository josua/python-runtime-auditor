#requires -Version 7.2
[CmdletBinding()]
param(
    [string[]]$Roots,
    [string]$OutputDirectory=(Join-Path $PSScriptRoot 'reports'),
    [string[]]$ExcludePaths=@(),
    [switch]$IncludeNetworkDrives,
    [switch]$OpenReport
)
$ErrorActionPreference='Stop'
$scan=@{OutputDirectory=$OutputDirectory;ExcludePaths=$ExcludePaths;PassThru=$true}
if ($Roots) { $scan.Roots=$Roots }
if ($IncludeNetworkDrives) { $scan.IncludeNetworkDrives=$true }
$result=& (Join-Path $PSScriptRoot 'scripts/list-python-executables.ps1') @scan
if (-not $result.Completed) { throw 'Scan did not finish; inspect the partial JSONL and scan summary.' }
& (Join-Path $PSScriptRoot 'scripts/analyze-python-inventory.ps1') -ReportDirectory $result.ReportDirectory
& (Join-Path $PSScriptRoot 'scripts/new-audit-report.ps1') -ReportDirectory $result.ReportDirectory
if ($OpenReport) { Start-Process -FilePath (Join-Path $result.ReportDirectory 'report.html') }
