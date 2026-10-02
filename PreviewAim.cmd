@echo off
setlocal
set "ROOMKIT_PREVIEW_GODOT=D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
set "ROOMKIT_PREVIEW_STATE=%~dp0data\preview-aim"
set "APPDATA=%ROOMKIT_PREVIEW_STATE%\appdata"
set "LOCALAPPDATA=%ROOMKIT_PREVIEW_STATE%\localappdata"
if not exist "%APPDATA%" mkdir "%APPDATA%"
if not exist "%LOCALAPPDATA%" mkdir "%LOCALAPPDATA%"
if not exist "%ROOMKIT_PREVIEW_GODOT%" (
  echo Godot 4.7.2 not found. This preview uses the local development engine.
  pause
  exit /b 1
)
start "" "%ROOMKIT_PREVIEW_GODOT%" --path "%~dp0." --script res://tests/run_aim_preview.gd
