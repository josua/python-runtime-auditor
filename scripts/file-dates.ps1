#requires -Version 7.2
function Get-RegisteredInstallDates {
    $records=[Collections.Generic.List[object]]::new()
    foreach ($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryHive]::LocalMachine)) {
        foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)) {
            $base=$null;$uninstall=$null
            try {
                $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
                $uninstall=$base.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall')
                if (-not $uninstall) { continue }
                foreach ($name in $uninstall.GetSubKeyNames()) {
                    $key=$null
                    try {
                        $key=$uninstall.OpenSubKey($name)
                        if (-not $key) { continue }
                        $raw=[string]$key.GetValue('InstallDate')
                        $location=[Environment]::ExpandEnvironmentVariables([string]$key.GetValue('InstallLocation')).Trim().Trim('"')
                        $date=[datetime]::MinValue
                        if (-not [datetime]::TryParseExact($raw,'yyyyMMdd',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)) { continue }
                        # Match only an explicit installation directory, never a version/name guess.
                        if (-not $location -or -not [IO.Path]::IsPathFullyQualified($location)) { continue }
                        $records.Add([pscustomobject]@{Root=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($location));
                            Date=$date.ToString('yyyy-MM-dd');Name=[string]$key.GetValue('DisplayName');
                            Source="$hive/$view/Software/Microsoft/Windows/CurrentVersion/Uninstall/$name : InstallDate + InstallLocation"})
                    } catch { Write-Verbose "Installation date unavailable: $_" }
                    finally { if ($key) { $key.Dispose() } }
                }
            } catch { Write-Verbose "Installation registration unavailable: $_" }
            finally { if ($uninstall) { $uninstall.Dispose() }; if ($base) { $base.Dispose() } }
        }
    }
    return $records.ToArray() | Sort-Object @{Expression={$_.Root.Length};Descending=$true},Source
}

function Get-ExecutableDates {
    param([Parameter(Mandatory)][string]$Path,[object[]]$Registrations=@(),$InventoryRow)
    $created=$null;$modified=$null;$metadataSource='Unavailable'
    if ($InventoryRow -and $InventoryRow.CreationTimeUtc) {
        $created=$InventoryRow.CreationTimeUtc;$modified=$InventoryRow.LastWriteTimeUtc;$metadataSource='Inventory scan'
    } else {
        # Older inventories can be enriched by stat-ing known paths, without another drive scan.
        try {
            $item=Get-Item -LiteralPath $Path -ErrorAction Stop
            $created=$item.CreationTimeUtc.ToString('o');$modified=$item.LastWriteTimeUtc.ToString('o')
            $metadataSource='Current filesystem metadata at analysis time'
        } catch { Write-Verbose "File dates unavailable for ${Path}: $_" }
    }
    $installation=$Registrations | Where-Object {
        $Path.StartsWith($_.Root+'\',[StringComparison]::OrdinalIgnoreCase)
    } | Sort-Object @{Expression={$_.Root.Length};Descending=$true},Source | Select-Object -First 1
    [pscustomobject]@{CreationTimeUtc=$created;LastWriteTimeUtc=$modified;FileDateSource=$metadataSource;
        RegisteredInstallDate=if ($installation) {$installation.Date} else {$null};
        InstallDateSource=if ($installation) {$installation.Source+' ('+$installation.Name+')'} else {$null}}
}
