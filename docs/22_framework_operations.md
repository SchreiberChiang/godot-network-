# 当前分支的本机启动与验证

当前分支为 codex/shooter-framework，规格见 docs/17，测试证据见 STATUS。这里说明现有入口，不把代码已编写等同于发布验收通过。

## 源码运行

Windows 需要 Godot 4.7.2；默认路径是 `D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`。不需要 Node、外部数据库服务或旧项目。脚本参数 `-Godot` 可以指定另一个引擎路径，但更换版本后应重新验证。

1. 双击仓库根目录 **StartManagement.cmd**。脚本从当前仓库生成独立游戏工程并启动管理服务，然后打开回环网页。默认网页地址为 http://127.0.0.1:28291/。
2. 首次创建管理员账号。管理员只能管理后台，不能作为游戏玩家入房。
3. 点击“启动服务器”。管理服务负责生成私有凭据并启动独立宿主，页面会显示宿主、房间和玩家状态。
4. 在邀请码页创建邀请码。双击 **StartShooterClient.cmd**，用邀请码注册新的玩家账号并登录。启动第二个客户端，用另一个账号登录；同一个玩家账号不能重复占用会话。
5. 在后台或玩家大厅创建射击房间。进入后左右移动/跳跃，鼠标瞄准射击；两名玩家开始五分钟自由混战。初始基础步枪免费，后台可给测试账号发金币。
6. 在大厅或死亡期间打开背包，先解锁，再单独选为默认配置。死亡至少三秒且此前资产请求已确认后才可手动复活。存活时服务端拒绝购买和配置变更。
7. **StartManagedTurns.cmd** 打开取石子客户端。它使用同一账号/钱包/所有权/默认配置服务，项目只定义经典/玉石主题及大厅可选用的规则。
8. 面板“停止服务器”默认公告六十秒后停止，期间拒绝新入房；“立即停止”要确认。它只停游戏宿主，不关闭管理网页。**StopManagement.cmd** 请求关闭整个管理服务及其宿主。

命令行等价入口（在当前项目目录）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_framework.ps1 -Mode panel
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_framework.ps1 -Mode client -Game shooter
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_framework.ps1 -Mode client -Game turns
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_framework.ps1 -Mode stop
```

`StartPanel.cmd`、`StartPlay.cmd`、`StartTurns.cmd` 保留原无账号演示。它们与本分支管理服务是不同入口，不能用旧演示测试代替新账号/射击验收。

## 数据与维护

默认私有目录为 `data/framework/`：accounts.sqlite 保存账号/会话/邀请码，assets.sqlite 保存资产/操作流水/成绩与结果授权，config.json 保存配置，server.key 是私钥。私有文件不进入 Git、玩家分发包或日志。当前单管理员本机后台不对外网监听。

后台可查看账号，重置密码、封禁、解封、踢下线；修改资产需要原因，购买、选用、授权和撤销分别记录。金币和经验调整有上下限，不能通过后台执行任意 SQL 或 shell。等级根据经验计算。首次注册没有测试金币。

只有停止游戏宿主后才能切换资产空间。独立和 shared 是不同的已命名空间；切换保留原空间数据，不复制、不合并。即使共享钱包，两款游戏的默认配置仍分别保存。实际房间服只能取得经过确认的配置，客户端不能上传武器属性。

后台默认每三十分钟备份，保留四十八份自动备份；手动和恢复前备份另存。恢复必须停服，先做恢复前备份，校验后恢复，全部账号会话失效，需要重新登录。不要直接替换运行中的 SQLite 文件。无法证明旧进程退出或旧端口空闲时保留 RECOVERY_REQUIRED，不按旧 PID 强杀进程。

宿主发生异常后先确认旧房间退出与端口回收，再尝试重启，十分钟最多三次。重新启动前清理旧玩家会话，玩家可再次登录，管理员会话保留；恢复整个备份会使管理员会话也失效。未完成的对局不续赛。主动停服不自动拉起。这里只管理本项目进程，不是全系统服务管理器。

## 局域网与独立导出

后台仍只由服务器本机访问。停服后在配置页设置服务器局域网 IPv4 地址作为 advertised_host，设置 lobby_bind=0.0.0.0，保留专用 TCP/UDP 范围，再启动宿主。公共连接配置生成在 artifacts/client/connection.json，与同目录 server.crt 一起交给玩家；不复制 server.key、数据库、run 文件或后台凭据。源码客户端支持 `-ConnectionConfig` 指向公开配置。跨电脑是否能连通还取决于两端网络和防火墙；脚本不自动修改系统防火墙。

新独立包脚本为 tools/build_framework_release.ps1，固定各自 MainLoop，生成 Operator、ManagedHost、两款 Server/Client 和哈希清单，不依赖编辑器的 --script 切换。包内提供 StartPanel、StartShooter、StartTurns、StopFramework 和公开客户端分发入口。导出成功仅证明产物生成；必须按 STATUS 的独立 EXE 运行记录确认实际联调结果。另一台实体设备、Linux 完整宿主和公网部署单独验收。

## 测试入口

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
```

