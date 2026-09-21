# 本轮：中文本机状态面板

2026-09-21：用户要求类似宝塔的服务器/房间/玩家数据查看，已新增可实际打开的中文只读网页面板。原房间生命周期、加密连接、SQLite和独立包继续保留；未引入额外后端、未访问旧工程、未部署公网。

打开仓库StartPanel.cmd（需本机Godot）或新版独立包StartPanel.cmd（无需编辑器）。面板与两个示例游戏窗口一起启动；查看宿主运行时间、PID/端口、房间状态/人数/心跳/实际工作集、在线玩家身份及最近100条SQLite对局成绩。支持房间搜索、状态筛选、按房间看成员、点击玩家看近期成绩。只读，不包含账号资产/背包/商城、网页开关房或远程系统管理。具体入口与数据来源见docs/16_dashboard.md。

默认面板仅监听127.0.0.1:28291，使用每次宿主随机生成的Bearer凭据；只从私有run描述文件交付给本机页面，不在应用日志打印访问链接。页面2秒刷新、数据库5秒异步读取；明确区分离线旧数据和存储错误。响应使用显式白名单，不返回控制token、票据/摘要、私钥、数据库授权或私有路径。真实响应Schema和例子已同步。测试随机端口使用独立描述文件，不覆盖用户正常面板的授权文件。

## 本轮实际测试（均在Windows本机）

| 命令/验证 | 最终结果 |
|---|---|
| tools/run.ps1 -Mode panel | 退出0，62/0；包含原双玩法47项及面板启动、真实HTTP/Schema、四个真实玩家、真实SQLite结果、401/403/404/405/400拒绝、敏感字段投影、关闭描述文件清理 |
| tools/run.ps1 -Mode unit | 退出0，250/0；未重复运行所有无关的100轮/20人测试，上轮对应结果保留历史范围 |
| tools/build_release.ps1 | 退出0；HTML随固定入口PCK导出，包内新增StartPanel.cmd |
| tools/package_release.ps1 | 退出0；37个不可变文件校验一致，程序ZIP共38项，data/run/logs/私钥/SQLite条目0 |
| tools/test_release.ps1 -Bundle 新解压目录 | 退出0；official EXE -Test -Panel -NoBrowser为48/0，授权HTTP核对真实宿主PID；另开两个窗口经Stop入口退出18/0，结果查看、备份及监听/日志清理通过 |
| 浏览器实际操作 | 源码面板显示真实2房/2玩家及旧库1条结果；搜索空结果、房间过滤、玩家详情、宿主退出后的离线提示通过。最终official包页面2房/2玩家，导航到玩家后刷新仍在线；中文布局和内存缺项说明已经截图/DOM核实 |
| 脚本检查 | PowerShell AST解析、CMD UTF8无BOM/CRLF、git diff --check通过；静态检查不代替上方运行测试 |

主要证据：logs/panel-final-test.txt、panel-unit.txt、panel-final-export.txt、panel-package-final.txt、panel-release-final.txt、panel-visual-session.txt、panel-user-session.txt及对应stderr。测试进程已回收；本轮结束时特意保留最终独立包的1个宿主、2个房间和2个玩家窗口供用户查看，浏览器标签页也保留。这些是交付中的运行会话，不宣称此时进程为零；关闭两个游戏窗口或包内StopRoomKit.cmd可停止，30分钟上限仍有效。

## 失败、修复和边界

- 一次重新解压测试32通过/16失败：首个客户端CONTROL_UNAVAILABLE，其它客户端等待双玩法后续阶段超时。连续同步启动/身份捕获会阻止宿主处理早到客户端的WSS连接；已将演示客户端启动改到独立工作线程，在主线程继续轮询连接，完成后移交精确进程身份记录。未延长超时或删测试；最终源码62/0、新解压official48/0通过。失败保留logs/panel-release-startup-failed.txt及对应旧解压目录的客户端日志。
- official Godot返回静态内存0（未提供该指标）；现明确显示“当前引擎未提供此指标”，不把0画成有效数据。每房工作集仍由真实Windows进程采样得到。未提供整机CPU/磁盘统计。
- 页面锚点最初可能在刷新时误当授权；改成仅64位十六进制片段作为凭据，其它锚点沿用当前标签页会话，最终浏览器导航/刷新通过。一次浏览器空字符串填充未清空搜索，改键盘选中删除后确认恢复；未把工具动作尝试计作成功。
- 新库没有对局时显示空状态；只有完成并保存的真实结果才出现。账号总资产、第三方身份服务、远程面板、公网、Linux完整宿主仍未实现或未验收。网页写操作未提供。

## 当前交付位置
- 程序ZIP：`F:\文档\GodotGame\Net\RoomKit\artifacts\RoomKit-0.1.0-windows-ba558c42d15d46f78efa2dff32b501ce.zip`
- 已解压启动器：`F:\文档\GodotGame\Net\RoomKit\artifacts\unpacked-ba558c42d15d46f78efa2dff32b501ce\StartPanel.cmd`
- 程序ZIP SHA256：`A1F1C6AEBE1D4D477B29F4B8214FB16F1EE4874B09A38E365AE6CA026990B1D9`

## 本轮文件清单（21个）

- `docs/02_contracts.md`
- `docs/06_roadmap_acceptance.md`
- `docs/16_dashboard.md`
- `examples/dashboard_status.example.json`
- `examples/showcase/host.gd`
- `host/dashboard.html`
- `host/dashboard_server.gd`
- `README.md`
- `release/README.md`
- `release/Run.ps1`
- `release/StartPanel.cmd`
- `schemas/dashboard_status.schema.json`
- `StartPanel.cmd`
- `STATUS.md`
- `tests/run_panel.gd`
- `tools/build_release.ps1`
- `tools/open_panel.ps1`
- `tools/panel.ps1`
- `tools/play.ps1`
- `tools/run.ps1`
- `tools/test_release.ps1`

