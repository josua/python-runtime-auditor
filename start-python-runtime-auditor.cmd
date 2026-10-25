@echo off
chcp 65001 >nul
set "runtimeAuditorPowerShell=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not exist "%runtimeAuditorPowerShell%" set "runtimeAuditorPowerShell=pwsh.exe"
"%runtimeAuditorPowerShell%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-python-runtime-auditor.ps1" -OpenReport %*
if errorlevel 1 echo Audit failed. Review the message above; existing scan results are retained.
pause
