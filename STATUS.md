# 当前状态：通用管理服务、账号、资产与射击示例

更新：2026-09-27。分支 `codex/shooter-framework`；账号请求改造和复核已整理为本地提交。本文件只记录**当前**状态、最新有效验证范围、未运行项与已知问题；逐轮过程、失败修复细节与原始证据链接见 [STATUS 历史归档](docs/archive/status_history.md)。启动方法见 [README](README.md)。

## 工作区与交接

- 提交 `4a2e11d` 收录了 2026-09-26 的三轮源码工作（托管新游戏模板、客户端双击无窗口修复、射击平滑/短弹迹/房间规则），以及 2026-09-27 的文档整理和项目插画；已推送到 `origin/codex/shooter-framework`，未部署。
- 2026-09-27 本轮相对 `4a2e11d` 完成账号请求去文件化（Claude 实现、Codex 复核）：修改 `host/core/account_service.gd`、`host/platform/bounded_helper.gd`、`tools/account_store.ps1`、`tools/bounded_helper.ps1`、`tools/test_helpers.ps1`、`tests/run_admin_http.gd`、`docs/21_managed_protocol.md`、`docs/22_framework_operations.md`、`docs/23_branch_files.md` 和本文件；新增 `tests/run_storage_timing.gd`、`tests/fixtures/storage_cost_breakdown.ps1`。运行证据在 Git 忽略的 `logs/`。
- 环境：Windows 10.0.26200；Godot `4.7.2.stable.steam.ed1daf0bf`（`D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`），导出使用同安装目录的 4.7.2 official 模板；Git `2.55.0.windows.3`；系统 `winsqlite3.dll` 3.51.1。

## 当前已实现

- **独立管理服务（Operator）**：回环 HTTP 中文后台，持有 SQLite 账号与资产库；通过认证的回环 TCP 启动、停止、重启、维护游戏宿主；宿主停止后后台继续运行。停服默认公告 60 秒；崩溃后确认旧进程退出、端口可重绑才重启，10 分钟最多 3 次。
- **账号**：邀请码注册、用户名密码登录（PBKDF2-SHA256，60 万次迭代）、单玩家会话、改昵称/密码；管理员重置、封禁/解封、踢出，并有持久审计。账号请求（含密码、session token、邀请码）经 Godot 管道写入助手的标准输入，不写请求文件（2026-09-27 起）。
- **永久资产**：金币、经验与等级阈值表、非堆叠所有权、按游戏分开的默认配置；独立或 shared 资产空间；购买、选择与流水同事务，幂等重试不重复扣款；成绩与奖励同事务结算。比赛临时经济与永久钱包分开。
- **运维**：在线备份（每 30 分钟，保留 48 份）、恢复前备份、恢复后撤销会话；进程身份核验，只回收本次创建且已核验的进程。
- **房间**：每房一个 Godot 进程；WSS 大厅 + DTLS/ENet；房间实际绑定 UDP 后才 READY；资产许可与异步刷新按成员代次隔离。可信清单可以声明通用整数 `room_rules`，宿主只校验范围，具体含义交给游戏适配器。
- **横版射击示例**（`shooter-dev-002` / `shooter-v2` / `game_protocol=2`）：自由混战，三把枪，服务器权威即时命中，死亡后可开背包选枪并手动复活，整局结算发奖。房间可设每局时长 30–3600 秒、获胜击杀数 0–1000（0 为不限）、复活等待 0–60 秒；已有房间用“规则 / 重建”修改。客户端对人物做 50 ms 显示平滑，并绘制最长 18 像素的短弹迹。
- **取石子示例**：共用同一账号和资产服务，可购买并选用玉石主题。
- **新游戏接入**：`tools/new_game.ps1 -Managed -GameId <id>` 生成自带 SDK 0.5.0、账号客户端、独立房间、资产目录/策略和结果 Schema 的工程；Operator 按受信注册表（`schemas/managed_game_registry.schema.json`）组装服务，宿主核心和 SDK 里没有射击或取石子的分支。
- **源码启动器**：`StartShooterClient.cmd` / `StartManagedTurns.cmd` 以可见窗口启动；要等到窗口稳定出现才报告成功，并为每次启动单独保存日志。

## 当前交付物

