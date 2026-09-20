@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo 方块漫游：WASD 或方向键移动
echo 即将打开两个玩家窗口。关闭两个窗口后自动结束。
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\play.ps1" -Game blocks %*
set "ROOMKIT_PLAY_EXIT=%ERRORLEVEL%"
if not "%ROOMKIT_PLAY_EXIT%"=="0" echo 启动失败，请查看 logs\play-stderr.log
pause
exit /b %ROOMKIT_PLAY_EXIT%
