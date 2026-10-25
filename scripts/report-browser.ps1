#requires -Version 7.2
# Browser discovery reads registration and known locations; it does not launch candidates.
function Get-ReportBrowserKind {
    param([string]$Path)
    switch ([IO.Path]::GetFileName($Path).ToLowerInvariant()) {
        'msedge.exe' { return 'edge' }
        'brave.exe' { return 'brave' }
        'chromium.exe' { return 'chromium' }
        'chrome.exe' {
            if ($Path -match '(?i)chromium' -or
                [Diagnostics.FileVersionInfo]::GetVersionInfo($Path).ProductName -match '(?i)chromium') { return 'chromium' }
            return 'chrome'
        }
        'firefox.exe' { return 'firefox' }
        'vivaldi.exe' { return 'vivaldi' }
        'opera.exe' { return 'opera' }
    }
}

function ConvertFrom-BrowserCommand {
    param([string]$Command)
    $expanded=[Environment]::ExpandEnvironmentVariables($Command).Trim()
    if ($expanded -match '^"([^"]+\.exe)"(?:\s|$)') { return $Matches[1] }
    if ($expanded -match '^(.+?\.exe)(?:\s|$)') { return $Matches[1] }
}

function Get-ReportBrowsers {
    $found=[Collections.Generic.List[object]]::new()
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $names=@{edge='Microsoft Edge';chrome='Google Chrome';chromium='Chromium';brave='Brave';firefox='Firefox';vivaldi='Vivaldi';opera='Opera'}
    $priority=@{edge=0;chrome=1;chromium=2;brave=3;firefox=4;vivaldi=5;opera=6}
    function Add-BrowserCandidate([string]$Path,[string]$Source) {
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        $candidate=[Environment]::ExpandEnvironmentVariables($Path).Trim().Trim('"')
        if (-not [IO.Path]::IsPathFullyQualified($candidate) -or
            -not (Test-Path -LiteralPath $candidate -PathType Leaf)) { return }
        $candidate=[IO.Path]::GetFullPath($candidate)
        $kind=Get-ReportBrowserKind $candidate
        if (-not $kind -or -not $seen.Add($candidate)) { return }
        $mode=if ($kind -in @('edge','chrome','chromium','brave')) { 'app' } else { 'window' }
        $found.Add([pscustomobject]@{Name=$kind;DisplayName=$names[$kind];Path=$candidate;Mode=$mode;
            Version=[Diagnostics.FileVersionInfo]::GetVersionInfo($candidate).ProductVersion;Source=$Source;Priority=$priority[$kind]})
    }
    $executables=@('msedge.exe','chrome.exe','chromium.exe','brave.exe','firefox.exe','vivaldi.exe','opera.exe')
    foreach ($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryHive]::LocalMachine)) {
        foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)) {
            $baseKey=$null
            try {
                $baseKey=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
                foreach ($executable in $executables) {
                    $key=$baseKey.OpenSubKey("Software\Microsoft\Windows\CurrentVersion\App Paths\$executable")
                    if ($key) { try { Add-BrowserCandidate ([string]$key.GetValue('')) 'app-paths' } finally { $key.Dispose() } }
                }
                $clients=$baseKey.OpenSubKey('Software\Clients\StartMenuInternet')
                if ($clients) {
                    try {
                        foreach ($client in $clients.GetSubKeyNames()) {
                            $key=$clients.OpenSubKey("$client\shell\open\command")
                            if ($key) { try { Add-BrowserCandidate (ConvertFrom-BrowserCommand ([string]$key.GetValue(''))) 'registered-browser' } finally { $key.Dispose() } }
                        }
                    } finally { $clients.Dispose() }
                }
            } catch { Write-Verbose "Browser registration unavailable ($hive/$view): $_" }
            finally { if ($baseKey) { $baseKey.Dispose() } }
        }
    }
    $relativePaths=@(
        'Microsoft\Edge\Application\msedge.exe','Microsoft\Edge Beta\Application\msedge.exe','Microsoft\Edge Dev\Application\msedge.exe',
        'Microsoft\Edge SxS\Application\msedge.exe','Google\Chrome\Application\chrome.exe','Google\Chrome Beta\Application\chrome.exe',
        'Google\Chrome Dev\Application\chrome.exe','Google\Chrome SxS\Application\chrome.exe','Chromium\Application\chrome.exe',
        'BraveSoftware\Brave-Browser\Application\brave.exe','Mozilla Firefox\firefox.exe','Firefox Developer Edition\firefox.exe',
        'Vivaldi\Application\vivaldi.exe','Programs\Vivaldi\Application\vivaldi.exe','Opera\opera.exe','Programs\Opera\opera.exe'
    )
    foreach ($root in @($env:ProgramFiles,${env:ProgramFiles(x86)},$env:LOCALAPPDATA) | Where-Object { $_ } | Select-Object -Unique) {
        foreach ($relative in $relativePaths) { Add-BrowserCandidate (Join-Path $root $relative) 'known-location' }
    }
    foreach ($executable in $executables) {
        foreach ($command in @(Get-Command -Name $executable -CommandType Application -All -ErrorAction SilentlyContinue)) {
            Add-BrowserCandidate $command.Source 'path'
        }
    }
    return $found.ToArray() | Sort-Object Priority,Path
}