| 交付物 | 状态 |
|---|---|
| 源码入口 `StartManagement.cmd` / `StartShooterClient.cmd` / `StartManagedTurns.cmd` / `StopManagement.cmd` | 当前推荐，包含全部 2026-09-26 修改 |
| 最新独立包 `artifacts/RoomKit-0.5.0-framework-windows-f4f40384083d45e28ffa38bcb5dea472.zip`（索引 `artifacts/framework-release.json`，SHA256 `49b8f13f92917b1305b9d2529bed9c371dce4c8397015501152e81ca542e173e`） | 2026-09-22 构建并验收；**不含** 09-26 的模板注册、启动器修复和房间规则，其射击客户端（shooter-v1）与当前源码的 shooter-v2 不兼容。需要重新构建并验收 |
| 早期无账号演示入口（仓库根 `StartPanel.cmd`、`StartPlay.cmd`、`StartTurns.cmd`、`StartDemo.cmd`、`ShowResults.cmd`）及 0.1.0 包 | 保留但不推荐，见 [早期入口](docs/archive/early_entrypoints.md) |

## 最新有效验证范围

每项的计数都是断言数，不是玩家数。“代码版本”指该结果对应的源码：**09-27** 表示当前工作区代码（账号请求 stdin 改造后）；**09-26** 表示提交 `4a2e11d` 中的同一批源码（改造前）；**09-22** 表示提交 `f0b4c8b` 前后的代码。同一专项以最新日期的结果为准。所有结果都只在同一台 Windows 电脑上取得。

### 2026-09-27（当前工作区代码：账号请求 stdin 改造后）

| 命令 / 专项 | 结果 | 范围与证据 |
|---|---|---|
| Godot `tests/run_storage_timing.gd -- --rounds=5 --label=final` | 53/0 | 真实账号/资产/结果服务的存储层计时；账号操作期间数据目录未出现任何临时文件；20 次账号调用前后 Godot 句柄 323 → 324；`logs/storage-timing-final.json` |
| 同上，改造前代码（`--label=baseline`） | 48/4（预期失败） | 4 条“账号操作不留请求体文件”断言在旧代码上全部失败，证明检测有效；`logs/storage-timing-baseline.json` |
| `tools/test_helpers.ps1` | 6/0 | 原 3 项（超时终止、路径白名单）＋ stdin 模式 3 项：中文请求体逐字节到达且不产生文件、stdin 模式超时仍终止子进程、非法请求体拒绝；`logs/helpers-stdin.stdout` |
| `tools/run.ps1 -Mode unit / accounts / assets / result_rewards / managed_contracts / managed_registry` | 320/0；81/0；83/0；74/0；273/0；77/0 | 均退出 0；`logs/stdin-regression-<模式>.txt` |
| `tools/run.ps1 -Mode admin_http` | 139/0，退出 0 | HTTP 层接收格式正确的资产空间映射并交给 Operator 注册表校验；非法路径在 HTTP 层拒绝。旧测试在改造前后的 137/1 记录保留于 `logs/stdin-regression-admin_http.txt`、`logs/stdin-regression-admin_http-HEAD-4a2e11d.txt`；本次复核结果 `logs/admin_http-console.log`。 |
| `tools/test_helpers.ps1`；Godot `tests/run_storage_timing.gd -- --rounds=1 --label=review` | 6/0；17/0，均退出 0 | Codex 复核中发现 Windows PowerShell 5.1 标准输入可能带 UTF-8 BOM；指定无 BOM 输入编码后，中文请求体测试和真实注册/登录/购买/结算小回归通过；证据 `logs/review-storage-timing.stdout`、`logs/storage-timing-review.json`。 |
| Godot `tests/run_account_recovery.gd` | 30/0 | 真实 SQLite 重开、清理玩家会话、恢复审计回滚；`logs/stdin-e2e-account_recovery.txt` |
| `tests/test_managed_template.ps1` | 74/0 | 真实 Operator/宿主/房间、WSS+DTLS/ENet 下注册、登录、发币、购买与幂等重放；`logs/stdin-e2e-managed_template.txt` |
| `tests/test_room_rules.ps1` | 18/0 | 两名真实注册玩家与 30 秒规则局；`logs/stdin-e2e-room_rules.txt` |
| `tests/test_asset_response_loss.ps1` | 25/0 | 真实 WSS 断连后重新登录，同一 operation_id 返回 DUPLICATE、只扣一次；`logs/stdin-e2e-asset_response_loss.txt` |
| `tests/test_operator.ps1 -Lifecycle` | 29/0 | 真实 60 秒重启、崩溃注入、恢复后清理玩家会话；`logs/stdin-e2e-operator_lifecycle.txt` |
| `tests/test_framework_capacity.ps1` | 174/0 | 16 个真实账号注册登录并满房，第 17 人 ROOM_FULL；`logs/stdin-e2e-framework_capacity.txt` |

