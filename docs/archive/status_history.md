# STATUS 历史归档

本文件保存 2026-09-27 文档整理前 `STATUS.md` 的全部历史过程记录，以及原 `docs/22_framework_operations.md` 中 2026-09-22 停服与调度专项的结果段。当前状态、最新验证范围与已知问题只看根目录 [STATUS](../../STATUS.md)。

整理规则：

- 正文逐字搬运，没有删减失败、未运行或限制记录；只把标题统一降一级，并把 Markdown 相对链接改为从本目录出发的路径。唯一改正是原文“host/admin_http.gd、host/admin.html”拼接笔误，已拆成两个真实文件名。
- 正文中的 `logs/…`、`data/…`、`artifacts/…` 均相对仓库根目录，属于 Git 忽略的本机证据目录，不随仓库分发。
- 2026-09-23 清理删除了旧导出包与旧解压副本；早期记录中引用的旧 `artifacts/…` 路径（包括 `artifacts/release.json`、`artifacts/delivery.json` 和 0.1.0 程序 ZIP）已逐项校验后压缩到私有归档 `data/cleanup-history-a4c423b0bdb6498bbb2b685ca8ac1452/artifact-evidence.zip`，原路径、大小与 SHA256 见同目录 `manifest.json`，可以按原路径恢复。该归档可能含测试账号数据，不用于公开分发。
- 各段的“本轮”“当前”指该段写入时，不代表今天的状态。

按时间倒序排列：

0. 2026-09-27 状态快照：交付物历史、09-21 至 09-27 验证表、未运行与已知问题原文、逐轮记录（2026-09-28 从 STATUS 迁出）
1. 2026-09-27 协作规则记录
2. 2026-09-26 房间规则、客户端启动修复、托管模板
3. 2026-09-23 本机清理；2026-09-22 暂停验收与完整本机验收
4. 2026-09-22 停服与调度专项（原 docs/22）
5. 2026-09-21 S0 资产基础、中文状态面板、M4/M5、M4 第一部分、M3
6. 2026-09-20 M2；2026-09-19 M0/M1

---

## 〇、2026-09-27 状态快照（2026-09-28 第一阶段文档整理时从 STATUS 迁出，原 STATUS 第 11–343 行）

以下是 2026-09-28 整理前 STATUS 中除“当前下一步（2026-09-28）”外的全部原文，逐字搬运，只把标题降一级、相对链接改为从本目录出发。其中“未推送”“当前工作区”“本轮”等说法指写入时；2026-09-28 核对时本地 `b0a707d` 已与 `origin/codex/shooter-framework` 一致。当前摘要见根目录 [STATUS](../../STATUS.md)。

更新：2026-09-27。分支 `codex/shooter-framework`；账号请求与 grant 密钥去文件化、资产 `asset.snapshot` 往返合并、常驻存储方案 B 第一阶段、8 字符密码和 Linux 待验收设备登记均已整理为本地提交，尚未推送。Codex 已复核常驻存储代码与证据，并独立重跑其专项。之后基于 `d79b1fc` 实现的测试阶段账号删除已由 Claude 实现、Codex 复核并本地提交为 `96d25d1`；独立 ZIP 已重建，包测试见下文。用户从项目目录启动并测试删除账号功能，反馈未发现问题；具体操作步骤未记录，不把这次反馈扩展成独立包或其他环境的验收。本文件记录当前状态、最新有效验证范围、未运行项与已知问题；较早过程见 [STATUS 历史归档](../archive/status_history.md)。启动方法见 [README](../../README.md)。

