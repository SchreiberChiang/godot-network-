# M0 本机环境与启动入口

环境首次检测：2026-09-18；启动与权限说明更新：2026-09-19。工作目录 `F:\文档\GodotGame\Net\RoomKit`。

- 操作系统：Microsoft Windows NT 10.0.26200.0。
- Git：2.55.0.windows.3。起始目录不属于任何上级仓库；仅在本目录执行 `git init .`。
- Godot：`4.7.2.stable.steam.ed1daf0bf`，真实执行 `--version` 且等待退出，退出码 0。
- 路径：`D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`。
- 导出模板：该安装采用自包含 `editor_data/export_templates/4.7.2.stable`，已发现 Windows x86_64 debug/release 等模板。用户 AppData 默认模板目录为空。发现模板不等于导出验收通过。
- 不安装或升级引擎，不修改全局配置，不读取其它游戏或服务器。

根 `project.godot` 同时提供本轮宿主与脚本测试入口，以 `res://` 引用唯一 `schemas/`。房间以独立 Godot OS 进程运行，不加载主场景。分发 SDK、独立游戏工程模板和正式发布包留待后续阶段。

## 重复运行

在 PowerShell 执行：

```powershell
Set-Location 'F:\文档\GodotGame\Net\RoomKit'
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode unit
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode integration
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode demo
```

`-Mode launcher` 单独运行 Windows 身份及句柄回收专项。`-Mode all` 按 unit → launcher → integration → demo 执行。`-Godot '完整路径'` 可显式指定可执行文件，但不同版本须重新验证；当前清单锁定上述版本。

demo 自动创建一间房，收到至少四次心跳后有序停止并退出。无需游戏资源或客户端。成功信号为 `DEMO_PASS` 和 `ROOMKIT_EXIT mode=demo code=0`。

unit 成功信号为 `UNIT_RESULT passed=... failed=0`；integration 为 `INTEGRATION_RESULT passed=... failed=0`。每种模式同时要求 `ROOMKIT_EXIT mode=<模式> code=0`。启动脚本检查操作系统退出码、Godot 脚本错误和成功标记，不以进程创建成功替代测试通过。

该 Godot 使用 Windows GUI 子系统，`tools/run.ps1` 通过 `Start-Process -PassThru -WindowStyle Hidden` 启动并保留返回进程的句柄，调用 `WaitForExit(超时毫秒)` 后读取 ExitCode；integration/launcher 总超时为 240 秒，unit/demo 为 60 秒。超时仅对这个已持有句柄的宿主进程执行终止，不枚举和终止其它 Godot 进程。子进程另有控制断线/宿主失联退出政策。脚本没有使用 `-Wait` 隐式无限等待。

日志存放 `logs/`，机器可读房间记录为 `logs/integration-result.json`；临时私有启动配置放在 `run/`，成功认证后删除。两目录不进入 Git。控制 TCP 和 ENet UDP 只绑定 `127.0.0.1`。端口范围和超时位于 `config/development.json`；默认 UDP 为 28100–28131，TCP 为系统分配的空闲端口。demo 和集成测试用当前宿主的可执行文件覆盖开发配置的 Godot 路径；集成测试还会调整超时以运行故障用例。

## 环境事件与边界

2026-09-18 开发环境曾出现 Windows 沙箱 `setup refresh had errors`，部分升级权限检查被拒绝；另有普通沙箱下的 WMI/CIM 进程身份检查失败。这些失败保留为历史结果，没有算作通过，也没有修改全局沙箱设置。

2026-09-19 当前会话由环境提供无沙箱执行权限，运行本项目不再需要向工具申请权限升级。这一会话设置不代表其它电脑或终端拥有同样权限。正常本机使用应能读取自己启动的子进程信息，包括 `Get-CimInstance Win32_Process` 返回的可执行路径、父进程与命令行，并能给本项目 `run/` 设置当前用户 ACL；不要求预先以管理员身份启动。如果身份核验不可用，宿主返回 `PROCESS_IDENTITY_UNVERIFIED` 并保留隔离，不能绕过校验或按裸 PID 任意终止进程。

ProcessLauncher 当前同步调用 PowerShell 辅助程序。CIM 查询设有 3 秒操作超时，但辅助程序整体尚无独立总超时；异常慢的系统调用可能阻塞宿主主循环。`run.ps1` 的总 watchdog 是测试/演示入口保护，不能代替未来常驻宿主的异步进程管理与总超时实现。

2026-09-20 已使用同一精确引擎实际验证两名独立本机测试客户端经 WebSocket 大厅及 ENet 入房/退房；入口为 StartDemo.cmd 或 run.ps1 -Mode players。不能据此宣称 Linux、跨电脑、WSS/公网安全或正式发布就绪。实际测试和未运行项以 STATUS.md 为准。