端到端专项由 `logs/run-stdin-e2e-20260927.ps1` 顺序执行，汇总见 `logs/stdin-e2e-summary.txt`；日志中没有脚本、解析或编译错误，运行后项目相关进程残留为 0，`data/` 下没有新增 `account-request-*` 文件。句柄回收依据的引擎行为另有探针证据：连续 40 次管道调用，回收时句柄 322 → 322，不回收时 322 → 402（`logs/stdin-pipe-probe-20260927/result.txt`）。

**存储层实测耗时**（5 轮中位数，毫秒；不含 WSS/大厅/房间/Operator RPC 时间）：

| 操作 | 改造前 baseline | 改造后 stdin | 改造后 final | 存储往返次数 |
|---|---:|---:|---:|---|
| 注册 | 3104 | 2988 | 3195 | 1（含 1 次 PBKDF2） |
| 登录 | 3149 | 3027 | 3190 | 1（含 1 次 PBKDF2） |
| 会话校验 / 登出 | 1191 / 1161 | 1136 / 1094 | 1159 / 1181 | 各 1 |
| 管理员发币 | 3071 | 3079 | 3253 | 3 |
| 购买 | 3104 | 3065 | 3347 | 3（receipt → read → commit） |
| 购买幂等重试 | 1026 | 1017 | 1095 | 1 |
| 结算（成绩＋奖励同事务） | 1070 | 1080 | 1166 | 1 |

成本拆解（`tests/fixtures/storage_cost_breakdown.ps1`）：PowerShell 冷启动约 210–290 ms，每次往返启动两次（外层有界助手＋内层存储脚本）；每次往返重新编译 SQLite 绑定约 150 ms，账号请求再编译密码类约 95 ms；PBKDF2-SHA256 60 万次迭代约 1.87–1.94 s。三轮之间的差异（final 一轮所有操作偏慢 5–8%，同轮 PowerShell 冷启动也变慢）属于机器负载波动；改造对耗时没有可测量的影响。

### 2026-09-26（提交 `4a2e11d` 中的源码，改造前；与 09-27 表同名的项以 09-27 为准）

| 命令 / 专项 | 结果 | 范围与证据 |
|---|---|---|
| Godot `tests/run_unit.gd`（等价 `tools/run.ps1 -Mode unit`） | 320/0 | 规则、契约、模拟生命周期；`logs/rules-run_unit.stdout` |
| Godot `tests/run_shooter.gd` | 83/0 | 射击规则、击杀目标提前结算、平滑/传送/弹迹去重；`logs/rules-run_shooter.stdout` |
| Godot `tests/run_managed_contracts.gd` | 273/0 | 管理/账号/资产协议正负例；`logs/rules-run_managed_contracts.stdout` |
| Godot `tests/run_managed_registry.gd` | 77/0 | 注册表、兼容、共享目录、失败原子性；`logs/rules-run_managed_registry.stdout` |
| `tests/test_room_rules.ps1` | 18/0 | 真实 Operator/宿主/房间与两名注册玩家，经 WSS/DTLS/ENet 收到自定义规则，打满一局 30 秒；非法重建保留旧房，合法重建后复用端口；`logs/room-rules-9eb8231a3e8b4f04927b1ee09f4392d8/result.json` |
| `tests/run_shooter_visual.gd`（baseline / smoothed） | 59.83 → 60 渲染 FPS；位置变化 20 → 59 次/秒 | 真实 OpenGL 渲染 + 合成的 20 Hz 状态，不是真实对局帧率或网络延迟；`logs/shooter-visual-{baseline,smoothed}.{json,png}` |
| `node tests/test_admin_room_rules.cjs`；`node tests/test_admin_asset_spaces.cjs` | 10/0；12/0 | 实际页面函数 + DOM/API 替身，不是浏览器点击 |
| `tests/test_managed_template.ps1` | 74/0 | 两个生成的新游戏、真实 Operator/宿主/房间、WSS+DTLS/ENet、SQLite；`logs/managed-template-89aff6560f914ceeadeef7f0b9dfa251/result.json`（房间规则修改之前运行） |
| `tests/test_operator.ps1 -Lifecycle`（隔离源码副本） | 29/0 | 共享钱包、备份恢复、真实 60 秒重启、崩溃注入与回收；`logs/framework-final-regression-20260926.log`（房间规则修改之前运行） |
| `tools/run.ps1 -Mode template` | 10/0 | 早期开发身份模板入房/离房；`logs/template-resume-20260926.log` |
| `tests/test_client_launcher.ps1`；真实 `run_framework.ps1 -Mode client -Game shooter` | 14/0；窗口可见 | 缺引擎/缺文件/早退时报失败；真实登录窗口截图 `logs/client-starts/shooter-dc4024f03fa2493cb8ac91169923952d/window-full.png`，没有登录或联机 |
| `node tests/test_admin_auth_errors.cjs` | 12/0 | 页面函数 + 替身 |

