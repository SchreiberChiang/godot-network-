@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run.ps1" %*
set "ROOMKIT_EXIT=%ERRORLEVEL%"
pause
exit /b %ROOMKIT_EXIT%
