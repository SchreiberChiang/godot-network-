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

2026-09-21 M4：实际加载C:\Windows\System32\winsqlite3.dll，查询版本3.51.1。无需下载DLL、额外数据库服务或更改全局配置。tools/protect_data.ps1仅在本项目data/设置当前用户ACL并拒绝越界/重解析目录。数据库、备份和签名outbox全部排除Git。同步PowerShell助手的busy_timeout=1500ms不包含进程启动/编译及全部系统调用；测试总超时不能代替常驻宿主的异步存储和总时限。Linux存储适配未实现。

2026-09-18 开发环境曾出现 Windows 沙箱 `setup refresh had errors`，部分升级权限检查被拒绝；另有普通沙箱下的 WMI/CIM 进程身份检查失败。这些失败保留为历史结果，没有算作通过，也没有修改全局沙箱设置。

2026-09-19 当前会话由环境提供无沙箱执行权限，运行本项目不再需要向工具申请权限升级。这一会话设置不代表其它电脑或终端拥有同样权限。正常本机使用应能读取自己启动的子进程信息，包括 `Get-CimInstance Win32_Process` 返回的可执行路径、父进程与命令行，并能给本项目 `run/` 设置当前用户 ACL；不要求预先以管理员身份启动。如果身份核验不可用，宿主返回 `PROCESS_IDENTITY_UNVERIFIED` 并保留隔离，不能绕过校验或按裸 PID 任意终止进程。

ProcessLauncher 当前同步调用 PowerShell 辅助程序。CIM 查询设有 3 秒操作超时，但辅助程序整体尚无独立总超时；异常慢的系统调用可能阻塞宿主主循环。`run.ps1` 的总 watchdog 是测试/演示入口保护，不能代替未来常驻宿主的异步进程管理与总超时实现。

2026-09-20 已使用同一精确引擎实际验证两名独立本机测试客户端经 WebSocket 大厅及 ENet 入房/退房；入口为 StartDemo.cmd 或 run.ps1 -Mode players。不能据此宣称 Linux、跨电脑、WSS/公网安全或正式发布就绪。实际测试和未运行项以 STATUS.md 为准。
# 2026-09-21 本轮实测补充

实际工作目录仍为F:\文档\GodotGame\Net\RoomKit，当前执行环境无文件沙箱限制；没有修改全局Git、Codex或系统证书配置。Git2.55.0.windows.3，Windows10.0.26200。使用原Godot4.7.2 Steam编辑器及同安装目录的4.7.2 official Windows/Linux模板，未升级或下载引擎。系统winsqlite3.dll实测3.51.1。

Windows正式模板已经运行真实宿主/房间/客户端及十轮进程句柄检查；Linux模板在已安装WSL Ubuntu（内核6.6.87.2-microsoft-standard-WSL2、x86_64）通过215项协议/准入/玩法检查。Linux没有本项目进程/数据库适配，不能算Linux完整宿主通过。可重复入口见docs/15和STATUS。

## 待验收的第二台设备（用户提供，2026-09-27）

- 设备：一台 Linux 笔记本；局域网 SSH 目标 `zhao@192.168.10.105`。
- 这是用户提供的连接信息，尚未连接；发行版、CPU 架构、Godot/导出环境、防火墙和实际客户端运行能力均未知。局域网地址可能变化，使用前需重新确认。
- 预定用途：以后做第二台实体设备的局域网联机验收。当前 Windows 宿主的账号/资产存储依赖 PowerShell 与 `winsqlite3.dll`，不能据此把 Linux 笔记本当作已经可运行完整宿主。
- 用户本轮要求暂缓验证；未执行 SSH 命令，也未在这台设备安装或修改任何东西。

## Linux 测试机只读检查（2026-09-30，Claude）

用户本人确认主机指纹并输入密码后，运行了 `tools/linux_device_check.sh`；脚本跑到末尾，原始输出在 `logs/linux-device-check/check-20260930.txt`。只读取了信息，没有安装、写入或复制任何东西。完成标记只表示脚本跑完；下面逐项写明是成功读到、没有找到，还是因为权限没有读取。

