@echo off
setlocal
set "client=%~dp0PlayerClient\StartGame.cmd"
if not exist "%client%" (
  echo Player client not prepared. Run PreparePlayerClient.cmd first.
  pause
  exit /b 1
)
call "%client%"
exit /b %errorlevel%
