@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run_framework.ps1" -Mode stop %*
if errorlevel 1 pause
