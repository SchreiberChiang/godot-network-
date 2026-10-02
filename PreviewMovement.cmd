@echo off
setlocal
set "ROOMKIT_PREVIEW_GODOT=D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
set "APPDATA=%~dp0data\preview-movement\appdata"
set "LOCALAPPDATA=%~dp0data\preview-movement\localappdata"
if not exist "%APPDATA%" mkdir "%APPDATA%"
if not exist "%LOCALAPPDATA%" mkdir "%LOCALAPPDATA%"
if not exist "%ROOMKIT_PREVIEW_GODOT%" (
  echo Godot development engine not found.
  pause
  exit /b 1
)
start "" "%ROOMKIT_PREVIEW_GODOT%" --path "%~dp0." --script res://tests/run_movement_preview.gd
