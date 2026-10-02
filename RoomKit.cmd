@echo off
setlocal
cd /d "%~dp0"
if errorlevel 1 exit /b 2
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File tools\roomkit.ps1 %*
exit /b %errorlevel%