### 2026-09-22（提交 `f0b4c8b` 代码；accounts、account_recovery、assets、result_rewards、admin_http、asset_response_loss、framework_capacity 已于 09-27 重跑，以 09-27 表为准，其余未重跑）

| 层级 | 专项与结果 | 证据 |
|---|---|---|
| 真实 SQLite | accounts 81/0；account_recovery 30/0；assets 83/0；result_rewards 74/0；operator_maintenance 35/0；asset_audit 14/0 | 各自 `logs/*-console.log`，明细见归档 |
| 真实 HTTP / 投影 / 替身 | admin_http 138/0；operator_projection 9/0；operator_auth_errors 6/0；asset_callbacks 32/0；framework_feedback 7/0；operator_logs 14/0 | 同上 |
| 真实多进程联机 | framework_clients `-Visual` 47/0（两种玩法，完整打满 300 秒射击局）；managed_shutdown 55/0；operator_schedules 52/0（受控时间）；framework_capacity 174/0（16 人满房，第 17 人 ROOM_FULL，持续 17.5 秒）；asset_response_loss 25/0；players 33/0；integration 133/0；recovery 24/0 | `logs/operator-68c27ae5f8bb40de977cdebca3ac19c6/clients-a982c3c81bb5453e9e802048a58c0068/result.json`、`logs/capacity-0f1e2cdae67c42a79129524c40530eef/result.json` 等 |
| 导出程序 | `tools/build_framework_release.ps1` 生成 6 个 EXE/PCK；`tests/test_framework_release.ps1` 44/0 | `logs/framework-release-0316ee0928e647b8b324ddd6a43e37b9/result.json` |
| 人工 UI（内置浏览器 + 原生 Client.exe） | 管理员设置、开服/建房、邀请码、发币、备份/恢复、审计、维护、封禁、60 秒停服；原生射击击杀/死亡背包/解锁/复活/300 秒结算；原生取石子主题与对局 | `logs/framework-ui-f6f9a767f89b47e1ab229fac2dd02d1f/`、`logs/framework-ui-6da6c5f70d2048c2b5e3e7d2510324de/`、`logs/framework-ui-deb891a63a1e4749b0865bfb6a3f2c2d/` |

### 2026-09-21（早期宿主，仍有效的基础结论）

`tools/run.ps1 -Mode all` 共 1144 条断言，其中 stress 用真实 100 轮开关房（404/0），load 用 20 个加密输入客户端（95/0），secure 37/0，limits 8/0；WSL Ubuntu 上 `PortableCheck.x86_64` 通过 215 项可移植检查（协议/准入/玩法，**不是** Linux 宿主）。明细见归档。

## 未运行 / 未验收

- 第二台实体设备的局域网联机（曾询问用户，未收到答复）、Linux 完整宿主、公网与公网 WSS 发布、长期满载压测、24 小时备份保留周期。
- 当前源码的新独立导出包（本轮未重新构建，独立包内的账号请求路径未实测）；新管理表单（房间规则）的真实浏览器点击；真人操作手感；托管模板的图形界面。
- 09-27 改造后未重跑：`tests/test_framework_clients.ps1 -Visual`（需两个终端、完整 5 分钟对局）、`test_managed_shutdown.ps1`、`test_operator_schedules.ps1`、`test_operator_maintenance.ps1`、`test_asset_audit.ps1`、`tools/run.ps1 -Mode players / integration / recovery` 及完整 `-Mode all`。这些专项的账号调用使用夹具，或者根本不经过账号助手。
- 经 WSS 的端到端单次延迟没有单独计时；上面的数字只是存储层耗时。
- 断电、磁盘满、真实网络丢包/延迟、证书轮换、外部身份服务。

