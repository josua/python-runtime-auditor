#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ReportPath,
    [ValidateSet('auto','edge','chrome','chromium','brave','firefox','vivaldi','opera','default')][string]$Browser='auto',
    [string]$BrowserPath,
    [string]$BrowserDataDirectory=(Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'python-runtime-auditor/browser-data'),
    [switch]$ListBrowsers,
    [switch]$PassThru
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'scripts/report-browser.ps1')
if ($ListBrowsers) { Get-ReportBrowsers | Select-Object Name,DisplayName,Mode,Version,Path,Source; return }
if (-not $ReportPath) {
    $reports=Join-Path $PSScriptRoot 'reports'
    $latest=if (Test-Path -LiteralPath $reports) {
        Get-ChildItem -LiteralPath $reports -Directory | Sort-Object Name -Descending |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'report.html') -PathType Leaf } | Select-Object -First 1
    }
    if (-not $latest) { throw 'No completed HTML report found under reports. Supply -ReportPath or run an audit first.' }
    $ReportPath=Join-Path $latest.FullName 'report.html'
}
$result=Open-ReportBrowser -ReportPath $ReportPath -Browser $Browser -BrowserPath $BrowserPath -BrowserDataDirectory $BrowserDataDirectory
if ($PassThru) { $result }
