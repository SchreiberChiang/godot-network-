@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo RoomKit - 两人本地联机自动演示
echo 正在启动大厅、房间和两名测试玩家，请等待测试结果。
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run.ps1" -Mode players
set "ROOMKIT_DEMO_EXIT=%ERRORLEVEL%"
echo.
if not "%ROOMKIT_DEMO_EXIT%"=="0" (echo 演示失败，请查看 logs\players-console.log) else (echo 演示通过：两名玩家已入房、退房，房间和端口已回收。)
pause
exit /b %ROOMKIT_DEMO_EXIT%