---

以下保留之前的里程碑历史；最新结论以上方为准。

# 实际开发状态

更新：2026-09-21。本轮继续用户“一口气全做完”的后续授权，完成 Windows 本机 M4 安全/恢复闭环和 M5 发布候选交付；**不把 M4/M5 全部正式门禁标为通过**。Linux完整宿主、跨电脑与公网、最坏玩法容量边界、另一台干净机器仍未验收。只修改当前独立仓库，没有读取、复制或修改旧游戏/旧服务器，没有云部署或账号商城。

## 现在可以直接用什么

- Windows独立程序ZIP：`artifacts/RoomKit-0.1.0-windows-3b92cb9c4c7f471ab9162e6490f837b8.zip`，181.73 MiB。无需Godot编辑器；需要Windows PowerShell与系统winsqlite3.dll。
- 已重新解压并测试的启动器：`artifacts/unpacked-3b92cb9c4c7f471ab9162e6490f837b8/StartRoomKit.cmd`。打开两个取石子窗口；传入`-Game blocks`玩方块。StopRoomKit.cmd正常停止，CheckRoomKit.cmd校验。
- SDK 0.4.0与独立新工程模板：`artifacts/RoomKit-SDK-0.4.0-template-3b92cb9c4c7f471ab9162e6490f837b8.zip`。也可运行`tools/new_game.ps1 -GameId my_game`重新生成。
- 源码原入口StartPlay.cmd、StartTurns.cmd、ShowResults.cmd保留。完整操作/备份/故障/升级见docs/15_release_operations.md，路线见docs/06_roadmap_acceptance.md。
- ZIP与日志不上传Git，源码与可重建脚本沿用用户授权上传指定GitHub的codex/m4-results分支；精确提交及远端核对见本轮最终回执。未修改全局Git配置。

## 本轮实现

身份提供方预配高熵凭据，持久文件只存摘要和稳定user_id/角色/期限；管理员停房授权，同用户第二会话拒绝，过期会话关闭。演示与独立包默认WSS + ENet DTLS，固定证书和主机名验证，凭据禁止走明文WS；保留基础M1/M2的无账号回环开发夹具。未实现第三方账号服务。

启动/终止/资源采样、结果写库改为工作线程/有界队列。助手超时只终止它自己创建并持有的原句柄；历史房间/并发启动/结果队列有限额，实测内存超限关闭房间。托管宿主在启动前记保留端口，重启隔离遗留实例，精确只读身份确认退出后才能释放；未知身份不猜测、不接管、不杀旧PID。

建立真正的Windows宿主、两个服务器、两个客户端EXE/PCK，固定入口适应官方模板；只读PCK与可写外部路径分开。新增启动/停止/校验/结果查看/备份脚本，按构建文件白名单打包，禁止夹带data/run/logs或私钥。SDK和新工程模板只通过GameAdapter与注册配置接入。源码SDK为0.4.0，开发及正式构建分别有独立兼容标识，详见docs/07。

## 实际命令与结果

下表均为实际执行，退出码0；通过数是断言数，不是玩家或测试机数量。模拟与真进程分开描述。

| 命令/阶段 | 结果与边界 |
|---|---|
| `powershell -NoProfile -ExecutionPolicy Bypass -File ./tools/run.ps1 -Mode all` | 整体退出0；依次结果如下，共1144断言，另含demo |
| unit | 250/0；契约/分帧/Schema及模拟生命周期，不是250次真实联机 |
| launcher | 64/0；十轮真实身份核验/终止/句柄回收，句柄320→320 |
| integration | 133/0；22个真实子进程，包含端口/启动/超时/故障隔离 |
| demo / players | demo四次心跳、leases=0；players 33/0，真实回环接入 |
| games / persistence | 47/0双玩法四客户端及真实SQLite；42/0结果幂等/故障补存/在线备份 |
| secure | 37/0；实际WSS/DTLS，错误CA、错误DTLS主机名和无效身份拒绝、权限；另含过期和明文配置拒绝检查 |
| stress | 404/0；真实100次创建—READY—至少两次心跳—停止—确认退出/端口回收 |
| load | 95/0；实际20个加密输入客户端，两房16+4人；第17人ROOM_FULL，各客户端移动并收到状态 |
| recovery | 21/0；真实终止宿主后立即重新开房，旧端口隔离/旧房自退/确认回收，未知身份继续隔离 |
| limits / template | 8/0真实工作集超限退出与历史上限；10/0生成独立新游戏、真实模板服务器和客户端入房离房 |
| `./tools/test_helpers.ps1` | 3/0；真实慢助手超时、持有句柄的原助手退出、助手路径白名单拒绝。慢助手是隔离测试夹具，不是制造SQLite磁盘故障 |
| `./tools/build_release.ps1` | 正式模板导出成功，检查出口和脚本错误；最终构建索引artifacts/release.json |
| 正式模板 `LauncherCheck.exe --headless` | 64/0；official模板十轮句柄测试，325→326，不随轮数增长 |
| WSL Ubuntu `PortableCheck.x86_64 --headless` | 215/0；实际Linux official引擎协议/准入/玩法与本地端口检查，未运行Linux完整宿主/存储/玩家联机 |
| `./tools/package_release.ps1` | 两个ZIP成功，重新解压后的34个不可变文件摘要一致；程序ZIP35项、模板ZIP38项，私有运行文件0 |
| `./tools/test_release.ps1 -Bundle <delivery.unpacked>` | 退出0；重新解压包用正式EXE跑双玩法47/0；再真实打开两个窗口，通过Stop脚本正常关闭18/0；结果查看、备份成功，监听False、启动日志0项。不是另一台机器或人工试玩 |

