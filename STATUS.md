# 当前状态：通用管理服务、账号、资产与射击示例

更新：2026-09-27。分支 `codex/shooter-framework`；账号请求与 grant 密钥去文件化、资产 `asset.snapshot` 往返合并、常驻存储方案 B 第一阶段、8 字符密码和 Linux 待验收设备登记均已整理为本地提交，尚未推送。Codex 已复核常驻存储代码与证据，并独立重跑其专项。之后基于 `d79b1fc` 实现的测试阶段账号删除已由 Claude 实现、Codex 复核并本地提交为 `96d25d1`；独立 ZIP 已重建，包测试见下文。用户反馈已实际测试删除账号功能，未发现问题；测试入口及具体步骤未记录，不把这次反馈扩展成其他环境的验收。本文件记录当前状态、最新有效验证范围、未运行项与已知问题；较早过程见 [STATUS 历史归档](docs/archive/status_history.md)。启动方法见 [README](README.md)。

后续产品取舍见 [docs/17 第五节](docs/17_framework_shooter_plan.md)：2–8 人熟人试玩、可选框架服务、赛车与合作种田边界、累计房间授权回收、8 字符密码和存储性能路线已讨论确认。资产 `asset.snapshot` 往返合并后，又按 [docs/17 第六节](docs/17_framework_shooter_plan.md#六常驻存储评估2026-09-27claude-实测仅评估未实施) 实施常驻存储第一阶段：资产读写和会话校验走常驻进程，客户端实测购买约 0.1 秒（旧路径约 3.7 秒），旧路径保留为可切换的回退。8 字符最低密码长度已在源码工作区实施；授权回收仍未实施，方案 C 暂缓。

## 工作区与交接

- 提交 `4a2e11d` 收录了 2026-09-26 的三轮源码工作（托管新游戏模板、客户端双击无窗口修复、射击平滑/短弹迹/房间规则），以及 2026-09-27 的文档整理和项目插画；已推送到 `origin/codex/shooter-framework`，未部署。
- 2026-09-27 本轮相对 `4a2e11d` 完成账号请求去文件化（Claude 实现、Codex 复核）：修改 `host/core/account_service.gd`、`host/platform/bounded_helper.gd`、`tools/account_store.ps1`、`tools/bounded_helper.ps1`、`tools/test_helpers.ps1`、`tests/run_admin_http.gd`、`docs/21_managed_protocol.md`、`docs/22_framework_operations.md`、`docs/23_branch_files.md` 和本文件；新增 `tests/run_storage_timing.gd`、`tests/fixtures/storage_cost_breakdown.ps1`。运行证据在 Git 忽略的 `logs/`。
- 2026-09-27 grant 轮（Claude 实现、Codex 复核，基于 `07aa0d2`）：修改 `host/storage/sqlite_repository.gd`、`tools/sqlite_store.ps1`、`tests/run_secure.gd`、`tests/fixtures/secure_client.gd`、`docs/21_managed_protocol.md`、`docs/22_framework_operations.md`（修复上一轮留下的两行路径转义错误）、`docs/23_branch_files.md` 和本文件；新增 `tests/run_grant_storage.gd`、`tests/fixtures/grant_database.ps1`。重建出的独立包和运行证据在 Git 忽略的 `artifacts/`、`logs/`。
- 2026-09-27 资产延迟小改动（Codex 实现，Claude 复核，已本地提交）：`asset.snapshot` 合并查重和读取状态，提交事务仍检查幂等和版本；修改 `host/core/asset_service.gd`、`tools/sqlite_store.ps1`、`tests/run_storage_timing.gd`、`docs/17_framework_shooter_plan.md` 和本文件。Claude 复核时新增 `tests/run_asset_snapshot.gd`，更新 `docs/22_framework_operations.md`、`docs/23_branch_files.md`（顺带补登 grant 轮漏记的 `tests/run_secure.gd`、`tests/fixtures/secure_client.gd`），没有改 Codex 的实现代码；独立包已用这份源码重建（见下表）。
- 2026-09-27 常驻存储评估（Claude，已本地提交，只增加测量工具和文档）：新增 `tests/perf/` 下 6 个测量脚本（`run_asset_e2e.gd`、`measure_asset_e2e.ps1`、`storage_oneshot_variants.ps1`、`resident_store_probe.ps1`、`run_resident_probe.gd`、`run_gd_pbkdf2_probe.gd`），更新 `docs/17_framework_shooter_plan.md` 第六节、`docs/22_framework_operations.md`、`docs/23_branch_files.md` 和本文件。生产代码和独立包都没有变化。
- 2026-09-27 常驻存储方案 B 第一阶段（Claude，已本地提交）：新增 `host/storage/resident_store.gd`、`tools/storage_worker.ps1`、`tests/run_resident_store.gd`；修改 `host/storage/sqlite_repository.gd`、`host/core/account_service.gd`、`host/operator.gd`、`tools/sqlite_store.ps1`（新增进程内 `-RequestJson` 入口，Codex 的 snapshot 改动原样保留）、`tools/account_store.ps1`、`tools/build_framework_release.ps1`（打包新脚本）、`tests/run_asset_snapshot.gd`、`tests/run_storage_timing.gd`、`tests/test_framework_clients.ps1`、`tests/test_framework_release.ps1`，以及 docs/17、21、22、23 和本文件。
- 2026-09-27 密码长度小阶段（Codex，已本地提交）：账号最低密码长度从 10 降为 8，服务、两套 Schema、管理后台和游戏客户端提示同步；真实账号与契约边界测试覆盖 7 字符拒绝及 8 字符可用。修改清单见 docs/23。已从当前工作区重新构建独立 ZIP。
- 环境：Windows 10.0.26200；Godot `4.7.2.stable.steam.ed1daf0bf`（`D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`），导出使用同安装目录的 4.7.2 official 模板；Git `2.55.0.windows.3`；系统 `winsqlite3.dll` 3.51.1。
- 用户提供一台待验收 Linux 笔记本的局域网 SSH 目标，记录于 `docs/10_environment.md`；2026-09-27 尚未连接或检测环境，用户要求暂缓验证。
- 用户纠正账号删除需求：测试阶段要在后台删除指定玩家在当前账号库、资产库中的账号数据与全部游戏资产；旧备份保留并单独标记/处理。前一轮“只停用”的决定已撤销，`account.ban/unban` 仍只负责可恢复的停用。
- 2026-09-27 测试阶段账号删除（Claude 实现，Codex 复核，本地提交 `96d25d1`，未推送）：新增 `account.delete` 和后台独立的“删除测试账号”按钮，设计见 [docs/17 第七节](docs/17_framework_shooter_plan.md#七测试阶段账号删除2026-09-27已实现待复核)，协议见 [docs/21](docs/21_managed_protocol.md#测试阶段账号删除)，文件清单见 docs/23。只在隔离测试目录中用假账号验证；没有删除或读取 `data/framework/` 中的真实账号，没有连接 Linux 设备；独立 ZIP 已重建并完成包测试。

## 当前已实现

- **独立管理服务（Operator）**：回环 HTTP 中文后台，持有 SQLite 账号与资产库；通过认证的回环 TCP 启动、停止、重启、维护游戏宿主；宿主停止后后台继续运行。停服默认公告 60 秒；崩溃后确认旧进程退出、端口可重绑才重启，10 分钟最多 3 次。
- **账号**：邀请码注册、用户名密码登录（PBKDF2-SHA256，60 万次迭代）、单玩家会话、改昵称/密码；管理员重置、停用/恢复、踢出，并有持久审计。测试阶段可由管理员永久删除玩家账号：两库分步执行、作业记录可恢复，比赛结果和审计保留匿名代号，后台列出可能仍含该账号的旧备份（2026-09-27，提交 `96d25d1`）。账号请求（含密码、session token、邀请码）经 Godot 管道写入助手的标准输入，不写请求文件（2026-09-27 起）。会话校验由账号库的常驻存储进程处理，其余账号操作仍走一次性助手。
- **永久资产**：金币、经验与等级阈值表、非堆叠所有权、按游戏分开的默认配置；独立或 shared 资产空间；购买、选择与流水同事务，幂等重试不重复扣款；成绩与奖励同事务结算。比赛临时经济与永久钱包分开。资产读取、购买和选择由资产库的常驻存储进程处理（每个数据库一个，串行排队，超时或出错时自动回退到一次性助手；`ROOMKIT_STORAGE_MODE=oneshot` 整体切回旧路径）。
- **运维**：在线备份（每 30 分钟，保留 48 份）、恢复前备份、恢复后撤销会话；进程身份核验，只回收本次创建且已核验的进程。
- **房间**：每房一个 Godot 进程；WSS 大厅 + DTLS/ENet；房间实际绑定 UDP 后才 READY；资产许可与异步刷新按成员代次隔离。可信清单可以声明通用整数 `room_rules`，宿主只校验范围，具体含义交给游戏适配器。
- **横版射击示例**（`shooter-dev-002` / `shooter-v2` / `game_protocol=2`）：自由混战，三把枪，服务器权威即时命中，死亡后可开背包选枪并手动复活，整局结算发奖。房间可设每局时长 30–3600 秒、获胜击杀数 0–1000（0 为不限）、复活等待 0–60 秒；已有房间用“规则 / 重建”修改。客户端对人物做 50 ms 显示平滑，并绘制最长 18 像素的短弹迹。
- **取石子示例**：共用同一账号和资产服务，可购买并选用玉石主题。
- **新游戏接入**：`tools/new_game.ps1 -Managed -GameId <id>` 生成自带 SDK 0.5.0、账号客户端、独立房间、资产目录/策略和结果 Schema 的工程；Operator 按受信注册表（`schemas/managed_game_registry.schema.json`）组装服务，宿主核心和 SDK 里没有射击或取石子的分支。
- **源码启动器**：`StartShooterClient.cmd` / `StartManagedTurns.cmd` 以可见窗口启动；要等到窗口稳定出现才报告成功，并为每次启动单独保存日志。

## 当前交付物

| 交付物 | 状态 |
|---|---|
| 源码入口 `StartManagement.cmd` / `StartShooterClient.cmd` / `StartManagedTurns.cmd` / `StopManagement.cmd` | 当前推荐，包含到本轮为止的全部修改 |
| 最新独立包 `artifacts/RoomKit-0.5.0-framework-windows-aa019dbc45f9461099ad5a8136b1e4a1.zip`（索引 `artifacts/framework-release.json`，SHA256 `e5d1cfb7c91975815bfda57cda85cd3e4f26d313780f7cb6ec947332ec44f48b`） | 2026-09-27 用当前未提交源码构建，包含测试账号删除及收尾修正。`tools/build_framework_release.ps1` 退出 0；从该 ZIP 全新解压后执行 `tests/test_framework_release.ps1 -Bundle <新解压目录>`，44/0、退出 0，证据 `logs/deletion2-review-final-build.txt`、`logs/deletion2-review-final-package-test.txt`、`logs/framework-release-ddc825734d194a0b8b9af6dadda7807c`。这项包测试验证原生启动、房间与联机基本流程，不包含包内删除按钮的实际点击或删除端到端测试；旁边解压目录含隔离测试数据，分发只用 ZIP |
| 最新独立包 `artifacts/RoomKit-0.5.0-framework-windows-12253e0acce8497fb173fd91d8a4f716.zip`（索引 `artifacts/framework-release.json`，228,983,858 字节，SHA256 `0761326e5ed0338bbb94a4d93b09c35c70826c7f1ec4d81f1a6fbb5122fb2bdc`） | 2026-09-27 由 `7567497` 加本地未提交的 snapshot、常驻存储第一阶段和 8 字符密码改动构建；默认使用常驻存储。包内 `tools/account_store.ps1` 的密码下限为 8，校验清单 36 项；自动包测试常驻模式 44/0、退出 0。修改包测试夹具后又用 ZIP 全新解压副本的恰好 8 字符管理员和玩家密码完成注册、登录，44/0、退出 0，证据 `logs/framework-release-b521b70977274676a9dec3f5f96a2815`。原解压目录复跑曾两次 6/1，见已知问题。旧路径在上一版包 44/0，本包未重跑；未人工点击新后台表单或试玩本包原生客户端。旁边已解压目录含测试私有数据，分发只用 ZIP |
| 上一版独立包 `…-bbc5f4ddb8c247b8af6bac9d9d8e800d.zip`（228,983,857 字节，SHA256 `3f4be8e9415b78598aefee36d4f76caf56ab5e92ac8ddbc46a8300a85e63100b`） | 2026-09-27 由 `7567497` 加 snapshot 与常驻存储第一阶段改动构建，不含 8 字符密码改动；常驻与旧路径包测试均为 44/0 |
| 上一版独立包 `…-a5eb4e454ac44da4bbfb76e10c81eec7.zip`（228,974,562 字节，SHA256 `43f7f04728dae72203a7b6d17a2258128192a22327d9d0e73f865b188ba7bcb7`） | 2026-09-27 由 `7567497` 加 snapshot 改动构建，不含常驻存储，已被上一行取代；包测试 44/0 |
| 更早独立包 `…-fc3df1a4490b40189245faaadb2fbae0.zip`（228,974,086 字节，SHA256 `c36d86c2087b03f19f9b5aab9632e1ec828c97572c7b7fcad4172c44ba542da6`） | 2026-09-27 由 `07aa0d2` 加 grant 改动构建，不含资产往返合并，已被上一行取代：含 09-26 的模板注册、启动器修复和房间规则（shooter-v2）、账号请求 stdin 和 grant 签名密钥 stdin。`tests/test_framework_release.ps1` 44/0。用户反馈该包后台、开房和客户端均正常；这是用户试玩报告，Codex 本轮只看过后台初始页，未独立完成客户端试玩。旁边已解压目录含测试私有数据，分发只用 ZIP |
| 更早独立包 `…-f4f40384083d45e28ffa38bcb5dea472.zip`（SHA256 `49b8f13f…e173e`） | 2026-09-22 构建，保留作证据，已被取代；射击客户端为 shooter-v1，与当前源码不兼容 |
| 早期无账号演示入口（仓库根 `StartPanel.cmd`、`StartPlay.cmd`、`StartTurns.cmd`、`StartDemo.cmd`、`ShowResults.cmd`）及 0.1.0 包 | 保留但不推荐，见 [早期入口](docs/archive/early_entrypoints.md) |

## 最新有效验证范围

密码长度小阶段（2026-09-27，当前本地提交源码）：`tools/run.ps1 -Mode accounts` 85/0、退出 0，真实 SQLite 覆盖 7 字符管理员设置/玩家注册/改密/管理员重置拒绝，以及 8 字符注册、登录、改密、重置成功；`-Mode managed_contracts` 281/0、退出 0，覆盖大厅密码字段 7/8 字符边界；`-Mode admin_http` 139/0、退出 0，检查真实回环后台 HTTP 处理；Godot `tests/run_account_recovery.gd` 30/0、退出 0，见 `logs/password8-account-recovery-rerun.stdout`。账号恢复首次工具会话中断，日志只写到中途，不计入通过或失败；原样重跑通过。新独立包构建退出 0；包测试夹具改用恰好 8 字符的管理员和玩家密码后，在 ZIP 全新解压副本中 44/0、退出 0。本包旧路径、人工点击新后台表单和人工客户端试玩未运行。已有账户密码及数据库格式不变。

### 2026-09-27 账号删除复核修正验收（提交 `96d25d1`）

Codex 复核指出两个问题，本轮修正：① 两库删除完成后，Operator 的审计去标识化和备份标记若因退出或写入失败遗漏，重启无法补做；② 管理员填写的删除原因可能含用户名或 user_id。现在作业多了“等待 Operator 收尾”状态，收尾（改写并读回校验 Operator 审计文件、重新取备份列表、写入并读回删除日志）全部成功后才调用 `local.deletion_close` 并报告成功，重启和重复请求都能补做；原因在写入任何审计前替换，其他审计、回执和维护审计文本中的该 user_id/用户名也会被替换。设计见 docs/17 第七节“复核修正”。

编排脚本 `logs/run-deletion2-acceptance-20260927.ps1`，汇总 `logs/deletion2-acceptance-summary.txt`，全部退出 0、0 失败，没有需要重跑的项：

| 测试 | 结果 | 新增覆盖 |
|---|---|---|
| Godot `tests/run_account_deletion.gd` | 常驻 83/0、旧路径 83/0 | 原因含大小写不同的用户名和 user_id（删除原因、错误确认的失败请求、其他账号审计、邀请审计、其他玩家回执）全部被替换；两库完成后只有作业行还持有名字，收尾后为 0；收尾未完成时重启仍交回作业、重复请求（账号行已删）仍核对用户名并继续；过早收尾返回 `DELETION_NOT_READY`；Operator 审计文件设为只读时报告 `AUDIT_WRITE_FAILED` 且文件原样、无临时文件残留；删除日志只读时写入失败被检测且作业仍未完成；恢复可写后收尾成功、重复收尾 DUPLICATE |
| `tests/test_account_deletion.ps1`（真实 Operator、宿主、房间、两个 WSS 客户端） | 常驻 52/0、旧路径 52/0 | 删除时 `operator-audit.jsonl` 只读 → 返回 `ACCOUNT_DELETION_INCOMPLETE`（stage operator / AUDIT_WRITE_FAILED），账号已从两库删除但审计仍含名字；恢复可写后原样重新提交才报告完成（约 5.1 秒）；各处原因写入被删玩家名字后，两库逐表扫描、合并审计、Operator 审计、维护审计、删除日志均不含其 user_id/用户名；Operator 停止时制造“只做第一步”和“两库已完成、未收尾”两种中断，重启后两者都完成、审计已去名、删除日志列出旧备份。证据 `logs/account-deletion-3d1b5481…` 及本轮编排的两个目录 |
| 回归 | resident_store 34/0、asset_snapshot 40/0、account_recovery 30/0、unit 320/0、assets 83/0、accounts 85/0（旧路径 85/0）、result_rewards 74/0（旧路径 74/0）、admin_http 143/0、managed_contracts 286/0、asset_audit 14/0、operator_maintenance 35/0、operator_lifecycle 29/0、完整客户端 47/0（持有的 Operator 11/0）、后台页面 Node 测试 12/0、12/0、10/0、9/0 | |

运行结束后没有残留 Godot 或存储工作进程；`data/framework/` 没有任何文件在本轮被修改；没有碰旧备份或 Linux 设备。

Codex 复核补充：审计文件改写后的读回现在同时检查文件打开错误，避免读回失败被误判为“无身份信息”（`host/core/account_deletion.gd`）。补丁后独立重跑 Godot `tests/run_account_deletion.gd` 83/0、退出 0，证据 `logs/deletion2-review-account_deletion.stdout`；未重跑删除端到端，沿用上表补丁前的 52/0。随后按上方“当前交付物”重建最终 ZIP 并从全新解压目录完成包测试。

用户人工反馈（2026-09-27）：已测试删除账号功能，未发现问题。没有提供启动入口、具体测试步骤或日志，本条只记为用户对删除功能的人工试玩反馈，不替代 Linux、第二台设备或包内删除端到端的验收。

### 2026-09-27 账号删除首版验收（历史记录，后续已修正）

编排脚本 `logs/run-deletion-acceptance-20260927.ps1`（汇总 `logs/deletion-acceptance-summary.txt`），完整客户端测试的原样重跑 `logs/run-deletion-retest-20260927.ps1`（汇总 `logs/deletion-retest-summary.txt`）。“常驻”为默认模式，“旧路径”为 `ROOMKIT_STORAGE_MODE=oneshot`。所有删除测试只使用 `data/test-account-deletion-<id>` 隔离目录里的假账号。

| 测试 | 结果 | 覆盖 |
|---|---|---|
| Godot `tests/run_account_deletion.gd` | 常驻 60/0、旧路径 60/0，退出 0 | 真实 SQLite：管理员保护、用户名确认（不分大小写）、玩家无权删除、旧 token、3 个资产空间、签名结果与迟到结算（只给其他玩家发奖、重试仍 DUPLICATE）、资产步骤失败与两库之间中断（替身注入）均报告未完成、启动恢复、重复删除、逐表扫描两库不再含 user_id/用户名/昵称、审计与回执保留代号、限流键删除、其他玩家不受影响、同名重新注册得到新身份、删除前的备份副本仍含该账号 |
| `tests/test_account_deletion.ps1`（真实 Operator、托管宿主、房间、两个 WSS 客户端） | 常驻 44/0（删除耗时 5720 ms）、旧路径 44/0（7100 ms），退出 0 | 后台 HTTP 删除；被删玩家坐在房间内时被踢出、旧会话与重新登录被拒（`AUTH_FAILED`）；其他玩家保持连接、资产不变；管理员不可删、错误用户名拒绝且不改数据；资产写入 `ACCOUNT_DELETED`、重复删除 `ACCOUNT_ALREADY_DELETED`；合并审计、删除日志、操作审计文件不含 user_id/用户名；备份列表标注；Operator 停止时只做第一步、重启后启动恢复完成；恢复删除前的备份后账号和资产确实回来且标注仍在。证据 `logs/account-deletion-58fae399…`、`…ab6ebfc4…` |
| `node tests/test_admin_account_deletion.cjs` | 9/0 | 后台删除对话框的备份提示、用户名输入与勾选、最终确认取消时不发请求、只发送三个字段、结果文案、“删除未完成”状态与错误说明（DOM/API 替身，不是浏览器验收） |
| 回归（常驻） | resident_store 34/0、asset_snapshot 40/0、account_recovery 30/0、grant_storage 24/0、unit 320/0、assets 83/0、accounts 85/0、result_rewards 74/0、admin_http 143/0、managed_contracts 286/0、test_helpers 6/0、asset_audit 14/0、operator_maintenance 35/0、asset_response_loss 25/0、operator_lifecycle 29/0，均退出 0 | admin_http 与契约新增 `account.delete` 的有效/缺字段/非法用户名/自选数据库用例 |
| 回归（旧路径） | accounts 85/0、result_rewards 74/0，退出 0 | |
| 完整客户端 `test_framework_clients.ps1 -Visual` | 首次 39/1（测试驱动 `Access is denied`，已知问题 3），原样重跑 47/0，持有的 Operator 两次 11/0 | 含原有停用/恢复流程 |
| 其余三个后台页面 Node 测试 | 12/0、12/0、10/0 | 编排脚本里这四个 Node 测试因我把函数命名为 `Node`（与 `node` 命令同名，PowerShell 不区分大小写）而自我递归、全部退出 1，未执行测试；随后直接用 `node` 运行，结果如左 |

运行结束后：没有残留 Godot 或存储工作进程；`data/framework/` 中没有任何文件在本轮开始后被修改；`git diff --check` 通过；改动的 .ps1 均为纯 ASCII。

### 2026-09-27 常驻存储第一阶段验收（当前工作区代码，Claude）

编排脚本 `logs/run-resident-acceptance-20260927.ps1`（汇总 `logs/resident-acceptance-summary.txt`），失败项的对照复测 `logs/run-resident-confirm-20260927.ps1`，测试修正后的重跑 `logs/run-resident-retest-20260927.ps1` 与 `…retest2…`。“常驻”即默认模式，“旧路径”指设置 `ROOMKIT_STORAGE_MODE=oneshot`。

Codex 独立复核：检查 `ResidentStore`、工作进程的四操作白名单、内存请求通道、数据库提交时的回执与版本校验，并核对两批真实客户端原始 JSON、最终双模式包测试日志和 ZIP SHA256；独立运行 Godot `tests/run_resident_store.gd`，退出 0、34/0，证据 `logs/codex-review-resident.stdout`。未独立重跑完整客户端或人工试玩。

用户人工验收（2026-09-27）：按源码入口重启后试玩，反馈死亡背包买枪、切枪“确实很快”。这是用户在本机源码版的体感反馈，不是人工秒表计时；新独立包的人工试玩、第二台设备和长时间耐久仍未验收。

**客户端实测**（`tests/perf/measure_asset_e2e.ps1`，真实 Operator 和 WSS，大厅内 3 个账号；常驻与旧路径在同一时段交替各测两批，均退出 0、0 失败；`logs/asset-e2e-{resident,oneshot}-{1,2}.json`）：

| 客户端视角 | 常驻（中位 / 最大） | 旧路径（中位） |
|---|---:|---:|
| 购买 | 97 / 111 ms | 3730 ms |
| 切换默认武器 | 97 / 117 ms | 3746 ms |
| 读取资产 | 83 / 110 ms | 2525 ms |
| 重复购买 | 76 / 83 ms | 2498 ms |

存储层（`run_storage_timing.gd` 5 轮中位数，两种模式各 58/0）：购买 38 对 2393 ms，切枪 37 对 2397 ms，会话校验 22 对 1267 ms，管理员发币 42 对 2347 ms；未迁移的注册、登录、登出、结算，两种模式一致。Godot 句柄前后只差 1（`logs/storage-timing-{resident,oneshot}.json`）。

| 命令 / 专项 | 结果 | 说明与证据 |
|---|---|---|
| Godot `tests/run_resident_store.gd` | 34/0（运行两次） | 新旧路径返回逐项一致，每库一个工作进程，常驻路径不产生请求文件，新旧路径同时并发写同一个库，助手内部报错后进程继续服务，超时和运行中崩溃之后只提交一次，队列上限，空闲退出与重启，模式开关，全部关闭后自动重启，会话校验两条路径一致，句柄 327 → 328。首次运行 31/3：一处是常驻路径的错误返回少了空 `payload` 字段（已在仓储层统一），另两处是测试里统计进程的命令把自己也算了进去（已排除自身）；`logs/resident-store-1.*` 保留 |
| Godot `tests/run_asset_snapshot.gd` | 常驻 40/0；旧路径 40/0 | 购买、选择、重复、冲突、重开重试、三种并发；常驻模式下存储调用次数改由工作进程计数，仍为 2/2/2/1 |
| `tools/run.ps1 -Mode unit / assets / accounts / result_rewards / admin_http / managed_contracts` | 320/0；83/0；81/0；74/0；139/0；273/0 | 常驻模式。assets 与 accounts 另在旧路径模式下复测，83/0、81/0 |
| Godot `run_account_recovery.gd`；`run_grant_storage.gd` | 30/0；24/0 | |
| `tools/test_helpers.ps1`；`test_asset_audit.ps1`；`test_operator_maintenance.ps1` | 6/0；14/0；35/0 | |
| `tests/test_asset_response_loss.ps1` | 常驻 25/0；旧路径 25/0 | 真实 WSS 断线后重登，同一 operation_id 只扣一次 |
| `tests/test_managed_template.ps1`；`test_room_rules.ps1`；`test_operator.ps1 -Lifecycle` | 74/0；18/0；29/0 | 生命周期测试包含备份恢复（恢复前关闭常驻进程）与重启 |
| `tests/test_framework_capacity.ps1` | 第 1 次 **93/1**；原样重跑 174/0 | 第 1 次在第 13 个玩家入房时，测试驱动写命令文件报 `Access is denied`（已知问题 3，与之前同类）；重跑时 16 人满房、第 17 人 ROOM_FULL 均通过 |
| `tests/test_framework_clients.ps1 -Visual`（配合 HoldForIntegration） | 修正前常驻 **21/1**（两次稳定复现）；修正后常驻 47/0、旧路径 47/0 | 失败原因是测试的时间假设：服务器会静默拒绝复活等待期内的复活请求，以前背包操作要十几秒，掩盖了这一点；现在背包操作不到 1 秒，复活请求落在了 3 秒等待期内。修正为复活前先等服务器报告的倒计时归零。修正后旧路径模式有一次 14/1：开火循环 35 秒内只命中 3 枪（对手剩 25 血），属于游戏测试驱动的偶发，与存储无关，原样重跑 47/0 |
| `tools/build_framework_release.ps1`；`tests/test_framework_release.ps1 -Bundle <新包>` | 构建退出 0；修正前常驻 **28/1**（两次稳定复现），修正后常驻 44/0、旧路径 44/0 | 失败原因同样是测试的时间假设：宿主每约 1 秒才推送一次房间状态，测试在客户端入房后立刻读取一次状态；入房变快后就读到了旧状态（旧路径模式下 44/0）。修正为最多轮询 5 秒 |

日志中没有脚本、解析或编译错误；运行结束后没有残留的常驻存储进程或其它项目进程，`data/` 下没有残留请求文件。

### 2026-09-27 常驻存储评估（当前工作区代码，Claude，仅测量）

| 命令 / 专项 | 结果 | 范围与证据 |
|---|---|---|
| `tests/perf/measure_asset_e2e.ps1 -Clients 3`（配合 `tests/test_operator.ps1 -HoldForIntegration`，编排脚本 `logs/run-asset-e2e-20260927.ps1`） | 退出 0，0 失败；Operator 侧退出 0 | 客户端视角经真实 Operator 和 WSS（大厅内，无房间许可跳转）：购买中位数 3623 ms、切换武器 3616 ms、读取 2415 ms、重复购买 2429 ms；`logs/asset-e2e-current-2.json`。第一批数据相近（3657/3623/2422/2443 ms），但因为我的脚本对重复购买返回码断言写错，三个客户端都以退出码 1 结束，不计为通过；`logs/asset-e2e-current.json` |
| `tests/perf/storage_oneshot_variants.ps1 -Rounds 7` | 退出 0 | 单次 `asset.read`：现状 1092 ms，去掉外层助手 585 ms，再加预编译 DLL 478 ms；`logs/storage-oneshot-variants.json`。第一次运行因生成的脚本写死了中文路径而失败，改为相对路径后重跑 |
| Godot `tests/perf/run_resident_probe.gd` | 51/0，退出 0 | 常驻工作进程 snapshot 13.5 ms、commit 16.7 ms、读改写周期 30.5 ms（一次性为 2213 ms）；首次应答 628 ms，重启 614 ms；440 次请求内存未增长；并发 4 个进程 p95 773 ms，共用 1 个进程 p95 143 ms；`logs/resident-probe.json` |
| Godot `tests/perf/run_gd_pbkdf2_probe.gd`（带 .NET 交叉校验参数） | 退出 0 | 通过 PBKDF2-HMAC-SHA256 公开测试向量；完整 60 万次迭代与 `account_store.ps1` 的 .NET 派生值逐字节一致；推算 60 万次约 1.70 s；`logs/gd-pbkdf2-probe.json` |

结论和迁移风险见 [docs/17 第六节](docs/17_framework_shooter_plan.md#六常驻存储评估2026-09-27claude-实测仅评估未实施)。以上都是测量，没有改动生产代码、协议或数据库格式。

### 2026-09-27 资产 snapshot 复核（当前工作区代码，Claude）

| 命令 / 专项 | 结果 | 范围与证据 |
|---|---|---|
| Godot `tests/run_asset_snapshot.gd`（当前代码） | 40/0，退出 0 | 走真实 `AssetService`：购买只扣一次、同请求重复返回回执、同 ID 不同内容 REQUEST_CONFLICT、未拥有物品/余额不足/重复购买均拒绝且不改流水、选择只改默认配置、重开服务后重试返回原回执；4 个线程并发同一请求只提交 1 次（另 3 个 DUPLICATE）；两笔合计超额的并发购买只成功 1 笔，余额不为负，失败请求之后用同一 ID 重试可以成功；5 个并发加币没有丢失更新。每步之后用回执流水链（前后 body 首尾相接、版本等于回执数）核对。实测存储调用次数：购买 2、选择 2、发币 2、已提交请求重复 1；`logs/asset-snapshot-working.stdout` |
| 同一专项，未改动的 `7567497` 副本 | 39/1（预期） | 全部行为断言通过，唯一失败的是调用次数断言（旧代码购买/选择/发币各 3 次，重复 1 次），证明改造只减少了往返，行为不变；三种并发的结果类别与改造后相同；`logs/asset-snapshot-baseline-7567497.stdout` |
| Godot `tests/run_storage_timing.gd -- --rounds=5`，旧 `7567497` 与新代码按旧→新→旧→新交替各两次 | 4 次均 58/0，退出 0 | 同一份计时脚本、同一台空闲机器；四次测得的 PowerShell 冷启动均为 218–284 ms，句柄均为 326 → 327。见下方对照表；`logs/storage-timing-snapshot-{old,new}-{1,2}.json`，汇总 `logs/snapshot-timing-summary.txt` |
| `tools/run.ps1 -Mode unit / assets / result_rewards` | 320/0；83/0；74/0 | 均退出 0；`logs/snapshot-review-<模式>.txt` |
| `tests/test_asset_audit.ps1`；`tests/test_operator_maintenance.ps1` | 14/0；35/0 | `sqlite_store.ps1` 其它操作（审计、在线备份/恢复）不受影响；`logs/snapshot-review-asset_audit.txt`、`logs/snapshot-review-operator_maintenance.txt` |
| `tests/test_asset_response_loss.ps1` | 25/0 | 真实 WSS 断线后重新登录，同一 operation_id 返回 DUPLICATE、只扣一次；`logs/snapshot-review-asset_response_loss.txt` |
| `tests/test_managed_template.ps1` | 74/0 | 真实 Operator/宿主/房间下的注册、发币、购买、选择与幂等重放；`logs/snapshot-review-managed_template.txt` |
| `tests/test_operator.ps1 -Lifecycle` | 29/0 | 共享钱包、备份恢复、重启与崩溃回收；`logs/snapshot-review-operator_lifecycle.txt` |
| `tests/test_operator.ps1 -HoldForIntegration` ＋ `tests/test_framework_clients.ps1 -Visual` | 47/0；Operator 侧 11/0 | 真实两种玩法：存活时伪造购买/选择被拒、死亡背包购买/幂等/选枪、持新枪复活、300 秒结算到账；`logs/snapshot-review-framework_clients.txt` |
| Godot `tests/run_grant_storage.gd` | 24/0，退出 0 | `sqlite_store.ps1` 的 grant 标准输入路径不受影响；`logs/snapshot-review-grant_storage.stdout` |
| `tools/build_framework_release.ps1`；`tests/test_framework_release.ps1 -Bundle <新包>` | 构建退出 0；44/0 | 新包见“当前交付物”；`logs/snapshot-review-build_release.txt`、`logs/snapshot-review-release_test.txt` |

**改造前后存储层耗时**（毫秒；每侧 2 次 × 5 轮 = 10 个样本的中位数，括号内为两次运行各自的中位数；不含 WSS/大厅/房间/Operator RPC 时间）：

| 操作 | 旧 `7567497` | 新（snapshot） | 差值 |
|---|---:|---:|---:|
| 购买 | 3295（3302 / 3281） | 2238（2215 / 2238） | −1057 |
| 选择默认武器 | 3288（3291 / 3274） | 2203（2200 / 2227） | −1085 |
| 管理员发币 | 3292（3306 / 3249） | 2213（2220 / 2205） | −1079 |
| 购买幂等重试 | 1085 | 1097 | +12（未改动，一次往返） |
| 结算 | 1150 | 1159 | +9（未改动） |
| 注册 / 登录 | 3148 / 3230 | 3165 / 3161 | 未改动，波动内 |
| 会话校验 / 登出 | 1243 / 1169 | 1202 / 1143 | 未改动，波动内 |

结论：购买、选择和发币各少一次存储往返，稳定快约 1.06–1.09 秒（约 32%）；未改动的操作差值都在 ±70 ms 以内，说明两侧条件一致。这仍是约 2.2 秒的等待，瓶颈（每次往返两次 PowerShell 冷启动加编译）没变。

复核中的一次过程失败：第一版编排脚本 `logs/run-snapshot-review-20260927.ps1` 写死了含中文的临时目录路径，Windows PowerShell 5.1 按系统代码页读取无 BOM 的脚本，把路径读成乱码，其中 4 次计时和 grant 专项根本没有启动（汇总里是空退出码的 0 秒记录，不算测试结果）。已改为从 `$env:TEMP` 取路径的纯 ASCII 脚本 `logs/run-snapshot-timing-20260927.ps1`，在其余回归结束、机器空闲后重跑，结果如上。

Codex 初测（保留原记录）：资产延迟小改动（2026-09-27，本地未提交）：`tools/run.ps1 -Mode assets` 83/0、退出 0；`tests/test_asset_response_loss.ps1` 25/0、退出 0，覆盖真实 WSS 断线后重放而不重复扣款；Godot `tests/run_storage_timing.gd -- --rounds=3 --label=snapshot-3` 38/0，输出 `logs/storage-timing-snapshot-3.json`。本机存储层购买中位数 2195.9 ms（此前五轮基线 3346.5 ms，轮数和负载不同，不是严格对照实验），选择默认武器 2225.6 ms（此前未单独计时）。计时脚本的运行器已确认完整成功标记，但该次通过直接启动 Windows GUI 子系统的 Godot，外层 PowerShell 未读到进程退出码；不把成功标记冒充退出码验证。此次未重建独立包、未做新源码的人工试玩。

用户在 Claude 复核后反馈：直接从仓库目录启动试玩，购买和切换武器**体感没有明显区别**。这是人工主观反馈，不是端到端延迟测量；收到反馈时本机没有 RoomKit 进程，无法追溯该次试玩进程的启动时间和代码版本。即使加载新版，本地存储层仍需约 2.2 秒，当前优化尚未达到可感知的即时响应目标。新独立包的人工操作仍未验收。

每项的计数都是断言数，不是玩家数。“代码版本”指该结果对应的源码：**09-27 资产 snapshot 复核**表示当前工作区（`7567497` 加未提交的 snapshot 改动）；**09-27 grant 轮**表示 `07aa0d2` 加 grant 改造及 secure 测试修正；**09-27 账号轮**表示提交 `07aa0d2` 的代码；**09-26** 表示提交 `4a2e11d` 中的同一批源码；**09-22** 表示提交 `f0b4c8b` 前后的代码。同一专项以最新的结果为准。所有结果都只在同一台 Windows 电脑上取得。

### 2026-09-27 grant 轮（本轮提交代码）

| 命令 / 专项 | 结果 | 范围与证据 |
|---|---|---|
| Godot `tests/run_grant_storage.gd` | 24/0，退出 0 | 走真实 `ResultService.prepare_launch`：5 次 grant 调用期间数据目录没有出现任何临时文件；除 SQLite 外没有文件含密钥；重开后密钥逐字节一致，用它签名的结果被接受、伪造签名仍返回 AUTH_FAILED；重复 launch_id 仍返回 STORAGE_UNAVAILABLE 且不改原密钥；第 256 条授权可写、第 257 条仍返回 STORAGE_CAPACITY_EXCEEDED；Godot 句柄 323 → 323。单次 grant 中位数 962 ms；`logs/grant-storage-stdin.stdout` |
| 同一专项在未改动的 `07aa0d2` 副本上 | 22/2（预期失败） | 失败的正是两条“grant 调用期间不应有临时文件”的断言（扫到 `request-*`、`helper-*`），证明检测有效；其余错误码断言在旧代码上同样通过，说明错误行为不变；中位数 1065 ms；`logs/grant-storage-baseline-07aa0d2.stdout` |
| `tools/run.ps1 -Mode all`（首次） | unit 320/0、launcher 64/0、integration 133/0、demo 通过、players 33/0、games 47/0、persistence 42/0，**secure 36/1** 后停止 | games 与 persistence 会真实生成 grant 并提交签名结果；旧 secure 测试错误已在本轮复核时修正，完整 `-Mode all` 未重跑；`logs/grant-regression-run_all.txt` |
| `tools/run.ps1` 补跑 `-Mode all` 中被跳过的 stress / load / recovery / limits / template / panel / assets | 404/0；95/0；24/0；8/0；10/0；62/0；83/0 | 均退出 0；`logs/grant-regression-2-<模式>.txt` |
| `tools/run.ps1 -Mode secure`，未改动的 `07aa0d2` 副本 vs 当前代码 | 36/1 vs 36/1 | 同一条断言、同样失败，确认与本轮无关；`logs/grant-regression-2-secure_pristine_07aa0d2.txt`、`logs/grant-regression-2-secure_working.txt` |
| Codex 复核：`tools/run.ps1 -Mode secure`；Godot `tests/run_grant_storage.gd` | 37/0；24/0，均退出 0 | 测试客户端先完成 WSS 认证，再仅给 DTLS 使用错误主机名；实际进入 DTLS 握手后返回 `AUTH_FAILED`。grant 重跑见 `logs/review-grant-storage.stdout`；secure 结果见 `logs/secure-console.log`、`data/secure-test-9ddfd8900ade81f30d01c8ede39f5cc1/bad-dtls-name.log`。 |
| `tools/run.ps1 -Mode result_rewards` | 74/0 | 含真实 grant → 签名提交 → 成绩与奖励同事务；`logs/grant-regression-result_rewards.txt` |
| `tests/test_room_rules.ps1` | 18/0 | 真实 Operator/宿主/房间与两名玩家打满 30 秒规则局并结算；`logs/grant-regression-room_rules.txt` |
| `tests/test_operator.ps1 -Lifecycle` | 29/0 | 真实 60 秒重启、崩溃注入与回收；`logs/grant-regression-operator_lifecycle.txt` |
| `tests/test_operator.ps1 -HoldForIntegration` ＋ `tests/test_framework_clients.ps1 -Visual`（第 1 次） | **14/1，退出 1**；Operator 侧 11/0 | 驱动在开火循环中抛出 `Access is denied`，之后的步骤未执行，见已知问题 3；`logs/grant-regression-framework_clients.txt`，客户端证据 `logs/operator-df44bb1a3a0d4383b120b3cb90add04c/clients-244cffaa5cb44238a6933a7f7e7143a0/` |
| 同上，原样重跑（第 2 次） | 47/0，退出 0；Operator 侧 11/0 | 真实 WSS+DTLS/ENet 两种玩法，完整 300 秒射击局的签名结算与准确到账；`logs/grant-regression-2-framework_clients.txt` |
| `tools/build_framework_release.ps1` | 退出 0，`FRAMEWORK_RELEASE_BUILD_OK` | 新包见“当前交付物”；`logs/grant-regression-build_release.txt` |
| `tests/test_framework_release.ps1 -Bundle <新包>` | 44/0，退出 0 | 35 项哈希、原生 Operator/宿主/双房间、实际 WSS/ENet 联调及退出/端口回收；`logs/grant-regression-release_test.txt` |

两批回归分别由 `logs/run-grant-regression-20260927.ps1` 和 `logs/run-grant-regression-2-20260927.ps1` 顺序执行，汇总见 `logs/grant-regression-summary.txt`、`logs/grant-regression-2-summary.txt`。日志中没有脚本、解析或编译错误；运行后项目相关进程残留为 0，`data/` 下没有残留请求文件。

### 2026-09-27 账号轮（提交 `07aa0d2` 代码）

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
- 常驻存储第一阶段未运行：房间内（死亡背包）购买和复活前资产刷新的单独计时（完整客户端测试已覆盖其功能）；`test_managed_shutdown.ps1`、`test_operator_schedules.ps1`；`tools/run.ps1 -Mode all` 中与存储无关的模式（launcher/integration/players/games/persistence/secure/stress/load/recovery/limits/template/panel）；`managed_registry`；常驻进程长时间运行（数小时以上）的耐久与内存观察；用新包做人工试玩；第二台设备。
- 用最新独立包（`aa019dbc…`）做有记录的人工浏览器操作和原生客户端试玩（自动的 44 项包测试已通过；用户已反馈删除账号功能测试正常，但未说明是否使用该 ZIP）；新管理表单（房间规则、8 字符密码）的真实浏览器点击；真人操作手感；托管模板的图形界面。
- 大厅内的玩家资产请求已通过真实 WSS 客户端单独计时；房间内死亡背包及复活前刷新仍未单独计时。
- 断电、磁盘满、真实网络丢包/延迟、证书轮换、外部身份服务。
- 账号删除尚未独立验证：最新 ZIP 内实际点击删除并完成端到端流程（包已包含删除功能，但 44 项包测试没有此项；用户测试的入口未说明）；删除时房间正在进行、之后才提交结果的完整真实对局（迟到结算只在 SQLite 层用真实签名结果验证）；outbox 中存在待处理/已拒绝结果文件时的残留报告（代码有扫描，未构造此场景）；大量账号或大审计文件下的删除耗时；Linux 设备（按要求未连接）。

## 已知问题与限制

1. **仅限 Windows**：账号、资产、结果存储和进程身份核验都通过 PowerShell 助手与 `winsqlite3.dll` 实现，Linux 上直接返回 `UNSUPPORTED_STORAGE`。
2. **存储调用开销（09-27 常驻存储第一阶段后）**：资产读取/购买/选择和会话校验改由常驻进程处理，客户端实测购买、切枪约 0.1 秒，读取约 0.08 秒（见上方验收表）。仍走一次性助手的操作每次往返约 1.0–1.2 秒（两次 PowerShell 冷启动加每次重新编译 C#），包括注册、登录（另有约 1.9 秒 PBKDF2，有意保留的安全成本）、登出、结算、grant、邀请码和后台管理写操作。常驻进程每个约 0.1 GB 内存，空闲 5 分钟退出，下次请求约 0.6 秒重启；长时间运行没有测过。以下为第一阶段之前的记录：购买、选择和管理员发币已从 3 次往返降为 2 次；同条件交替对照中，三者中位数从约 3.29 秒降到约 2.20–2.24 秒，仍有明显等待。上方账号轮旧表的 3.1–3.3 秒是改造前基线。但玩家在游戏里感受到的更慢：Operator 处理每次玩家资产请求前，都会先用一次账号助手往返校验会话，所以客户端实测购买和切枪约 3.6 秒、读取约 2.4 秒（09-27 常驻存储评估），这就是 snapshot 改动后体感改善不明显的原因。助手在工作线程执行，初始化与离线管理仍是同步调用。常驻工作进程方案随后已实施第一阶段，见 docs/17 第六节。
3. **客户端测试驱动有偶发失败**：`tests/test_framework_clients.ps1` 和 `tests/test_framework_capacity.ps1` 的 `Save-Json` 写命令文件（先写 `.tmp` 再 `Move-Item`）没有重试，09-27 分别出现过一次 `Access is denied` 中止（完整客户端 14/1、容量 93/1），原样重跑都通过；具体是哪个进程占用了文件没有查明。另外，完整客户端测试的开火循环一边跳一边射击，偶尔 35 秒内打不死对手（09-27 旧路径模式一次 14/1，对手剩 25 血），原样重跑通过。这些测试驱动都没有改动。
4. **临时请求文件的剩余范围**：账号请求（09-27）和 grant 签名密钥（09-27 grant 轮）已不落盘。其余资产、结果和维护请求仍用私有目录下的短期请求文件，它们不含账号口令、session token 或签名密钥。另外，用户真实数据目录 `data/framework/` 下有一个 09-26 23:33 残留的 `account-request-*.json`（104 字节，未读取内容，不能确认其内容或是否过期）和两个 `helper-*.json`；没有读取、移动或删除。
5. **射击网络模型只按局域网设计**：服务器每秒 20 次发送完整状态；客户端只做显示平滑，没有客户端预测，也没有命中回溯（按 [docs/17](docs/17_framework_shooter_plan.md) 的首版范围）。公网延迟下的手感没有评估。
6. **容量与耐久**：16 人满房只持续了 17.5 秒；100 轮开关房是 09-21 的早期宿主做的，托管宿主没有做长期测试。
7. **原因未查明的现象**：09-22 有一个可视化夹具中途消失，没有清理报告（未计为通过）；另有一次管理员意外退出登录，日志里没有根因（同期修复了一个相关的错误码映射缺陷，但不能认定就是根因）。
8. **预期诊断输出**：unit 的恶意指数用例会打印 `Exponent too high`；测试主动断开 TLS 时出现 `mbedtls -0x6c00`；load 模式会多打印一行 `SECURE_RESULT`（复用 secure 的测试框架）。这些都不是失败。
9. `tools/run.ps1 -Mode all` 只包含早期基础回归（外加 panel、assets），遇到第一项失败就停止；账号、管理、射击和托管专项需按 [docs/22](docs/22_framework_operations.md#测试入口) 单独运行。
10. **结果库容量上限没有清理机制**：每库最多 256 条启动授权、10000 条结果，每房 128 条待发送（[docs/15](docs/15_release_operations.md)）。09-27 代码检查确认，托管宿主每开一间房都会新增一条授权，而代码里没有任何删除授权的路径。所以同一个资产库在整个使用期内累计开到第 257 间房时，建房会因 `STORAGE_CAPACITY_EXCEEDED` 失败；上限本身已由 `run_grant_storage.gd` 实测。这不是本轮引入的问题，本轮也没有改；需要单独设计授权的回收策略（例如确认房间退出、结果补存完成之后再删除）。
11. **重复运行同一解压目录的包测试不稳定**：新包初次测试 44/0；将测试夹具改用 8 字符密码后，在同一已测试过的解压目录里连续两次都在射击导出客户端 UI 初始化标记处失败（6/1），进程退出码 0，控制台只有 Godot 启动横幅，尚未进入账号测试。用同一 ZIP 全新解压后原样运行通过 44/0，包含 8 字符管理员和玩家注册/登录。两次失败证据在 `logs/framework-release-d720d222ab154c4980cba1bd2c7301e3`、`logs/framework-release-50ad9127e6a04304aa2c999e6a60815a`；原因尚未确定，验包时使用干净解压副本。

## 本轮记录（2026-09-27）

**账号删除复核修正（Claude 实现、Codex 复核，提交 `96d25d1`）**：修正 Codex 复核的两个问题：Operator 收尾（审计去标识化、备份标记）可恢复、未完成不报告成功；删除原因中的用户名/user_id 不留在当前数据库或 Operator 审计中。

- 完成：账号库作业新增 `username`、`closed` 两列（首版未发布表自动补列）、`operator_pending` 状态和 `local.deletion_close`；`local.deletion_finish` 替换其他审计文本中的名字，作业保留 user_id/用户名直到收尾；`account.delete_begin` 在写入前替换原因中的名字，账号行已删、只差收尾时也接受重复请求；资产库 `asset.purge_user` 可带用户名，替换其他玩家回执命令中的名字。`host/core/account_deletion.gd` 新增审计文件改写并读回校验、删除日志追加并读回、内存审计替换；Operator 收尾在主线程执行，任一步失败返回 `ACCOUNT_DELETION_INCOMPLETE`（stage operator/close），启动时先完成只差收尾的作业；Operator 自己的审计行替换原因中的名字。同步响应 Schema、后台错误说明、docs/17、21、22、23。验收见上方“账号删除复核修正验收”。
- 失败：本轮新旧测试均一次通过，没有失败项。过程中我用内联 Node 脚本改 `tools/sqlite_store.ps1` 时转义出错，把正则里的 `\x00-\x1f\x7f` 写成了真实控制字符，随即修正并确认文件只含可打印 ASCII，之后才运行测试。
- 限制：昵称不在替换范围（可能是常见词，会误伤其他文本）；收尾完成前作业行仍保存 user_id 和用户名；旧备份、已拒绝的结果文件和运行日志仍只报告不改写。
- 未运行：真实浏览器点击；Linux；磁盘满等真实系统级写入失败（用只读属性模拟）。独立 ZIP 与包测试、提交由 Codex 后续完成，见上方交付物与复核记录；未推送。

**测试阶段账号删除首版（历史记录；后续修正并提交 `96d25d1`）**：用户要求实现仅管理员可用的测试账号删除，删除指定玩家在当前账号库及资产库中的账号数据和所有游戏资产，保留停用/恢复为独立操作；不改写旧备份，但明确提示并记录可能恢复该账号的备份；重点处理在线会话、交易回执、审计、比赛结果、迟到结算和跨库中断恢复，做不到就拒绝。

- 完成：账号库新增作业表和 `account.delete_begin` / `local.deletion_pending` / `local.deletion_finish`，待删除账号不可解封、改名、重置；资产库新增墓碑表和 `asset.purge_user`，`asset.commit` 拒绝已删除账号，结算跳过已删除玩家并只存代号；新增 `host/core/account_deletion.gd` 编排两库步骤与启动恢复；Operator 新增 `account.delete`（先取备份清单、踢出在线玩家、完成后去标识化自己的审计文件、扫描残留文件、写删除日志）、备份列表标注、删除期间的备份/恢复/配置互斥，并在启动时先完成未完成的删除再开放 HTTP；后台新增独立的“删除测试账号”区块和“删除未完成”状态、备份页标注与恢复提醒。同步三份 Schema、契约样例、错误码、README、CONTEXT、docs/17、21、22、23。验收见上方“账号删除验收”。
- 失败：端到端首跑 42/1，是测试假设错误（对局进行中商店关闭，玩家在房内购买被游戏策略以 `ASSET_OPERATION_DENIED` 拒绝），改为先在大厅购买再入房后 44/0，产品代码未改。完整客户端测试一次 `Access is denied` 驱动中止，原样重跑通过。编排脚本的 Node 步骤写错（见验收表），直接运行通过。更新 docs/21 时一次 shell 引号错误把反引号当成命令执行、写坏了该文件的新增段落，已用 `git checkout` 还原该文件（此前本轮未改过它）并改用脚本文件重做。
- 限制：旧备份、已拒绝的结果文件（`*.rejected.json`）和运行日志不改写，只报告；复制到项目外的备份无法处理；匿名代号由 user_id 派生，持有旧备份的人可以据此关联。审计中管理员自己填写的删除原因会保留，页面提示不要写用户名。
- 未运行：见上文“未运行 / 未验收”。没有提交、推送、部署或连接 Linux；没有读取、修改或删除 `data/framework/` 中的真实账号或残留文件；没有重建独立包。

**常驻存储方案 B 第一阶段（Claude 实现、Codex 复核，未提交）**：用户要求按 docs/17 第六节的阶段决定实施方案 B，先处理资产读写和会话校验，保留旧路径回退，用真实客户端计时验收。

- 完成：新增 `ResidentStore`（每个数据库一个串行工作进程、队列上限 16、单次请求 10 秒超时、按持有的句柄管理进程、失败时对同一请求回退到一次性路径各执行一次）和 `storage_worker.ps1`（进程内调用原有助手，请求在内存中传递，只接受 `asset.read/snapshot/commit` 和 `session.authenticate`，空闲 300 秒退出）。仓储层和账号服务只把这四个操作交给常驻进程。Operator 启动时在后台预热两个工作进程，恢复前和退出时关闭它们。独立包会打包新脚本。线上协议、错误码、数据库格式都没有改；注册、登录、grant、邀请码和结算没有迁移。验收数字见上方“常驻存储第一阶段验收”。
- 失败：首版专项 31/3（常驻路径错误返回少了空 `payload`，以及测试进程计数把自身算入），已修正后 34/0。完整客户端测试和包测试在常驻模式下各稳定失败 1 项，对照复测确认两者都是测试依赖了“存储慢”的时间假设（旧路径下通过）；修正两处测试后，两种模式均通过。另有容量测试和开火循环各一次测试驱动偶发，原样重跑通过。
- 未运行：见上文“未运行 / 未验收”。没有提交、推送或部署；没有删除 `data/framework/` 下的旧残留文件。

**常驻存储评估（Claude，未提交，仅测量与文档）**：用户从源码试玩后反馈，买枪和切枪的体感没有明显改善，要求按 docs/17 评估常驻存储方案，先测性能和迁移风险，不要直接重写框架。

- 完成：沿真实调用链找到体感慢的主因（每次玩家资产请求前都有一次会话校验往返），并在客户端实测了端到端耗时。实测对比了现状、两种轻量一次性优化、常驻工作进程原型，以及 GDScript 版 PBKDF2 的可行性与兼容性；结论、风险与建议写入 docs/17 第六节。新增 6 个 `tests/perf/` 测量脚本，并在 docs/22、23 登记。生产代码、协议、数据库格式和独立包都没有变化；Codex 此前未提交的 snapshot 改动保持原样。
- 失败：我的测量脚本出过两次问题，都已修正并重跑：一是端到端脚本对重复购买返回码的断言写错，第一批三个客户端退出码为 1（数据仍保留、未计为通过）；二是一次性变体脚本生成的 PowerShell 文件写死了中文路径，被 PowerShell 5.1 读成乱码。没有生产测试失败。
- 未运行：房间内（死亡背包）路径的端到端计时、复活前资产刷新的计时、约 0.2 秒网络/排队开销的细分、方案 C（Godot 原生 SQLite 扩展，需要下载第三方库，未取得同意）、长时间运行的常驻进程耐久测试、第二台设备。没有提交或推送。

**资产 `asset.snapshot` 复核与独立包重建（Codex 实现、Claude 复核，未提交，待 Codex 复核）**：用户要求保留工作区现有 5 个未提交文件，复核 Codex 的 `asset.snapshot` 改动，重点验证购买、选择、重复请求、断线重试和并发扣款，并用相同条件测改造前后耗时；通过后更新 STATUS、重建并验证独立包。不开始常驻存储服务、不换语言、不推送。

- 复核结论：代码审阅认为新流程与原来的“查回执 → 读状态 → 应用规则 → 提交”在解码、投影、校验和 `expected_revision` 上等价。`asset.snapshot` 的两次查询不在同一事务内，但原来这两次读取分属两个进程，隔离性本来就更弱；真正的幂等和版本检查仍在 `asset.commit` 的 `BEGIN IMMEDIATE` 事务里，未改动。`asset.receipt` 操作已无调用方，但仍保留在 `sqlite_store.ps1` 中，不影响行为。实测验证见上面的复核表：行为与改造前一致，往返从 3 次降为 2 次，购买/选择/发币各快约 1.06–1.09 秒。
- 修改：没有改 Codex 的实现代码。新增 `tests/run_asset_snapshot.gd`；在 docs/22 补充命令和说明；在 docs/23 登记本轮文件并补登 grant 轮漏记的两个测试文件；更新本文件。Codex 原有的 5 个未提交文件保留，本文件只在其基础上补充。
- 失败：第一版编排脚本因中文路径编码问题，没有启动计时和 grant 专项，已用纯 ASCII 脚本在空闲时重跑（见复核表下的说明）。没有测试失败。
- 未运行：见上文“未运行 / 未验收”。没有删除 `data/framework/` 下的旧残留文件，没有提交、推送或部署，没有开始常驻存储服务或换语言。

**grant 签名密钥去文件化与独立包重建（Claude 实现、Codex 复核，基于 `07aa0d2`）**：用户要求只处理 grant 请求中签名密钥临时落盘的问题，保持协议和业务行为不变，运行相关真实 Godot 测试，重建并验证独立包。

- 完成：`SqliteRepository` 对 `grant` 操作改用已有的 `BoundedHelper.execute_input`，请求经标准输入交给 `sqlite_store.ps1`；`sqlite_store.ps1` 的 `-Request` 改为可选，不传时从标准输入读取一行 base64 UTF-8 JSON（上限 65536 字符）。其余操作、`release/Manage.ps1` 和测试脚本直接调用时仍用文件模式。授权表结构、SQL、256 条上限、错误码、签名算法和结果协议都没有改。新增 `tests/run_grant_storage.gd` 与预填 255 条授权的夹具。用改造后的源码重建了独立包，并跑了包测试。
- 失败与修复：旧 `secure` 测试 36/1 是阶段混淆，Codex 修正测试后 37/0。第一次完整客户端测试因驱动写文件 `Access is denied` 失败，原样重跑通过（已知问题 3）。另有两处 Claude 的过程失误已修正：用 Node 的 `String.replace` 插入 PowerShell 正则时，替换文本里的 `$'` 被当成特殊替换符，把 `sqlite_store.ps1` 写坏了，发现后从 `07aa0d2` 还原并改用精确编辑重做；复查时发现上一轮写进 docs/22 的两行命令被转义吃掉了反斜杠（已随 `07aa0d2` 提交），本轮已修正。
- Codex 复核：修正原有 secure 测试的阶段混淆，测试客户端先完成 WSS，再仅给 DTLS 使用错误主机名；真实 Godot secure 37/0，grant 专项重跑 24/0。旧 secure 36/1 证据保留。
- 未运行：见上文“未运行 / 未验收”。没有删除 `data/framework/` 下的旧残留文件；本地提交，未推送或部署。

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
