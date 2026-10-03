@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0examples\racing\integration\launch.ps1" %*
set "result=%errorlevel%"
if not "%result%"=="0" pause
exit /b %result%