| 项目 | 结果 | 状态 |
|---|---|---|
| 系统 | Linux Mint 22.3（基于 Ubuntu），内核 7.0.0-34，glibc 2.39 | 已读到 |
| 架构 | x86_64 | 已读到 |
| CPU | Intel i5-5200U，2 核 4 线程；检查时负载约 1.9 | 已读到 |
| 内存 | 共 7.7 GB，可用约 5.3 GB；交换分区 2 GB，已用约 0.9 GB | 已读到 |
| 磁盘 | 根分区 ext4，439 GB，可用 378 GB；主目录和 `/tmp` 在同一分区 | 已读到 |
| 用户 | `zhao`，属于 `sudo` 组；主目录权限 750，umask 0002；最多打开 1024 个文件 | 已读到（sudo 没有调用） |
| systemd 用户服务 | 在运行；Linger 为 no，也就是用户退出登录后用户服务会停止 | 已读到 |
| 进程信息 | 内核支持 pidfd；`/proc` 的 stat 和 exe 可读；pid_max 为 4194304 | 已读到 |
| Godot | PATH 和约定目录里都没有；没有导出模板 | 没有找到 |
| PowerShell 7（pwsh） | 没有 | 没有找到 |
| dotnet | 没有（不需要，pwsh 自带运行时） | 没有找到 |
| pwsh 依赖的系统库 | libicu 74、libssl 3 都在 | 已读到 |
| SQLite | `libsqlite3.so.0`（文件名 0.8.6）在系统库目录；具体 SQLite 版本没有查；没有 `sqlite3` 命令行 | 库已读到，版本未知 |
| 网络 | 无线网卡 `wlp3s0`，192.168.10.105/24，网关 192.168.10.1 | 已读到 |
| 防火墙 | ufw 在运行；规则需要 root，没有读取 | 状态已读到，规则未知 |
| RoomKit 默认端口 | 28291、28300、28301、28400–28431 都没有被占用 | 已读到 |
| 工具 | bash 5.2、tar、unzip、curl、wget、git 2.43、python3 3.12、openssl 3.0、sha256sum 都在 | 已读到 |
| Node | 脚本没有检查 | 未知 |
| 区域 | zh_CN.UTF-8 | 已读到 |

## Linux 测试机依赖安装（2026-09-30，Claude）

用户同意后，只在 `~/roomkit/` 内安装。没有用 sudo，没有改 PATH、登录配置或防火墙，没有常驻服务，没有复制真实数据。原始输出在 `logs/linux-setup/run-20260930121157-ab0563.txt`；第一次尝试在 `logs/linux-setup/run-20260930114137-46a6c3.txt`，那次因为笔记本连不上 GitHub，停在下载这一步，没有安装任何东西。

| 项目 | 位置 | 版本与校验 |
|---|---|---|
| Godot | `~/roomkit/tools/godot/4.7.2-stable/`（140 MB） | `4.7.2.stable.official.ed1daf0bf`，与 Windows 是同一个提交；压缩包与官方 `SHA512-SUMS.txt` 一致 |
| PowerShell | `~/roomkit/tools/pwsh/7.6.6/`（180 MB） | 7.6.6 Core，.NET 10.0.12；7.6.6 是官方元数据里标注的当前 LTS；压缩包与官方 `hashes.sha256` 一致 |
| 源码 | `~/roomkit/src/c96e848b7b216ec1273edf77cca9e94155fe6e11/`（5.9 MB，360 个文件） | 本地提交 `c96e848` 的 `git archive`，全部是 LF 换行；传输包 SHA256 为 `df5b6e8b35bf0867a95f82b0460842714861d1372e6efab81c86ceb58f3e6f89`，两端一致 |
| 安装包原件 | `~/roomkit/downloads/` | 用户在笔记本浏览器里从官方地址下载 |
| 运行输出 | `~/roomkit/runs/20260930121157-ab0563/` | 引擎和 pwsh 的配置、缓存、临时文件都重定向到这里 |

补查到：Node v18.19.1（系统已有）；系统 SQLite 3.45.1。`~/roomkit` 合计 485 MB。笔记本不能直接访问 GitHub（curl 连接超时）。

## Linux 测试机 L1 存储切片（2026-09-30，Claude）

复用已安装的 PowerShell 7.6.6，没有新安装任何东西。新增源码目录 `~/roomkit/src/c96e848b7b21-worktree-1b02768baf5e/`，内容是本地提交 `c96e848` 加未提交改动的工作区快照，共 366 个文件。运行输出在 `~/roomkit/runs/20260930124548-a50b91/`。系统 SQLite 库是 `/lib/x86_64-linux-gnu/libsqlite3.so.0`，版本 3.45.1，由存储脚本实际加载。测试数据全部是新生成的假账号和假资产，目录权限 700、数据库 600。结果见 [docs/17 L1 存储切片结果](17_framework_shooter_plan.md#l1-存储切片结果claude2026-09-30未提交待-codex-复核)。
