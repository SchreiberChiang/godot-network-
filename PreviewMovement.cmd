@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\movement_preview.ps1" %*
set "ROOMKIT_PREVIEW_EXIT=%ERRORLEVEL%"
if not "%ROOMKIT_PREVIEW_EXIT%"=="0" pause
exit /b %ROOMKIT_PREVIEW_EXIT%