## 已知问题与限制

1. **仅限 Windows**：账号、资产、结果存储和进程身份核验都通过 PowerShell 助手与 `winsqlite3.dll` 实现，Linux 上直接返回 `UNSUPPORTED_STORAGE`。
2. **存储调用开销（09-27 已实测，未优化）**：每个存储往返约 1.0–1.2 秒，是两次 PowerShell 冷启动加上每次重新编译 C# 所致；注册和登录另有约 1.9 秒的 PBKDF2（有意保留的安全成本）。购买需要 3 次往返，约 3.1–3.3 秒。数字见上面的实测表。助手在工作线程执行，初始化与离线管理仍是同步调用。并发下的排队延迟没有单独测量。
3. **临时请求文件的剩余范围**：账号请求已不落盘（09-27）。资产、结果和维护请求仍用私有目录下的短期请求文件，它们不含账号口令或 session token，但结果授权 `grant` 请求带有每房结果签名密钥（该密钥本身也保存在资产库中）。另外，用户真实数据目录 `data/framework/` 下有一个 09-26 23:33 残留的 `account-request-*.json`（104 字节，未读取内容，不能确认其内容或是否过期）和两个 `helper-*.json`；没有读取、移动或删除。
4. **射击网络模型只按局域网设计**：服务器每秒 20 次发送完整状态；客户端只做显示平滑，没有客户端预测，也没有命中回溯（按 [docs/17](docs/17_framework_shooter_plan.md) 的首版范围）。公网延迟下的手感没有评估。
5. **容量与耐久**：16 人满房只持续了 17.5 秒；100 轮开关房是 09-21 的早期宿主做的，托管宿主没有做长期测试。
6. **原因未查明的现象**：09-22 有一个可视化夹具中途消失，没有清理报告（未计为通过）；另有一次管理员意外退出登录，日志里没有根因（同期修复了一个相关的错误码映射缺陷，但不能认定就是根因）。
7. **预期诊断输出**：unit 的恶意指数用例会打印 `Exponent too high`；测试主动断开 TLS 时出现 `mbedtls -0x6c00`。两者都不是失败。
8. `tools/run.ps1 -Mode all` 只包含早期基础回归（外加 panel、assets）；账号、管理、射击和托管专项需按 [docs/22](docs/22_framework_operations.md#测试入口) 单独运行。
9. 早期结果库有容量上限且没有自动归档：每库 256 个授权、10000 条结果，每房 128 条待发送（[docs/15](docs/15_release_operations.md)）。

## 本轮记录（2026-09-27）

**存储耗时实测与账号请求去文件化（Claude 实现、Codex 复核）**：用户要求先实测注册、登录、购买、结算的耗时，再消除明文账号请求临时文件；保持协议、事务和幂等行为不变，不引入新的后端语言，跑真实 Godot 回归。

- 完成：新增 `tests/run_storage_timing.gd` 与成本拆解夹具，在改造前后各跑 5 轮（结果见上文实测表）。`AccountService` 改用新增的 `BoundedHelper.execute_input`：通过 `OS.execute_with_pipe` 把 base64 UTF-8 JSON 写入 `bounded_helper.ps1` 的标准输入，外层助手再写入 `account_store.ps1` 的标准输入；`account_store.ps1` 删除了 `-Request` 文件参数，8192 字节上限和 `INVALID_ACCOUNT_REQUEST` 保持不变。其它助手调用仍用原来的文件模式。`execute_with_pipe` 会在 Godot 进程表里保留子进程句柄，所以确认退出后，按与 `ProcessLauncher` 相同的 Godot 4.7.2 版本门槛调用 `OS.kill` 释放句柄；依据是引擎源码（`platform/windows/os_windows.cpp` 4.7.2-stable）和上文探针。外层助手在异常路径中会通过持有的句柄终止仍在等待输入的子进程。账号 SQL、事务、限流、审计和线上协议均未改动。
- 失败与修复：`admin_http` 原有 137/1 在 Codex 复核时确认为旧测试混淆了 HTTP 格式校验与 Operator 注册表校验；测试分层修正后 139/0。改造前基线的 4 条去文件断言按预期失败。过程中修正过两处测试脚本问题：`test_helpers.ps1` 起初含中文字面量，改为用字符码构造以符合 .ps1 只用 ASCII 的约定，重跑 6/0；计时脚本加入句柄断言后重跑为 53/0。
- 未运行：见上文“未运行 / 未验收”。本轮没有删除 `data/framework/` 下的旧残留文件；已做本地提交，未推送或部署。

**Codex 复核补充**：复现 `tools/test_helpers.ps1` 的中文请求体失败，确认 Windows PowerShell 5.1 的内层标准输入默认 UTF-8 BOM 会污染 base64 第一字符；在 `bounded_helper.ps1` 内部指定无 BOM 控制台输入编码后，真实助手 6/0、Godot 单轮存储调用 17/0。测试夹具输出编码对齐实际账号脚本。修正 `tests/run_admin_http.gd` 的职责分层断言后 139/0；运行结果与失败来源均已记录。结果授权 `grant` 的签名密钥仍可能进入私有临时请求文件，作为后续独立改造项。本次未修改或删除用户真实数据目录中的残留文件。

**Codex 独立复核（源码和文档）**：在本机实际执行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode unit`（320/0）、`-Mode shooter`（83/0）、`-Mode managed_contracts`（273/0）、`-Mode managed_registry`（77/0），均退出 0；`powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test_client_launcher.ps1`（14/0，退出 0，证据 `logs/client-launcher-80b3e390cfcc4e4fa6c3d408675a71da`）；`powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test_room_rules.ps1`（真实本机 Operator、宿主、房间和两玩家 WSS/DTLS/ENet，18/0，退出 0，证据 `logs/room-rules-da5027610f3947a3a3fc8b139f30fbd2/result.json`）。独立扫描 333 个 Markdown 本地相对链接，缺失 0；`git diff --check` 退出 0；立绘副本 SHA256 与生成源一致。此次未重跑托管模板 74 项、完整 `-Mode all`、浏览器人工操作、跨设备、Linux 或新导出包。用户已明确同意本轮本地提交沿用仓库上次提交的作者身份，仅通过单次 Git 命令传入；未读取或修改全局 Git 配置。

**项目插画**：用户选定的 Claude 二次元角色立绘已保存为 [docs/assets/claude-character.png](docs/assets/claude-character.png)，SHA256 `D530B536AF330D88FF27A58CC65D84FD847C9042123FE4966F4994DD0AF43B7B`，非游戏玩法资产。路径已记入 AGENTS.md 供双方交接，并已随 `4a2e11d` 推送。

**协作规则（仅文档）**：AGENTS.md 已记录 Claude 负责主要实施、Codex 负责复核的分工，以及阶段试玩、交接、并行目录隔离和技能选择规则。没有切换模型，也没有改动代码或测试结论，原文见归档。

**文档整理（Claude，仅文档）**：用户要求 README 只保留当前推荐入口，STATUS 只保留当前状态，历史过程归档并保留证据链接，同时合并重复的入门说明、修复引用；不改代码、不删证据、不提交。

- 完成：STATUS 全部历史原文迁入 [docs/archive/status_history.md](docs/archive/status_history.md)，逐行校验除本文件标题外无遗漏。README 改为当前入口，原文与早期入口迁入 [docs/archive/early_entrypoints.md](docs/archive/early_entrypoints.md)。根目录 `START_HERE.md`、`VALIDATION.md` 合并移入 [docs/archive/design_package_v0.2.md](docs/archive/design_package_v0.2.md)。README 的测试模式表并入 docs/22，目录地图并入 docs/01；docs/22 的 09-22 专项结果移入归档。CHANGELOG 改为只记版本变化。修复 docs/15、docs/16、docs/08 对已归档或已移动文件的引用，并在 docs/23 补记本轮文件。
- 检查：用 Node 脚本检查全部 Markdown 的相对链接和锚点，并核对仓库文件路径的纯文本引用；另对 STATUS/docs/22 被搬走的行逐行比对。结果见本轮报告。
- 未运行：本轮没有运行 Godot、联机或任何代码测试，上面的测试结论沿用原记录。开始前已把所有 Markdown 的基线快照和 SHA256 存到本会话临时目录，用于核对差异范围；AGENTS.md 与他人未提交的源码改动均未触碰。