100轮耗时142922ms，Godot静态分配25,887,396→27,020,300字节（保留100条历史记录，约增加1.13MB）；宿主poll间隔P95 7ms、最大27ms，不能解释为网络RTT。20玩家全加入后继续15秒，报告包含之前逐个入场阶段：每人输入298—665次，快照165—375个，快照间隔P95 104—110ms；两个房间工作集97,923,072/96,854,016字节。应用层收发字节见load-result.json，不是包含DTLS/IP开销的链路带宽，也未测到全局安全容量上限。测试期间本机也执行构建任务，不是专门隔离的性能实验。

主要证据：logs/completion-final-all.txt、completion-helpers.txt、completion-final-export.txt、completion-package.txt、completion-unpacked-release.txt、native-launcher-console.log、completion-linux-portable.txt、release-stop-console.log及对应stderr；机器报告stress-result.json、load-result.json、各*-lifecycle-result.json、completion-audit.json。最终审计当前项目Godot残留0、run顶层私有启动JSON 0、最终脚本/编译/退出泄漏错误日志0；常见凭据模式扫描命中0。此扫描不等于独立安全审计。

## 本轮失败、修复及未运行

- 导出初次使用--main-pack/--path被official模板拒绝；只去掉路径但保留--script仍不能选择所需入口。改固定MainLoop后又发现必须有主场景，最终固定类+空场景通过。没有把这些失败计为导出通过；早期失败日志仍在logs/及对应旧artifacts目录。
- 本轮扩充文档消息例子后，unit首次249通过/1失败，因为例子数量断言仍为17。同步为18并保留逐项Schema校验，最终250/0；失败证据completion-example-count-failed.txt。
- 一次WSL路径转换丢失Windows反斜杠，程序未启动（127）；改为明确/mnt/f路径后实际Linux退出0。首次进程残留审计遇到空ExecutablePath，修正为空字符串处理后重新执行，最终审计无错误。
- 单元恶意指数产生预期Exponent too high警告；负向证书用例产生预期TLS握手失败。未隐藏这些输出。完整回归最终无GDScript编译错误或退出资源泄漏。
- Windows正式程序已验证，Linux只有可移植测试：ProcessLauncher、RoomManager保护目录和SQLite适配仍为Windows实现，Linux宿主缺失；未将它伪装为环境测试通过。
- 没有跨电脑/LAN/公网部署、外部身份服务、长期满载、最坏玩法/实体规模、容量边界、真实网络丢包、证书轮换、硬CPU/内存配额、磁盘满或断电测试。尚未成功写入outbox的结果不能承诺恢复。凭据仅本地预配，不是完整账号系统。
- 资源上限是应用层采样/队列上限，初始化和离线管理仍有同步调用。数据授权/结果容量有限且无自动归档，不宣称生产长驻已完成。任意跨路径/跨机器数据迁移未验证。

## 本轮实际修改文件

- `docs/02_contracts.md`
- `docs/03_sdk_integration.md`
- `docs/06_roadmap_acceptance.md`
- `docs/07_versions_decisions.md`
- `docs/10_environment.md`
- `docs/13_m4_results.md`
- `docs/14_completion_work.md`
- `docs/15_release_operations.md`
- `examples/blocks/game_manifest.json`
- `examples/m2_messages.example.json`
- `examples/minimal/multiplayer_manifest.json`
- `examples/result_messages.example.json`
- `examples/showcase/client.gd`
- `examples/showcase/host.gd`
- `examples/turn_based/game_manifest.json`
- `host/core/identity_provider.gd`
- `host/core/recovery_guard.gd`
- `host/core/result_service.gd`
- `host/core/room_manager.gd`
- `host/development.gd`
- `host/lobby_server.gd`
- `host/platform/bounded_helper.gd`
- `host/platform/process_launcher.gd`
- `host/storage/sqlite_repository.gd`
- `README.md`
- `release/CheckRoomKit.cmd`
- `release/host.gd`
- `release/Manage.ps1`
- `release/README.md`
- `release/Run.ps1`
- `release/StartRoomKit.cmd`
- `release/StopRoomKit.cmd`
- `schemas/identities.schema.json`
- `schemas/lobby_request.schema.json`
- `schemas/process_journal.schema.json`
- `sdk/roomkit/client/room_client.gd`
- `sdk/roomkit/README.md`
- `sdk/roomkit/server/room_runtime.gd`
- `sdk/roomkit/shared/paths.gd`
- `sdk/roomkit/shared/secure_transport.gd`
- `STATUS.md`
- `templates/game/adapter.gd`
- `templates/game/client.gd`
- `templates/game/README.md`
- `templates/game/room.gd`
- `tests/fixtures/load_client.gd`
- `tests/fixtures/recovery_host.gd`
- `tests/fixtures/secure_client.gd`
- `tests/run_limits.gd`
- `tests/run_load.gd`
- `tests/run_portable.gd`
- `tests/run_recovery.gd`
- `tests/run_secure.gd`
- `tests/run_stress.gd`
- `tests/run_template.gd`
- `tests/test_admission.gd`
- `tests/test_launcher_real.gd`
- `tests/test_results.gd`
- `tools/bounded_helper.ps1`
- `tools/build_release.ps1`
- `tools/new_game.ps1`
- `tools/package_release.ps1`
- `tools/process_identity.ps1`
- `tools/results.gd`
- `tools/run.ps1`
- `tools/test_helpers.ps1`
- `tools/test_release.ps1`

