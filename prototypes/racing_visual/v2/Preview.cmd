@echo off
setlocal
py -B "%~dp0open_preview.py"
if errorlevel 1 pause
endlocal
