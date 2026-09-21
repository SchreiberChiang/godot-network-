@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Manage.ps1" -Operation verify
set "result=%errorlevel%"
pause
exit /b %result%