---

# 以下是先前阶段历史记录，当前结论以上方为准

# 实际开发状态

更新：2026-09-21。M0—M3已有本机验证；本轮继续实现M4第一部分：SQLite结果保存、幂等确认、持久outbox、宿主退出后的结果补存和在线备份。M4整体未完成。仅在当前独立仓库开发，未读取、复制或修改旧项目。

## 本轮M4第一部分：结果可保存、重发、恢复与备份

本轮从干净main建立codex/m4-results开发分支，沿用用户对指定GitHub仓库的上传授权。无公网部署、账号/商城开发或云资源消耗。当前工作目录仍为F:\文档\GodotGame\Net\RoomKit；引擎4.7.2.stable.steam.ed1daf0bf、Git 2.55.0.windows.3，系统SQLite实测3.51.1。

完成：宿主集中写SQLite，结果ID及同局最终结果双重唯一约束；每房独立签名授权；房间先写持久outbox再发送，只有提交成功且确认摘要匹配才删除；丢ACK重试不重复写库；真实终止宿主后房间自行退出、UDP可重新绑定，新宿主补存遗留结果；在线备份及从备份打开验证。回合玩法已经实际接入，方块玩法不生成成绩。SDK更新为0.3.0，示例构建及兼容标识同步更新，协议/例子/错误码见docs/02、07、13。

本机验证：双击StartTurns.cmd，两个窗口轮流取完一局石子，关闭窗口后双击ShowResults.cmd，可用中文查看已保存的局数和玩家分数。数据位于data/showcase-results/results.sqlite，不进入Git。成绩记录不等于账号累计积分；新房不会自动恢复旧局。

### 本轮实际测试

以下均在本项目运行，退出码0；计数是断言数，不是玩家数。

| 实际命令 | 结果 |
|---|---|
| powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode all | unit 248/248；launcher 63/63（句柄321→321）；integration 133/133（22子进程）；demo 4心跳、leases=0；players 33/33；games 47/47；persistence 42/42 |
| powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode unit | 补充控制封装深度边界后最终249/249；包含非有限数拒绝、签名小数精度及协议例子 |
| powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode persistence | 最终代码复验42/42；真实SQLite、真实Godot子进程及宿主终止恢复，中文/引号往返一致，备份integrity_check=ok |
| powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode games | 最终代码重新打包复验47/47；SDK与两个独立工程一致，实际回合结果落库 |
| cmd /c "StartTurns.cmd -Smoke < NUL" | 18/18；实际启动两个图形窗口并自动调用关闭处理，房间/客户端回收；非人工试玩 |
| cmd /c "ShowResults.cmd -Store <games报告中的result_store> < NUL" | 显示真实双玩法测试保存的1局回合结果，两玩家分别0/1分，退出0 |
| powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\results.ps1 -Store <persistence报告中的data_root> -Operation inspect / backup / recover | 三种操作分别运行、分别退出0；已保存结果可查看，备份产生新文件，无待恢复记录时不重复写入 |

主要日志：logs/m4-all-run.txt、m4-unit-final.txt、m4-persistence-final.txt、m4-games-final.txt、m4-play-turns.txt、m4-show-results.txt及m4-results-*.txt。机器报告为logs/m4-games-result.json、m4-persistence-result.json、m4-final-audit.json。最终核查退出0：当前项目Godot残留0、私有启动配置0、最终运行时错误0、独立工程SDK差异0。41个改动文件中常见凭据模式命中0；最终测试使用的6个真实签名密钥在日志/产物文本中命中0。初始全套回归后补充了封装深度拒绝，不再重复无关的进程启动器测试。

### 失败修复与未运行

- 初次unit为242通过/1失败：嵌套NaN绕过通用结果校验；增加递归JSON有限数及深度校验。初次persistence因GDScript动态变量类型推断编译失败，总watchdog终止原宿主句柄，未算作运行通过。证据保留m4-unit-attempt-failed.txt、m4-persistence-parse-failed.log。
- 首次能运行的持久化测试出现RefCounted循环引用退出泄漏；结果服务改用WeakRef引用管理器，后续最终stderr无泄漏/资源未释放错误。
- 增加中文与引号断言后一次全套回归persistence为41通过/1失败：数据库内容正确，Windows管道返回Godot时乱码；助手改用ASCII JSON Unicode转义，最终往返断言通过。失败保留m4-all-attempt-failed.txt、m4-unicode-attempt-failed.log。另补文件和控制帧完整小数精度，避免签名摘要漂移。
- 单元恶意1e999仍产生预期Exponent too high警告，拒绝断言通过；没有隐藏警告。
- ACK丢失是在真实控制链路的测试宿主中故意跳过首个ACK；宿主终止前的未提交状态由测试故障钩子保持。不是网络设备丢包或真实磁盘故障。SQLite损坏文件拒绝是真实执行；存储不可用ACK保留文件由单元验证。
- 未验证断电、磁盘满、写临时文件中途崩溃、正式奖励业务、16人/100轮、Linux、专用导出或公网。同步PowerShell存储存在阻塞延迟；每库256授权/10000结果、每房128待发送的当前上限没有自动清理策略。M4的正式身份、安全传输、完整资源治理和立即重开房的遗留实例隔离仍未完成，详见docs/13。

### 本轮实际修改文件（41个）

