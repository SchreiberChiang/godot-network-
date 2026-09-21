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
```

专项分别覆盖纯规则、真实 SQLite、真实 HTTP、真实子进程；不相互冒充。`tools/run.ps1 -Mode all` 仍是原基础回归集合，新增账号、管理及玩法专项需要单独执行。tests/test_operator.ps1 使用独立 data/test-operator-* 测试目录，并在退出前请求停止本次进程；`-Lifecycle` 增加空间切换、备份恢复、真实60秒优雅重启和已核验宿主崩溃测试。保留原进程句柄的 watchdog 只作用于本次子进程。

完整客户端测试：在一个终端运行 `tests/test_operator.ps1 -HoldForIntegration`；待日志出现 OPERATOR_INTEGRATION_READY 后，在另一个终端运行 `tests/test_framework_clients.ps1 -Visual`。测试会完成未缩短的五分钟对局；运行结束后，在前一终端打印的本次 data/test-operator-* 目录内创建空文件 `integration-done.request`，通知它继续停止与清理（否则最多等待40分钟）。两个脚本都必须退出0。该目录的 test-context.json 含私有测试凭据，不要交给玩家。该测试使用真实本机多进程，不能据此宣称第二台电脑已经连通。

独立包先运行 `tools/build_framework_release.ps1`，再对生成的本仓库绝对目录运行 `tests/test_framework_release.ps1 -Bundle '完整包目录'`。它验证六个真实导出程序、客户端界面初始化、原生宿主和房间的WSS/ENet联调及退出/端口回收；网络客户端使用源码测试驱动，不能替代导出客户端的人工完整试玩。证据写入 logs/framework-release-*，发布 ZIP 不含测试后生成的私有目录。