function Get-ReportBrowserPlan {
    param([Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)][string]$ReportPath,
        [Parameter(Mandatory)][string]$BrowserDataDirectory)
    # Uri handles spaces, Unicode, percent signs and # without corrupting the local filename.
    $url=([uri]::new($ReportPath)).AbsoluteUri
    $arguments=[Collections.Generic.List[string]]::new()
    $profile=$null;$cache=$null
    if ($Candidate.Mode -eq 'app') {
        # Separate channels/installations cannot open the same profile with incompatible versions.
        $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Candidate.Path.ToLowerInvariant()))).Substring(0,12).ToLowerInvariant()
        $browserRoot=Join-Path $BrowserDataDirectory ($Candidate.Name+'-'+$hash)
        $profile=Join-Path $browserRoot 'profile'
        $cache=Join-Path $browserRoot 'cache'
        foreach ($argument in @("--user-data-dir=$profile","--disk-cache-dir=$cache",'--disk-cache-size=67108864',
            '--disable-sync','--no-first-run','--no-default-browser-check','--disable-features=Translate',"--app=$url")) { $arguments.Add($argument) }
    } elseif ($Candidate.Name -eq 'firefox') {
        $arguments.Add('--new-window');$arguments.Add($url)
    } else { $arguments.Add($url) }
    [pscustomobject]@{Browser=$Candidate.Name;DisplayName=$Candidate.DisplayName;Executable=$Candidate.Path;
        Mode=$Candidate.Mode;ReportPath=$ReportPath;Url=$url;ProfileDirectory=$profile;CacheDirectory=$cache;Arguments=$arguments.ToArray()}
}

function Start-ReportBrowserProcess {
    param([Parameter(Mandatory)]$Plan)
    foreach ($directory in @($Plan.ProfileDirectory,$Plan.CacheDirectory) | Where-Object { $_ }) {
        $null=New-Item -ItemType Directory -Path $directory -Force
    }
    $startInfo=[Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName=$Plan.Executable
    $startInfo.WorkingDirectory=Split-Path $Plan.ReportPath -Parent
    $startInfo.UseShellExecute=$false
    # ArgumentList quotes Windows arguments; do not concatenate paths into a shell command.
    foreach ($argument in $Plan.Arguments) { $startInfo.ArgumentList.Add($argument) }
    $process=[Diagnostics.Process]::Start($startInfo)
    if (-not $process) { throw 'The browser process could not be started.' }
    try {
        if ($process.WaitForExit(1500) -and $process.ExitCode -ne 0) {
            throw "Browser exited immediately with code $($process.ExitCode)."
        }
        return $process.Id
    } finally { $process.Dispose() }
}

function Open-ReportBrowser {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$ReportPath,
        [ValidateSet('auto','edge','chrome','chromium','brave','firefox','vivaldi','opera','default')][string]$Browser='auto',
        [string]$BrowserPath,[Parameter(Mandatory)][string]$BrowserDataDirectory,
        [object[]]$Candidates=@(Get-ReportBrowsers))
    if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf) -or [IO.Path]::GetExtension($ReportPath) -notin @('.html','.htm')) {
        throw "HTML report not found: $ReportPath"
    }
    $resolvedReport=(Resolve-Path -LiteralPath $ReportPath).ProviderPath
    $resolvedData=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BrowserDataDirectory)
    if ($BrowserPath) {
        $resolvedBrowser=(Resolve-Path -LiteralPath $BrowserPath -ErrorAction Stop).ProviderPath
        $kind=Get-ReportBrowserKind $resolvedBrowser
        if (-not $kind -or ($Browser -notin @('auto',$kind))) { throw 'BrowserPath must point to a supported browser matching Browser.' }
        $Candidates=@([pscustomobject]@{Name=$kind;DisplayName=$kind;Path=$resolvedBrowser;
            Mode=if ($kind -in @('edge','chrome','chromium','brave')) { 'app' } else { 'window' };Priority=0})
    } elseif ($Browser -notin @('auto','default')) {
        $Candidates=@($Candidates | Where-Object Name -eq $Browser)
        if ($Candidates.Count -eq 0) { throw "Browser '$Browser' not found. Use -ListBrowsers or -BrowserPath." }
    }
    if ($Browser -ne 'default') {
        $ordered=@($Candidates | Sort-Object @{Expression={if ($_.Mode -eq 'app') {0} else {1}}},Priority,Path)
        foreach ($candidate in $ordered) {
            $plan=Get-ReportBrowserPlan -Candidate $candidate -ReportPath $resolvedReport -BrowserDataDirectory $resolvedData
            if (-not $PSCmdlet.ShouldProcess($candidate.Path,"Open report in $($candidate.Mode) mode")) { return $plan }
            try {
                Write-Host "Opening report: $($candidate.DisplayName) ($($candidate.Mode))"
                $browserProcessId=Start-ReportBrowserProcess $plan
                $plan | Add-Member -NotePropertyName ProcessId -NotePropertyValue $browserProcessId
                return $plan
            } catch {
                if ($Browser -ne 'auto' -or $BrowserPath) { throw }
                Write-Warning "Could not start $($candidate.DisplayName): $_ Trying the next browser."
            }
        }
    }
    $defaultPlan=[pscustomobject]@{Browser='default';DisplayName='Windows default HTML application';Executable=$null;
        Mode='default';ReportPath=$resolvedReport;Url=([uri]::new($resolvedReport)).AbsoluteUri;ProfileDirectory=$null;CacheDirectory=$null;Arguments=@()}
    if ($PSCmdlet.ShouldProcess($resolvedReport,'Open report with the Windows default HTML application')) {
        Write-Host 'Opening report with the Windows default HTML application (no app-mode guarantee).'
        $null=Start-Process -FilePath $resolvedReport -ErrorAction Stop
    }
    return $defaultPlan
}
