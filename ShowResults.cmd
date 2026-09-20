@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\results.ps1" %*
set "ROOMKIT_RESULTS_EXIT=%ERRORLEVEL%"
pause
exit /b %ROOMKIT_RESULTS_EXIT%