- 根入口/说明：ShowResults.cmd、README.md、STATUS.md。
- 宿主：host/core/result_service.gd、host/core/room_manager.gd、host/storage/sqlite_repository.gd。
- SDK：sdk/roomkit/server/game_adapter.gd、room_runtime.gd、result_outbox.gd；sdk/roomkit/shared/result_format.gd、control_transport.gd。
- 工具：tools/protect_data.ps1、sqlite_store.ps1、results.gd、results.ps1、run.ps1。
- Schema：schemas/result_record.schema.json、result_submission.schema.json、result_ack.schema.json、summary_result.schema.json、control.schema.json。
- 示例：examples/showcase/host.gd；examples/turn_based/adapter.gd、game.gd、game_manifest.json；examples/blocks/game_manifest.json；examples/minimal/multiplayer_manifest.json；examples/result_messages.example.json、m2_messages.example.json。
- 测试：tests/test_results.gd、run_persistence.gd、run_unit.gd；tests/fakes/lost_result_ack.gd；tests/fixtures/result_host.gd、result_room.gd。
- 文档：docs/02_contracts.md、03_sdk_integration.md、06_roadmap_acceptance.md、07_versions_decisions.md、10_environment.md、13_m4_results.md。

## 以下为M3历史：可以打开窗口试玩的两个游戏

Git 交付完成（2026-09-21）：用户已明确授权上传 GitHub，覆盖初始任务中“不推送远端”的限制。首次本地提交为65bd328，源码与文档纳入版本管理；run/、logs/、artifacts/、私有配置与密钥文件继续排除。上传前扫描102个待提交文件，未命中常见GitHub令牌/私钥格式。用户指定远端 https://github.com/SchreiberChiang/godot-network-.git，已配置为origin，并合并保留远端main的初始MIT许可证提交88137fb。首次推送因GitHub未认证失败；用户完成Git Credential Manager设备登录后，git push -u origin HEAD:main 退出0，远端main已从88137fb推进至02a9a37，包含完整源码和文档。本地分支同步命名为main；本状态更新作为后续提交推送。全程未强制推送，未改动全局Git配置。本次只处理Git交付，没有重跑或改变上方运行时验收结果。

用户继续授权后，按 docs/06 从零实现方块移动与无 CharacterBody/武器的回合取石子游戏，范围决定和协议见 docs/12_m3_games.md。宿主与 SDK 核心未改：本轮开始记录的13个 GDScript 文件 SHA-256 全部一致，两个独立产物携带的 SDK 也与源码一致。新增游戏通过自己的 GameAdapter、房间子类和本机注册配置接入。

**试玩方式：** 双击 `StartPlay.cmd`，点击玩家窗口后用 WASD/方向键移动；双击 `StartTurns.cmd`，轮到自己时取1或2颗石子。每个入口打开两个玩家窗口；可退出房间并重新入房，关闭两个窗口后自动结束。建议依次运行两个入口。原 `StartDemo.cmd` 保留 M2 文字自动测试。

### 本轮真实执行

全部命令在 `F:\文档\GodotGame\Net\RoomKit` 执行，使用 `4.7.2.stable.steam.ed1daf0bf` 和 Git 2.55.0.windows.3。当前执行环境无沙箱限制，未修改用户全局配置。下表均以真实退出码及成功标记核实。

| 实际命令 | 退出码 | 结果 |
|---|---:|---|
| powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode all | 0 | unit 229/229；launcher 63/63（句柄320→320）；integration 133/133（22子进程）；demo 4次心跳、leases=0；players 33/33；games 44/44 |
| powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode games -Visual | 0 | 48/48；4个真实图形客户端、2个房间；移动/回合、跨游戏拒绝、退房重入、全部回收；4张实际GPU截图 |
| cmd /c "StartPlay.cmd -Smoke < NUL" | 0 | 17/17；完整批处理入口打开两个方块窗口，自动调用关闭处理程序后回收 |
| cmd /c "StartTurns.cmd -Smoke < NUL" | 0 | 17/17；完整批处理入口打开两个石子窗口，自动调用关闭处理程序后回收 |
| 核心哈希、独立产物及残留核查 | 0 | 核心改动0，产物SDK差异0；无另一游戏代码/Schema或host；当前项目Godot残留0、私有配置0、最终扫描脚本错误0、凭据模式匹配0 |

最新综合日志：`logs/m3-all-run.txt`。机器证据：`logs/games-result.json`（最终44/44）、`logs/m3-visual-result.json`（48/48及截图目录）、`logs/m3-play-blocks-result.json`、`logs/m3-play-turns-result.json`（各17/17）、`logs/m3-final-audit.json`。独立工程索引在 `artifacts/games.json`，各游戏自己的服务器日志在其工程目录 `server.log`。生成产物和日志均忽略入Git。

实际图形验证使用 NVIDIA GeForce RTX 3080 / OpenGL 3.3.0 NVIDIA 591.86。已读取并目视检查两种游戏的最新视口PNG：中文、玩家方块、石子、分数和按钮均正常。截图位置由 m3-visual-result.json 的 evidence_dir 给出；本次为 logs/games-c16df5152b62ed533487e34cf111e533/。图形测试是实际GPU渲染，自动操作仍由代码产生；未用桌面自动化手动点击鼠标/键盘，不能把 -Smoke 描述为人工试玩通过。

### 本轮修复与限制

