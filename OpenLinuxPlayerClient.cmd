@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\open_linux_player_client.ps1"
set "result=%errorlevel%"
if not "%result%"=="0" pause
exit /b %result%
