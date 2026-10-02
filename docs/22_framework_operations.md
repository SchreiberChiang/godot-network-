# 当前分支的本机启动与验证

当前主线为 main，规格见 docs/17，测试证据见 STATUS。这里说明现有入口，不把代码已编写等同于发布验收通过。

## 配套交付与离线更新

构建机的 `PrepareDeployment.cmd` 默认生成 Linux 服务端与匹配的 Windows 玩家目录；`-ServerPlatform Windows` 改为 Windows 服务端。`OpenDeployment.cmd` 打开最近的干净目录。目标机启动、玩家 `SetServer.cmd` 配置和 Linux `UpdateRoomKit.sh` 更新流程见 [首版交付](17_framework_shooter_plan.md#deployment-stage-result)；准备依赖需显式使用下面的入口，构建和更新不会操作运行服务。目录用途见 [根目录说明](01_scope_architecture.md#root-folders)。

配对及拒绝专项：`powershell -NoProfile -ExecutionPolicy Bypass -File tests/test_deployment_pair.ps1 -DeploymentDirectory <本机新生成的干净目录>`。仅接受本工作区 `artifacts` 中未运行的目录，用后恢复自己注入的文件；不运行服务。Linux 更新工具专项为 `tests/test_linux_package_update.ps1`（真实 pwsh/SQLite、假包）；真实导出包更新驱动 `tests/test_linux_deployment_integration.ps1 -Stage Seed|Verify -ContextPath <显式准备清单>` 只接受专用测试目录和端口，私有准备清单不随 Git 分发，不能对正式服务使用。

<a id="environment-and-retention"></a>
## 依赖准备与生成物保留（2026-10-02）

Windows 源码用 `CheckEnvironment.cmd` 只读检查；导出 Windows 包用自己的 `CheckFramework.cmd`。Linux 源码或导出包在各自根目录执行：

```bash
bash PrepareEnvironment.sh check                 # 默认行为；不联网、不安装、不启动服务
bash PrepareEnvironment.sh prepare               # 显式下载固定官方归档，验证哈希后准备
```

源码需要编辑器 Godot 4.7.2 和 pwsh 7.6.6；Linux 导出服务器已经带引擎，只补缺少的 pwsh。检测先用显式 ROOMKIT_GODOT/ROOMKIT_PWSH，再用项目 `artifacts/environment/tools`，最后兼容原 `~/roomkit/tools`。显式路径不兼容时拒绝，不悄悄替换。系统 SQLite/ICU/OpenSSL 不由脚本安装，缺少则报告；需要系统安装时另按机器环境处理。

不能联网时，从官方取得以下归档，在目标机用绝对路径导入；源码同时给两个，导出包只给 pwsh：

```bash
bash PrepareEnvironment.sh prepare --offline \
  --godot-archive /绝对路径/Godot_v4.7.2-stable_linux.x86_64.zip \
  --pwsh-archive /绝对路径/powershell-7.6.6-linux-x64.tar.gz
# 导出包：去掉 --godot-archive 那一行，再运行 CheckPackage.sh
```

脚本内固定官方 SHA256，校验全部所需原包后才安装到项目目录；错误哈希、链接/越界、重复参数或覆盖已存在的不兼容目标拒绝。Mint 导出包和 WSL2 源码的实际离线准备已通过；在线下载和任意新系统没有因此被算通过。

生成物保留由 `tools/artifact_retention.ps1` 登记，默认 **每个用途最近两份**。清除大目录后轻量记录仍在 `artifacts/retention-ledger/`，包含结果、文件清单/大小/哈希与删除或跳过原因。最新成功交付、当前指针和必要输入保护；两个失败版本不会挤掉最后可用版本。内容改变、链接、活跃进程、Git 源文件或无法确认安全时跳过。旧未登记目录不自动接管，真实账号库、业务备份及测试源码/夹具不删。

隔离入口只自动管理 `data/` 直属、名字以 `test-`、`isolated-`、`acceptance-` 或 `retention-test-` 开始的新目录。先登记所有权，再运行；确认进程退出后登记该测试用途的结果和 stdout/stderr 哈希。其它历史命名仍兼容，但提示未纳入自动保留。例子（使用一个尚不存在的绝对路径，按本次运行改名）：

```powershell
$isolated = Join-Path (Get-Location) 'data/test-grant-review-001'
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_isolated_test.ps1 -Script tests/run_grant_recycling.gd -Isolation $isolated -Log (Join-Path $isolated 'grant')
powershell -NoProfile -ExecutionPolicy Bypass -File tests/test_artifact_retention.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/test_isolated_runner.ps1
```

授权专项使用预填数据和测试时钟，不真的开 256 房或等七天。涉及真实服务的 `run_grant_control_loss.gd` 还须显式隔离数据/索引/公开目录与非正式面板参数，按隔离入口校验准备，不能直接裸运行。测试结果与边界见 [阶段交付](17_framework_shooter_plan.md#stage6-result)。

## 源码运行

Linux 同机的最终结果、原始失败和退出补修见 [备份等待收尾](17_framework_shooter_plan.md#l3-backup-wait)；Windows → Linux 的独立局域网验收、专用客户端与端口见 [跨机试玩](17_framework_shooter_plan.md#linux-lan)。

Linux 导出服务器普通目录的构建、依赖、启停与自动验收见 [独立目录](17_framework_shooter_plan.md#linux-server-directory)。构建入口 `tools/build_linux_server.ps1`，包内入口 `CheckPackage.sh`、`RoomKit.sh`。专项 `tests/test_linux_server_package.ps1 -ContextPath <本机显式准备清单> -FullRound` 会新建假数据，使用固定隔离端口，不接受旧实例；清单与构建产物在忽略目录，不能直接对真实服务运行。业务由源码 SDK 客户端验证，真实 Client.exe 的入退房另列结果。

本机独立包真人入口为 **PlayLinuxPackage.cmd**，结束用 **StopLinuxPackage.cmd**；三步说明、固定实例与凭据位置见 [独立包试玩](17_framework_shooter_plan.md#linux-package-playtest)。入口防护专项：`powershell -NoProfile -ExecutionPolicy Bypass -File tests/test_linux_package_entry.ps1`，只创建假工程，不运行引擎/远端服务；测试期间本地 28691 必须空闲。

Windows 需要 Godot 4.7.2；默认路径是 `D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`。不需要 Node、外部数据库服务或旧项目。脚本参数 `-Godot` 可以指定另一个引擎路径，但更换版本后应重新验证。

1. 双击仓库根目录 **StartManagement.cmd**。脚本从当前仓库生成独立游戏工程并启动管理服务，然后打开回环网页。默认网页地址为 http://127.0.0.1:28291/。
2. 首次创建管理员账号。管理员只能管理后台，不能作为游戏玩家入房。
3. 点击“启动服务器”。管理服务负责生成私有凭据并启动独立宿主，页面会显示宿主、房间和玩家状态。
4. 在邀请码页创建邀请码。双击 **StartShooterClient.cmd**，用邀请码注册新的玩家账号并登录。启动第二个客户端，用另一个账号登录；同一个玩家账号不能重复占用会话。
5. 在后台或玩家大厅创建射击房间。进入后左右移动/跳跃，鼠标瞄准射击；两名玩家开始自由混战。后台创建表单可设每局时长、获胜击杀数和复活等待，默认五分钟、击杀不限、等待三秒；已有房间点击“规则 / 重建”。[设置与更新说明](25_shooter_room_rules.md)。初始基础步枪免费，后台可给测试账号发金币。
6. 在大厅或死亡期间打开背包，先解锁，再单独选为默认配置。死亡等待达到房间设置且此前资产请求已确认后才可手动复活。存活时服务端拒绝购买和配置变更。
7. **StartManagedTurns.cmd** 打开取石子客户端。它使用同一账号/钱包/所有权/默认配置服务，项目只定义经典/玉石主题及大厅可选用的规则。
8. 面板“停止服务器”默认公告六十秒后停止，期间拒绝新入房；“立即停止”要确认。它只停游戏宿主，不关闭管理网页。**StopManagement.cmd** 请求关闭整个管理服务及其宿主。

### 双击客户端后没看到窗口

2026-09-26已修复源码启动器将玩家窗口设为隐藏的问题。正常启动会显示标题含“RoomKit · 零号仓库”的登录窗口；如果在其它窗口后面，用任务栏或 `Alt+Tab` 切过去。先在后台开服并生成邀请码，再点客户端“没有账号？使用邀请码注册”，注册玩家账号后登录。管理员账号不能直接作为玩家登录。

启动器现在为每次启动保存 `logs/client-starts/shooter-<编号>/`（取石子为 `turns-<编号>`）下的 `engine.log`、`console.log` 和 `stderr.log`；等待可见窗口出现后才报告成功。缺少文件、程序提前退出或窗口未出现时会报错，CMD保留错误供查看。此启动检查只证明窗口出现，不代表已登录或联机通过。

命令行等价入口（在当前项目目录）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_framework.ps1 -Mode panel
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_framework.ps1 -Mode client -Game shooter
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_framework.ps1 -Mode client -Game turns
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_framework.ps1 -Mode stop
```

`StartPanel.cmd`、`StartPlay.cmd`、`StartTurns.cmd` 保留原无账号演示。它们与本分支管理服务是不同入口，不能用旧演示测试代替新账号/射击验收；说明见 [早期入口](archive/early_entrypoints.md)。

## 数据与维护

默认私有目录为 `data/framework/`：accounts.sqlite 保存账号/会话/邀请码，assets.sqlite 保存资产/操作流水/成绩与结果授权，config.json 保存配置，server.key 是私钥。私有文件不进入 Git、玩家分发包或日志。当前单管理员本机后台不对外网监听。

后台可查看账号，重置密码、停用、恢复、踢下线，以及在测试阶段永久删除玩家账号（见下文）；修改资产需要原因，购买、选用、授权和撤销分别记录。金币和经验调整有上下限，不能通过后台执行任意 SQL 或 shell。等级根据经验计算。首次注册没有测试金币。

只有停止游戏宿主后才能切换资产空间。独立和 shared 是不同的已命名空间；切换保留原空间数据，不复制、不合并。即使共享钱包，两款游戏的默认配置仍分别保存。实际房间服只能取得经过确认的配置，客户端不能上传武器属性。

后台默认每三十分钟备份，保留四十八份自动备份；手动和恢复前备份另存。恢复必须停服，先做恢复前备份，校验后恢复，全部账号会话失效，需要重新登录。不要直接替换运行中的 SQLite 文件。无法证明旧进程退出或旧端口空闲时保留 RECOVERY_REQUIRED，不按旧 PID 强杀进程。

宿主发生异常后先确认旧房间退出与端口回收，再尝试重启，十分钟最多三次。重新启动前清理旧玩家会话，玩家可再次登录，管理员会话保留；恢复整个备份会使管理员会话也失效。未完成的对局不续赛。主动停服不自动拉起。这里只管理本项目进程，不是全系统服务管理器。

### 删除测试账号

“玩家 → 详情 → 删除测试账号”永久删除该玩家在当前账号库和资产库中的账号与全部游戏资产，不可恢复；它和“停用账号 / 恢复账号”是两个独立操作。对话框会列出可能仍含该账号的旧备份，要求输入用户名、勾选确认，发送前再确认一次。操作原因里不要写用户名等可识别信息。完成后提示中给出匿名代号、清除的资产空间与回执数、仍提及该玩家的残留文件，以及旧备份清单。

如果提示“删除未完成”，说明删除还没有做完，不能当作已删除：可能是数据库没删完（账号保持停用、无法登录），也可能数据库已删完、只差管理服务改写自己的审计文件和记录备份清单（例如审计文件被设为只读或磁盘写入失败）。在同一对话框再次提交，或对仍在列表里的账号点“继续删除测试账号”即可；重启管理服务也会在启动时自动完成。操作原因里即使写了用户名或 user_id，也会被换成匿名代号。删除进行中，手动备份、恢复和配置保存会提示稍后再试。

旧备份不会被改写。“备份与恢复”页对早于某次删除的备份标注“可能含 N 个”，恢复这类备份会把已删除的账号和资产带回来；如需彻底清除，要在恢复后再删一次，或者删除这些备份文件（后者需人工决定）。复制到项目以外的备份不在后台管理范围内。

### 常驻存储与回退开关

管理服务启动后，会为账号库和资产库各启动一个常驻存储进程（`powershell.exe … storage_worker.ps1`，每个约 0.1 GB 内存），用于资产读取、购买、选择和会话校验；空闲 5 分钟后自动退出，下次请求再启动。管理服务正常退出和备份恢复前都会关闭它们。如果怀疑常驻进程有问题，可以先停止管理服务，在同一个命令行窗口里设置 `set ROOMKIT_STORAGE_MODE=oneshot`，再从这个窗口启动 `StartManagement.cmd` 或包内 `StartPanel.cmd`，这样全部回到原来的一次性存储路径。数据库文件和格式不变，两种模式可以随时切换。

## 局域网与独立导出

后台仍只由服务器本机访问。停服后在配置页设置服务器局域网 IPv4 地址作为 advertised_host，设置 lobby_bind=0.0.0.0，保留专用 TCP/UDP 范围，再启动宿主。公共连接配置生成在 artifacts/client/connection.json，与同目录 server.crt 一起交给玩家；不复制 server.key、数据库、run 文件或后台凭据。源码客户端支持 `-ConnectionConfig` 指向公开配置。跨电脑是否能连通还取决于两端网络和防火墙；脚本不自动修改系统防火墙。

新独立包脚本为 tools/build_framework_release.ps1，固定各自 MainLoop，生成 Operator、ManagedHost、两款 Server/Client 和哈希清单，不依赖编辑器的 --script 切换。包内提供 StartPanel、StartShooter、StartTurns、StopFramework 和公开客户端分发入口。导出成功仅证明产物生成；必须按 STATUS 的独立 EXE 运行记录确认实际联调结果。另一台实体设备、Linux 完整宿主和公网部署单独验收。

## 测试入口

每条命令都要检查真实退出码。`tools/run.ps1` 的模式除了成功标记，还必须输出 `ROOMKIT_EXIT mode=<模式> code=0`；脚本会检查退出码、脚本错误和成功标记，并设置整体超时。日志写入 `logs/<模式>-console.log`、`*-stderr.log`、`*-godot.log`。`-Godot '完整路径'` 可指定引擎，换版本需要重新验收。

<a id="small-group-login"></a>
### 2–8 人突发登录（隔离数据）

`tests/test_concurrent_login.ps1 -RequireAll` 在全新的私有 `data/concurrent-login-*` 目录里准备游戏索引并启动真实 Operator、宿主和无窗口客户端。按 2、4、8 人顺序运行，不能把允许部分拒绝的默认诊断模式记为全员登录通过：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/test_concurrent_login.ps1 -Clients 2 -PanelPort 29291 -RequireAll
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/test_concurrent_login.ps1 -Clients 4 -PanelPort 29391 -RequireAll
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/test_concurrent_login.ps1 -Clients 8 -PanelPort 29491 -RequireAll
```

每组必须全员成功，后台实际在线玩家集合须与全部存活客户端的身份一致。注册、突发登录和逐一复登的每次退出后，都要确认在线人数及清理的 pending/running/failed 归零；全部客户端须有符合预期的真实退出码且错误输出为空。分项结果保存在该隔离目录的 `logs/result.json`；总退出码非零就不算通过。`after_ms` 是驱动看到结果的时间，不能当作各玩家的独立登录延迟；这些是同机真实 WSS 突发登录，不代替 Linux、朋友设备或压力下的长期验收。

定位与边界专项：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/test_account_login_lock.ps1
$r = Join-Path (Get-Location) ('data/account-admission-' + [guid]::NewGuid().ToString('N'))
$a = "--data-root=$r/data;--games=$r/games.json;--public-client-dir=$r/public;--operator-log-path=$r/operator.log;--panel-port=30091"
./tools/run_isolated_test.ps1 -Script tests/run_operator_account_admission.gd -Isolation $r -Log "$r/result" -TestArgs $a
$r = Join-Path (Get-Location) ('data/shutdown-cleanup-' + [guid]::NewGuid().ToString('N'))
$a = "--data-root=$r/data;--games=$r/games.json;--public-client-dir=$r/public;--operator-log-path=$r/operator.log;--panel-port=30091"
./tools/run_isolated_test.ps1 -Script tests/run_operator_shutdown_cleanup.gd -Isolation $r -Log "$r/result" -TestArgs $a
```

写锁专项复制真实存储助手，在真实密码验证后设置有限屏障，另一个 SQLite 连接只有 300 毫秒锁等待：覆盖改密、封禁、限流、删除、同名重建及新身份读取。准入和关停专项使用生产处理器与替身，不启动服务或数据库，不替代真实多客户端验收。关停同时核对 `SHUTDOWN_CLEANUP_RESULT` / 私有结果中的 failed，不能只看退出码。真实备份登录驱动 `tests/test_operator_backup_login.ps1` 另核对同一玩家的登录审计增量恰好一条，包含失败重发检查；其隔离游戏索引与实际等待日志仍是必需证据。

### 基础回归（`tools/run.ps1`）

备份期间的账号等待与玩家退出取消，分别由 [run_operator_backup_wait.gd](../tests/run_operator_backup_wait.gd) 和 [run_local_rpc_cancel.gd](../tests/run_local_rpc_cancel.gd) 检查。前者使用生产 Operator 处理器加替身，包含实际 10 秒截止与结果 outbox 保留；后者使用真实认证回环 TCP，不启动数据库或管理服务。Windows 通过隔离入口执行：

```powershell
$r = Join-Path (Get-Location) ('data/backup-wait-' + [guid]::NewGuid().ToString('N'))
$a = "--data-root=$r/data;--games=$r/games.json;--public-client-dir=$r/public;--operator-log-path=$r/operator.log;--panel-port=28395"
./tools/run_isolated_test.ps1 -Script tests/run_operator_backup_wait.gd -Isolation $r -Log "$r/result" -TestArgs $a
$r = Join-Path (Get-Location) ('data/rpc-cancel-' + [guid]::NewGuid().ToString('N'))
./tools/run_isolated_test.ps1 -Script tests/run_local_rpc_cancel.gd -Isolation $r -Log "$r/result"
```

Linux C/D/E 驱动 [linux_l3_slice.sh](../tools/linux_l3_slice.sh) 同样先跑这两个专项，再跑正式入口与 60 分钟耐久。耐久单列实际自动备份次数和等待命中数；没有自然命中等待时标为未运行，不用整体退出 0 代替这项证据。

真实备份与 WSS 登录重叠由 [test_operator_backup_login.ps1](../tests/test_operator_backup_login.ps1) 补测。先准备新的源码副本并构建它自己的游戏索引，再传入 `-ProjectRoot '副本绝对路径' -GamesIndex '副本自己的索引绝对路径'`；不要在正在使用的源码目录运行。脚本会调整该副本的 `run/` 权限，在其新建的 `data/test-backup-login-*` 内启动独立 Operator、宿主与玩家，执行真实手动备份和一次登录，要求实际等待日志、备份成功、登录成功、退出码 0，以及会话清理的等待/运行/失败计数都归零。它最多启动三次独立试验以捕获重叠，不会自动重发失败的登录；手动备份重叠不代替自然自动备份的证据。

`-Mode all` 按顺序运行 unit、launcher、integration、demo、players、games、persistence、secure、stress（100 轮）、load（16+4 玩家）、recovery、limits、template、panel、assets。它**不包含**下文的账号、管理、射击和托管专项。

| 模式 | 执行内容 | 成功标记 |
|---|---|---|
| `unit` | 注册与端口、协议/分帧、Schema、模拟进程生命周期、玩法规则 | `UNIT_RESULT passed=... failed=0` |
| `launcher` | 10 轮真实进程身份核验与 Windows 句柄回收 | `REAL_LAUNCHER_RESULT passed=... failed=0` |
| `integration` | 真实 Godot 子进程、TCP 控制、ENet 端口、故障与连续开关房 | `INTEGRATION_RESULT passed=... failed=0` |
| `demo` | 自动创建一房，收到至少四次心跳后停止并退出 | `DEMO_PASS` |
| `players` | 真实 WebSocket 大厅、两名 ENet 测试玩家进出、非法票据/满员拒绝 | `PLAYERS_RESULT passed=... failed=0` |
| `games` | 两个早期示例、四名真实客户端、实际回合结果落库；`-Visual` 打开图形窗口并截图 | `GAMES_RESULT passed=... failed=0` |
| `persistence` | 真实 SQLite、丢 ACK 重试、宿主终止/房间自退、离线补存、备份 | `PERSISTENCE_RESULT passed=... failed=0` |
| `secure` / `stress` / `load` / `recovery` / `limits` / `template` / `panel` | 加密与权限、100 轮开关房、并发输入、重启隔离、资源上限、早期模板接入、早期状态面板 | 对应 `*_RESULT passed=... failed=0`（stress 另含 `cycles=100`） |

### 账号、管理、射击与托管专项

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode unit
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode accounts
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode assets
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode admin_http
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode asset_callbacks
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode result_rewards
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode managed_contracts
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode shooter
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test_operator_maintenance.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test_asset_audit.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test_operator.ps1 -Lifecycle
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\tests\test_managed_shutdown.ps1
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\tests\test_operator_schedules.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode managed_registry
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test_managed_template.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test_room_rules.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test_client_launcher.ps1
node tests/test_admin_room_rules.cjs
node tests/test_admin_asset_spaces.cjs
node tests/test_admin_auth_errors.cjs
node tests/test_admin_account_deletion.cjs
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test_helpers.ps1
& 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path . --script res://tests/run_storage_timing.gd -- --rounds=5 --label=my-run
& 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path . --script res://tests/run_grant_storage.gd
& 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path . --script res://tests/run_asset_snapshot.gd
& 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path . --script res://tests/run_resident_store.gd
& 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path . --script res://tests/run_account_deletion.gd
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test_account_deletion.ps1
```

`run_account_deletion.gd` 在隔离目录 `data/test-account-deletion-<id>` 中用假账号直接驱动两个真实 SQLite 库：管理员保护、用户名确认、玩家无权删除、旧 token、多个资产空间、签名结果与迟到结算、资产步骤失败和两库之间中断（用替身制造）、Operator 收尾中断后的重启与重复请求、审计文件和删除日志设为只读时的写入失败、原因里含用户名/user_id 的替换、启动恢复、重复删除、其他玩家不受影响、审计与回执去标识化，最后逐表扫描两个库确认不再含 user_id、用户名和昵称，并确认删除前的备份副本仍含该账号。`test_account_deletion.ps1` 启动真实 Operator、托管宿主和房间，用两个真实 WSS 客户端（被删玩家坐在房间里）走后台 HTTP 删除，检查踢下线、旧凭据、其他玩家资产、审计与删除日志、备份标注；删除时先把 `operator-audit.jsonl` 设为只读，确认返回“删除未完成”，恢复可写后重新提交才完成；各处原因写入被删玩家的用户名和 user_id，最后逐表扫描两个库和 Operator 审计文件确认已替换；再在 Operator 停止时分别制造“只做第一步”和“两库已完成、未收尾”两种中断，重启后确认都已完成；最后恢复删除前的备份，确认账号和资产会被带回。两者都可以设置 `ROOMKIT_STORAGE_MODE=oneshot` 重跑。

`run_resident_store.gd` 检查常驻存储：新旧路径返回完全一致、每个数据库只有一个工作进程、不产生请求文件、新旧路径并发写同一个库、助手报错时进程不退出、超时和崩溃后重试只扣一次、队列上限、空闲退出、模式开关、全部关闭后自动重启，以及会话校验两条路径一致和句柄不泄漏。其余专项默认走常驻路径；在启动 Godot 或测试脚本前设置 `ROOMKIT_STORAGE_MODE=oneshot`，就可以用一次性路径重跑。

`managed_shutdown` 与 `operator_schedules` 会各自创建私有数据目录，运行前需要存在 `artifacts/framework-games.json` 及其中引用的工程产物；`operator_schedules` 用受控时间验证 30 分钟备份和 10 分钟重启窗口，没有真实等待。`test_helpers.ps1` 覆盖有界助手的超时终止、路径白名单和账号请求的 stdin 模式。`run_storage_timing.gd` 在私有测试目录里实测注册、登录、会话校验、登出、发币、购买、重试和结算的存储层耗时，同时检查账号操作期间数据目录没有出现请求文件、Godot 句柄没有增长；报告写入 `logs/storage-timing-<label>.json`，输出 `STORAGE_TIMING_RESULT passed=... failed=0` 且退出 0 才算通过。耗时受机器负载影响，只能在同一台机器上前后对比。`run_grant_storage.gd` 检查房间签名密钥不落盘及授权上限。`run_asset_snapshot.gd` 走真实资产服务，检查购买、选择、重复请求、同 ID 不同内容、重开后重试、同一请求并发、超额并发购买和并发加币；每步之后用回执流水链核对余额与版本，并数出每个操作实际发生的存储调用次数（购买、选择、发币各 2 次，已提交请求的重复调用 1 次）。在这几条之前的八条依次对应托管注册、[托管模板](24_managed_game_template.md)、[房间规则](25_shooter_room_rules.md)、客户端启动器和四个管理页面函数测试；Node 测试用的是 DOM/API 替身，不算浏览器验收。射击渲染平滑对比 `tests/run_shooter_visual.gd` 需要图形窗口，命令见 [docs/25](25_shooter_room_rules.md)。各专项的最新结果与证据见 [STATUS](../STATUS.md#status-validation)。

### 性能测量（评估用，不属于回归门禁）

`tests/perf/` 下的脚本只用于测量，结论见 [docs/17 第六节](17_framework_shooter_plan.md#六常驻存储评估与第一阶段实施2026-09-27)：

```powershell
# 客户端视角的资产耗时：先在另一个终端运行 tests\test_operator.ps1 -HoldForIntegration，
# 等出现 OPERATOR_INTEGRATION_READY 后再执行下一行；结束后按“完整客户端测试”的方式写入 integration-done.request
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\perf\measure_asset_e2e.ps1 -Clients 3 -Label my-run
# 一次性调用的轻量变体对比（在私有测试目录中生成修改过的副本，不改生产脚本）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\perf\storage_oneshot_variants.ps1 -Rounds 7
# 常驻工作进程原型与 GDScript PBKDF2 可行性
& 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path . --script res://tests/perf/run_resident_probe.gd
& 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path . --script res://tests/perf/run_gd_pbkdf2_probe.gd
```

结果分别写入 `logs/asset-e2e-<label>.json`、`logs/storage-oneshot-variants.json`、`logs/resident-probe.json`、`logs/gd-pbkdf2-probe.json`。`resident_store_probe.ps1` 是原型，仍通过测试目录里的短期文件把请求交给 `sqlite_store.ps1`，不能直接用于生产。

专项分别覆盖纯规则、真实 SQLite、真实 HTTP、真实子进程；不相互冒充。`tools/run.ps1 -Mode all` 仍是原基础回归集合，新增账号、管理及玩法专项需要单独执行。tests/test_operator.ps1 使用独立 data/test-operator-* 测试目录，并在退出前请求停止本次进程；`-Lifecycle` 增加空间切换、备份恢复、真实60秒优雅重启和已核验宿主崩溃测试。保留原进程句柄的 watchdog 只作用于本次子进程。

完整客户端测试：在一个终端运行 `tests/test_operator.ps1 -HoldForIntegration`；待日志出现 OPERATOR_INTEGRATION_READY 后，在另一个终端运行 `tests/test_framework_clients.ps1 -Visual`。测试会完成未缩短的五分钟对局；运行结束后，在前一终端打印的本次 data/test-operator-* 目录内创建空文件 `integration-done.request`，通知它继续停止与清理（否则最多等待40分钟）。两个脚本都必须退出0。该目录的 test-context.json 含私有测试凭据，不要交给玩家。该测试使用真实本机多进程，不能据此宣称第二台电脑已经连通。

独立包先运行 `tools/build_framework_release.ps1`，再对生成的本仓库绝对目录运行 `tests/test_framework_release.ps1 -Bundle '完整包目录'`。它验证六个真实导出程序、客户端界面初始化、原生宿主和房间的WSS/ENet联调及退出/端口回收；网络客户端使用源码测试驱动，不能替代导出客户端的人工完整试玩。证据写入 logs/framework-release-*，发布 ZIP 不含测试后生成的私有目录。

2026-09-22 停服（55/0）与调度（52/0）专项的原始结果、受控时间边界和证据目录已移入 [STATUS 历史归档](archive/status_history.md)；当前结论见 STATUS。

## 独立 EXE 的人工 UI 夹具与源码对手

[run_framework_ui_fixture.ps1](../tests/run_framework_ui_fixture.ps1) 用于人工操作最终导出的程序。先把发布包解压到本仓库内一个独立目录；不要使用已经有本包进程运行的目录。在终端 A 启动：

```powershell
$bundle = 'F:\文档\GodotGame\Net\RoomKit\artifacts\本次独立解压目录'
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\tests\run_framework_ui_fixture.ps1 -Bundle $bundle
```

等待 `FRAMEWORK_UI_FIXTURE_READY id=... url=... evidence=...`。这个终端需保持运行，最长 40 分钟。夹具启动真正的 `Operator.exe`，分配独立端口、私有数据库和证书；它不会自动创建管理员、邀请码、宿主或房间。通过输出的回环 URL 在浏览器完成这些操作。

在终端 B 使用 READY 输出的非秘密 id 定位私有目录，以下命令不会打印 context 内容：

```powershell
$bundle = 'F:\文档\GodotGame\Net\RoomKit\artifacts\本次独立解压目录'
$fixtureId = '替换为 READY 输出的 id'
$private = Join-Path $bundle ('data\ui-test-' + $fixtureId)
$contextFile = Join-Path $private 'context.json'
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $private 'commands\ui-shooter-1.command.json'), '{"action":"launch_shooter"}', $utf8)
```

夹具据此打开本包的 `clients/shooter/Client.exe` 可见窗口。取石子用新的命令文件名和 `{"action":"launch_turns"}`；命令结果保存在同目录的 `command-results/`。文件名每次应不同，重复命令 id 不再执行。被人工验收的是这些真实导出窗口中的注册、登录、入房、背包和游戏交互，不是源码测试驱动。

`context.json` 含私有测试账号口令，只供本机验收工具读取；不要把其全文输出到终端、聊天、截图、Git 或玩家包。公开连接配置路径为该私有目录中的 `connection-public.json`，内容不含后台凭据或服务器私钥。最终可公开的 UI 结果由操作前后证据和 STATUS 记录，不由夹具 READY 自动判定。

如需第二名玩家配合，可使用 [run_ui_opponent.ps1](../tests/run_ui_opponent.ps1)。先在浏览器创建有效邀请码，并通过后台或真实导出客户端创建目标房间。在终端 B 写入私有请求再启动对手；邀请码使用不回显输入，不出现在命令行参数或输出中：

```powershell
$roomId = Read-Host '目标房间 ID'
$inviteInput = Read-Host '邀请码（不回显）' -AsSecureString
$opponentRequest = @{
    game_id = 'shooter' # 取石子改为 turns
    room_id = $roomId
    invite_code = (New-Object Net.NetworkCredential('', $inviteInput)).Password
}
[IO.File]::WriteAllText((Join-Path $private 'opponent-request.json'), ($opponentRequest | ConvertTo-Json -Compress), $utf8)
$opponentRequest.Clear()
$inviteInput.Dispose()
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\tests\run_ui_opponent.ps1 -ContextFile $contextFile
```

对手只接受 shooter/turns，使用本次 context 中对应的 `players.<game>_two` 随机账号、包内 `artifacts/framework-games.json` 的 manifest 和私有公开连接配置。它运行的是本仓库 `tests/run_framework_clients.gd` **源码 SDK 驱动，不是导出的 Client.exe**。真实完成 WSS 注册/登录、ENet 入房且权威快照包含自己后，才输出 `UI_SOURCE_OPPONENT_READY`，其中 `report` 和 `control_directory` 是不含口令的报告/控制路径。测试口令通过一次性私有 bootstrap 传递，不进入程序参数。

辅助脚本不会发送管理员请求，不会自动攻击或替你选石子。需要动作时，由验收者在输出的 control_directory 中写入带唯一 id 的合法 `input`/`choose` 等 `.command.json`；格式以现有 [run_framework_clients.gd](../tests/run_framework_clients.gd) 为准。报告不包含 session token。对手最多运行 15 分钟，然后请求正常关闭；首次注册使用的二号账号已经存在时不能把再次注册失败当成登录故障，重复完整验收宜启用新的独立 UI 夹具。

结束时，在另一个终端重新设置同一个 `$bundle/$fixtureId/$private`，先请求源码对手退出：

```powershell
[IO.File]::WriteAllText((Join-Path $private 'opponent-close.request'), 'close')
```

等待对手终端输出 `UI_SOURCE_OPPONENT_STOPPED` 并退出。脚本先写入自己的 `close.command.json` 等待 driver 退出，watchdog 只使用其本次捕获的子进程句柄。然后结束整个 UI 夹具：

```powershell
[IO.File]::WriteAllText((Join-Path $private 'close.request'), 'close')
```

该标记也会通知仍运行的源码对手关闭。UI 夹具关闭自己启动的导出客户端，请求自己的 Operator 停止，核验自己的宿主/房间退出，再恢复本次包中原有的公开连接文件。确认两个脚本均退出 0，且 `FRAMEWORK_UI_FIXTURE_STOPPED` 的 `cleanup_failed=False`、`forced_cleanup=False`、`live_owned=0`；查看 `logs/framework-ui-<id>/fixture-result.json` 保留清理证据。不要用按名称全局结束 Godot/Client/Operator 进程的方式清理，也不要把这一夹具的退出成功当作完整 UI 功能都已验收。
