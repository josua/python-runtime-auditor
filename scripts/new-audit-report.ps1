#requires -Version 7.2
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReportDirectory)
$ErrorActionPreference='Stop'
$report=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportDirectory)
$assets=Join-Path (Split-Path $PSScriptRoot -Parent) 'assets'
function Read-ReportJson([string]$Name) {
    return Get-Content -LiteralPath (Join-Path $report $Name) -Raw | ConvertFrom-Json -NoEnumerate
}
function Read-OptionalJson([string]$Name) {
    if (Test-Path -LiteralPath (Join-Path $report $Name)) { Read-ReportJson $Name }
}
$payload=[ordered]@{
    scan=(Read-ReportJson 'scan-summary.json');summary=(Read-ReportJson 'audit-summary.json')
    files=(Read-ReportJson 'python-classification.json');runtimes=(Read-ReportJson 'runtime-folders.json')
    dependencies=(Read-ReportJson 'base-runtime-dependencies.json');commands=(Read-ReportJson 'command-resolution.json')
    findings=(Read-ReportJson 'audit-findings.json');issues=(Read-ReportJson 'scan-issues.json')
    packages=(Read-OptionalJson 'python-packages.json');packageSummary=(Read-OptionalJson 'package-summary.json')
    packageEnvironments=(Read-OptionalJson 'package-environments.json');packageLocations=(Read-OptionalJson 'package-locations.json')
    packageIssues=(Read-OptionalJson 'package-issues.json')
}
# JSON is data inside a script element; escape HTML delimiters to prevent closing that element.
$encoded=(ConvertTo-Json -InputObject $payload -Depth 20 -Compress).Replace('<','\u003c').Replace('>','\u003e').Replace('&','\u0026')
$template=Get-Content -LiteralPath (Join-Path $assets 'report-template.html') -Raw
$mark=Get-Content -LiteralPath (Join-Path $assets 'python-runtime-auditor.svg') -Raw
$template=$template.Replace('<!--PROJECT_MARK-->',$mark.Replace('<svg ','<svg class="project-mark" aria-hidden="true" focusable="false" ').Trim())
$template=[regex]::Replace($template,'<!--ICON:([a-z0-9-]+)-->',{
    param($match)
    $icon=Get-Content -LiteralPath (Join-Path $assets ('icons/'+$match.Groups[1].Value+'.svg')) -Raw
    return $icon.Replace('<svg ','<svg class="icon" aria-hidden="true" focusable="false" ').Trim()
})
$iconLicense=Get-Content -LiteralPath (Join-Path $assets 'icons/tabler-license.txt') -Raw
$template=$template.Replace('<!--ICON_LICENSE-->',('<!-- Inline icons: Tabler Icons. '+$iconLicense.Replace('--','- -')+' -->'))
$html=$template.Replace('<!--AUDIT_DATA-->',$encoded)
$html | Set-Content -LiteralPath (Join-Path $report 'report.html') -Encoding utf8
$destination=Join-Path $report 'assets'
$null=New-Item -ItemType Directory -Path $destination -Force
foreach ($name in @('report.css','report.js','python-runtime-auditor.svg')) { Copy-Item -LiteralPath (Join-Path $assets $name) -Destination (Join-Path $destination $name) -Force }
Write-Host "Offline HTML report: $(Join-Path $report 'report.html')"