- 新增玩法单元首次221通过/3失败：数值 enum 经JSON解析为float，旧校验器的数组成员比较不接受原生int；将“只能取1或2”改为语义等价的 integer/minimum=1/maximum=2，保留原失败断言并补充拒绝1.5。没有放宽合法值，也未改SDK。失败证据保留 logs/m3-unit-attempt-failed.log 及对应stderr；最终229/0。
- 原单元恶意 `1e999` 仍触发预期 Exponent too high 警告，拒绝断言通过；没有隐藏该警告。
- 每房真实验证2名玩家，配置最大16；未运行16人、100轮、跨电脑、Linux、浏览器或公网。没有专用服务器可执行文件导出验证：两个产物是独立Godot开发工程。
- 方块没有碰撞、预测或插值；石子分数只在当前房间成员上保留，离房会清除。没有账号、商城、持久化、断线续局或完整游戏。
- 本轮房间子类通过锁定SDK的 members 字典将已准入 user_id 映射到传输peer，未来SDK内部表示变化需要复验。输入/状态协议各归自己游戏，不统一为核心战斗API。
- 私有凭据、路径控制和安全终止沿用M1/M2；同步Windows进程助手的限制仍存在。尚未进行公网安全/容量验收。

### 本轮实际文件清单

新增：

- StartPlay.cmd、StartTurns.cmd；tools/build_games.ps1、play.ps1。
- examples/blocks/README.md、game_manifest.json、room.gd、adapter.gd、game.gd。
- examples/turn_based/game_manifest.json、room.gd、adapter.gd、game.gd。
- examples/showcase/host.gd、client.gd、view.gd；examples/gameplay_messages.example.json。
- schemas/blocks_input.schema.json、blocks_state.schema.json、turns_input.schema.json、turns_state.schema.json。
- tests/test_games.gd、run_games.gd；docs/12_m3_games.md。

修改：host/development.gd（仅注册组合入口）、tests/run_unit.gd、tools/run.ps1、examples/turn_based/README.md、README.md、docs/07_versions_decisions.md、STATUS.md。host/core/ 与 sdk/roomkit/ 源码未修改。未提交、未推送、未部署或花费云资源。

后续为 M4 持久化与故障/安全闭环；当前本机玩法演示不能视为公网或正式发行已完成。

## 以下为 M2 与 M0/M1 历史记录

以下旧结果保留历史含义；共用日志已被本轮回归更新，当前结论以本轮 M3 记录为准。

## 2026-09-20 本轮结果：两名真实测试客户端

用户在 M0/M1 完成后授权继续，范围决定见 docs/11_m2_implementation.md。新增标准 WebSocket JSON 大厅、开发会话身份、创建幂等、版本检查、席位预留和一次性票据、ENet 认证、加载/快照确认、双端 SDK 与 GameAdapter；适配器示例只记录玩家身份，不含角色/地图。

最简单的验证方式：双击 `StartDemo.cmd`，它会自动跑完流程并停在结果页面。正常应看到 `PLAYERS_RESULT passed=33 failed=0` 和 `ROOMKIT_EXIT mode=players code=0`。这次也实际通过 cmd 执行了该批处理入口；没有用桌面自动化模拟鼠标双击。

| 本轮实际命令（均在当前项目目录） | 退出码 | 结果 |
|---|---:|---|
| powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode players | 0 | 33/33；真实 WS + ENet，两个正常客户端及一个非法票据客户端，两个房间进程均退出 |
| powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode all | 0 | 顺序完成 unit 182/182、launcher 63/63、integration 133/133、demo、players 33/33 |
| powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode unit（补充到期竞态和17条协议样例后） | 0 | 最终 201/201；已覆盖加载期限到达但清理尚未执行的边界 |
| cmd /c "StartDemo.cmd < NUL"（最终版本） | 0 | 33/33，中文输出正常，房间/客户端退出，席位和端口归零 |
| 最后只读核查 | 0 | 当前项目 Godot 残留 0；私有配置 0；最终日志脚本错误 0；64位凭据模式匹配 0 |

最终日志：logs/unit-console.log、launcher-console.log、integration-console.log、demo-console.log、players-console.log；机器报告 logs/integration-result.json、players-result.json、m2-final-audit.json。players-result.json 的 evidence_dir 保存本轮各客户端的完整日志及报告。启动器专项十轮句柄为 318→318。单元 `1e999` 恶意输入仍产生预期 Exponent too high 警告；拒绝检查通过，未隐藏警告。

已真实检查：双客户端看到同一房间的两名不同业务身份、场景准备前不能进入 IN_ROOM、正式席位不重复计数、第三人满员拒绝、错误票据不能正式入房、非创建者不能停房、不兼容构建拒绝、离房后沿用同一大厅会话、所有本次启动子进程退出且回收资源。

边界：创建幂等测试是相同 key 重发，不是真实丢包注入；过期/重放/跨房/跨游戏票据主要由单元测试验证；慢加载使用异步计时器，快照只有成员名单。真实客户端是自动化 headless 测试程序，还没有可操作游戏画面。未运行跨电脑、浏览器、Linux、导出产物、公网、16 人或100轮压力。未做账号、商城、持久化、断线续局、第二玩法或插件发布。SDK 目前管理默认 SceneMultiplayer，每客户端进程一个实例。

本轮失败与修复：最初新增单元有 1 项失败（181/1），原因是 GDScript 点号赋值生成 StringName 字典键被内部校验拒绝；允许 String/StringName 对象键后通过，线上的 JSON 仍严格校验。复核中补上加载到期确认检查。批处理入口首次实际运行暴露 UTF-8/LF 被 cmd 错误拆行，未启动测试且 shell 误报0；改成 CRLF、保留内部退出码，并加入 .gitattributes 后重新运行通过。没有将这些失败当作成功。

本轮新增文件：

