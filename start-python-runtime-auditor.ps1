#requires -Version 7.2
[CmdletBinding()]
param(
    [string[]]$Roots,
    [string]$OutputDirectory=(Join-Path $PSScriptRoot 'reports'),
    [string[]]$ExcludePaths=@(),
    [switch]$IncludeNetworkDrives,
    [switch]$SkipUserSitePackages,
    [switch]$OpenReport,
    [ValidateSet('auto','edge','chrome','chromium','brave','firefox','vivaldi','opera','default')][string]$ReportBrowser='auto',
    [string]$ReportBrowserPath,
    [string]$BrowserDataDirectory=(Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'python-runtime-auditor/browser-data')
)
$ErrorActionPreference='Stop'
$scan=@{OutputDirectory=$OutputDirectory;ExcludePaths=$ExcludePaths;PassThru=$true}
if ($Roots) { $scan.Roots=$Roots }
if ($IncludeNetworkDrives) { $scan.IncludeNetworkDrives=$true }
$result=& (Join-Path $PSScriptRoot 'scripts/list-python-executables.ps1') @scan
if (-not $result.Completed) { throw 'Scan did not finish; inspect the partial JSONL and scan summary.' }
& (Join-Path $PSScriptRoot 'scripts/analyze-python-inventory.ps1') -ReportDirectory $result.ReportDirectory -SkipUserSitePackages:$SkipUserSitePackages
& (Join-Path $PSScriptRoot 'scripts/new-audit-report.ps1') -ReportDirectory $result.ReportDirectory
if ($OpenReport) {
    & (Join-Path $PSScriptRoot 'open-audit-report.ps1') -ReportPath (Join-Path $result.ReportDirectory 'report.html') `
        -Browser $ReportBrowser -BrowserPath $ReportBrowserPath -BrowserDataDirectory $BrowserDataDirectory
}
