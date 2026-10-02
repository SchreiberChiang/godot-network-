@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\project_space.ps1" -IncludeUserData %*
set "roomkit_exit=%ERRORLEVEL%"
if not "%roomkit_exit%"=="0" echo Space check incomplete. Exit code: %roomkit_exit%
if "%~1"=="" pause
exit /b %roomkit_exit%