- .gitattributes、StartDemo.cmd。
- host/lobby_server.gd、host/core/admission_store.gd。
- sdk/roomkit/client/room_client.gd；sdk/roomkit/server/game_adapter.gd、room_runtime.gd；sdk/roomkit/shared/json_wire.gd、net_room.gd。
- schemas/lobby_request.schema.json、lobby_response.schema.json、admission_hello.schema.json、admission_reply.schema.json、room_snapshot.schema.json。
- examples/m2_messages.example.json；examples/minimal/multiplayer_manifest.json、multiplayer_room.gd、empty_adapter.gd、test_player.gd。
- tests/test_admission.gd、run_players.gd；docs/11_m2_implementation.md。

本轮修改文件：host/core/room_manager.gd、host/development.gd、schemas/control.schema.json、sdk/roomkit/shared/schema_validator.gd、control_transport.gd、tests/run_unit.gd、tools/run.ps1、README.md、sdk/roomkit/README.md、docs/07_versions_decisions.md、docs/09_m1_control.md、docs/10_environment.md、STATUS.md。运行证据和诊断探针位于已忽略的 logs/。本仓库仍未提交或推送。

## 以下为 M0/M1 历史验收记录

以下 2026-09-19 的数字保留为历史记录；通用日志文件已由上述 2026-09-20 回归更新，当前数字和边界以上述本轮结果为准。

## 已完成

- 独立 Godot 工程、可重复运行的 demo／单元／真实进程入口；Git 仅初始化于当前目录，未提交、未推送。
- GameRegistry：Schema 校验、管理员产物白名单、模式／地图／人数校验；远程式创建参数不能指定执行路径。
- RoomManager / PortAllocator：创建、分配、启动、注册、READY、心跳、停止、核实退出、UDP 重绑定后回收。FAILED 与 cleaned 分开；未知身份或忙端口保持隔离。
- Windows ProcessLauncher：参数数组启动；校验本次 launch_id、PID、父进程、程序路径、创建时间。强制停止使用已持有的进程句柄；缓存句柄回收仅用于精确验证过的引擎构建。
- ControlTransport：4 字节大端长度 + UTF-8 JSON、拆包／粘包／部分写入、队列上限、严格 JSON、有限数与深度检查；协议从 schemas/ 读取。
- 无玩法房间实际创建 ENet UDP 服务后才发送 READY；双向控制心跳；已认证控制断开立即退出 READY 并开始清理。
- 私有配置只写当前项目 run/，ACL 限当前用户，注册后删除；命令行仅含 launch_id 与配置路径，公开快照不含凭据。
- 具体示例注册移到 host/development.gd，host/core 与共享 SDK 不引用示例场景或玩法。

## 最终真实结果

所有下列命令均在 F:\文档\GodotGame\Net\RoomKit 执行，日期为 2026-09-19；通过退出码和成功标记共同确认。

| 实际命令 | 退出码 | 结果 | 证据 |
|---|---:|---|---|
| powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode unit | 0 | 150 通过、0 失败 | logs/unit-console.log；logs/unit-stderr.log |
| powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode integration | 0 | 133 通过、0 失败；22 个真实子进程 | logs/integration-console.log；logs/integration-result.json |
| powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode demo | 0 | DEMO_PASS；4 次心跳；leases=0 | logs/demo-console.log |
| powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode launcher | 0 | 10 轮真实子进程、63 通过、0 失败；句柄 324→324 | logs/launcher-console.log |
| 最终只读进程、配置和日志核对 | 0 | 当前项目 Godot 残留 0；私有启动文件 0；未清理房间 0；最终日志未检出 64 位控制凭据模式 | logs/final-audit.json |

unit 是 Godot 内执行的算法／契约／模拟测试，并包含真实回环 UDP 探测；部分写入使用可控写入器模拟，不能称为内核真实部分写入测试。integration 使用真实 Windows Godot 子进程、TCP 和 ENet UDP；占用端口由另一个真实进程持有，只有分配后争用窗口由测试分配器注入。launcher 是进程专项，不混称房间联机测试。

unit 对恶意 JSON `1e999` 的拒绝用例触发 Godot `Exponent too high` 警告，最终拒绝断言通过；没有隐藏警告。其余最终 launcher/integration/demo stderr 为空。

## G00–G09

| 编号 | 最终状态 | 证据范围 |
|---|---|---|
| G00 | 已通过 | 工作目录与 Git 根一致；实际 Godot 4.7.2.stable.steam.ed1daf0bf，Git 2.55.0.windows.3，Windows 10.0.26200.0 |
| G01 | 已通过：真实进程 | 完整 ALLOCATING→STARTING→READY→DRAINING→STOPPING→STOPPED；注册、UDP 被房间占用、心跳、停止通知、OS 退出与回收分别检查 |
| G02 | 已通过：单元＋真实宿主 | 未知游戏／执行路径注入拒绝；缺失程序 PROGRAM_NOT_FOUND，租约与私有配置回收 |
| G03 | 已通过：真实进程＋竞态注入 | UDP 占用不 READY；占用者未被误杀；失败进程退出后端口仍隔离，直到占用者退出可重绑定 |
| G04 | 已通过：真实进程 | 不注册与不 READY 均 START_TIMEOUT，并核实退出和回收 |
| G05 | 已通过：真实双房 | 仅终止身份已核验的 A，A 为 PROCESS_EXITED 并清理；B 继续心跳 |
| G06 | 已通过：单元／可控写入 | 拆包、粘包、UTF-8 边界、部分写、零写、错误写、长度／深度／队列上限、非法消息、非有限数 |
| G07 | 已通过：模拟＋真实 TCP | 在 STARTING 注册前注入错误 token、正确 token 配错误 launch，均拒绝；随后真实子进程正常注册 READY；模拟另测 PID 与重复注册 |
| G08 | 已通过：真实房间 | 连续 10 轮 READY/停止/退出/回收；所有记录子进程已退出、活动记录和端口租约为 0；独立启动器 10 轮句柄计数不增长 |
| G09 | 已通过：运行证据＋源码核对 | 所有 listen/bind/connect 显式回环；请求不能带执行路径，快照无 token，私有配置删除；最终 ACL 仅当前用户，最终日志凭据格式扫描为 0；只在本项目修改 |