专项分别覆盖纯规则、真实 SQLite、真实 HTTP、真实子进程；不相互冒充。`tools/run.ps1 -Mode all` 仍是原基础回归集合，新增账号、管理及玩法专项需要单独执行。tests/test_operator.ps1 使用独立 data/test-operator-* 测试目录，并在退出前请求停止本次进程；`-Lifecycle` 增加空间切换、备份恢复、真实60秒优雅重启和已核验宿主崩溃测试。保留原进程句柄的 watchdog 只作用于本次子进程。

完整客户端测试：在一个终端运行 `tests/test_operator.ps1 -HoldForIntegration`；待日志出现 OPERATOR_INTEGRATION_READY 后，在另一个终端运行 `tests/test_framework_clients.ps1 -Visual`。测试会完成未缩短的五分钟对局；运行结束后，在前一终端打印的本次 data/test-operator-* 目录内创建空文件 `integration-done.request`，通知它继续停止与清理（否则最多等待40分钟）。两个脚本都必须退出0。该目录的 test-context.json 含私有测试凭据，不要交给玩家。该测试使用真实本机多进程，不能据此宣称第二台电脑已经连通。

独立包先运行 `tools/build_framework_release.ps1`，再对生成的本仓库绝对目录运行 `tests/test_framework_release.ps1 -Bundle '完整包目录'`。它验证六个真实导出程序、客户端界面初始化、原生宿主和房间的WSS/ENet联调及退出/端口回收；网络客户端使用源码测试驱动，不能替代导出客户端的人工完整试玩。证据写入 logs/framework-release-*，发布 ZIP 不含测试后生成的私有目录。

## 停服与调度新增专项

2026-09-22，在 Windows / Godot 4.7.2.stable.steam 上运行上面的两个独立 PowerShell 命令，结果如下。脚本均创建自己的私有数据目录，`managed_shutdown` 还复制当前仓库生成的射击工程，避免改写其他测试房间的日志；运行前需要存在 `artifacts/framework-games.json` 及其中引用的当前工程产物。

| 专项 | 实际结果 | 已验证内容与边界 |
| --- | --- | --- |
| `test_managed_shutdown.ps1` | `MANAGED_SHUTDOWN_RESULT passed=55 failed=0`，退出码 0 | 真实托管宿主、两个射击房间子进程、SDK WSS/DTLS 客户端。实际客户端两次读取停服公告得到 59 → 57 秒；重复停服不延长期限，维护开关不能解除停服或覆盖公告。覆盖已发票据、异步资产读取与重建房间跨越停服/禁入边界，及席位、进程、UDP 和私有进程日志回收。可信内部账号/资产/成绩 RPC 使用夹具，不是本专项的 SQLite 验收。 |
| `test_operator_schedules.ps1` | `OPERATOR_SCHEDULE_RESULT passed=52 failed=0`，退出码 0，71.495 秒 | 使用真实 Operator 初始化、轮询、工作线程、SQLite helper 和托管宿主。连续四次真实崩溃：前三次各启动替代宿主，第四次保留 `RESTART_LIMIT_REACHED`；主动重启不消耗崩溃配额，主动停止不自动拉起。原定时分支生成四份真实自动备份及四条系统审计，验证到期前不执行、后续帧不重复、维护/退出门禁、等待真实工作线程排空。 |

`operator_schedules` 在测试实例内移动 `next_backup`，并为历史重启记录设置过期/未过期时间戳。它验证真实初始化将下一次备份设为 30 分钟之后，并执行实际定时分支；**没有真实等待 30 分钟，也没有等待 10 分钟验证历史自然过期**。四次连续崩溃和前三次自动重启使用真实进程与正常两秒延迟；历史窗口淘汰部分使用受控时间。测试子类仅禁止发布共享的公开连接配置，未替换备份 helper 或宿主生命周期实现。没有创建房间来重测孤儿回收，也没有通过浏览器点击管理按钮；这些属于其他专项与 UI 验收。

本轮原始证据：

- `logs/managed-shutdown-2cf23012230d4a928f6f17878062952b/`：`result.json`、`console.log`、`managed-host.log`；stderr 为空。立即停服断开 WSS 时 stdout 出现一条 `mbedtls -0x6c00`，日志保留，不能描述成完全没有引擎诊断。
- `data/test-operator-schedules-691ba27c01ae4828b4a50cc1b46796e2/`：`schedule-result.json`、`console.log`、`operator-test.log`；stderr 为空。记录七个真实宿主的启动身份，最终全部确认退出并释放记录，`host-running.json` 无遗留。

两个专项均未使用其他正在运行的 UI 夹具或源码对手，不证明另一台设备已经连通。这里的结果不能替代最终独立包的交互与清理报告。

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
