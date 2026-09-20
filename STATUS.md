# 实际开发状态

更新：2026-09-20。**M0/M1、M2 接入闭环与 M3 本地双玩法开发工程验证已完成。** 现在可打开窗口操作方块移动或回合取石子；两个游戏可以同时开房，四名客户端实际操作、退房重入并回收。所有证据限本机 Windows / Godot 4.7.2；未读取、复制或修改旧游戏／服务器。

## 本轮 M3：可以打开窗口试玩的两个游戏

Git 交付准备（2026-09-21）：用户已明确授权上传 GitHub，覆盖初始任务中“不推送远端”的限制。本次使用 Git 命令行整理首次提交，源码与文档纳入版本管理；run/、logs/、artifacts/、私有配置与密钥文件继续排除。上传前扫描102个待提交文件，未命中常见GitHub令牌/私钥格式。尚无目标远端，Git Credential Manager 未发现已登录的GitHub账号；当前不能将本地提交表述为已经上传。本次只处理Git交付，没有重跑或改变上方运行时验收结果。

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
