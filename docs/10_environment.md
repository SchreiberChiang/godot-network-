# M0 本机环境与启动入口

<a id="linux-current"></a>
## Linux 现状速查（2026-10-01）

下文按日期保留安装与验收历史；旧条目“未连接/未安装”不代表现状。硬件/发行版沿用 Claude 记录；2026-10-01 Codex 复验重新核对的运行时、内核、可用资源和工具哈希见下方。

| 项目 | 当前记录与证据边界 |
|---|---|
| 设备 | zhao@192.168.10.105；Mint 22.3、x86_64、i5-5200U（2 核 4 线程）、7.7 GB RAM；IP/负载/空闲磁盘需运行前复查 |
| 主线引擎 | ~/roomkit/tools/godot/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64，official ed1daf0bf；不替换 |
| 正式存储运行时 | ~/roomkit/tools/pwsh/7.6.6/pwsh；系统 libsqlite3.so.0；不接实验扩展 |
| 主线源码/证据 | ~/roomkit/src/<快照>/、incoming/<运行号>/、runs/<运行号>/；库在该源码快照 data/，不用真实库 |
| 旁路实验 | ~/roomkit/experiments/sqlite-import-lab/；另一 AI 负责，最新仅报告准备补丁、未编译；本轮未进入核查 |
| Codex 独立复验 | codex-l2b1-7f1a0ba8-r2 已新建 incoming/src/runs 并完成；16 步失败 1 步（既有 unit），退出 1 |
| SSH | 保留主机指纹核验；历史 retry-02 经用户输入密码完成测试。本轮 `BatchMode=yes` 已成功认证，没有修改 SSH 或读取认证配置，不在聊天/文件保存密码 |
| L3 同机验收（10-01，Claude） | `20261001060258-bdccea`：45 步失败 1 步（60 分钟耐久 75/78 周期）。运行前系统盘 439G 已用 46G、内存可用约 5.8 GB；耐久时 6–8 客户端 CPU 常 93–100%（同机另有 sunshine、ZCode 等）。正式入口 `tools/roomkit_linux.sh`，实例在源码快照 `data/instance-l3/`，只绑 127.0.0.1；每轮新源码目录带 `-r<后缀>`。只读辅助：`tools/linux_progress.sh`、`tools/linux_fetch_evidence.sh`（`ssh … "bash -s" < 脚本`） |
| L3 独立复验（10-01，Codex） | `20261001203131-57358f`：C/D/E 功能通过，完整对局 47/0、60 分钟 82/82，自动备份两次成功，一次登录等待 1542 ms；原始 38 步因 HOME 目录项变化失败 1 步，退出 1，详见 docs/17。`20261001221221-79ad35` 新快照验证结果服务退出补修：集成 133/0、引用/回执 9/0、真实备份登录 13/0，退出 0，后台错误输出 0 |
| Windows → Linux LAN（10-01，Codex） | 同一提交 `572c356`，Windows 192.168.10.100（以太网）直连 Linux 192.168.10.105（wlp3s0）；最终 38/0、退出 0，含源码 SDK 与导出的 Client.exe 双人 WSS/DTLS 入退房；详细边界见 docs/17 的 linux-lan。未改防火墙或 TUN |
| 尚不支持的结论 | 不能声称公网、Linux 导出服务器包或其它发行版通过；跨机未做完整五分钟结算和长期耐久，不能用同机结果替代；不代表突发并发登录或长期部署可靠性 |

现场核查按需集中一次完成，不反复让用户输密码。主线核查只读共享工具与本次快照、进程元数据；不扫描实验和用户配置目录。实验源码哈希/补丁需要另行明确只读范围，本次先标待核实。未授权安装、sudo、SSH/防火墙修改、主线与实验并跑。

