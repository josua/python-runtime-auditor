#requires -Version 7.2
[CmdletBinding()]
param([string]$OutputDirectory=(Join-Path (Split-Path $PSScriptRoot -Parent) 'output/demo'))
$ErrorActionPreference='Stop'
$destination=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$null=New-Item -ItemType Directory -Path $destination -Force
function Save-Json([string]$Name,[object]$Value) { ConvertTo-Json -InputObject $Value -Depth 12 | Set-Content -LiteralPath (Join-Path $destination $Name) -Encoding utf8 }
$base='C:\demo\python312';$venv='C:\demo\projects\art\.venv';$embedded='C:\demo\paint-studio\python'
$config=$venv+'\pyvenv.cfg'
$files=@(
    @{Path=$base+'\python.exe';Category='standalone-runtime';FileVersion='3.12.0';BaseHome=$null},
    @{Path=$base+'\pythonw.exe';Category='standalone-runtime';FileVersion='3.12.0';BaseHome=$null},
    @{Path=$venv+'\Scripts\python.exe';Category='virtual-environment';FileVersion='3.12.0';BaseHome=$base},
    @{Path=$venv+'\Scripts\pythonw.exe';Category='virtual-environment';FileVersion='3.12.0';BaseHome=$base},
    @{Path=$embedded+'\python.exe';Category='embedded-runtime';FileVersion='3.11.0';BaseHome=$null},
    @{Path='C:\demo\WindowsApps\python.exe';Category='alias';FileVersion=$null;BaseHome=$null},
    @{Path=$base+'\Lib\venv\scripts\nt\python.exe';Category='venv-template';FileVersion='3.12.0';BaseHome=$null},
    @{Path='C:\demo\manager\bin\python.exe';Category='launcher';FileVersion=$null;BaseHome=$null},
    @{Path='C:\demo\backups\python.exe';Category='backup';FileVersion='3.10.0';BaseHome=$null}
)
$runtimes=@(
    @{Root=$base;Category='standalone-runtime';Paths=2;FileVersions=@('3.12.0');ObservedDependentEnvironments=@($config);Executables=@($files[0].Path,$files[1].Path)},
    @{Root=$venv;Category='virtual-environment';Paths=2;FileVersions=@('3.12.0');ObservedDependentEnvironments=@();Executables=@($files[2].Path,$files[3].Path)},
    @{Root=$embedded;Category='embedded-runtime';Paths=1;FileVersions=@('3.11.0');ObservedDependentEnvironments=@();Executables=@($files[4].Path)}
)
for ($index=0;$index -lt $files.Count;$index++) {
    $files[$index].CreationTimeUtc=([datetime]::new(2026,10,1,12,0,0,[DateTimeKind]::Utc)).AddDays($index).ToString('o')
    $files[$index].LastWriteTimeUtc=$files[$index].CreationTimeUtc
    $files[$index].FileDateSource='Synthetic demonstration timestamp'
}
$files[0].RegisteredInstallDate='2026-10-01';$files[0].InstallDateSource='Synthetic installer registry example'
for ($index=0;$index -lt $runtimes.Count;$index++) {
    $runtimes[$index].FirstFileCreatedUtc=$files[$index*2].CreationTimeUtc
}
$runtimes[0].RegisteredInstallDate='2026-10-01';$runtimes[0].InstallDateSources=@('Synthetic installer registry example')
$storeRoot='C:\demo\WindowsApps\PythonSoftwareFoundation.Python.3.12_demo'
$files+=@{Path=$storeRoot+'\python3.12.exe';Category='standalone-runtime';FileVersion='3.12.10';CreationTimeUtc='2026-10-25T14:37:19Z';BaseHome=$null}
$runtimes+=@{Root=$storeRoot;Category='standalone-runtime';Paths=1;FileVersions=@('3.12.10');DisplayName='Python 3.12.10 · Microsoft Store';FirstFileCreatedUtc='2026-10-25T14:37:19Z';RegisteredInstallDate=$null;ObservedDependentEnvironments=@();Executables=@($storeRoot+'\python3.12.exe')}
Save-Json 'scan-summary.json' @{Completed=$true;DirectoriesVisited=125;ElapsedSeconds=0.2;Roots=@('C:\demo');IsSynthetic=$true;Scope='Synthetic demonstration; no filesystem was scanned'}
Save-Json 'audit-summary.json' @{ExecutablePaths=$files.Count;RuntimeFolders=$runtimes.Count;VirtualEnvironments=1;Findings=1;IsSynthetic=$true}
Save-Json 'python-classification.json' $files
Save-Json 'runtime-folders.json' $runtimes
Save-Json 'base-runtime-dependencies.json' @(@{ResolvedBaseHome=$base;Accessible=$true;Environments=@($config)})
Save-Json 'command-resolution.json' @(@{Command='py';Priority=1;Type='Application';Source='C:\demo\shadow-bin\py'},@{Command='py';Priority=2;Type='Application';Source='C:\demo\manager\py.exe'})
Save-Json 'audit-findings.json' @(@{Code='empty-extensionless-command';Severity='warning';Path='C:\demo\shadow-bin\py';Message='Synthetic example: an empty file shadows the real launcher. Review the file and command routing before making changes.'})
Save-Json 'scan-issues.json' @(@{Path='C:\demo\protected';Operation='enumerate-directories';Reason='Synthetic example of an access-denied directory.'})
$packageFixtures=@(
    @{Root=$base;Name='pip';Version='25.0';Bytes=8388608;Description='Python package installer'},
    @{Root=$base;Name='torch';Version='2.7.0';Bytes=2684354560;Description='Tensor computation with GPU acceleration'},
    @{Root=$venv;Name='open-webui';Version='0.6.0';Bytes=75497472;Description='Example web interface installation in a project environment'},
    @{Root=$venv;Name='torch';Version='2.6.0';Bytes=2415919104;Description='A different version in this environment'},
    @{Root=$venv;Name='transformers';Version='4.51.0';Bytes=136314880;Description='Model inference and training utilities'},
    @{Root=$venv;Name='peft';Version='0.15.0';Bytes=5242880;Description='Parameter-efficient fine-tuning'},
    @{Root=$embedded;Name='numpy';Version='1.26.0';Bytes=41943040;Description='Example bundled application dependency'},
    @{Root=$embedded;Name='custom-tools';Version='1.0';Bytes=$null;Description='Legacy package without a RECORD estimate'}
)
$demoPackages=@(foreach ($fixture in $packageFixtures) {
    $site=$fixture.Root+'\Lib\site-packages'
    @{
        EnvironmentId=$fixture.Root;EnvironmentRoot=$fixture.Root;Scope='runtime'
        Name=$fixture.Name;Version=$fixture.Version;Summary=$fixture.Description
        RequiresDist=$(if ($fixture.Name -eq 'open-webui') {@('transformers>=4.0','torch>=2; extra == "local"')} else {@()})
        SitePackages=$site;MetadataPath=$site+'\'+$fixture.Name.Replace('-','_')+'-'+$fixture.Version+'.dist-info\METADATA'
        MetadataKind='dist-info';MetadataStatus='read';EstimatedBytes=$fixture.Bytes
        SizeCoverage=$(if ($null -eq $fixture.Bytes) {'unavailable'} else {'partial'});RecordedFiles=100;FilesWithDeclaredSize=$(if ($null -eq $fixture.Bytes) {0} else {99})
    }
})
$demoEnvironments=@(foreach ($runtime in $runtimes) {
    $local=@($demoPackages | Where-Object EnvironmentId -eq $runtime.Root)
    @{Id=$runtime.Root;Root=$runtime.Root;Scope='runtime';Category=$runtime.Category;PackageCount=$local.Count;PackagesWithSize=@($local | Where-Object {$null -ne $_.EstimatedBytes}).Count;LocationsScanned=1;Issues=0}
})
Save-Json 'python-packages.json' $demoPackages
Save-Json 'package-environments.json' $demoEnvironments
Save-Json 'package-locations.json' @(foreach ($runtime in $runtimes) { @{EnvironmentId=$runtime.Root;Path=$runtime.Root+'\Lib\site-packages';Status='scanned';Packages=@($demoPackages | Where-Object EnvironmentId -eq $runtime.Root).Count} })
Save-Json 'package-issues.json' @()
Save-Json 'package-summary.json' @{SchemaVersion=1;Packages=$demoPackages.Count;Environments=$runtimes.Count;LocationsScanned=$runtimes.Count;Issues=0;IsSynthetic=$true}
& (Join-Path $PSScriptRoot 'new-audit-report.ps1') -ReportDirectory $destination