后续产品取舍见 [docs/17 第五节](../17_framework_shooter_plan.md)：2–8 人熟人试玩、可选框架服务、赛车与合作种田边界、累计房间授权回收、8 字符密码和存储性能路线已讨论确认。资产 `asset.snapshot` 往返合并后，又按 [docs/17 第六节](../17_framework_shooter_plan.md#六常驻存储评估与第一阶段实施2026-09-27) 实施常驻存储第一阶段：资产读写和会话校验走常驻进程，客户端实测购买约 0.1 秒（旧路径约 3.7 秒），旧路径保留为可切换的回退。8 字符最低密码长度已在源码工作区实施；授权回收仍未实施，方案 C 暂缓。

### 工作区与交接

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
- 2026-09-27 测试阶段账号删除（Claude 实现，Codex 复核，本地提交 `96d25d1`，未推送）：新增 `account.delete` 和后台独立的“删除测试账号”按钮，设计见 [docs/17 第七节](../17_framework_shooter_plan.md#七测试阶段账号删除2026-09-27已实现)，协议见 [docs/21](../21_managed_protocol.md#测试阶段账号删除)，文件清单见 docs/23。只在隔离测试目录中用假账号验证；没有删除或读取 `data/framework/` 中的真实账号，没有连接 Linux 设备；独立 ZIP 已重建并完成包测试。

### 当前已实现

- **独立管理服务（Operator）**：回环 HTTP 中文后台，持有 SQLite 账号与资产库；通过认证的回环 TCP 启动、停止、重启、维护游戏宿主；宿主停止后后台继续运行。停服默认公告 60 秒；崩溃后确认旧进程退出、端口可重绑才重启，10 分钟最多 3 次。
- **账号**：邀请码注册、用户名密码登录（PBKDF2-SHA256，60 万次迭代）、单玩家会话、改昵称/密码；管理员重置、停用/恢复、踢出，并有持久审计。测试阶段可由管理员永久删除玩家账号：两库分步执行、作业记录可恢复，比赛结果和审计保留匿名代号，后台列出可能仍含该账号的旧备份（2026-09-27，提交 `96d25d1`）。账号请求（含密码、session token、邀请码）经 Godot 管道写入助手的标准输入，不写请求文件（2026-09-27 起）。会话校验由账号库的常驻存储进程处理，其余账号操作仍走一次性助手。
- **永久资产**：金币、经验与等级阈值表、非堆叠所有权、按游戏分开的默认配置；独立或 shared 资产空间；购买、选择与流水同事务，幂等重试不重复扣款；成绩与奖励同事务结算。比赛临时经济与永久钱包分开。资产读取、购买和选择由资产库的常驻存储进程处理（每个数据库一个，串行排队，超时或出错时自动回退到一次性助手；`ROOMKIT_STORAGE_MODE=oneshot` 整体切回旧路径）。
- **运维**：在线备份（每 30 分钟，保留 48 份）、恢复前备份、恢复后撤销会话；进程身份核验，只回收本次创建且已核验的进程。
- **房间**：每房一个 Godot 进程；WSS 大厅 + DTLS/ENet；房间实际绑定 UDP 后才 READY；资产许可与异步刷新按成员代次隔离。可信清单可以声明通用整数 `room_rules`，宿主只校验范围，具体含义交给游戏适配器。
- **横版射击示例**（`shooter-dev-002` / `shooter-v2` / `game_protocol=2`）：自由混战，三把枪，服务器权威即时命中，死亡后可开背包选枪并手动复活，整局结算发奖。房间可设每局时长 30–3600 秒、获胜击杀数 0–1000（0 为不限）、复活等待 0–60 秒；已有房间用“规则 / 重建”修改。客户端对人物做 50 ms 显示平滑，并绘制最长 18 像素的短弹迹。
- **取石子示例**：共用同一账号和资产服务，可购买并选用玉石主题。
- **新游戏接入**：`tools/new_game.ps1 -Managed -GameId <id>` 生成自带 SDK 0.5.0、账号客户端、独立房间、资产目录/策略和结果 Schema 的工程；Operator 按受信注册表（`schemas/managed_game_registry.schema.json`）组装服务，宿主核心和 SDK 里没有射击或取石子的分支。
- **源码启动器**：`StartShooterClient.cmd` / `StartManagedTurns.cmd` 以可见窗口启动；要等到窗口稳定出现才报告成功，并为每次启动单独保存日志。

### 当前交付物

| 交付物 | 状态 |
|---|---|
| 源码入口 `StartManagement.cmd` / `StartShooterClient.cmd` / `StartManagedTurns.cmd` / `StopManagement.cmd` | 当前推荐，包含到本轮为止的全部修改 |
| 最新独立包 `artifacts/RoomKit-0.5.0-framework-windows-aa019dbc45f9461099ad5a8136b1e4a1.zip`（索引 `artifacts/framework-release.json`，SHA256 `e5d1cfb7c91975815bfda57cda85cd3e4f26d313780f7cb6ec947332ec44f48b`） | 2026-09-27 用当前未提交源码构建，包含测试账号删除及收尾修正。`tools/build_framework_release.ps1` 退出 0；从该 ZIP 全新解压后执行 `tests/test_framework_release.ps1 -Bundle <新解压目录>`，44/0、退出 0，证据 `logs/deletion2-review-final-build.txt`、`logs/deletion2-review-final-package-test.txt`、`logs/framework-release-ddc825734d194a0b8b9af6dadda7807c`。这项包测试验证原生启动、房间与联机基本流程，不包含包内删除按钮的实际点击或删除端到端测试；旁边解压目录含隔离测试数据，分发只用 ZIP |
| 最新独立包 `artifacts/RoomKit-0.5.0-framework-windows-12253e0acce8497fb173fd91d8a4f716.zip`（索引 `artifacts/framework-release.json`，228,983,858 字节，SHA256 `0761326e5ed0338bbb94a4d93b09c35c70826c7f1ec4d81f1a6fbb5122fb2bdc`） | 2026-09-27 由 `7567497` 加本地未提交的 snapshot、常驻存储第一阶段和 8 字符密码改动构建；默认使用常驻存储。包内 `tools/account_store.ps1` 的密码下限为 8，校验清单 36 项；自动包测试常驻模式 44/0、退出 0。修改包测试夹具后又用 ZIP 全新解压副本的恰好 8 字符管理员和玩家密码完成注册、登录，44/0、退出 0，证据 `logs/framework-release-b521b70977274676a9dec3f5f96a2815`。原解压目录复跑曾两次 6/1，见已知问题。旧路径在上一版包 44/0，本包未重跑；未人工点击新后台表单或试玩本包原生客户端。旁边已解压目录含测试私有数据，分发只用 ZIP |
| 上一版独立包 `…-bbc5f4ddb8c247b8af6bac9d9d8e800d.zip`（228,983,857 字节，SHA256 `3f4be8e9415b78598aefee36d4f76caf56ab5e92ac8ddbc46a8300a85e63100b`） | 2026-09-27 由 `7567497` 加 snapshot 与常驻存储第一阶段改动构建，不含 8 字符密码改动；常驻与旧路径包测试均为 44/0 |
| 上一版独立包 `…-a5eb4e454ac44da4bbfb76e10c81eec7.zip`（228,974,562 字节，SHA256 `43f7f04728dae72203a7b6d17a2258128192a22327d9d0e73f865b188ba7bcb7`） | 2026-09-27 由 `7567497` 加 snapshot 改动构建，不含常驻存储，已被上一行取代；包测试 44/0 |
| 更早独立包 `…-fc3df1a4490b40189245faaadb2fbae0.zip`（228,974,086 字节，SHA256 `c36d86c2087b03f19f9b5aab9632e1ec828c97572c7b7fcad4172c44ba542da6`） | 2026-09-27 由 `07aa0d2` 加 grant 改动构建，不含资产往返合并，已被上一行取代：含 09-26 的模板注册、启动器修复和房间规则（shooter-v2）、账号请求 stdin 和 grant 签名密钥 stdin。`tests/test_framework_release.ps1` 44/0。用户反馈该包后台、开房和客户端均正常；这是用户试玩报告，Codex 本轮只看过后台初始页，未独立完成客户端试玩。旁边已解压目录含测试私有数据，分发只用 ZIP |
| 更早独立包 `…-f4f40384083d45e28ffa38bcb5dea472.zip`（SHA256 `49b8f13f…e173e`） | 2026-09-22 构建，保留作证据，已被取代；射击客户端为 shooter-v1，与当前源码不兼容 |
| 早期无账号演示入口（仓库根 `StartPanel.cmd`、`StartPlay.cmd`、`StartTurns.cmd`、`StartDemo.cmd`、`ShowResults.cmd`）及 0.1.0 包 | 保留但不推荐，见 [早期入口](../archive/early_entrypoints.md) |

### 最新有效验证范围

密码长度小阶段（2026-09-27，当前本地提交源码）：`tools/run.ps1 -Mode accounts` 85/0、退出 0，真实 SQLite 覆盖 7 字符管理员设置/玩家注册/改密/管理员重置拒绝，以及 8 字符注册、登录、改密、重置成功；`-Mode managed_contracts` 281/0、退出 0，覆盖大厅密码字段 7/8 字符边界；`-Mode admin_http` 139/0、退出 0，检查真实回环后台 HTTP 处理；Godot `tests/run_account_recovery.gd` 30/0、退出 0，见 `logs/password8-account-recovery-rerun.stdout`。账号恢复首次工具会话中断，日志只写到中途，不计入通过或失败；原样重跑通过。新独立包构建退出 0；包测试夹具改用恰好 8 字符的管理员和玩家密码后，在 ZIP 全新解压副本中 44/0、退出 0。本包旧路径、人工点击新后台表单和人工客户端试玩未运行。已有账户密码及数据库格式不变。

#### 2026-09-27 账号删除复核修正验收（提交 `96d25d1`）

Codex 复核指出两个问题，本轮修正：① 两库删除完成后，Operator 的审计去标识化和备份标记若因退出或写入失败遗漏，重启无法补做；② 管理员填写的删除原因可能含用户名或 user_id。现在作业多了“等待 Operator 收尾”状态，收尾（改写并读回校验 Operator 审计文件、重新取备份列表、写入并读回删除日志）全部成功后才调用 `local.deletion_close` 并报告成功，重启和重复请求都能补做；原因在写入任何审计前替换，其他审计、回执和维护审计文本中的该 user_id/用户名也会被替换。设计见 docs/17 第七节“复核修正”。

编排脚本 `logs/run-deletion2-acceptance-20260927.ps1`，汇总 `logs/deletion2-acceptance-summary.txt`，全部退出 0、0 失败，没有需要重跑的项：

| 测试 | 结果 | 新增覆盖 |
|---|---|---|
| Godot `tests/run_account_deletion.gd` | 常驻 83/0、旧路径 83/0 | 原因含大小写不同的用户名和 user_id（删除原因、错误确认的失败请求、其他账号审计、邀请审计、其他玩家回执）全部被替换；两库完成后只有作业行还持有名字，收尾后为 0；收尾未完成时重启仍交回作业、重复请求（账号行已删）仍核对用户名并继续；过早收尾返回 `DELETION_NOT_READY`；Operator 审计文件设为只读时报告 `AUDIT_WRITE_FAILED` 且文件原样、无临时文件残留；删除日志只读时写入失败被检测且作业仍未完成；恢复可写后收尾成功、重复收尾 DUPLICATE |
| `tests/test_account_deletion.ps1`（真实 Operator、宿主、房间、两个 WSS 客户端） | 常驻 52/0、旧路径 52/0 | 删除时 `operator-audit.jsonl` 只读 → 返回 `ACCOUNT_DELETION_INCOMPLETE`（stage operator / AUDIT_WRITE_FAILED），账号已从两库删除但审计仍含名字；恢复可写后原样重新提交才报告完成（约 5.1 秒）；各处原因写入被删玩家名字后，两库逐表扫描、合并审计、Operator 审计、维护审计、删除日志均不含其 user_id/用户名；Operator 停止时制造“只做第一步”和“两库已完成、未收尾”两种中断，重启后两者都完成、审计已去名、删除日志列出旧备份。证据 `logs/account-deletion-3d1b5481…` 及本轮编排的两个目录 |
| 回归 | resident_store 34/0、asset_snapshot 40/0、account_recovery 30/0、unit 320/0、assets 83/0、accounts 85/0（旧路径 85/0）、result_rewards 74/0（旧路径 74/0）、admin_http 143/0、managed_contracts 286/0、asset_audit 14/0、operator_maintenance 35/0、operator_lifecycle 29/0、完整客户端 47/0（持有的 Operator 11/0）、后台页面 Node 测试 12/0、12/0、10/0、9/0 | |

运行结束后没有残留 Godot 或存储工作进程；`data/framework/` 没有任何文件在本轮被修改；没有碰旧备份或 Linux 设备。

Codex 复核补充：审计文件改写后的读回现在同时检查文件打开错误，避免读回失败被误判为“无身份信息”（`host/core/account_deletion.gd`）。补丁后独立重跑 Godot `tests/run_account_deletion.gd` 83/0、退出 0，证据 `logs/deletion2-review-account_deletion.stdout`；未重跑删除端到端，沿用上表补丁前的 52/0。随后按上方“当前交付物”重建最终 ZIP 并从全新解压目录完成包测试。

用户人工反馈（2026-09-27）：从项目目录启动并测试删除账号功能，未发现问题。具体操作步骤和日志未记录；这次反馈不替代 Linux、第二台设备或包内删除端到端的验收。

#### 2026-09-27 账号删除首版验收（历史记录，后续已修正）

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

#### 2026-09-27 常驻存储第一阶段验收（当前工作区代码，Claude）

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

#### 2026-09-27 常驻存储评估（当前工作区代码，Claude，仅测量）

| 命令 / 专项 | 结果 | 范围与证据 |
|---|---|---|
| `tests/perf/measure_asset_e2e.ps1 -Clients 3`（配合 `tests/test_operator.ps1 -HoldForIntegration`，编排脚本 `logs/run-asset-e2e-20260927.ps1`） | 退出 0，0 失败；Operator 侧退出 0 | 客户端视角经真实 Operator 和 WSS（大厅内，无房间许可跳转）：购买中位数 3623 ms、切换武器 3616 ms、读取 2415 ms、重复购买 2429 ms；`logs/asset-e2e-current-2.json`。第一批数据相近（3657/3623/2422/2443 ms），但因为我的脚本对重复购买返回码断言写错，三个客户端都以退出码 1 结束，不计为通过；`logs/asset-e2e-current.json` |
| `tests/perf/storage_oneshot_variants.ps1 -Rounds 7` | 退出 0 | 单次 `asset.read`：现状 1092 ms，去掉外层助手 585 ms，再加预编译 DLL 478 ms；`logs/storage-oneshot-variants.json`。第一次运行因生成的脚本写死了中文路径而失败，改为相对路径后重跑 |
| Godot `tests/perf/run_resident_probe.gd` | 51/0，退出 0 | 常驻工作进程 snapshot 13.5 ms、commit 16.7 ms、读改写周期 30.5 ms（一次性为 2213 ms）；首次应答 628 ms，重启 614 ms；440 次请求内存未增长；并发 4 个进程 p95 773 ms，共用 1 个进程 p95 143 ms；`logs/resident-probe.json` |
| Godot `tests/perf/run_gd_pbkdf2_probe.gd`（带 .NET 交叉校验参数） | 退出 0 | 通过 PBKDF2-HMAC-SHA256 公开测试向量；完整 60 万次迭代与 `account_store.ps1` 的 .NET 派生值逐字节一致；推算 60 万次约 1.70 s；`logs/gd-pbkdf2-probe.json` |

结论和迁移风险见 [docs/17 第六节](../17_framework_shooter_plan.md#六常驻存储评估与第一阶段实施2026-09-27)。以上都是测量，没有改动生产代码、协议或数据库格式。

#### 2026-09-27 资产 snapshot 复核（当前工作区代码，Claude）

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

#### 2026-09-27 grant 轮（本轮提交代码）

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

#### 2026-09-27 账号轮（提交 `07aa0d2` 代码）

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

#### 2026-09-26（提交 `4a2e11d` 中的源码，改造前；与 09-27 表同名的项以 09-27 为准）

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

#### 2026-09-22（提交 `f0b4c8b` 代码；accounts、account_recovery、assets、result_rewards、admin_http、asset_response_loss、framework_capacity 已于 09-27 重跑，以 09-27 表为准，其余未重跑）

| 层级 | 专项与结果 | 证据 |
|---|---|---|
| 真实 SQLite | accounts 81/0；account_recovery 30/0；assets 83/0；result_rewards 74/0；operator_maintenance 35/0；asset_audit 14/0 | 各自 `logs/*-console.log`，明细见归档 |
| 真实 HTTP / 投影 / 替身 | admin_http 138/0；operator_projection 9/0；operator_auth_errors 6/0；asset_callbacks 32/0；framework_feedback 7/0；operator_logs 14/0 | 同上 |
| 真实多进程联机 | framework_clients `-Visual` 47/0（两种玩法，完整打满 300 秒射击局）；managed_shutdown 55/0；operator_schedules 52/0（受控时间）；framework_capacity 174/0（16 人满房，第 17 人 ROOM_FULL，持续 17.5 秒）；asset_response_loss 25/0；players 33/0；integration 133/0；recovery 24/0 | `logs/operator-68c27ae5f8bb40de977cdebca3ac19c6/clients-a982c3c81bb5453e9e802048a58c0068/result.json`、`logs/capacity-0f1e2cdae67c42a79129524c40530eef/result.json` 等 |
| 导出程序 | `tools/build_framework_release.ps1` 生成 6 个 EXE/PCK；`tests/test_framework_release.ps1` 44/0 | `logs/framework-release-0316ee0928e647b8b324ddd6a43e37b9/result.json` |
| 人工 UI（内置浏览器 + 原生 Client.exe） | 管理员设置、开服/建房、邀请码、发币、备份/恢复、审计、维护、封禁、60 秒停服；原生射击击杀/死亡背包/解锁/复活/300 秒结算；原生取石子主题与对局 | `logs/framework-ui-f6f9a767f89b47e1ab229fac2dd02d1f/`、`logs/framework-ui-6da6c5f70d2048c2b5e3e7d2510324de/`、`logs/framework-ui-deb891a63a1e4749b0865bfb6a3f2c2d/` |

#### 2026-09-21（早期宿主，仍有效的基础结论）

`tools/run.ps1 -Mode all` 共 1144 条断言，其中 stress 用真实 100 轮开关房（404/0），load 用 20 个加密输入客户端（95/0），secure 37/0，limits 8/0；WSL Ubuntu 上 `PortableCheck.x86_64` 通过 215 项可移植检查（协议/准入/玩法，**不是** Linux 宿主）。明细见归档。

### 未运行 / 未验收

- 第二台实体设备的局域网联机（曾询问用户，未收到答复）、Linux 完整宿主、公网与公网 WSS 发布、长期满载压测、24 小时备份保留周期。
- 常驻存储第一阶段未运行：房间内（死亡背包）购买和复活前资产刷新的单独计时（完整客户端测试已覆盖其功能）；`test_managed_shutdown.ps1`、`test_operator_schedules.ps1`；`tools/run.ps1 -Mode all` 中与存储无关的模式（launcher/integration/players/games/persistence/secure/stress/load/recovery/limits/template/panel）；`managed_registry`；常驻进程长时间运行（数小时以上）的耐久与内存观察；用新包做人工试玩；第二台设备。
- 用最新独立包（`aa019dbc…`）做有记录的人工浏览器操作和原生客户端试玩（自动的 44 项包测试已通过；用户此次测试的是项目目录启动入口）；新管理表单（房间规则、8 字符密码）的真实浏览器点击；真人操作手感；托管模板的图形界面。
- 大厅内的玩家资产请求已通过真实 WSS 客户端单独计时；房间内死亡背包及复活前刷新仍未单独计时。
- 断电、磁盘满、真实网络丢包/延迟、证书轮换、外部身份服务。
- 账号删除尚未独立验证：最新 ZIP 内实际点击删除并完成端到端流程（包已包含删除功能，但 44 项包测试没有此项；用户验收的是项目目录启动入口）；删除时房间正在进行、之后才提交结果的完整真实对局（迟到结算只在 SQLite 层用真实签名结果验证）；outbox 中存在待处理/已拒绝结果文件时的残留报告（代码有扫描，未构造此场景）；大量账号或大审计文件下的删除耗时；Linux 设备（按要求未连接）。

### 已知问题与限制

1. **仅限 Windows**：账号、资产、结果存储和进程身份核验都通过 PowerShell 助手与 `winsqlite3.dll` 实现，Linux 上直接返回 `UNSUPPORTED_STORAGE`。
2. **存储调用开销（09-27 常驻存储第一阶段后）**：资产读取/购买/选择和会话校验改由常驻进程处理，客户端实测购买、切枪约 0.1 秒，读取约 0.08 秒（见上方验收表）。仍走一次性助手的操作每次往返约 1.0–1.2 秒（两次 PowerShell 冷启动加每次重新编译 C#），包括注册、登录（另有约 1.9 秒 PBKDF2，有意保留的安全成本）、登出、结算、grant、邀请码和后台管理写操作。常驻进程每个约 0.1 GB 内存，空闲 5 分钟退出，下次请求约 0.6 秒重启；长时间运行没有测过。以下为第一阶段之前的记录：购买、选择和管理员发币已从 3 次往返降为 2 次；同条件交替对照中，三者中位数从约 3.29 秒降到约 2.20–2.24 秒，仍有明显等待。上方账号轮旧表的 3.1–3.3 秒是改造前基线。但玩家在游戏里感受到的更慢：Operator 处理每次玩家资产请求前，都会先用一次账号助手往返校验会话，所以客户端实测购买和切枪约 3.6 秒、读取约 2.4 秒（09-27 常驻存储评估），这就是 snapshot 改动后体感改善不明显的原因。助手在工作线程执行，初始化与离线管理仍是同步调用。常驻工作进程方案随后已实施第一阶段，见 docs/17 第六节。
3. **客户端测试驱动有偶发失败**：`tests/test_framework_clients.ps1` 和 `tests/test_framework_capacity.ps1` 的 `Save-Json` 写命令文件（先写 `.tmp` 再 `Move-Item`）没有重试，09-27 分别出现过一次 `Access is denied` 中止（完整客户端 14/1、容量 93/1），原样重跑都通过；具体是哪个进程占用了文件没有查明。另外，完整客户端测试的开火循环一边跳一边射击，偶尔 35 秒内打不死对手（09-27 旧路径模式一次 14/1，对手剩 25 血），原样重跑通过。这些测试驱动都没有改动。
4. **临时请求文件的剩余范围**：账号请求（09-27）和 grant 签名密钥（09-27 grant 轮）已不落盘。其余资产、结果和维护请求仍用私有目录下的短期请求文件，它们不含账号口令、session token 或签名密钥。另外，用户真实数据目录 `data/framework/` 下有一个 09-26 23:33 残留的 `account-request-*.json`（104 字节，未读取内容，不能确认其内容或是否过期）和两个 `helper-*.json`；没有读取、移动或删除。
5. **射击网络模型只按局域网设计**：服务器每秒 20 次发送完整状态；客户端只做显示平滑，没有客户端预测，也没有命中回溯（按 [docs/17](../17_framework_shooter_plan.md) 的首版范围）。公网延迟下的手感没有评估。
6. **容量与耐久**：16 人满房只持续了 17.5 秒；100 轮开关房是 09-21 的早期宿主做的，托管宿主没有做长期测试。
7. **原因未查明的现象**：09-22 有一个可视化夹具中途消失，没有清理报告（未计为通过）；另有一次管理员意外退出登录，日志里没有根因（同期修复了一个相关的错误码映射缺陷，但不能认定就是根因）。
8. **预期诊断输出**：unit 的恶意指数用例会打印 `Exponent too high`；测试主动断开 TLS 时出现 `mbedtls -0x6c00`；load 模式会多打印一行 `SECURE_RESULT`（复用 secure 的测试框架）。这些都不是失败。
9. `tools/run.ps1 -Mode all` 只包含早期基础回归（外加 panel、assets），遇到第一项失败就停止；账号、管理、射击和托管专项需按 [docs/22](../22_framework_operations.md#测试入口) 单独运行。
10. **结果库容量上限没有清理机制**：每库最多 256 条启动授权、10000 条结果，每房 128 条待发送（[docs/15](../15_release_operations.md)）。09-27 代码检查确认，托管宿主每开一间房都会新增一条授权，而代码里没有任何删除授权的路径。所以同一个资产库在整个使用期内累计开到第 257 间房时，建房会因 `STORAGE_CAPACITY_EXCEEDED` 失败；上限本身已由 `run_grant_storage.gd` 实测。这不是本轮引入的问题，本轮也没有改；需要单独设计授权的回收策略（例如确认房间退出、结果补存完成之后再删除）。
11. **重复运行同一解压目录的包测试不稳定**：新包初次测试 44/0；将测试夹具改用 8 字符密码后，在同一已测试过的解压目录里连续两次都在射击导出客户端 UI 初始化标记处失败（6/1），进程退出码 0，控制台只有 Godot 启动横幅，尚未进入账号测试。用同一 ZIP 全新解压后原样运行通过 44/0，包含 8 字符管理员和玩家注册/登录。两次失败证据在 `logs/framework-release-d720d222ab154c4980cba1bd2c7301e3`、`logs/framework-release-50ad9127e6a04304aa2c999e6a60815a`；原因尚未确定，验包时使用干净解压副本。

### 本轮记录（2026-09-27）

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

**项目插画**：用户选定的 Claude 二次元角色立绘已保存为 [docs/assets/claude-character.png](../assets/claude-character.png)，SHA256 `D530B536AF330D88FF27A58CC65D84FD847C9042123FE4966F4994DD0AF43B7B`，非游戏玩法资产。路径已记入 AGENTS.md 供双方交接，并已随 `4a2e11d` 推送。

**协作规则（仅文档）**：AGENTS.md 已记录 Claude 负责主要实施、Codex 负责复核的分工，以及阶段试玩、交接、并行目录隔离和技能选择规则。没有切换模型，也没有改动代码或测试结论，原文见归档。

**文档整理（Claude，仅文档）**：用户要求 README 只保留当前推荐入口，STATUS 只保留当前状态，历史过程归档并保留证据链接，同时合并重复的入门说明、修复引用；不改代码、不删证据、不提交。

- 完成：STATUS 全部历史原文迁入 [docs/archive/status_history.md](../archive/status_history.md)，逐行校验除本文件标题外无遗漏。README 改为当前入口，原文与早期入口迁入 [docs/archive/early_entrypoints.md](../archive/early_entrypoints.md)。根目录 `START_HERE.md`、`VALIDATION.md` 合并移入 [docs/archive/design_package_v0.2.md](../archive/design_package_v0.2.md)。README 的测试模式表并入 docs/22，目录地图并入 docs/01；docs/22 的 09-22 专项结果移入归档。CHANGELOG 改为只记版本变化。修复 docs/15、docs/16、docs/08 对已归档或已移动文件的引用，并在 docs/23 补记本轮文件。
- 检查：用 Node 脚本检查全部 Markdown 的相对链接和锚点，并核对仓库文件路径的纯文本引用；另对 STATUS/docs/22 被搬走的行逐行比对。结果见本轮报告。
- 未运行：本轮没有运行 Godot、联机或任何代码测试，上面的测试结论沿用原记录。开始前已把所有 Markdown 的基线快照和 SHA256 存到本会话临时目录，用于核对差异范围；AGENTS.md 与他人未提交的源码改动均未触碰。

---

## 一、2026-09-27 至 2026-09-22（原 STATUS 第 1–164 行）

### 2026-09-27 协作规则记录（仅文档）

已在 AGENTS.md 记录 Claude 主实施/Codex 复核、阶段试玩、上下文交接、按任务分对话、并行目录隔离与主动技能选择规则。使用 OpenAI Docs 技能核对压缩、缓存与技能资料；API 机制不作为 Codex/Claude 订阅额度或跨模型缓存承诺。当前模型未切换，Claude 端未配置，文档历史归档尚未实施。本轮仅修改 AGENTS.md 与本条状态；不改变代码或既有测试结论，未运行游戏/联机测试。

### 2026-09-26 人物平滑、短弹迹与房间规则

完成：射击人物从直接显示20 Hz状态改为逐显示帧50 ms平滑，死亡/复活/传送不滑动；修正服务器补步时间戳，UI文本降至10 Hz并显示渲染FPS。整条长射线改为最长18像素的快速弹迹和短暂撞击点，重复包不重播、断流能过期、换房重置序号；服务器继续权威即时判定。

房间面板可设置每局时长30–3600秒、获胜击杀数0–1000（0不限）、复活等待0–60秒；已有房间点“规则 / 重建”。通用核心只验证可信清单声明的整数参数，具体规则由射击适配器处理。达到击杀数提前结算时记录真实时长，60秒参与奖励门槛不变。无效重建在停房前拒绝。射击升级 shooter-dev-002 / shooter-v2 / game_protocol=2，需要重启管理服务并重新打开客户端；没有终止用户当前运行的旧进程，旧ZIP未更新。

通过：Godot 4.7.2单元320/0、射击83/0、管理契约273/0、托管注册77/0；面板JS表单10/0、资产空间回归12/0。真实本机两客户端WSS/DTLS/ENet集成18/0：自定义规则到达客户端、30秒对局结束、非法规则保留旧房、合法重建确认退出后复用端口、测试宿主和房间回收。命令均退出0，日志见 `logs/rules-run_*.stdout` 与 `logs/room-rules-9eb8231a3e8b4f04927b1ee09f4392d8/result.json`。全部测试使用独立账号/目录，未读改用户账号。

真实渲染+合成20 Hz状态：基线59.83渲染FPS / 每秒20次位置变化；修改后60渲染FPS / 每秒59次位置变化，证据 `logs/shooter-visual-{baseline,smoothed}.json`、PNG。这证实一种“看起来掉帧”的原因，并非用户现有联机对局的FPS/网络延迟测量。初次渲染测试退出清理错误、换房测试输入引用错误已修复，保留断言后最终通过；无剩余已知测试失败。

未运行：真人操作手感、新管理表单真实浏览器点击、跨设备、Linux、公网、长期压力和新版导出包。具体修改文件、命令和启动验收步骤见 [docs/25_shooter_room_rules.md](../25_shooter_room_rules.md)。源码更新后需退出旧客户端 → StopManagement.cmd → StartManagement.cmd → 网页启动服务器/创建房间 → StartShooterClient.cmd；账号资产保留，未完成对局结束。


### 2026-09-26 客户端双击无窗口修复

用户报告 `StartShooterClient.cmd` 无反应。现场核实管理服务、宿主及房间正在运行；既有客户端PID33464实际拥有标题为“RoomKit · 零号仓库 · 自由混战”的窗口，但Win32 `IsWindowVisible=false`。根因为 `tools/run_framework.ps1` 将交互客户端也使用 `-WindowStyle Hidden` 启动，并立即报告成功。

源码客户端现改为Normal可见窗口启动，先校验工程/连接文件，为每次启动保存独立console/stderr/engine日志；最多等待20秒、可见窗口稳定1秒后才报告 `window_ready=true`。程序早退、脚本错误、无窗口均返回失败，CMD会保留报错；启动看门狗仅持有本次新建客户端的原进程句柄。后台进程继续隐藏启动，没有重启或停止用户现有服务器、房间或旧客户端。

实际执行 `powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_framework.ps1 -Mode client -Game shooter` 退出0，新客户端PID1844窗口可见且非最小化。已查看完整原生窗口截图，确认登录表单、“没有账号？使用邀请码注册”按钮和“请输入账号和密码”提示，stderr为空。证据 `logs/client-starts/shooter-dc4024f03fa2493cb8ac91169923952d/window-full.png`。此客户端留给用户操作，未代填密码、注册账号或加入房间；本次没有重跑整局联机。

`powershell -NoProfile -ExecutionPolicy Bypass -File tests/test_client_launcher.ps1` 最终14/0、退出0，证据 `logs/client-launcher-6e0cc113c2a748e1b4ba9935f0e9997c/result.json`。隔离测试覆盖缺引擎、缺客户端、缺连接配置和快速退出；失败不会报告成功。早退使用系统where.exe替身，不冒充真实游戏运行；可见界面由上一段真实Godot客户端验证。修改为启动器、新增失败测试和 [操作说明](../22_framework_operations.md)，同步本状态及分支清单；没有更改旧ZIP。

### 2026-09-26 继续：托管新游戏模板完成本机源码验收

用户要求继续；仍在 `codex/shooter-framework`，未读旧项目、未推送远端、未部署。核对实际仓库为 `F:\文档\GodotGame\Net\RoomKit`，Godot 为 `D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`、`4.7.2.stable.steam.ed1daf0bf`，Git `2.55.0.windows.3`。从18项SHA256校验通过的WIP快照恢复并完成托管模板；原快照保留，以下9月22日暂停说明为历史。

已完成：`new_game.ps1 -Managed` 生成自带SDK/账号客户端/独立房间/资产目录与策略/结果Schema的新工程；Operator按受信本地注册表装配服务，不再写死两个示例的资产空间、名称、策略和奖励。管理配置页与请求Schema支持登记的新GameId；模式从游戏清单枚举。新增游戏只需自己的工程和注册/空间配置，框架不增加枪械、角色或赛车规则。两个独立生成工程均已实际运行，模板客户端为命令驱动接入程序，没有新增图形游戏界面。

| 实际命令/专项 | 退出码与结果 | 范围和证据 |
|---|---|---|
| `tools/new_game.ps1 -Managed -GameId starter_demo`；Godot `--check-only` 检查生成的 `client.gd` 和 `game/room.gd` | 全部0 | 实际生成及编译检查；不能单独证明联网 |
| `tools/run.ps1 -Mode unit` | 0，306/0 | 单元/模拟进程与受控线程；`logs/room-capacity-after-20260926-console.log` |
| `tools/run.ps1 -Mode managed_registry` | 0，77/0 | Godot注册/兼容/共享目录/服务接口/失败原子性；`logs/managed_registry-console.log` |
| Godot `--headless --path . --script res://tests/run_managed_contracts.gd` | 0，260/0 | 契约与解析；`logs/admin-generic-contracts-20260926-console.log` |
| `tests/test_managed_template.ps1` | 0，74/0 | 两个实际生成游戏、真实Operator/宿主/房间、WSS＋DTLS/ENet、SQLite；`logs/managed-template-89aff6560f914ceeadeef7f0b9dfa251/result.json` |
| `tests/test_operator.ps1 -Lifecycle`（由 `logs/run-framework-regression-20260926.ps1` 在隔离源码副本构建并运行） | 0，29/0 | 现有示例注册、共享钱包、备份恢复、真实60秒重启、精确身份崩溃注入/回收；`logs/framework-final-regression-20260926.log`，副本 `data/framework-resume-regression-a5688590c79e4b25bcd368e0975dd07f/` |
| `tools/run.ps1 -Mode template` | 0，10/0 | 早期模板实际加密入房/离房，保持原入口兼容；`logs/template-resume-20260926.log` |
| `node tests/test_admin_asset_spaces.cjs`；`node tests/test_admin_auth_errors.cjs` | 各0、12/0 | 实际页面函数＋DOM/API替身；不是浏览器验收 |

新模板真实专项覆盖：任意登记GameId的配置保存、未知游戏/空间被拒且内存和磁盘配置不变；两房绑定UDP后READY；注册/登录；后台发40金币、购买扣25剩15；同operation_id重放不重复扣款；选择徽标并通过房间权威快照确认；房内只读/拒绝选择；离房、退出登录、新客户端重登保留身份和资产；第二游戏独立客户端入房；三个客户端、两房、宿主和Operator正常退出，两房UDP可重新绑定。全部在同一台Windows完成。

失败与修复保留：首次生成遇到PowerShell5.1将 `File.Replace(...,$null)` 的备份路径变为空字符串，改为 `[NullString]::Value` 后重试与旧/新索引替换验证通过。另修复缺失注册报告、模式枚举、误把SDK的void离房接口当作Dictionary，以及NUL字面量警告。首次真实模板为27/2，第二房返回 `HOST_CAPACITY_EXCEEDED`，证据 `logs/managed-template-595dd301478b47fc9d9dad892a798af7/result.json`；根因是 `active_count()` 将后台采样等工作也算入房间限额。新增回归在原代码复现303/3，修后306/0；`max_rooms` 现只统计未完成清理的房间，停止流程仍等待全部后台工作。没有提高容量、删除失败用例或吞异常。首次生命周期29/0仍带NUL警告，最终副本重新全程29/0且Operator stderr为空。

注册专项最初的测试清单使用了不符合manifest格式的 `Engine.string`，改为实际major/minor/patch/status组成的版本后完整77/0；没有放宽生产契约。unit的恶意指数边界仍产生预期 `Exponent too high` 警告。最终两套真实专项日志扫描无SCRIPT/Parse/Compile/Unicode错误，项目Godot进程检查为0。

启动和复跑见 [新游戏接入说明](../24_managed_game_template.md)。日常试玩仍是 `StartManagement.cmd` / `StartShooterClient.cmd`；新模板自动验证为 `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test_managed_template.ps1`。当前工作区相对本轮开始的HEAD共33个新增/修改文件，完整分支清单见 [分支文件](../23_branch_files.md)。本次主要修改Operator/注册器/房间计数、管理UI/Schema、生成器/构建索引、托管模板及对应测试和说明。

尚未运行：新模板图形界面验收、这次源码的新独立导出包、第二台实体设备、Linux完整宿主及公网。本轮未运行完整射击对局视觉复验，不能沿用旧包结果声明新导出已通过。9月22日旧ZIP仍保持SHA256 `49b8f13f92917b1305b9d2529bed9c371dce4c8397015501152e81ca542e173e`，不包含此次代码更新；原18项WIP快照再次校验通过。未新增EXE或大型发布ZIP，项目占用约0.927 GiB。

### 2026-09-23 本机清理

用户授权清理重复构建产物；开发继续暂停等待验收。删除44个旧导出包、旧解压副本及临时构建目录，移除约14.955 GiB；清理后整个项目约0.917 GiB，其中 artifacts 约0.851 GiB，可执行文件从130个减为6个。源码、Git历史、原有 data/logs、最新验收ZIP及解压目录、当前运行索引引用的工程和未完成模板快照均保留。

删除前，将旧目录内3319个非可再生成二进制文件（含源码、日志和测试数据）逐项校验后压缩到私有目录 `data/cleanup-history-a4c423b0bdb6498bbb2b685ca8ac1452/artifact-evidence.zip`，约3.120 MiB；同目录 `manifest.json` 记录原路径、大小、SHA256及删除清单，状态为 complete。下方历史记录引用的部分旧 artifacts 路径已归档，可按原路径从该ZIP恢复。旧 `artifacts/release.json` 和 `artifacts/delivery.json` 同样归档，避免继续指向已删除的旧包；当前 `artifacts/framework-release.json` 保留。历史归档可能含测试账号数据，不用于公开分发。

实际执行 `powershell -NoProfile -ExecutionPolicy Bypass -File logs/cleanup-artifacts-20260923.ps1` 预览及添加 `-Apply` 清理，两次退出码均为0。删除前检查项目进程及路径边界、重解析点；没有终止进程。归档3319项内容校验通过；清理后最新包35/35项、模板快照18/18项SHA256校验通过，最新发布ZIP的SHA256保持 `49b8f13f92917b1305b9d2529bed9c371dce4c8397015501152e81ca542e173e`。本轮仅做文件清理及完整性验证，没有重跑游戏或联机测试，没有推送远端。

### 暂停验收状态

2026-09-22用户要求暂停以便验收：当前交付为下述已验证的f4 Windows独立候选包及对应源码。新托管游戏模板尚未完成，进行中的18个文件已校验保存至 artifacts/managed-template-wip-20260922-299f0c53cca342e2bbc685e103879878/，并从验收源码中撤下；没有丢弃其工作。该模板仅生成过工程，未运行Godot编译/联机；客户端registration报告与测试尚需对齐。继续时先读该目录snapshot.json，不能把WIP当作可用模板。用户验收前不再新增功能。

2026-09-22，分支 codex/shooter-framework。开发规格继续以 docs/17_framework_shooter_plan.md 为准。已按“通用框架 → 可选能力 → 游戏模式”实施；宿主/SDK 不包含枪械、死亡或取石子规则。本段覆盖下方 S0 历史状态。已补充真实浏览器、导出客户端双玩法操作及本机16人容量验收；复活提示、备份大小和空日志显示已用导出包实际复验。第二台实体设备仍未验收，不把本机多进程结果当作跨电脑联机。

### 已实现并分别验证

- 独立管理进程拥有 SQLite 与回环 HTTP 中文后台，使用认证回环 TCP 管理实际宿主子进程；宿主可启动、停止、重启、维护，后台独立存活。
- 邀请码注册、用户名密码登录、稳定身份、单玩家会话、改昵称/密码、管理员重置/封禁/解封/踢出、真实持久审计。密码 PBKDF2-SHA256，不进入公开包或日志。
- 永久金币/经验/所有权/游戏配置；独立或 shared 空间；管理员调整/授权/撤销/配置。资产与流水同事务，结果和全部奖励同事务，幂等重试不重复支付。
- 真实房间许可、资产异步刷新、60 秒有界等待、成员代次隔离；SDK 回调只接收游戏定义的 operation，不解释复活。射击适配器决定死亡限制与出生。
- 横版射击自由混战、三枪、即时命中、死亡背包/选枪/手动复活、五分钟结算。取石子通过同一资产服务购买/配置玉石主题，实际入房快照采用选定主题。
- SQLite 在线备份、恢复前备份、恢复后撤销全部会话、损坏与路径边界检查、自动备份保留。新源码入口 StartManagement.cmd / StartShooterClient.cmd / StartManagedTurns.cmd / StopManagement.cmd 已写入；使用见 docs/22_framework_operations.md。

### 本轮当前真实结果

环境：本仓库 Windows；开发 Godot 4.7.2.stable.steam.ed1daf0bf；SQLite 为 Windows winsqlite3.dll。未读取其它游戏或服务器工程。下列均有真实执行及退出 0 证据，但各自范围不同。

| 命令或专项 | 已核实结果 | 范围/证据 |
|---|---:|---|
| tools/run.ps1 -Mode unit | 293/0 | Godot 规则/契约，增加等级表边界，保留恶意指数预期警告；最终logs/final-regression-20260922-accounts/unit-console.log |
| tests/run_accounts.gd | 81/0 | 真实 SQLite/PBKDF2/会话/邀请码；logs/accounts-console.log |
| tests/run_account_recovery.gd | 30/0 | 真实SQLite重开、清理玩家会话/保留管理员、恢复审计失败回滚；logs/account-recovery-console.log |
| tests/run_admin_http.gd | 138/0 | 真实 TCP/HTTP 与严格 action Schema，业务处理为夹具；logs/admin-http-strict-final-console.log |
| tools/run.ps1 -Mode assets | 83/0 | 等级表逻辑、真实资产仓储与并发/CAS/回滚；logs/assets-level-regression.txt |
| tests/run_result_rewards.gd | 74/0 | 成绩＋奖励＋流水同事务、并发重试/失败回滚/容量；logs/result-rewards-console.log |
| tests/test_operator_maintenance.ps1 | 35/0 | 实际 SQLite 在线备份/WAL/恢复/文件占用/junction/48份保留，补备份大小与路径不泄露检查；原33项证据仍保留 |
| tests/test_asset_audit.ps1 | 14/0 | 真实最近100条固定SQL审计，只读与前后值；logs/asset-audit-console.log |
| examples/shooter/test_runner.gd | 68/0 | Godot 玩法逻辑与配置验证；logs/shooter-console.log |
| tests/run_asset_callbacks.gd | 32/0 | 通用回调、超时与成员代次的可控测试；logs/asset-callbacks-console.log |
| tools/run.ps1 -Mode managed_contracts | 241/0 | 64个协议正例及权限/畸形负例，纯契约；最终logs/final-regression-20260922-accounts/managed_contracts-console.log |
| tools/run.ps1 -Mode players | 33/0 | 原真实 WS/ENet 双客户端回归；logs/framework-regression-players.txt |
| tools/run.ps1 -Mode integration | 133/0、22子进程 | 生命周期、失败路径与回收；logs/framework-regression-integration.txt |
| tools/run.ps1 -Mode recovery | 24/0 | 真实旧进程退出、未知身份隔离与新房间；logs/recovery-fix-console.log |
| tests/test_framework_clients.ps1 -Visual | 47/0 | 真实 WSS＋DTLS/ENet、两个玩法、未缩短的300秒射击局及准确到账 |
| tests/test_operator.ps1 -Lifecycle | 29/0 | 真实60秒优雅重启、已核验宿主崩溃、房间退出/UDP回收、共享空间、备份恢复与后台持续存活；logs/operator-lifecycle-final2.txt |
| tools/run.ps1 -Mode operator_projection | 9/0 | 指标失败不沿用旧值、审计查询失败不返回半份成功，纯响应投影；logs/operator-projection-check.txt |
| tests/test_managed_shutdown.ps1 | 55/0 | 真实宿主/双房间/WSS/DTLS客户端，维护与停服竞争门禁、59→57秒公告；账号/资产RPC使用夹具；logs/managed-shutdown-2cf23012230d4a928f6f17878062952b |
| tests/test_operator_schedules.ps1 | 52/0 | 7个真实宿主，三次崩溃自动重启/第四次拒绝，4次真实SQLite自动备份；到期和历史时间受控，不是30分钟墙钟测试；data/test-operator-schedules-691ba27c01ae4828b4a50cc1b46796e2/schedule-result.json |
| tests/test_framework_capacity.ps1 | 174/0 | 16真实账号/客户端满房，第17人ROOM_FULL；17.528秒同步/心跳/移动，空位复用与全部进程/端口回收；logs/capacity-0f1e2cdae67c42a79129524c40530eef/result.json |
| tests/run_framework_feedback.gd | 7/0 | 复活确认后的提示更新，Godot纯界面状态回归；logs/framework-feedback-console.log |
| tests/test_operator_logs.ps1 | 14/0 | 实际Godot启动日志、合法空日志、缺失及真实Windows独占锁不可读；详见docs/19_admin_ui.md |
| tests/run_operator_auth_errors.gd | 6/0 | 实际Operator线程准入/管理请求/HTTP映射，账号响应与HTTP输出使用替身；临时存储失败不误撤销会话；logs/operator-auth-errors-after-console.log |
| node tests/test_admin_auth_errors.cjs | 12/0 | 执行真实HTML api函数，fetch/DOM为可控替身；重试、失效提示和晚到旧请求隔离，不是浏览器故障注入；logs/admin-auth-errors-after.log |
| tests/test_asset_response_loss.ps1 | 25/0 | 真实源码Operator/宿主/WSS/SQLite：提交购买后测试发送边界丢弃成功回复并断开TCP，重连同operation_id得DUPLICATE、只扣一次；data/test-asset-response-loss-201117a964ef48558280a20d3569e42d/response-loss-result.json |
| tools/build_framework_release.ps1 | 6个EXE/PCK，退出0 | Godot官方模板真实导出；logs/framework-export-f4f40384083d45e28ffa38bcb5dea472-* |
| tests/test_framework_release.ps1 -Bundle <新包绝对目录> | 44/0 | 35项哈希、原生管理/宿主/双房间、实际WSS/ENet及回收，补日志路径与备份大小；logs/framework-release-0316ee0928e647b8b324ddd6a43e37b9/result.json |
| tools/run_framework.ps1 -Mode panel -NoBrowser / -Mode stop | 分别退出0 | 实际源码启动和关闭，stderr空；logs/framework-source-launcher.txt、framework-source-stop.txt；没有浏览器操作 |

完整客户端证据：logs/operator-68c27ae5f8bb40de977cdebca3ac19c6/clients-a982c3c81bb5453e9e802048a58c0068/result.json，以及该目录各客户端报告/截图/日志。实际验证注册登录、初始免费枪、管理员发币、入房、存活伪造购买/选用拒绝、实际射击死亡、过早复活拒绝、死亡读背包/购买/幂等/默认配置、持新枪复活、离房重入保留；取石子玉石主题与真实回合；重复登录拒绝、封禁断开与解封。五个测试客户端全部退出。仍是同一台电脑的真实多进程，不是跨设备联机。

独立包自动网络专项采用“源码测试客户端 → 导出宿主和房间”；该专项中的 Client.exe 初始化检查不充当完整试玩。下文另列原生 Client.exe 的真实鼠标/键盘与浏览器操作。默认 data/framework 只初始化了空账号库，尚未创建用户管理员；可视化验收账号在包内独立 ui-test 目录，不作为用户正式账号交付。

最终干净 ZIP：artifacts/RoomKit-0.5.0-framework-windows-f4f40384083d45e28ffa38bcb5dea472.zip，228951845字节，SHA256 `49b8f13f92917b1305b9d2529bed9c371dce4c8397015501152e81ca542e173e`。ZIP包含36项、35项不可变文件校验，私有数据/测试夹具0；最新路径记录在 artifacts/framework-release.json。旁边已解压目录经过测试，含测试私有数据，不能整体转发代替干净 ZIP。之前d909/e102/e288/9d16候选保留用于证据追踪，不是当前推荐包。

### 已发现并修复后复验

- 最初 PowerShell HTTP 健康探针自动发 Expect:100-continue，服务端按有界协议拒绝；测试明确关闭该测试进程的 Expect 行为。服务端拒绝规则保留。
- 新管理员 Schema 的 Unicode 转义正则不兼容 PCRE2；改为受支持的十六进制范围后 HTTP 专项138/0。第一次跑到房间READY后遇到该失败，未计作整套管理流程通过。
- 邀请码实际字段为 invite_code，原测试误读空的成功状态 code；修正后真实客户端47/0。管理员UI同步修正该字段。
- 更改密码/登出先关闭连接会丢失成功响应；现先返回成功并立即拒绝后续业务，再结束连接。
- 重新加载 JSON 后端口被格式化成28300.0，导致公开客户端配置无效；现显式整数格式，最终独立包42/0已包含公开WSS整数端口验证。
- 旧管理测试停止请求漏填 reason、配置切换请求漏字段；最初退出1，finally 均停止本次进程。测试补齐实际契约后继续完整重跑。
- 旧恢复测试两次读取正在改写的报告可能取到空快照，误把UDP端口记为0；现在使用同一份已验证快照、动态空闲端口并显式断言范围，真实恢复24/0。原19/2失败记录保留在 logs/framework-regression-recovery.txt。
- 生命周期崩溃注入首次因Windows路径斜杠比较不一致拒绝执行；现按绝对路径比较，身份要求未放宽。随后28/1发现新宿主已RUNNING时旧journal尚未清空；现在确认旧进程退出且UDP能绑定后原子清空，再启动新宿主，最终29/0。失败日志 logs/operator-lifecycle-final.txt 保留。
- 管理服务本身重启后旧玩家会话曾阻止再次登录；现只在旧进程安全确认之后执行内部会话清理，保留管理员，删除与审计同事务，专用30/0。该操作未加入公开Schema或远程RPC白名单。
- 启动器遇到死进程遗留描述文件时，只有确认PID已不存在才删除固定标记并重启；PID仍存在或描述畸形则拒绝。包启动器专项3/0，见 logs/descriptor-test-b5485314269842fe8101488ed120106f/result.json。
- 奖励测试首次夹具误带额外 duration_ms；已更正并完整74/0。契约初次重复键断言用了不负责HTTP重复键的通用解析器，改为实际AdminHTTP检查后241/0。失败日志保留。
- 停服期间关闭维护可能重开准入；异步资产加载和房间重建也存在等待后的状态变化。现停止状态不能被维护开关解除，重复停止只能缩短截止时间，票据消费/资产加载后/重建等待后均复查；真实55/0验证，未延长测试超时掩盖问题。
- CPU采集失败曾残留旧值，资产/账号审计查询失败曾显示部分成功。现指标带采样时间、15秒过期显式不可用；两路审计任一路失败则明确失败。纯投影9/0，不能写成真实存储故障注入。
- 等级原为固定除100，现由可信资产目录的等级阈值表派生；表必须从0严格递增，共享空间使用同一表，旧目录缺省保持1级。unit293/0、assets83/0及真实UI的250经验→3级验证。
- 容量测试前两次为测试驱动读错SDK返回错误码、报告文件原子替换期间读空；修复驱动/短暂文件读取重试后174/0。人数、ROOM_FULL与真实网络停滞门槛均未放宽，失败证据保留。
- 实际原生UI发现死亡复活后仍显示等待提示，已修复dead→alive消息；定向Godot状态测试由6/1变为7/0。还发现备份列表缺少大小、导出启动器日志路径与API不一致、停止态运行时间标签误导及重新登录遗留旧错误提示，均在后续新包修复。日志独占锁/空文件/缺失区分已有真实14/0验证；Godot会消耗--log-file参数，因此采用受信启动器同步传入--operator-log-path，不新增任意路径HTTP入口。
- 前一个可视化夹具0f978611214d40b0a6c42a71dcd19576途中进程消失且无最终清理报告，原因未能确认；不能记为通过。随后由根持有进程句柄的f6f9a767f89b47e1ab229fac2dd02d1f完整操作并正常收尾，exit0、cleanup_failed=false、forced_cleanup=false、live_owned_processes=0。
- 管理员身份校验曾把存储不可用或线程容量不足改写成认证失败，浏览器因此清除登录且提示留在隐藏页面。现保留可重试的原错误码，真实失效在登录页显示原因，并防止旧请求撤销新登录。实际生产函数定向回归由Operator 3/3、页面7/5修复为6/0、12/0；替身边界如上表，不当作真实数据库故障注入。

### 本次可视化验收与剩余边界

前一轮浏览器因工具安全检查停止的证据 logs/browser-qa-20260922/report-final.json 保留。本次续跑重新获得可用的内置浏览器，并实际访问隔离管理服务；没有绕过安全警告。已实际操作首次管理员设置、宿主启动、射击/取石子房间创建、邀请码、玩家资产发放、在线备份、审计、配置只读、维护公告、封禁/解封。浏览器发起真实60秒停服后显示宿主已停止、活动房间0、后台在线，原宿主及两个房间PID均不存在。还实际恢复手动备份、生成恢复前备份、撤销管理员旧会话并重新登录。

这次UI会话中管理进程实际启动于01:45:04，未缩时自动备份于02:15:17生成并在浏览器列为“自动备份”；这补充了52/0受控时间测试之外的一次真实30分钟墙钟观察，仍不代表24小时保留周期长测。UI夹具及两个源码对手均正常exit0且无需强制清理；完整观察记录为 logs/framework-ui-f6f9a767f89b47e1ab229fac2dd02d1f/ui-observations.json，收尾为 fixture-result.json。

原生 e10231265ab7478ea7daaf228757b5d1 包已用可见 Client.exe 操作完成：邀请码注册/登录；射击进房、服务器真实击杀、死亡背包读300金币/250经验/等级3、100金币解锁SMG且另行选择、复活快照hp100/weapon=smg；真实300秒对局后返回大厅220金币/默认SMG；注销后同一账号登录取石子，独立空间0金币/经典主题，发放100金币后解锁并选择jade，真实六步取石子进入第二局且UI玩家1分。对手使用源码SDK测试驱动发送合法动作，服务端与被操作的两个客户端均为实际导出程序；不是两台实体设备。证据 logs/framework-ui-f6f9a767f89b47e1ab229fac2dd02d1f 中的截图/快照及隔离对手目录的动作证据。

后续9d16d01539bb4f5bb235b1b0aadf9c6f包复验：实际注册/登录新玩家、创建并加入原生射击房间，源码SDK对手合法击杀一次后停火，点击手动复活得到生命100及“已复活，可以继续战斗”提示；浏览器创建备份成功并显示103 KB，空operator日志明确显示“当前日志为空”，重新登录没有遗留旧全局提示。证据 logs/framework-ui-6da6c5f70d2048c2b5e3e7d2510324de/ui-observations.json、shooter-respawn-fixed.png、shooter-respawn-report.json。对手首次150秒等待未入房是失败等待记录，后续成功另存；不删除此前记录。UI夹具、对手均exit0，无强制终止、清理错误或遗留自有进程。该轮也观察到一次管理员意外退登录，日志无实际根因；代码检查发现临时存储/限流失败被误映射为AUTH_FAILED，按独立缺陷修复，不把推断写成事故根因已查明。

最后f4f40384083d45e28ffa38bcb5dea472包实际浏览器复验：首次管理员设置成功，停服态显示“未运行”；创建真实SQLite手动备份，列表显示103 KB；执行恢复后旧管理员会话失效，登录页明确显示“用户名、密码或登录凭据无效。”；重新登录成功，无旧全局错误提示，刷新列表可见手动备份与恢复前备份。已检查实际页面截图，未向浏览器注入模拟响应。证据 logs/framework-ui-deb891a63a1e4749b0865bfb6a3f2c2d/ui-observations.json 与 fixture-result.json；夹具退出0，cleanup_failed=false、forced_cleanup=false、live_owned_processes=0。此次没有重复完整射击局，也没有通过浏览器注入真实存储繁忙；相应范围分别由先前可视化与定向替身测试记录。

本机容量174/0仅覆盖17.528秒短时满房与准入，不代表长期压测。第二台电脑局域网、Linux完整宿主和公网仍未运行；没有部署公网或花费云资源。已向用户询问第二台Windows设备，未收到答复，不推定已验收。

新增响应丢失专项25/0实际在数据库完成500→400金币及解锁SMG后，由测试Lobby的发送边界不发送成功应答并中断真实WSS TCP；原版AccountClient收到CONTROL_UNAVAILABLE，重新登录后用同一operation_id得到DUPLICATE，金币、所有权和版本不再变化，真实SQLite购买流水只有1条。测试不是“已经收到成功后再重复点击”，也不涉及玩法房间或独立导出客户端。故意断TLS的mbedtls -0x6c00保留在console，无脚本异常；cleanup-recheck.json确认测试退出0、宿主退出、标记移除、大厅及控制TCP能重新绑定。

### 修改文件和本机入口

本轮实际新增/修改文件完整清单见 docs/23_branch_files.md。主要入口为 host/operator.gd、host/managed_host.gd、host/managed_lobby.gd、host/admin_http.gd、host/admin.html、host/core/account_service.gd、通用资产/结果服务和SDK资产回调；示例位于 examples/framework、examples/shooter、examples/turn_based；契约统一位于 schemas。启动、备份、构建与测试脚本分别在 tools 和 tests。

本机从仓库双击 StartManagement.cmd，首次设置管理员后点击“启动服务器”，创建邀请码；打开两个 StartShooterClient.cmd 用两个玩家账号注册登录、加入同一房间。五分钟真实规则、背包与死亡操作、取石子及关闭方法见 docs/22_framework_operations.md。开发路线见 docs/17_framework_shooter_plan.md，SDK兼容决策见 docs/07_versions_decisions.md 与 docs/21_managed_protocol.md。

本次收尾修改47个源码/测试/文档文件，完整本轮差异清单相对711a657共120个文件。2026-09-22最新提供的AGENTS.md要求不推送远端，本次收尾只做本地提交；日志、私有数据及独立包继续留在Git忽略目录。新托管模板和第二台实体设备的门槛未关闭，用户现要求暂停验收，不能把整个分支目标标为全部完成。

---

## 二、2026-09-22 停服与调度专项（原 docs/22_framework_operations.md）

### 停服与调度新增专项

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


---

## 三、2026-09-21 及更早（原 STATUS 第 166–636 行）

## 以下为前一轮 S0 与更早历史
## 本轮：通用框架分支与资产基础

2026-09-21：已从 `codex/m4-results` 的 `1a8bec5` 创建并切换到 `codex/shooter-framework`。用户确认采用“通用框架＋可选玩法模块＋具体游戏模式”，永久账号资产与比赛临时经济分开；当前示例为横版自由混战，战术回合玩法仅保留扩展边界。完整范围已写入 docs/17_framework_shooter_plan.md，原 CODEX_START/docs/00 的 M0/M1 标为历史启动任务。

### 已完成

- S0 分支、架构边界、阶段和契约；完成 S3 的第一批内部资产基础，尚未接公共网络/UI。
- 可信资产目录与配置槽、独立/共享空间选择；同一个钱包可以共享，默认配置按游戏分别保存。
- Godot 内部资产服务、SQLite 永久金币/经验/非堆叠所有权/默认配置、购买与选用分开、管理员调整、版本冲突检查、幂等回执与前后状态审计。
- SQLite 助手 v1→v2 保留式初始化升级、真实事务回滚、在线备份；不迁移旧项目账号。
- 独立的可选比赛内存钱包，不连接永久数据库，随实例结束清空。
- 射击策略（大厅/死亡允许）与取石子策略（只允许大厅）分别实现，框架不包含死亡/枪械分支。已验证内部接口复用，不等同于两个完整客户端已接入。

### 本轮真实测试

环境：当前项目 `F:\文档\GodotGame\Net\RoomKit`，Windows、Godot `4.7.2.stable.steam.ed1daf0bf`、SQLite `3.51.1`。所有命令均从本目录运行。

| 实际命令 | 退出码 | 结果与范围 |
|---|---:|---|
| powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode unit | 0 | 最终 284/0；原 250 项＋34 项资产目录、契约、策略和比赛内存钱包检查 |
| powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode assets | 0 | 70/0；其中 30 项纯逻辑＋40 项真实 SQLite/内部服务检查；随后补充的 4 个文档例子在上方 unit 中验收，不虚增此轮 assets 实测数 |
| powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode persistence | 0 | 42/0；原真实 Godot 子进程结果保存、丢 ACK 重试、宿主退出/恢复、签名校验与资源回收回归 |

资产测试真实验证：v1 数据库旧结果保留；购买/选择跨服务重开保留；重复请求只扣一次；不同用户/空间隔离；共用钱包但不同游戏配置不覆盖；两个独立 SQLite 写者同版本竞争仅一方成功；中文审计；备份可读；在写状态后通过测试库触发器让回执写入失败，状态和回执均回滚。

证据：logs/unit-console.log、assets-console.log、persistence-console.log 及各自 stderr。最终资产测试库为 data/test-assets-13d7d40cf0d4c6ceacdc5c7c1888b6ff；失败触发器仅在该独立测试库内，未改用户演示库。运行数据不进入 Git。

### 失败和修复

新增旧库测试夹具首次为 30 通过/1 失败、退出 1。原因是直接调用 PowerShell 脚本后检查没有设置的 LASTEXITCODE，将已成功创建的私有目录误判失败；改为同时依赖脚本异常和 PRIVATE_DATA_READY 成功标记，未降低目录边界检查。保留 logs/assets-legacy-attempt-failed.log 和对应 stderr；修复后的完整资产测试 70/0。单元原有恶意 JSON 指数过大警告仍保留，拒绝断言通过。

### 未完成 / 未运行

尚未实现 S1 常驻可操作后台、S2 用户名密码/邀请码账号、真实房间资产许可及复活串行控制、射击客户端/地图/伤害/背包 UI、整场奖励和自动运维。当前 StartPanel.cmd 仍打开原只读双示例面板。内部 identity/context 只接受宿主可信调用，不是可直接暴露的网络权限接口。

这轮未运行射击联机、跨电脑局域网、Linux、浏览器视觉或新独立包导出。SQLite 竞争测试是真实数据库写入，不是网络并发玩家；死亡策略使用测试上下文，不是真实角色状态；重复请求测试不等于网络丢包注入。没有把新分支的全部开发计划标为完成。

### 文件与启动

- 范围/架构/路线：AGENTS.md、CODEX_START.md、README.md、docs/00_greenfield_start.md、docs/01_scope_architecture.md、docs/02_contracts.md、docs/03_sdk_integration.md、docs/06_roadmap_acceptance.md、docs/17_framework_shooter_plan.md、docs/18_asset_foundation.md、STATUS.md。
- 内部实现：host/core/asset_catalog.gd、asset_rules.gd、asset_service.gd；sdk/roomkit/server/asset_policy.gd、match_wallet.gd；tools/sqlite_store.ps1。
- 示例/契约：examples/asset_catalog.example.json、asset_messages.example.json、shooter/asset_policy.gd、turn_based/asset_policy.gd；schemas/asset_catalog.schema.json、asset_command.schema.json、asset_state.schema.json。
- 验证：tests/test_assets.gd、run_assets.gd、run_unit.gd、fixtures/asset_database.ps1；tools/run.ps1。

复现新增基础功能使用上表 `-Mode assets`；接口、错误码与数据版本边界见 docs/18_asset_foundation.md。当前还没有可以启动的射击游戏入口。后续按 docs/17 继续常驻后台和账号接入，无需重新确定架构方向。

---

## 历史：中文本机状态面板

2026-09-21：用户要求类似宝塔的服务器/房间/玩家数据查看，已新增可实际打开的中文只读网页面板。原房间生命周期、加密连接、SQLite和独立包继续保留；未引入额外后端、未访问旧工程、未部署公网。

打开仓库StartPanel.cmd（需本机Godot）或新版独立包StartPanel.cmd（无需编辑器）。面板与两个示例游戏窗口一起启动；查看宿主运行时间、PID/端口、房间状态/人数/心跳/实际工作集、在线玩家身份及最近100条SQLite对局成绩。支持房间搜索、状态筛选、按房间看成员、点击玩家看近期成绩。只读，不包含账号资产/背包/商城、网页开关房或远程系统管理。具体入口与数据来源见docs/16_dashboard.md。

默认面板仅监听127.0.0.1:28291，使用每次宿主随机生成的Bearer凭据；只从私有run描述文件交付给本机页面，不在应用日志打印访问链接。页面2秒刷新、数据库5秒异步读取；明确区分离线旧数据和存储错误。响应使用显式白名单，不返回控制token、票据/摘要、私钥、数据库授权或私有路径。真实响应Schema和例子已同步。测试随机端口使用独立描述文件，不覆盖用户正常面板的授权文件。

### 本轮实际测试（均在Windows本机）

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

### 失败、修复和边界

- 一次重新解压测试32通过/16失败：首个客户端CONTROL_UNAVAILABLE，其它客户端等待双玩法后续阶段超时。连续同步启动/身份捕获会阻止宿主处理早到客户端的WSS连接；已将演示客户端启动改到独立工作线程，在主线程继续轮询连接，完成后移交精确进程身份记录。未延长超时或删测试；最终源码62/0、新解压official48/0通过。失败保留logs/panel-release-startup-failed.txt及对应旧解压目录的客户端日志。
- official Godot返回静态内存0（未提供该指标）；现明确显示“当前引擎未提供此指标”，不把0画成有效数据。每房工作集仍由真实Windows进程采样得到。未提供整机CPU/磁盘统计。
- 页面锚点最初可能在刷新时误当授权；改成仅64位十六进制片段作为凭据，其它锚点沿用当前标签页会话，最终浏览器导航/刷新通过。一次浏览器空字符串填充未清空搜索，改键盘选中删除后确认恢复；未把工具动作尝试计作成功。
- 新库没有对局时显示空状态；只有完成并保存的真实结果才出现。账号总资产、第三方身份服务、远程面板、公网、Linux完整宿主仍未实现或未验收。网页写操作未提供。

### 当前交付位置
- 程序ZIP：`F:\文档\GodotGame\Net\RoomKit\artifacts\RoomKit-0.1.0-windows-ba558c42d15d46f78efa2dff32b501ce.zip`
- 已解压启动器：`F:\文档\GodotGame\Net\RoomKit\artifacts\unpacked-ba558c42d15d46f78efa2dff32b501ce\StartPanel.cmd`
- 程序ZIP SHA256：`A1F1C6AEBE1D4D477B29F4B8214FB16F1EE4874B09A38E365AE6CA026990B1D9`

### 本轮文件清单（21个）

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

## 实际开发状态

更新：2026-09-21。本轮继续用户“一口气全做完”的后续授权，完成 Windows 本机 M4 安全/恢复闭环和 M5 发布候选交付；**不把 M4/M5 全部正式门禁标为通过**。Linux完整宿主、跨电脑与公网、最坏玩法容量边界、另一台干净机器仍未验收。只修改当前独立仓库，没有读取、复制或修改旧游戏/旧服务器，没有云部署或账号商城。

### 现在可以直接用什么

- Windows独立程序ZIP：`artifacts/RoomKit-0.1.0-windows-3b92cb9c4c7f471ab9162e6490f837b8.zip`，181.73 MiB。无需Godot编辑器；需要Windows PowerShell与系统winsqlite3.dll。
- 已重新解压并测试的启动器：`artifacts/unpacked-3b92cb9c4c7f471ab9162e6490f837b8/StartRoomKit.cmd`。打开两个取石子窗口；传入`-Game blocks`玩方块。StopRoomKit.cmd正常停止，CheckRoomKit.cmd校验。
- SDK 0.4.0与独立新工程模板：`artifacts/RoomKit-SDK-0.4.0-template-3b92cb9c4c7f471ab9162e6490f837b8.zip`。也可运行`tools/new_game.ps1 -GameId my_game`重新生成。
- 源码原入口StartPlay.cmd、StartTurns.cmd、ShowResults.cmd保留。完整操作/备份/故障/升级见docs/15_release_operations.md，路线见docs/06_roadmap_acceptance.md。
- ZIP与日志不上传Git，源码与可重建脚本沿用用户授权上传指定GitHub的codex/m4-results分支；精确提交及远端核对见本轮最终回执。未修改全局Git配置。

### 本轮实现

身份提供方预配高熵凭据，持久文件只存摘要和稳定user_id/角色/期限；管理员停房授权，同用户第二会话拒绝，过期会话关闭。演示与独立包默认WSS + ENet DTLS，固定证书和主机名验证，凭据禁止走明文WS；保留基础M1/M2的无账号回环开发夹具。未实现第三方账号服务。

启动/终止/资源采样、结果写库改为工作线程/有界队列。助手超时只终止它自己创建并持有的原句柄；历史房间/并发启动/结果队列有限额，实测内存超限关闭房间。托管宿主在启动前记保留端口，重启隔离遗留实例，精确只读身份确认退出后才能释放；未知身份不猜测、不接管、不杀旧PID。

建立真正的Windows宿主、两个服务器、两个客户端EXE/PCK，固定入口适应官方模板；只读PCK与可写外部路径分开。新增启动/停止/校验/结果查看/备份脚本，按构建文件白名单打包，禁止夹带data/run/logs或私钥。SDK和新工程模板只通过GameAdapter与注册配置接入。源码SDK为0.4.0，开发及正式构建分别有独立兼容标识，详见docs/07。

### 实际命令与结果

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

### 本轮失败、修复及未运行

- 导出初次使用--main-pack/--path被official模板拒绝；只去掉路径但保留--script仍不能选择所需入口。改固定MainLoop后又发现必须有主场景，最终固定类+空场景通过。没有把这些失败计为导出通过；早期失败日志仍在logs/及对应旧artifacts目录。
- 本轮扩充文档消息例子后，unit首次249通过/1失败，因为例子数量断言仍为17。同步为18并保留逐项Schema校验，最终250/0；失败证据completion-example-count-failed.txt。
- 一次WSL路径转换丢失Windows反斜杠，程序未启动（127）；改为明确/mnt/f路径后实际Linux退出0。首次进程残留审计遇到空ExecutablePath，修正为空字符串处理后重新执行，最终审计无错误。
- 单元恶意指数产生预期Exponent too high警告；负向证书用例产生预期TLS握手失败。未隐藏这些输出。完整回归最终无GDScript编译错误或退出资源泄漏。
- Windows正式程序已验证，Linux只有可移植测试：ProcessLauncher、RoomManager保护目录和SQLite适配仍为Windows实现，Linux宿主缺失；未将它伪装为环境测试通过。
- 没有跨电脑/LAN/公网部署、外部身份服务、长期满载、最坏玩法/实体规模、容量边界、真实网络丢包、证书轮换、硬CPU/内存配额、磁盘满或断电测试。尚未成功写入outbox的结果不能承诺恢复。凭据仅本地预配，不是完整账号系统。
- 资源上限是应用层采样/队列上限，初始化和离线管理仍有同步调用。数据授权/结果容量有限且无自动归档，不宣称生产长驻已完成。任意跨路径/跨机器数据迁移未验证。

### 本轮实际修改文件

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

## 以下是先前阶段历史记录，当前结论以上方为准

## 实际开发状态

更新：2026-09-21。M0—M3已有本机验证；本轮继续实现M4第一部分：SQLite结果保存、幂等确认、持久outbox、宿主退出后的结果补存和在线备份。M4整体未完成。仅在当前独立仓库开发，未读取、复制或修改旧项目。

### 本轮M4第一部分：结果可保存、重发、恢复与备份

本轮从干净main建立codex/m4-results开发分支，沿用用户对指定GitHub仓库的上传授权。无公网部署、账号/商城开发或云资源消耗。当前工作目录仍为F:\文档\GodotGame\Net\RoomKit；引擎4.7.2.stable.steam.ed1daf0bf、Git 2.55.0.windows.3，系统SQLite实测3.51.1。

完成：宿主集中写SQLite，结果ID及同局最终结果双重唯一约束；每房独立签名授权；房间先写持久outbox再发送，只有提交成功且确认摘要匹配才删除；丢ACK重试不重复写库；真实终止宿主后房间自行退出、UDP可重新绑定，新宿主补存遗留结果；在线备份及从备份打开验证。回合玩法已经实际接入，方块玩法不生成成绩。SDK更新为0.3.0，示例构建及兼容标识同步更新，协议/例子/错误码见docs/02、07、13。

本机验证：双击StartTurns.cmd，两个窗口轮流取完一局石子，关闭窗口后双击ShowResults.cmd，可用中文查看已保存的局数和玩家分数。数据位于data/showcase-results/results.sqlite，不进入Git。成绩记录不等于账号累计积分；新房不会自动恢复旧局。

#### 本轮实际测试

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

#### 失败修复与未运行

- 初次unit为242通过/1失败：嵌套NaN绕过通用结果校验；增加递归JSON有限数及深度校验。初次persistence因GDScript动态变量类型推断编译失败，总watchdog终止原宿主句柄，未算作运行通过。证据保留m4-unit-attempt-failed.txt、m4-persistence-parse-failed.log。
- 首次能运行的持久化测试出现RefCounted循环引用退出泄漏；结果服务改用WeakRef引用管理器，后续最终stderr无泄漏/资源未释放错误。
- 增加中文与引号断言后一次全套回归persistence为41通过/1失败：数据库内容正确，Windows管道返回Godot时乱码；助手改用ASCII JSON Unicode转义，最终往返断言通过。失败保留m4-all-attempt-failed.txt、m4-unicode-attempt-failed.log。另补文件和控制帧完整小数精度，避免签名摘要漂移。
- 单元恶意1e999仍产生预期Exponent too high警告，拒绝断言通过；没有隐藏警告。
- ACK丢失是在真实控制链路的测试宿主中故意跳过首个ACK；宿主终止前的未提交状态由测试故障钩子保持。不是网络设备丢包或真实磁盘故障。SQLite损坏文件拒绝是真实执行；存储不可用ACK保留文件由单元验证。
- 未验证断电、磁盘满、写临时文件中途崩溃、正式奖励业务、16人/100轮、Linux、专用导出或公网。同步PowerShell存储存在阻塞延迟；每库256授权/10000结果、每房128待发送的当前上限没有自动清理策略。M4的正式身份、安全传输、完整资源治理和立即重开房的遗留实例隔离仍未完成，详见docs/13。

#### 本轮实际修改文件（41个）

- 根入口/说明：ShowResults.cmd、README.md、STATUS.md。
- 宿主：host/core/result_service.gd、host/core/room_manager.gd、host/storage/sqlite_repository.gd。
- SDK：sdk/roomkit/server/game_adapter.gd、room_runtime.gd、result_outbox.gd；sdk/roomkit/shared/result_format.gd、control_transport.gd。
- 工具：tools/protect_data.ps1、sqlite_store.ps1、results.gd、results.ps1、run.ps1。
- Schema：schemas/result_record.schema.json、result_submission.schema.json、result_ack.schema.json、summary_result.schema.json、control.schema.json。
- 示例：examples/showcase/host.gd；examples/turn_based/adapter.gd、game.gd、game_manifest.json；examples/blocks/game_manifest.json；examples/minimal/multiplayer_manifest.json；examples/result_messages.example.json、m2_messages.example.json。
- 测试：tests/test_results.gd、run_persistence.gd、run_unit.gd；tests/fakes/lost_result_ack.gd；tests/fixtures/result_host.gd、result_room.gd。
- 文档：docs/02_contracts.md、03_sdk_integration.md、06_roadmap_acceptance.md、07_versions_decisions.md、10_environment.md、13_m4_results.md。

### 以下为M3历史：可以打开窗口试玩的两个游戏

Git 交付完成（2026-09-21）：用户已明确授权上传 GitHub，覆盖初始任务中“不推送远端”的限制。首次本地提交为65bd328，源码与文档纳入版本管理；run/、logs/、artifacts/、私有配置与密钥文件继续排除。上传前扫描102个待提交文件，未命中常见GitHub令牌/私钥格式。用户指定远端 https://github.com/SchreiberChiang/godot-network-.git，已配置为origin，并合并保留远端main的初始MIT许可证提交88137fb。首次推送因GitHub未认证失败；用户完成Git Credential Manager设备登录后，git push -u origin HEAD:main 退出0，远端main已从88137fb推进至02a9a37，包含完整源码和文档。本地分支同步命名为main；本状态更新作为后续提交推送。全程未强制推送，未改动全局Git配置。本次只处理Git交付，没有重跑或改变上方运行时验收结果。

用户继续授权后，按 docs/06 从零实现方块移动与无 CharacterBody/武器的回合取石子游戏，范围决定和协议见 docs/12_m3_games.md。宿主与 SDK 核心未改：本轮开始记录的13个 GDScript 文件 SHA-256 全部一致，两个独立产物携带的 SDK 也与源码一致。新增游戏通过自己的 GameAdapter、房间子类和本机注册配置接入。

**试玩方式：** 双击 `StartPlay.cmd`，点击玩家窗口后用 WASD/方向键移动；双击 `StartTurns.cmd`，轮到自己时取1或2颗石子。每个入口打开两个玩家窗口；可退出房间并重新入房，关闭两个窗口后自动结束。建议依次运行两个入口。原 `StartDemo.cmd` 保留 M2 文字自动测试。

#### 本轮真实执行

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

#### 本轮修复与限制

- 新增玩法单元首次221通过/3失败：数值 enum 经JSON解析为float，旧校验器的数组成员比较不接受原生int；将“只能取1或2”改为语义等价的 integer/minimum=1/maximum=2，保留原失败断言并补充拒绝1.5。没有放宽合法值，也未改SDK。失败证据保留 logs/m3-unit-attempt-failed.log 及对应stderr；最终229/0。
- 原单元恶意 `1e999` 仍触发预期 Exponent too high 警告，拒绝断言通过；没有隐藏该警告。
- 每房真实验证2名玩家，配置最大16；未运行16人、100轮、跨电脑、Linux、浏览器或公网。没有专用服务器可执行文件导出验证：两个产物是独立Godot开发工程。
- 方块没有碰撞、预测或插值；石子分数只在当前房间成员上保留，离房会清除。没有账号、商城、持久化、断线续局或完整游戏。
- 本轮房间子类通过锁定SDK的 members 字典将已准入 user_id 映射到传输peer，未来SDK内部表示变化需要复验。输入/状态协议各归自己游戏，不统一为核心战斗API。
- 私有凭据、路径控制和安全终止沿用M1/M2；同步Windows进程助手的限制仍存在。尚未进行公网安全/容量验收。

#### 本轮实际文件清单

新增：

- StartPlay.cmd、StartTurns.cmd；tools/build_games.ps1、play.ps1。
- examples/blocks/README.md、game_manifest.json、room.gd、adapter.gd、game.gd。
- examples/turn_based/game_manifest.json、room.gd、adapter.gd、game.gd。
- examples/showcase/host.gd、client.gd、view.gd；examples/gameplay_messages.example.json。
- schemas/blocks_input.schema.json、blocks_state.schema.json、turns_input.schema.json、turns_state.schema.json。
- tests/test_games.gd、run_games.gd；docs/12_m3_games.md。

修改：host/development.gd（仅注册组合入口）、tests/run_unit.gd、tools/run.ps1、examples/turn_based/README.md、README.md、docs/07_versions_decisions.md、STATUS.md。host/core/ 与 sdk/roomkit/ 源码未修改。未提交、未推送、未部署或花费云资源。

后续为 M4 持久化与故障/安全闭环；当前本机玩法演示不能视为公网或正式发行已完成。

### 以下为 M2 与 M0/M1 历史记录

以下旧结果保留历史含义；共用日志已被本轮回归更新，当前结论以本轮 M3 记录为准。

### 2026-09-20 本轮结果：两名真实测试客户端

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

### 以下为 M0/M1 历史验收记录

以下 2026-09-19 的数字保留为历史记录；通用日志文件已由上述 2026-09-20 回归更新，当前数字和边界以上述本轮结果为准。

### 已完成

- 独立 Godot 工程、可重复运行的 demo／单元／真实进程入口；Git 仅初始化于当前目录，未提交、未推送。
- GameRegistry：Schema 校验、管理员产物白名单、模式／地图／人数校验；远程式创建参数不能指定执行路径。
- RoomManager / PortAllocator：创建、分配、启动、注册、READY、心跳、停止、核实退出、UDP 重绑定后回收。FAILED 与 cleaned 分开；未知身份或忙端口保持隔离。
- Windows ProcessLauncher：参数数组启动；校验本次 launch_id、PID、父进程、程序路径、创建时间。强制停止使用已持有的进程句柄；缓存句柄回收仅用于精确验证过的引擎构建。
- ControlTransport：4 字节大端长度 + UTF-8 JSON、拆包／粘包／部分写入、队列上限、严格 JSON、有限数与深度检查；协议从 schemas/ 读取。
- 无玩法房间实际创建 ENet UDP 服务后才发送 READY；双向控制心跳；已认证控制断开立即退出 READY 并开始清理。
- 私有配置只写当前项目 run/，ACL 限当前用户，注册后删除；命令行仅含 launch_id 与配置路径，公开快照不含凭据。
- 具体示例注册移到 host/development.gd，host/core 与共享 SDK 不引用示例场景或玩法。

### 最终真实结果

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

### G00–G09

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

### 本轮遇到并修复的失败

- 初次集成脚本 check-only 退出 1：两处 Variant 推断缺少显式类型；修复后通过。
- 单元初次完整运行 133 通过／5 失败：四处测试把 JSON 解码 float 与原始 int 字典作严格深比较；真实 Godot 探针证实标量相等而字典不等，改为明确线上接收类型，仍验证全文、结构、顺序与逐字节数据。第五项为 ACL 重复设置触发 SeSecurityPrivilege；改为只修改 DACL，连续执行两次通过。保留 logs/unit-attempt-failed.log 与对应 stderr。
- 第一次真实房间集成 130 通过／3 失败，退出 1：新 delayed_register 用例提前建立 TCP 但延迟发送认证，触发正常认证期限。改成延迟建立连接，保留认证门禁；最终 133/0。首轮记录 logs/integration-attempt-failed.log/json 保留；失败运行也完成全部子进程回收。
- 暂停前 2026-09-18 曾有沙箱 setup refresh 错误、被拒绝的权限检查，以及沙箱 WMI 权限不足导致真实启动器专项失败；这些不算通过。本次环境已无沙箱限制，未修改用户全局权限配置。
- 上轮大补丁工具调用卡住后拆成小补丁落盘；本轮补齐当时未完成的 tests/test_transport.gd。

### 实际文件变更

从初始设计包新增：

- project.godot；config/development.json。
- host/main.gd、host/main.tscn、host/development.gd；host/core/game_registry.gd、port_allocator.gd、room_manager.gd；host/platform/process_launcher.gd。
- sdk/roomkit/README.md；sdk/roomkit/shared/schema_validator.gd、protocol.gd、strict_json.gd、control_transport.gd。
- schemas/control.schema.json；examples/control_messages.example.json。
- examples/minimal/game_manifest.json、room.gd；examples/turn_based/README.md；templates/README.md。
- tests/run_unit.gd、run_integration.gd、test_transport.gd、test_registry_ports.gd、test_manager.gd、test_launcher.gd、test_launcher_real.gd；tests/fakes/fake_launcher.gd；tests/fixtures/udp_holder.gd、racing_ports.gd。
- tools/run.ps1、protect_runtime.ps1、process_identity.ps1；docs/09_m1_control.md、docs/10_environment.md。

修改已有文档：README.md、STATUS.md、docs/02_contracts.md、docs/07_versions_decisions.md。原始设计／Schema 外壳与清单来源保留。运行日志与调试探针在已忽略的 logs/，不作为运行时代码；run/ 当前只有 .gdignore。没有提交、推送、部署、花费云资源或变更用户全局 Git 配置。

### 本机启动与验证

```powershell
Set-Location 'F:\文档\GodotGame\Net\RoomKit'
# 自动创建一间房，心跳后停止并退出
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode demo
# 依次执行单元、启动器专项、房间集成及 demo
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode all
```

引擎：D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe；可用 -Godot 指定路径，但更换版本要重新验收。config/development.json 配置 UDP 28100–28131、系统分配控制 TCP 端口和超时。需要正常用户有权查询自己创建的 Windows 进程并设置本项目 run/ DACL，不需要下载其它后端。详细说明见 README.md、docs/10_environment.md。

每个模式必须同时输出成功标记和 ROOMKIT_EXIT mode=... code=0。-Mode all 是上述已验证各模式的顺序入口；本轮实际命令按表逐项运行。

### 明确未运行／限制

- 未运行专用服务器导出产物、Linux、16 人、100 轮压力、浏览器或公网。虽然已找到 4.7.2 导出模板，当前使用的是开发工程子进程。两名本机真实测试客户端已经由 2026-09-20 的 M2 验证补齐。
- M2 大厅、身份、票据和源码双端 SDK／GameAdapter 回调已实现；可分发插件与完整模板、M3 第二玩法、M4 持久化／安全／宿主重启恢复、M5 发布压测未完成。
- 无崩溃续局或宿主重启认领保证。失败进程身份不明／端口仍忙时保持隔离，不通过未经核验的 PID 强行回收。
- Windows 辅助程序目前同步执行；CIM 操作有 3 秒超时，但辅助程序整体尚无独立总超时，异常系统阻塞可能影响宿主心跳。测试入口有 240/60 秒总 watchdog；常驻生产服务仍需异步进程管理与总超时改进。
- 原生句柄回收针对精确 Windows Godot 4.7.2 Steam 源码 hash 验证；其他引擎不执行该专用回收路径，不能沿用本轮句柄结论。

本历史记录之后，M3 已按上方新记录完成本机双玩法开发工程验证；后续仍不能将这些结果当作完整游戏、公网或正式导出验收通过。
