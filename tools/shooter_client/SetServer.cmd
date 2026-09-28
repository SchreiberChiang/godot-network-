@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0SetServer.ps1" %*
set "result=%errorlevel%"
if not "%result%"=="0" pause
exit /b %result%