分工与下一步只看 [协作总览](17_framework_shooter_plan.md#coordination-current)。


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

## Linux 测试机：P 补测与原生 SQLite 原型（2026-09-30，Claude）

复用已安装的 Godot 4.7.2 和 PowerShell 7.6.6，没有安装系统包，没有用 sudo。新增的内容：
- 第三方扩展 godot-sqlite v4.9（MIT，内置 SQLite 3.51.0）：`~/roomkit/prototypes/godot-sqlite-v4.9/`，约 300 MB（包里带所有平台的库）。`addons.zip` 由用户在笔记本浏览器里从官方地址下载到 `~/Downloads`，脚本核对 SHA256 `95e91b72…7c2cb0` 后复制到 `~/roomkit/downloads/`。
- 源码快照：`~/roomkit/src/b9aa587e5a5d-worktree-a88b31b8b401/`，内容是提交 `b9aa587` 加未提交改动。
- 运行输出：`~/roomkit/runs/20260930135302-8e17ee/`，约 305 MB，因为每次运行的临时工程里带了一份扩展。

`~/roomkit` 合计约 1.2 GB。运行结束后没有残留进程。结果见 [docs/17 补测与原型结果](17_framework_shooter_plan.md#补测与原型结果claude2026-09-30未提交待-codex-复核)。

## Linux 测试机：L2-A 进程与权限（2026-09-30，Claude）

复用已安装的 Godot 4.7.2（official），没有安装任何东西，没有用 sudo。新增源码快照 `~/roomkit/src/b9aa587e5a5d-worktree-2503cedd7903/`（提交 `b9aa587` 加未提交改动，379 个文件）和运行输出 `~/roomkit/runs/20260930145153-ed5871/`（128 KB）。只启动了测试子程序和一个由脚本自己管理的哨兵 `sleep`，结束后没有残留进程。内核 7.0.0-34；测试时 1 分钟负载约 5.4。结果见 [docs/17 L2-A 结果](17_framework_shooter_plan.md#l2-a-结果claude2026-09-30未提交待-codex-复核)。

补修验收（同日）：同样复用已装 Godot 4.7.2 official（`ed1daf0bf`，所有权模块现在只接受这一提交），没有安装、没有 sudo。新增源码快照 `~/roomkit/src/b9aa587e5a5d-worktree-9ed0faa14705/`（379 个文件）、传入包 `~/roomkit/incoming/20260930152015-6c116e/` 和运行输出 `~/roomkit/runs/20260930152015-6c116e/`（168 KB）。引擎以运行目录下的 `process/` 为工作目录启动，测试不再调用 `stat`、`ln`，`mkfifo` 经所有权模块直接 exec。只启动测试子程序和脚本自管的哨兵 `sleep`，结束后无残留进程。测试时 1 分钟负载约 2.1。权限保护模块会拒绝经过符号链接的路径（包括祖先目录）；本机 `~/roomkit` 路径不含链接。结果见 [docs/17 L2-A 补修结果](17_framework_shooter_plan.md#l2-a-补修结果claude2026-09-30未提交待-codex-复核)。

## Linux 测试机：L2-B1 存储接入（2026-10-01，Claude）

复用已安装的 Godot 4.7.2 official 和 pwsh 7.6.6，没有安装、没有 sudo。四次运行：`~/roomkit/runs/20260930160333-dac463`、`20260930164826-d4d496`、`20260930165629-d50c6d`、`20260930171501-208b39`（最终，448 KB），对应源码快照在 `~/roomkit/src/b9aa587e5a5d-worktree-*`（每个约 385 个文件），传入包在 `~/roomkit/incoming/<运行号>/`。测试库在快照的 `data/l2b1-*` 下（服务只接受项目 `data/` 内的目录，每次约 592 KB，全部 700/600）。

- **宿主启动条件**：以 `trap '' PIPE` 忽略 SIGPIPE、`umask 022`（有意放宽，用来证明保护不依赖调用方 umask）启动；`ROOMKIT_PWSH` 指向 `~/roomkit/tools/pwsh/7.6.6/pwsh`；XDG 与 TMPDIR 指向各自的运行目录。
- **助手环境**：`posix_helper.gd` 在启动助手前设置 `DOTNET_EnableDiagnostics=0` 和 `POWERSHELL_DIAGNOSTICS_OPTOUT=1`，避免强杀的 pwsh 在临时目录留下 FIFO 和套接字。
- **只读环境核对**：`tools/linux_env_check.sh` 在验收前执行，核对共享工具与原始安装包是否一致、主线快照有无扩展、用户级目录和 `.godot` 是否共享、实验进程和资源占用。结论见 [docs/17](17_framework_shooter_plan.md#l2-b1-结果claude2026-10-01未提交待-codex-复核)。
- **核对时的机器状态**：4 核，内存 7.7 GB（可用约 5.1 GB，交换区已用 1.2 GB），磁盘可用 372 GB；桌面上有远程串流（sunshine）等程序占用 CPU。`~/roomkit` 中 experiments 1.6 GB、runs 311 MB、tools 320 MB、prototypes 300 MB、downloads 216 MB。

另外，本机 Windows 上有 WSL Ubuntu（内核 6.6.87.2）。用它加官方 Linux 调试模板可以在本地试跑 Linux 行为，这只是开发调试手段，不算验收证据。模板会忽略 `--script`，需要把目标测试设为打包工程的主循环来运行。

**超时补修验收（同日，Claude）**：同样复用已装依赖，没有安装、没有 sudo。新增源码快照 `~/roomkit/src/b9aa587e5a5d-worktree-1359779ebcdb/`（386 个文件）、传入包 `~/roomkit/incoming/20260930182509-d7d0cd/` 和运行目录 `~/roomkit/runs/20260930182509-d7d0cd/`。`tools/linux_env_check.sh` 已改用 Codex 收窄后的版本，不进入 `~/roomkit/experiments/` 和用户配置目录。开跑时负载 0.02，没有匹配的实验、编译、Godot 或 pwsh 进程；运行中没有持续监视。结果见 [docs/17 管道超时补修结果](17_framework_shooter_plan.md#管道超时补修结果claude2026-10-01未提交待-codex-复核)。

**绝对截止与预算补修验收（同日，Claude）**：同样复用已装依赖，没有安装、没有 sudo，环境核对沿用收窄版本。新增源码快照 `~/roomkit/src/b9aa587e5a5d-worktree-a5f135e32e43/`、传入包和运行目录 `20260930185629-ebc89a`。开跑时负载 1.0，内存可用约 5.2 GB，没有匹配的实验、编译、Godot 或 pwsh 进程；运行中没有持续监视。本机 WSL 另跑了一次旧代码副本做对照，只是开发环路。结果见 [docs/17](17_framework_shooter_plan.md#绝对截止与原子预算补修结果claude2026-10-01未提交待-codex-复核)。

## Linux 测试机：L2-B2 房间生命周期（2026-10-01，Claude）

复用已安装的 Godot 4.7.2 official，没有安装、没有 sudo，也没有用 pwsh。新增源码快照 `~/roomkit/src/b9aa587e5a5d-worktree-3f6049b0471a/`（388 个文件）、传入包 `~/roomkit/incoming/20260930193037-54ca61/` 和运行目录 `~/roomkit/runs/20260930193037-54ca61/`（308 KB）。房间运行目录是快照里的 `run/`（700），测试结束后只剩 `.gdignore`。房间子进程只在本机回环地址和 28100–28199 端口段上绑定 UDP，运行前后本用户在这个端口段上都没有 UDP 套接字；没有改防火墙。环境核对使用收窄版本（不进入实验目录）；开跑时没有匹配的实验、编译、Godot 或 pwsh 进程，运行中没有持续监视。结果见 [docs/17](17_framework_shooter_plan.md#l2-b2-第一小项结果linux-房间生命周期claude2026-10-01未提交待-codex-复核)。

## Linux 测试机：Operator 第一切片（2026-10-01，Claude）

复用已安装的 Godot 4.7.2 official 和 pwsh 7.6.6，没有安装、没有 sudo、没有改防火墙。共两轮，每轮都用全新的源码快照、运行目录和隔离目录：
- 第一轮 `~/roomkit/src/9d82d20b6e0f-worktree-78e346f46a6e/`、`~/roomkit/runs/20260930230000-20f6ae/`；
- 第二轮 `~/roomkit/src/9d82d20b6e0f-worktree-b3eb1ca8dfe8/`、`~/roomkit/runs/20260930232030-ec349a/`。

Operator 写出的所有内容（数据库、配置、TLS、游戏索引、宿主日志）都在快照的 `data/l2b3-<运行号>/` 里，目录 700、数据文件 600。管理面板只监听本机回环地址的 28391 端口；运行前后本用户在 28391、28300、28301 上都没有监听。启动方式为 `trap '' PIPE`、`umask 022`、`ROOMKIT_PWSH` 指向已装 pwsh，XDG 和 TMPDIR 指向运行目录。开跑时环境核对通过，没有实验、编译、Godot 或 pwsh 进程；运行中没有持续监视。结果见 [docs/17](17_framework_shooter_plan.md#linux-operator-第一切片结果claude2026-10-01未提交待-codex-复核)。

## Codex 独立 L2-B1 实机复验（2026-10-01）

运行号 codex-l2b1-7f1a0ba8-r2。内核 7.0.0-34-generic，Godot 4.7.2.stable.official.ed1daf0bf，pwsh 7.6.6 / .NET 10.0.12；开始时内存总量 7851 MB、可用约 5212 MB，磁盘可用 372 GB，负载 0.51/0.95/0.74。桌面还有 sunshine 等进程，不能称独占整机。

源码包哈希已匹配，共享 Godot 和 pwsh 启动程序与本地保留安装包一致；没有逐文件校验 pwsh 全目录。仅在新源码/运行目录写测试库、日志和缓存，未进入 experiments 或扫描用户 Godot 配置目录。收尾报告无 Godot/pwsh 残留，权限、请求文件和 FIFO/套接字扫描通过。结果及边界见 [协作总览](17_framework_shooter_plan.md#coordination-current)。这次复验后尚未安排实验重启。
