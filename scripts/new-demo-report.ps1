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
Save-Json 'scan-summary.json' @{Completed=$true;DirectoriesVisited=125;ElapsedSeconds=0.2;Roots=@('C:\demo');IsSynthetic=$true;Scope='Synthetic demonstration; no filesystem was scanned'}
Save-Json 'audit-summary.json' @{ExecutablePaths=9;RuntimeFolders=3;VirtualEnvironments=1;Findings=1;IsSynthetic=$true}
Save-Json 'python-classification.json' $files
Save-Json 'runtime-folders.json' $runtimes
Save-Json 'base-runtime-dependencies.json' @(@{ResolvedBaseHome=$base;Accessible=$true;Environments=@($config)})
Save-Json 'command-resolution.json' @(@{Command='py';Priority=1;Type='Application';Source='C:\demo\shadow-bin\py'},@{Command='py';Priority=2;Type='Application';Source='C:\demo\manager\py.exe'})
Save-Json 'audit-findings.json' @(@{Code='empty-extensionless-command';Severity='warning';Path='C:\demo\shadow-bin\py';Message='Synthetic example: an empty file shadows the real launcher. Review the file and command routing before making changes.'})
Save-Json 'scan-issues.json' @(@{Path='C:\demo\protected';Operation='enumerate-directories';Reason='Synthetic example of an access-denied directory.'})
& (Join-Path $PSScriptRoot 'new-audit-report.ps1') -ReportDirectory $destination
