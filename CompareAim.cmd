@echo off
setlocal
set "ROOMKIT_PREVIEW_PROJECT=%~dp0."
set "ROOMKIT_PREVIEW_GODOT=D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
set "APPDATA=%ROOMKIT_PREVIEW_PROJECT%\data\preview-compare\appdata"
set "LOCALAPPDATA=%ROOMKIT_PREVIEW_PROJECT%\data\preview-compare\localappdata"
if not exist "%ROOMKIT_PREVIEW_GODOT%" (
  echo Godot 4.7.2 not found.
  pause
  exit /b 1
)
if not exist "%APPDATA%" mkdir "%APPDATA%"
if not exist "%LOCALAPPDATA%" mkdir "%LOCALAPPDATA%"
start "" "%ROOMKIT_PREVIEW_GODOT%" --path "%ROOMKIT_PREVIEW_PROJECT%" --script res://tests/run_aim_compare_preview.gd -- --candidate-label=dot
