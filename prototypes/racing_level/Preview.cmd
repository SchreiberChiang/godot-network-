@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Preview.ps1" %*
exit /b %errorlevel%
