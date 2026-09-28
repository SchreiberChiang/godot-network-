@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\prepare_player_client.ps1" %*
if errorlevel 1 (
  pause
  exit /b 1
)
explorer "%~dp0PlayerClient"
pause