附加真实测试：拒绝正常停止后按期限安全终止；控制断开但子进程仍活着时立即失败并清理；无心跳与模拟步停滞分别返回 HEARTBEAT_TIMEOUT / LOGIC_STALLED。

## 本轮遇到并修复的失败

- 初次集成脚本 check-only 退出 1：两处 Variant 推断缺少显式类型；修复后通过。
- 单元初次完整运行 133 通过／5 失败：四处测试把 JSON 解码 float 与原始 int 字典作严格深比较；真实 Godot 探针证实标量相等而字典不等，改为明确线上接收类型，仍验证全文、结构、顺序与逐字节数据。第五项为 ACL 重复设置触发 SeSecurityPrivilege；改为只修改 DACL，连续执行两次通过。保留 logs/unit-attempt-failed.log 与对应 stderr。
- 第一次真实房间集成 130 通过／3 失败，退出 1：新 delayed_register 用例提前建立 TCP 但延迟发送认证，触发正常认证期限。改成延迟建立连接，保留认证门禁；最终 133/0。首轮记录 logs/integration-attempt-failed.log/json 保留；失败运行也完成全部子进程回收。
- 暂停前 2026-09-18 曾有沙箱 setup refresh 错误、被拒绝的权限检查，以及沙箱 WMI 权限不足导致真实启动器专项失败；这些不算通过。本次环境已无沙箱限制，未修改用户全局权限配置。
- 上轮大补丁工具调用卡住后拆成小补丁落盘；本轮补齐当时未完成的 tests/test_transport.gd。

## 实际文件变更

从初始设计包新增：

- project.godot；config/development.json。
- host/main.gd、host/main.tscn、host/development.gd；host/core/game_registry.gd、port_allocator.gd、room_manager.gd；host/platform/process_launcher.gd。
- sdk/roomkit/README.md；sdk/roomkit/shared/schema_validator.gd、protocol.gd、strict_json.gd、control_transport.gd。
- schemas/control.schema.json；examples/control_messages.example.json。
- examples/minimal/game_manifest.json、room.gd；examples/turn_based/README.md；templates/README.md。
- tests/run_unit.gd、run_integration.gd、test_transport.gd、test_registry_ports.gd、test_manager.gd、test_launcher.gd、test_launcher_real.gd；tests/fakes/fake_launcher.gd；tests/fixtures/udp_holder.gd、racing_ports.gd。
- tools/run.ps1、protect_runtime.ps1、process_identity.ps1；docs/09_m1_control.md、docs/10_environment.md。

修改已有文档：README.md、STATUS.md、docs/02_contracts.md、docs/07_versions_decisions.md。原始设计／Schema 外壳与清单来源保留。运行日志与调试探针在已忽略的 logs/，不作为运行时代码；run/ 当前只有 .gdignore。没有提交、推送、部署、花费云资源或变更用户全局 Git 配置。

## 本机启动与验证

```powershell
Set-Location 'F:\文档\GodotGame\Net\RoomKit'
# 自动创建一间房，心跳后停止并退出
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode demo
# 依次执行单元、启动器专项、房间集成及 demo
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode all
```

引擎：D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe；可用 -Godot 指定路径，但更换版本要重新验收。config/development.json 配置 UDP 28100–28131、系统分配控制 TCP 端口和超时。需要正常用户有权查询自己创建的 Windows 进程并设置本项目 run/ DACL，不需要下载其它后端。详细说明见 README.md、docs/10_environment.md。

每个模式必须同时输出成功标记和 ROOMKIT_EXIT mode=... code=0。-Mode all 是上述已验证各模式的顺序入口；本轮实际命令按表逐项运行。

## 明确未运行／限制

- 未运行专用服务器导出产物、Linux、16 人、100 轮压力、浏览器或公网。虽然已找到 4.7.2 导出模板，当前使用的是开发工程子进程。两名本机真实测试客户端已经由 2026-09-20 的 M2 验证补齐。
- M2 大厅、身份、票据和源码双端 SDK／GameAdapter 回调已实现；可分发插件与完整模板、M3 第二玩法、M4 持久化／安全／宿主重启恢复、M5 发布压测未完成。
- 无崩溃续局或宿主重启认领保证。失败进程身份不明／端口仍忙时保持隔离，不通过未经核验的 PID 强行回收。
- Windows 辅助程序目前同步执行；CIM 操作有 3 秒超时，但辅助程序整体尚无独立总超时，异常系统阻塞可能影响宿主心跳。测试入口有 240/60 秒总 watchdog；常驻生产服务仍需异步进程管理与总超时改进。
- 原生句柄回收针对精确 Windows Godot 4.7.2 Steam 源码 hash 验证；其他引擎不执行该专用回收路径，不能沿用本轮句柄结论。

本历史记录之后，M3 已按上方新记录完成本机双玩法开发工程验证；后续仍不能将这些结果当作完整游戏、公网或正式导出验收通过。
