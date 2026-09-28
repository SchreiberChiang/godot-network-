@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0CheckClient.ps1" %*
set "result=%errorlevel%"
pause
exit /b %result%
