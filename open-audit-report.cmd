@echo off
chcp 65001 >nul
set "runtimeAuditorPowerShell=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not exist "%runtimeAuditorPowerShell%" set "runtimeAuditorPowerShell=pwsh.exe"
"%runtimeAuditorPowerShell%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0open-audit-report.ps1" %*
if errorlevel 1 (
  echo Could not open the report. Review the message above.
  pause
  exit /b 1
)
