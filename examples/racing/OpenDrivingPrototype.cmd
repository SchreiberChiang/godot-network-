@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0prototype\launch.ps1" %*
exit /b %errorlevel%
