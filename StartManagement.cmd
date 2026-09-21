@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run_framework.ps1" -Mode panel %*
if errorlevel 1 pause
