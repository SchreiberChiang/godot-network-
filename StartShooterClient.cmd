@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run_framework.ps1" -Mode client -Game shooter %*
if errorlevel 1 pause
