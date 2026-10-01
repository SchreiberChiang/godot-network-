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


<a id="status-20261001"></a>
## 2026-10-01 协作整理前的 STATUS 全文

以下原文保留原时点措辞；其中多处“当前下一步”、分支和未连接状态已过时。当前结论只看根目录 STATUS。仅调整相对链接，正文和失败记录未删。

# 当前状态：通用管理服务、账号、资产与射击示例

**当前下一步：Claude 补修 L2-B1 的管道超时边界**（Codex，2026-10-01）。正常 Linux 存储链路的实机记录认可，但 B1 暂不放行进入 B2：助手/worker 仍使用阻塞读写，超时看门狗在终止失败后直接结束，调用线程可能无法到达 `HELPER_UNFINISHED` 返回处。独立故障注入：150 ms 截止，828 ms 后调用仍在读管道、子进程仍运行，安全断言失败、退出 1；测试在 Windows 用真实 Godot 子进程/管道，只替换 Linux 启动入口并注入 kill 错误，没有在 Linux 复现，未改生产代码，测试自管子进程已确认结束、记录释放。证据 `logs/l2b1-codex-review-9a80562ebb904089a307732024ed94d8/review_timeout.txt`。新规则独立重跑 55/0、unit 320/0，退出 0；Windows 常驻存储回归结果见下方追加记录。实机最终轮 16 步的唯一失败仍是 unit 292/1，保持非零汇总。修补任务见 [当前交接](../../docs/17_framework_shooter_plan.md#next-plan)。本轮只更新 STATUS/docs/17 和忽略目录内的复核驱动，没有连接 Linux、修改真实服务或提交推送。

本轮补充回归（Codex，2026-10-01）：最终工作区 Windows `run_resident_store.gd` **34/0、退出 0**，测试自建隔离目录，结束后该目录的 worker 数为 0；输出在上述复核目录的 `run_resident_store.txt`。`git diff --check` 通过。

**历史复核：L2-A → L2-B1**（Codex，2026-09-30）。L2-A 补修在已锁定 Godot 4.7.2 提交、普通非特权用户、受管进程统一经所有权模块和私有真实路径的范围内复核通过。独立 Windows Godot 规则 52/0、自写补充断言 12/0、unit 320/0，三项退出 0，证据 `logs/l2a-codex-fix-review-61c753efec2b4a32bbc7beafe54e7e37/`；补充断言只用假进程表，没有创建真实子进程。已核对 Claude 实机原始汇总：真实子程序/权限 67/0、规则 52/0，10 步中仍有 1 失败（unit 292/1，既有房间管理器限制），不称 Linux 全量通过。本轮没有连接或重跑 Linux，没有更改生产代码、真实服务数据或正式客户端，没有提交推送。Claude 下一项按 [当前交接](../../docs/17_framework_shooter_plan.md#next-plan) 接入 Linux 一次性/常驻存储，先以隔离 Godot 驱动验收；Operator/RoomManager 交接及完整房间另做 L2-B2。

以下为原补修要求与交付记录；此前“暂未放行”已由上方限定范围的复核结论更新。

**当前下一步：Claude 修补 L2-A 后再进入 L2-B**（Codex，2026-09-30）。已核对代码、Linux 原始汇总及 Godot 对应提交源码；L2-A 暂未放行，以下交付数字保留，但“唯一所有权/不误杀保证”尚不成立。独立 Windows Godot 规则测试 24/0、退出 0；补充隔离假进程断言 0/3、退出 1：结束调用返回错误却报告 EXITED，同一交接记录被两个对象接受，普通观测记录也能导入为所有权。证据：[复核输出](../../logs/l2a-codex-review-7c1f0875fd8d42cb9050fe453a813ce8/review_probe.txt)、[原规则重跑](../../logs/l2a-codex-review-7c1f0875fd8d42cb9050fe453a813ce8/existing_rules.txt)。权限检查的 `OS.execute(..., output)` 在该 Godot Unix 实现中经过 shell，不能当作安全参数向量调用。修补任务见 [当前交接](../../docs/17_framework_shooter_plan.md#next-plan)。本轮仅修改 STATUS/docs/17 和忽略目录内的复核驱动，没有启动真实子进程专项、连接 Linux、修改生产代码或真实服务数据，没有提交推送。

L2-B1 Linux Godot 存储接入（Claude，2026-10-01，未提交，待 Codex 复核）：Godot 经账号服务和资产仓储，通过所有权模块调用真实 PowerShell 存储脚本；没有启动 Operator、宿主或房间，没有解除平台限制，没有改存储脚本、协议或安全参数。详见 [docs/17 L2-B1 结果](../../docs/17_framework_shooter_plan.md#l2-b1-结果claude2026-10-01未提交待-codex-复核)。
- **新增/改动**：`host/platform/posix_helper.gd`（pwsh 路径只来自 `ROOMKIT_PWSH`，stdin 传请求、看门狗截止、输出上限、stderr 排空、无法确认结束时报 `HELPER_UNFINISHED`）、`host/platform/posix_data_root.gd`（data 内目录 700、库 600，前后各核验一次）；`bounded_helper`、`account_service`、`sqlite_repository`、`resident_store` 增加 Linux 分支，Windows 分支不变；所有权模块可选保留管道、受信表加锁。
- **新前提**：Godot 4.7.2 不忽略 SIGPIPE，宿主必须在忽略 SIGPIPE 的状态下启动，否则所有助手以 `HELPER_PIPE_UNSAFE` 拒绝（已实机验证拒绝路径）。
- **Linux 实机最终轮**（`20260930171501-208b39`）：一次性模式 48/0（注入 2/0）、常驻模式 67/0（注入 5/0）、替身 shell 助手限制 27/0、SIGPIPE 拒绝 2/0、所有权回归 55/0 与 67/0；哨兵、残留进程、权限、请求文件、FIFO/套接字、密码扫描通过。汇总 16 步失败 1 步：`run_unit` 292/1（既有限制），退出非零。
- **过程中的失败**：前三轮各有 1–2 项失败。强杀 pwsh 留下的调试管道和监听套接字是真实问题，已通过关闭 .NET 诊断和 PowerShell 监听解决；“外部杀掉空闲 worker”一条是断言过严（多线程进程退出期间会回退一次），修正断言后通过。
- **耗时**：一次性调用约 1.5–3.1 秒（登录类超过 2 秒门槛）；常驻热请求 9–77 毫秒。
- **Windows 回归**：规则 55/0、unit 320/0、真实启动器 64/0、常驻存储 34/0、账号 85/0、资产 83/0、grant 24/0、结算 74/0、删除 83/0、集成 133/0、助手 6/0、Codex 12 条 12/0。
- **未运行**：Windows 专用夹具的账号、资产、删除、结算、恢复、常驻存储专项没有在 Linux 上跑。
- **只读环境核对**：共享 Godot 与 pwsh 和原始安装包一致；主线没有加载实验扩展；主线全部运行重定向了 XDG，与实验使用的用户级 Godot 目录不共享；核对时没有实验、gdb 或编译进程。实验报告里的源码哈希和 `godot_src_patched` 内容未由主线核实。

L2-A 安全边界补修（Claude，2026-09-30，未提交，待 Codex 复核）：按上面四点补修并在笔记本新隔离快照上验收；没有进入 L2-B，没有解除房间管理器平台限制，没有改 Operator/RoomManager 调用点，没有动真实服务和数据。详见 [docs/17 L2-A 补修结果](../../docs/17_framework_shooter_plan.md#l2-a-补修结果claude2026-09-30未提交待-codex-复核)。
- **结束失败**：检查 kill 返回值并复核 `/proc`；失败时记录保持运行、管道不关、不可释放，可重试，3 次后隔离。
- **唯一所有权**：进程级一张表一把锁，每条记录一个持有者；交接只认一次性令牌（`offer`/`accept`，launcher 为 `handoff`/`import_owned`），观测记录、副本、改 launch_id、重放、双接收方都被拒；持有者消失的记录可认领、不丢失；带管道交接为显式转交。
- **权限检查**：不再启动任何外部程序，直接读写权限位；检查到 `/` 为止的全部祖先链接；root 拒绝。
- **引擎前提**：固定 4.7.2 stable `ed1daf0bf…`，不符即拒绝；模块注释列出全部轮询/回收入口。
- **通过**：Linux 实机真实子程序 67/0、假进程规则 52/0、失败注入 11/0；哨兵、残留、权限扫描、金丝雀四项通过（权限扫描为上轮误报后的首次实机重跑）。Windows：规则 52/0、改写后的 Codex 三断言 3/0、unit 320/0、真实启动器 64/0、常驻存储 34/0、集成 133/0、助手 6/0。
- **失败**：Linux `run_unit` 292/1（既有房间管理器限制），汇总 10 步失败 1 步、退出非零。
- **未验证**：真实环境下的 kill 失败（仅假进程）；另一真实引擎版本的拒绝；Codex 原探针因方法已删除无法原样运行。WSL 65/0 只是开发环路，不作证据。
- **留给 L2-B**：Operator/RoomManager 的 `record()`→`import_owned` 调用点在 Linux 上会被安全拒绝，需改用 `handoff()`、检查返回值、且不把令牌写进 `host-running.json`；`bounded_helper`/`resident_store` 在 Linux 启用前要改经所有权模块启动。
- 证据：[Linux 输出](../../logs/l2a-linux/run-20260930152015-6c116e.txt)、`logs/l2a-fix-review/`。

L2-A 进程所有权与权限保护（首次交付，已被上面的复核与补修取代其安全结论；Claude，2026-09-30，未提交）：只用测试子程序验证，没有启动 Operator、宿主或房间，没有解除房间管理器的平台限制，没有动真实服务和数据。详见 [docs/17 L2-A 结果](../../docs/17_framework_shooter_plan.md#l2-a-结果claude2026-09-30未提交待-codex-复核)。
- **新增**：`host/platform/posix_process_owner.gd`（启动、存活、退出码、强制结束、回收，房间程序、助手和 worker 共用）、`host/platform/posix_private_path.gd`（目录 700、文件 600，创建和复制后核验，保护不了就拒绝）。`process_launcher.gd` 的 Linux 分支委托给新模块，Windows 分支未改。
- **不误杀的依据**：未回收的子进程的 PID 不会被重用；运行时核验 SIGCHLD 没有被忽略或捕获；对同一子进程的全部引擎调用走同一对象和同一把锁，观察到退出后永不再发信号；强杀前核对仍是直接子进程且启动时间一致，否则隔离。不是本进程子进程的记录不接受。这是受控生命周期，不是 pidfd；它依赖“引擎不自动回收”，升级引擎时需要重新核对。
- **Linux 实机**（Godot 4.7.2 official）：真实子程序 51/0，含用真实引擎参数启动的子进程；假进程表规则 24/0；失败注入 11/0。哨兵进程前后是同一个活进程；没有残留子进程；文件描述符 9 → 9。
- **Linux 汇总 8 步里失败 2 步**：`run_unit` 292/1 是已知的房间管理器限制；另一步是检查脚本把测试自己创建的符号链接算成了权限过宽（真实目录 700、文件 600），已修正，修正后只在本机 WSL 复验过 50/0，没有在设备上重跑。
- **Windows 回归**：unit 320/0、真实启动器 64/0、常驻存储 34/0、集成 133/0、助手 6/0；规则测试 24/0。
- **留给 L2-B**：Godot 在 Linux 上经新模块调用 pwsh 存储助手、worker 重启和超时回退、房间生命周期集成和平台限制解除、启动入口。

旁路实验安排（2026-09-30）：用户拟交另一 AI 在 Linux 独立重复测试 G 扩展首次导入。方案见 [独立重复实验任务](../../docs/17_framework_shooter_plan.md#sqlite-import-lab)：最多 100 轮首次/二次/无扩展对照，预计 1–3 小时、累计 4 小时停止；目录及写入与主线隔离，Claude 实机验收时先暂停实验。Codex 本轮只写方案，没有启动 Linux 测试或配置后台任务；不改变主线继续 P/L2-A 的决定。

当前决定与复核（Codex，2026-09-30）：L2/L3 继续用 PowerShell 方案 P，G 原型保留但不接入生产。已读代码和两端证据，原型资产专项 24/0 不改变首次导入崩溃、整体评估失败的结论。本轮独立失败注入 11/0、退出 0，Shell/PowerShell 语法及 diff 检查通过；没有重跑 Linux、原型或完整服务器。G 的约 1 MB 仅为已加载扩展后的数据库工作增量，完整服务内存未测，“1 GB 能跑”不作为保证。下一项交 Claude 实现 L2-A Linux 进程所有权、退出/超时回收及私有目录保护，在隔离子程序上验收；任务见 [当前交接](../../docs/17_framework_shooter_plan.md#next-plan)。本轮只改本文与 docs/17，未提交推送。

P 补测与原生 SQLite 原型（Claude，2026-09-30，未提交，待 Codex 复核）：只用隔离的假数据，没有切换正式后端，没有动真实服务和数据。详见 [docs/17 补测与原型结果](../../docs/17_framework_shooter_plan.md#补测与原型结果claude2026-09-30未提交待-codex-复核)。
- **扩展**：godot-sqlite v4.9（MIT），SHA256 与官方公布的一致，在 Godot 4.7.2 的 Windows 和 Linux 上实际加载成功；没有接入主工程、构建和客户端。
- **原型**：只移植了资产提交规则，Windows 24/0、Linux 24/0。覆盖参数绑定和 Unicode、事务、重放与冲突、锁等待、写事务中途被强杀后重新打开、SQLite 备份恢复。数据库操作在工作线程上，主线程没有被卡住。
- **原型的问题**：带扩展第一次做编辑器导入时，Godot 在退出阶段崩溃，两个平台都能复现，第二次正常，已记为失败；扩展的 SQL 错误输出关不掉（不含参数值）。
- **对照**（Linux，三轮）：P 读取 p50 约 8 ms、提交约 17 ms，两个常驻进程同时存活时 RSS 233 + 242 MB、私有 133 + 143 MB；G 读取约 0.03 ms、提交约 3.3 ms，比空引擎多约 1 MB。G 的第一轮冷打开约 2 秒，原因没有查。
- **P 口径修正**：设备空闲时，Linux 一次性调用（不含密码）是 1.26–1.58 秒，低于 2 秒门槛；登录是 1.96–2.08 秒。上一轮的 2.1–3.1 秒是在设备有负载时单次测得的，两组数字都保留。完整服务的内存门槛要到 L3 才能测。
- **权限和测试驱动**：复制和新建的测试库都显式设为仅属主可访问，`umask 022` 下 Linux 61/0；保护不了的副本会被拒绝使用（注入验证）。汇总失败注入自测在两个平台都是 11/0。
- **路线**：Codex 复核采纳 L2/L3 继续用 P；G 保留为后续候选，实际迁移先解决首次导入崩溃、验证完整存储语义与资源收益。本轮没有切换正式后端。

当前交接（2026-09-30）：已有 UI/音效/入房/构建摘要（`c96e848`）及 Linux 安装验证、L1 存储切片（`481f69f8892e4fcf89bd253fd863bd91bb8950e1`）已实际推送到 GitHub `main`，Git push 退出 0。下一步由 Claude 按 [已授权任务](../../docs/17_framework_shooter_plan.md#next-plan) 下载 godot-sqlite 做隔离小原型并补测性能，用户已批准。只用假数据，不切换正式存储后端，不动真实服务或防火墙。本轮提交前失败注入 6/0、退出 0，PowerShell/Shell 语法与 diff 检查通过；功能复测沿用下方独立 49/0 与 Claude 证据，没有重新跑 Linux 或完整服务器。交接记录作为后续文档提交，不改变成果基准。

L1 复核（Codex，2026-09-30）：脚本兼容性范围认可，Linux 完整服务器仍未实现。本轮独立 Windows 存储专项 49/0、not_run=2、退出 0，失败注入 6/0、退出 0；证据 `logs/l1-codex-review-b57a318667eb4fcf99efd5adf6cb6125/windows-slice.txt`。Linux 和双向互开结果来自下方交付日志，本轮未连接 Linux。一次性调用超 2 秒属实；448 MB 是两个 worker 独立采样工作集相加，原定“管理服务＋宿主＋一个房间”内存门槛尚未测。下一项建议由 Claude 补测并做原生 SQLite 隔离小原型，先评估、不重写正式存储；新依赖尚未下载，任务见 [当前建议](../../docs/17_framework_shooter_plan.md#next-plan)。本轮只改本文和 docs/17，未提交推送。

L1 存储切片（Claude，2026-09-30，未提交，待 Codex 复核）：只到共用 SQLite 绑定、平台路径和编码，以及隔离验证；没有实现 Linux 的 Godot 仓储接入、进程管理或完整服务器。没有安装，没有用 sudo，没有动真实服务和数据。详见 [docs/17 L1 存储切片结果](../../docs/17_framework_shooter_plan.md#l1-存储切片结果claude2026-09-30未提交待-codex-复核)。
- **改动**：`tools/sqlite_store.ps1`、`tools/account_store.ps1`。同一份绑定在 Windows 上用 `winsqlite3.dll`，在 Linux 上用 `libsqlite3.so.0`；备份路径检查按平台分隔符；JSON 里像日期的字符串在两个平台都保持为文本；密码派生改成两个运行时都能编译的写法，算法和参数不变。
- **对照**：同一个驱动 `tests/storage_slice_portable.ps1`，Windows（PowerShell 5.1）49/0，带 Linux 库时 57/0；Linux（PowerShell 7.6.6，.NET 10，SQLite 3.45.1）58/0。覆盖管理员初始化、邀请码注册、登录、会话、错误密码，资产幂等和冲突，备份恢复，中文加空格的路径，Unicode 文本，PBKDF2 已知答案。两个平台新生成的测试库能互相打开、登录并继续写入。
- **测试驱动**：汇总退出码已修，任何失败、超时或脚本错误都返回非零；失败注入自测在两个平台都是 6/0。
- **Windows 回归**：资产 83/0、账号 85/0、快照 40/0、结算 74/0、授权 24/0、常驻 34/0、删除 83/0、备份恢复 35/0、账号恢复 30/0。
- **性能待决**：Linux 一次性调用 2.1–3.1 秒超过 2 秒门槛；两个 worker 独立测量的工作集加总约 448 MB（Windows 257 MB），不能当成独占内存或整套服务总量。原定完整服务内存门槛尚未测。常驻请求中位数 12–25 ms 达标；会话 p95 54.1 ms。下一项建议补测并评估方案 G 小原型。
- **未运行**：Linux 上经 Godot 调用存储、结算、删除、维护脚本，并发和长时间运行，进程管理，完整服务器。

安装阶段复核（Codex，2026-09-30，历史）：Windows 便携摘要驱动 11/0、not_run=0、退出 0，证据 `logs/linux-review-11dcba4d4c3a466a91b6015380006c6f/windows-digest.txt`；Linux 单元 292/1 保留为失败。当时发现的测试汇总退出码问题已在 L1 修正并通过失败注入，安装脚本尚未在 Linux 完整重跑。

Linux 依赖安装与隔离验证（Claude，2026-09-30，未提交，待 Codex 复核）：只写了笔记本的 `~/roomkit/`；没有用 sudo，没有改防火墙，没有带真实数据；密码由用户输入。详见 [docs/17 安装与隔离验证结果](../../docs/17_framework_shooter_plan.md#安装与隔离验证结果claude2026-09-30未提交待-codex-复核)，原始输出在 `logs/linux-setup/run-20260930121157-ab0563.txt`。
- **安装**：Godot `4.7.2.stable.official.ed1daf0bf`，PowerShell 7.6.6（官方当前 LTS，.NET 10）。安装包由用户在笔记本浏览器里从官方地址下载，哈希与官方值一致后才安装。源码是本地提交 `c96e848` 的归档，两端哈希一致。
- **摘要实机对照**：由 Linux 上的 `pwsh` 实际运行生产摘要脚本，11/0。合成夹具复现了基准值 `05f794ef76f0`；射击 `de37edca7f1d`、取石子 `772421bf94d2`，与 Windows 完全相同。Windows 那边的文件是 CRLF，Linux 这边是 LF。
- **纯 GDScript 测试**：射击规则 83/0、客户端反馈 7/0、音效 41/0、入房回归 16/0、托管契约 286/0，都与 Windows 一致。`run_unit` 是 292/1，失败点是房间管理器在非 Windows 平台返回 `UNSUPPORTED_PLATFORM`，属于预期的平台边界，不算通过。
- **未运行**：Linux 上的存储、进程管理、Operator、房间和跨机联机。笔记本不能直接访问 GitHub。
- **下一步**：L1 存储最小切片。新增的 `tests/content_digest_portable.ps1` 和 `tools/linux_isolated_setup.sh` 还没有提交。

当前授权（2026-09-30）：用户同意本地提交现有成果、不推送；随后由 Claude 在 Linux 笔记本 `~/roomkit/` 内安装官方 Godot、PowerShell 7 和该提交源码，执行隔离测试。SSH 保留密码、不配置免密；不用 sudo、不改防火墙、不复制真实数据库。任务见 docs/17 顶部已授权任务，本轮未连接设备或安装。此前等待安装授权/只读阶段描述保留为历史；远端代码与旧发布候选尚未同步，部署必须取此次本地提交，不能直接用旧 origin/main。

Linux 设备只读检查（Claude，2026-09-30，未提交，待 Codex 复核）：用户本人确认主机指纹并输入密码后运行了 `tools/linux_device_check.sh`，脚本跑完。没有安装、写入或复制任何东西。结果见 [docs/17 设备检查结果](../../docs/17_framework_shooter_plan.md#设备检查结果claude2026-09-30未提交待-codex-复核) 和 [环境记录](../../docs/10_environment.md#linux-测试机只读检查2026-09-30claude)，原始输出在 `logs/linux-device-check/check-20260930.txt`。
- **设备**：Linux Mint 22.3，内核 7.0，glibc 2.39，x86_64；i5-5200U 2 核 4 线程；内存 7.7 GB（可用约 5.3 GB）；磁盘可用 378 GB。
- **已有**：`libsqlite3.so.0`、libicu、libssl、git、curl、tar、python3；内核支持 pidfd，`/proc` 可读；RoomKit 默认端口都空闲。
- **缺少**：Godot 4.7.2、PowerShell 7。两者都可以装在用户目录，不需要 sudo。
- **未知**：Node、SQLite 的具体版本、ufw 规则（ufw 在运行，读规则需要 root）。
- **下一步**：先提交现有成果，让源码副本有确定的提交；用户同意后安装 Godot 和 pwsh；然后在设备上用 `pwsh` 实跑摘要，对照基准值 `05f794ef76f0`。摘要的 Linux 实机一致性仍然没有验证。

摘要复核完成（Codex，2026-09-30）：已读 PowerShell 实现、Node 独立参考及测试，独立重跑 `tests/test_content_digest.ps1` 55/0、not_run=0、退出 0，基准值 `05f794ef76f0`；证据 `logs/content-digest-73efe55342f347f8adc1c2b1f33b34b5/`。共享游戏索引未变化；未重跑完整客户端，未连接 Linux。下一步交 Claude 按 docs/17 顶部任务执行指定笔记本的只读设备检查；任务未自动发送。当前未提交成果继续保留，未提交推送。

跨平台构建身份（Claude，2026-09-30，未提交，待 Codex 复核）：只改了构建摘要 `tools/content_digest.ps1`；规则、证据和上线步骤见 [docs/17 构建身份修复结果](../../docs/17_framework_shooter_plan.md#构建身份修复结果claude2026-09-30未提交待-codex-复核)。
- **规则**：路径统一用 `/`；`.godot` 目录在两种分隔符下都排除；按序数排序；只对固定扩展名且不含 NUL 的文本把 CRLF 统一成 LF；二进制按原始字节计算。版本校验没有放宽。
- **测试**：新增 `tests/test_content_digest.ps1`，55/0，合成夹具的基准值是 `05f794ef76f0`。LF、CRLF、混合、反序得到的摘要一致；代码、Schema、配置、二进制和文件名的变化都会改变摘要；独立的 Node 参考实现结果一致。真实的射击和取石子工程转成纯 LF 或纯 CRLF 后摘要不变。`test_player_client.ps1` 28/0，错误版本仍被拒绝。
- **版本**：新规则下源码的 build_id 是 `shooter-dev-002-src-de37edca7f1d`。正在运行的服务、共享索引和用户的 PlayerClient 仍是 `675fa4d8063e`，三者互相匹配，本轮没有动。仓库副本和 Release 附件仍是 `0f559378dddc`。
- **未验证**：Linux 实机。本机的结果只是对检出形式的模拟，不能算跨平台通过；下一步要在设备上复现基准值和同一提交的摘要。`build_framework.ps1` 里的反斜杠路径留给后续平台实现。
- **用户**：重启管理服务后 build_id 会变化，需要运行 `PreparePlayerClient.cmd` 重新生成客户端；不重启的话，现有服务和客户端照常工作。

L0 复核（Codex，2026-09-30）：已检查检查脚本、构建摘要和任务记录。脚本已收窄为 PATH 与已约定工具目录，取消 HOME 广泛扫描；本机 `bash -n`、`git diff --check` 均退出 0，未连接 Linux、未运行设备测试。版本摘要除换行外还需处理路径分隔符和确定性排序，下一任务已写入 docs/17 顶部交 Claude。进程锁的安全结论仍依赖所有回收路径均受控，未验明前不判通过。未修改真实服务/数据、未安装、未提交推送。

L0 交付（Claude，2026-09-30，未提交，待 Codex 复核）：没有改功能、没有连接设备、没有安装、没有提交推送。详见 [docs/17 L0 交付](../../docs/17_framework_shooter_plan.md#l0-交付claude2026-09-30未提交待-codex-复核)。
- **可以冻结的成果**：后台 UI（A）、基础音效（B）、入房修复与诊断（C）。三组的文件归属、证据和剩余验收项已列表。本轮重跑的专项：入房回归 16/0、音效 41/0、页面 Node 44/0。
- **版本**：源码、真实服务索引和用户的 PlayerClient 都是 `shooter-dev-002-src-675fa4d8063e`。仓库副本 `clients/shooter-windows/` 和 Release 附件仍是 `0f559378dddc`；独立 ZIP 未重新构建；Release 未创建。
- **新发现**：build_id 按原始字节计算，而工作区的构建输入里 CRLF、LF 混用（56 / 16，另有 1 个混合文件）。同一提交在 Linux 上检出会得到不同的 build_id，会导致 Windows 客户端与 Linux 服务端版本不匹配。本轮没有改，需要在 L3 联调之前单独处理。
- **Linux 准备**：新增只读检查脚本 `tools/linux_device_check.sh`（尚未在设备上运行）、依赖清单、L1 的七个小任务，以及进程安全的方向和验证方式。
- **缺项**：公网外部设备的独立证据和 TUN 共存（已暂停）；客户端 `AUTH_FAILED` 还不能区分连接失败和认证失败；后台深色和窄窗口截图；设备上的一切都未知。

开发安排（2026-09-30）：下一任务为 docs/17 顶部 L0：由 Claude 收尾当前 UI/音效/入房修复的差异与证据，整理提交候选和 Linux 只读检查脚本，Codex 复核。之后依次跨平台存储最小验证、Linux 进程与运维、完整服务入口、跨设备验收。当前 main 为 bf21fe0，已有多项未提交改动；本轮仅写计划，未连接设备、未安装依赖、未运行功能测试、未提交推送，任务尚未自动发送给 Claude。

当前决定（用户，2026-09-30）：暂停 Windows 公网联机及 Clash Mi TUN 共存排查，待 Linux 服务端实现后再安排跨设备/公网验收。用户已反馈关闭 TUN 后本人和朋友均能入房，添加 Godot DIRECT 规则后开启 TUN 仍失败；这是用户真人反馈，Codex 未独立复测该对照，TUN 共存尚未解决。下方此前的排查任务和要求关闭 TUN 复测的步骤保留为历史证据，不再要求用户继续执行。后续回到 Linux 服务端最小验证方案准备；尚未批准具体依赖安装或真实数据迁移。本轮仅记录决定，未改代理、路由器、服务或数据库，未运行测试、未提交推送。

公网入房继续诊断（2026-09-30）：用户确认本机与外网朋友都失败。当前房间进程 8756 在 0.0.0.0:28400/UDP 监听且保持 READY。使用 PlayerClient 的公开证书做无账号、无票据的低频 DTLS/ENet 握手探针：127.0.0.1 和 192.168.10.100 均约 510 ms 连接成功，60.163.125.109 等待 8 秒超时；探针不完成玩家入场，不算真实对局通过。证据 `logs/room-dtls-connect-probe.log`、脚本 `logs/room_dtls_connect_probe.gd`。Find-NetRoute 显示公网目标走 Clash Mi（172.19.0.1 → 172.19.0.2），局域网目标走以太网；TUN 可能影响请求与外网回包，尚未用关闭 TUN 的对照确认根因。pktmon status 因权限不足无法读取，未抓包、未修改代理/路由器/防火墙、未重启真实服务。下一步由用户临时关闭服务器电脑的 Clash Mi TUN 后，保持房间运行，让本机与外网朋友分别重试；普通系统代理开关不等价于关闭 TUN。

公网地址本机入房复测（Codex，2026-09-30）：用户报告新版仍不能入房。本轮只读核实：当前 PlayerClient 的 build_id 为 `shooter-dev-002-src-675fa4d8063e`，公开证书与服务器一致；客户端 godot.log 两次 `CLIENT_ROOM_JOIN_FAILED code=AUTH_FAILED phase=LOBBY lobby_open=true`。真实宿主房间 `r_ff82738ed411c2f7cc2dca75bdb7f729` READY 后约 127 秒才经 DRAINING/STOPPING 正常停止；房间日志为 HOST_STOP、members=0，没有再出现此前的控制故障停机。当前 AUTH_FAILED 同时用于 ENet connection_failed 与 peer_authentication_failed，日志不能判明是否到达认证阶段。Windows 有当前 Godot 程序 TCP/UDP 放行规则，但不等于公网 UDP 可达；本机公网回环、路由器 UDP 映射及外部设备入房仍待区分。观察时大厅和房间端口均无监听，未擅自启动服务，未改功能或真实配置。已向用户询问 UDP 28400–28431 映射及外网新版客户端结果。

当前阻塞（2026-09-29）：用户报告公网地址能连大厅，但空房间创建后几秒至十几秒自行消失，入房会退回登录。Codex 只读检查真实日志 `data/framework/logs/managed-host.log`，四次均为 STARTING → READY → FAILED / CONTROL_UNAVAILABLE；尚不能区分控制通道断开、消息拒绝或房间主动超时。不能归因于公网 UDP 或版本不匹配。隔离后台设置相同 advertised_host 后空房间约 40 秒保持 READY，证据 `logs/admin-ui-79a4ef588b5746d2ad6bc544eb30501b/idle-room-probe.jsonl`，仅证明该隔离实例稳定，不证明公网联机通过。真实服务和数据未修改，隔离实例已正常停止、stderr_errors=0。诊断脚本两次 config.set 请求不符合 Schema 被拒，修正为允许的五个配置字段并带 reason 后才完成测试，前两次不算通过。优先执行 docs/17 的空房间消失诊断任务，Linux 暂停推进。

音效复核（Codex，2026-09-29）：已阅读音效生成、客户端事件、设置保存与构建改动，隔离重跑 `run_client_sound.gd` 41/0、退出 0、stderr 为空，证据 `logs/sound-review-9ace1d0e42e6406f89b74b3f4d971511.log`；`git diff --check` 通过。本轮未重跑完整客户端、未监听音频。用户转交的试玩步骤标注三步已人工验收；保留 Claude 报告中自动测试与听感未验收的区别。当前 hit 是任何玩家掉血的场景反馈，不代表本机玩家命中；即使两人对战，也可能是自己被击中（代码以低音调区分）。暂不扩展协议实现射手归属，后续若需要个人命中确认应增加专用权威伤害事件，不能只给子弹补一个射手字段就推定归属。现有 UI 与音效改动仍未提交。
登录显示修复（Codex，2026-09-29）：用户反馈输入账号密码后仍停留登录页。隔离真实后台复现：认证成功后 `authView.hidden=true`，但 `.auth{display:grid}` 覆盖隐藏行为；已添加 `[hidden]{display:none!important}`，同时修复主界面及其他隐藏面板的显示。真实浏览器验证修复前复现、修复后登录显示总览、退出返回登录页；四项 Node 测试共 44/0（含新增结构防退化检查，非浏览器替代）。证据：[隔离后台截图](../../logs/admin-ui-b26d02ce107248e0b804bc3c9133cf6e/login-fixed.png)。未修改真实账号、未操作真实服务，未重跑 Godot 全量回归或独立包。后台在启动时读取 HTML，用户需正常停止并重新启动管理服务，再刷新页面。

更新：2026-09-28。当前主线 `main`，已从旧主线快进整合到 `74f3413`（包括第一阶段文档与路线图）。本轮只同步主线说明，其他分支保留；远端同步结果以 Git 核实为准。下方各轮提交和工作区描述保留当时含义。本文件只放当前结论、未验收项、已知问题和证据位置；逐轮过程和完整验证表见 [STATUS 历史归档](../../docs/archive/status_history.md)。怎样启动见 [README](../../README.md)，模块和开发顺序一览见根目录 **`ROADMAP.html`**（双击打开）。

## 当前下一步（2026-09-29）

空房间消失 / 入房回登录（Claude，2026-09-30，未提交，待 Codex 复核）：已在隔离环境复现、找到根因并修复，详见 [docs/17 诊断与修复](../../docs/17_framework_shooter_plan.md#诊断与修复claude2026-09-30未提交待-codex-复核)。
- **根因**：入房回复的 Schema 把 `host` 锁死为 `127.0.0.1`。通告地址一旦不是回环地址，客户端就会拒绝入房回复，关闭大厅连接并回到登录页。随后大厅清理时，对刚预留的座位发出空 `attempt_id` 的 revoke，房间校验失败后主动停机，宿主记为 `FAILED/CONTROL_UNAVAILABLE`。
- **修复**：`host` 改为严格的 IPv4 字面量；刚预留、还没有 attempt 的座位只在本地释放，不再发 revoke。认证和超时都没有放宽。另外增加了宿主、房间、客户端三侧的脱敏断开原因日志。
- **验证**：修复前连续 3 次复现，修复后同样配置下真实客户端能入房、退房，房间一直保持就绪。回归：新增专项 16/0，unit 320/0，托管契约 286/0，托管停机 55/0，射击规则 83/0，音效 41/0，玩家客户端 28/0（新 build_id 为 `shooter-dev-002-src-675fa4d8063e`）。
- **未验证**：公网外部设备、真实服务重启后的日志。用户需要重启管理服务，并重新生成 PlayerClient。

Linux 完整服务端可行性调查（Claude，2026-09-29，未提交，待 Codex 复核）：只读调查加一次本机隔离内存测量；没有改功能、没有安装、没有连接笔记本。详见 [docs/17 调查结果与推荐](../../docs/17_framework_shooter_plan.md#调查结果与推荐claude2026-09-29未提交待-codex-复核)。
- **推荐**：进程身份、目录保护和指标在 Linux 上用 GDScript 直接读 `/proc` 和文件权限；存储层先用 PowerShell 7 复用现有助手（方案 P），存储语义保持一份实现。只有实测达不到门槛，才评估 GDExtension SQLite（方案 G）。两种方案都要用户同意引入。
- **发现**：Godot 4.7.2 在 Unix 上检查进程是否在运行时会回收已退出的子进程，`OS.kill` 按 PID 发 SIGKILL。Windows 的“持有句柄再结束”规则不能照搬，否则可能误杀复用了 PID 的进程。现有代码已经被 Windows 限定条件挡住，所以 Linux 上常驻存储是关闭的，超时也不会真正结束助手。
- **内存基线**（Windows，隔离环境）：只有管理服务 287 MB 工作集；游戏服务器运行时 557 MB；加一个就绪房间 548 MB。PowerShell 进程约占三分之一到一半。证据在 `logs/admin-ui-2d98e12ebc1049c48474fbc965245b48/memory/`。
- **下一步**（需用户同意）：设备只读检查 → Linux 上的 Godot headless 测试 → 方案 P 最小存储切片，含跨平台库互开和 PBKDF2 对照 → 实测 → 平台层 → 跨机闭环。

基础音效（Claude，2026-09-29，未提交，待 Codex 复核）：开枪、命中、死亡、购买成功、按钮点击五种音效，全部在客户端由代码合成，没有外部素材；音量和静音保存在 `user://`，`M` 键切换静音。实施和证据见 [docs/17 基础音效实施](../../docs/17_framework_shooter_plan.md#基础音效实施claude2026-09-29未提交待-codex-复核)。
- **事件来源**：开枪、命中、死亡都从服务器快照推导，购买只在服务器确认后播放；失败、超时和重复响应都不出声。
- **测试**：新增 `tests/run_client_sound.gd` 41/0；射击规则 83/0；反馈测试 7/0；真实渲染跑通；隔离的玩家客户端联机测试 28/0，新 build_id 为 `shooter-dev-002-src-97b98fb2f74e`。
- **已知限制**：快照不带攻击者，三人以上时“命中”也会在别人互射时响，要改需要协议改动，待决定。
- **未验收**：听感；`test_framework_clients.ps1` 未跑（它读取真实服务的共享索引）；独立包、仓库副本、Release 附件和用户的 PlayerClient 都没有重新生成，仍是旧版本。
- **用户上线**：停止游戏服务器 → `StopManagement.cmd` → `StartManagement.cmd` → 启动游戏服务器 → `PreparePlayerClient.cmd`。

用户真人验收已确认创建房间等管理操作、退出后台和重新登录正常。Codex 本轮抽查房间截图、隐藏样式和浏览器结果文件，重跑四项 Node 测试 44/0；未重跑真实浏览器或 Godot 全量测试。下一项是 docs/17 的基础音效任务，交 Claude 实施；任务已落文档，尚未自动发送。未提交推送。

后台改版收尾（Claude，2026-09-29，未提交，待 Codex 复核）：已按 [docs/19 当前任务](../../docs/19_admin_ui.md#当前任务后台改版收尾2026-09-29交-claude) 完成，结果见该节下的“收尾结果”。
- **浏览器验收**：隔离后台加独立 Edge 无头实例，28/0。覆盖首次设置、退出、错误密码、已有管理员登录（隐藏的确认密码框不阻止登录）、刷新后会话恢复、七页切换只显示当前页、在线不显示离线横幅、启停服务器、建房、邀请码注册玩家后搜索、停服务后禁用写操作。
- **截图**：登录错误、总览、房间、玩家、离线五张，在 `logs/admin-ui-df17c850fa8540fab4f8c9155df216bc/browser/`。
- **修正**：截图发现房间表操作按钮被挤成竖排，已修（只改 CSS）。
- **检查**：Node 44/0。
- Codex 的 `[hidden]` 登录修复保留，未改。
- **未验收**：深色和窄窗口截图、独立包重新导出。用户真人复测范围见本节顶部。

Codex 复核通过后进入基础音效，随后是 Linux 调查。

后台 UI 接入（Claude，2026-09-29，未提交，待 Codex 复核）：用户确认预览布局后，已把布局接入 `host/admin.html`，使用现有真实接口，演示数据和模拟控件都没有带入。服务端和协议没有改动；权限、资产操作编号、必填原因和危险操作确认都原样保留。
- **隔离实测**：新增 `tests/run_admin_ui_fixture.ps1` 启动源码版真实 Operator，在内置浏览器里走通了首次设置、启停服务器、建房、生成邀请码、注册玩家后查询、按游戏调整资产、失败提示和离线状态。
- **回归**：Node 测试 43/0，`run_admin_http.gd` 143/0。
- **测试中修正**：页面切换选择器失效（所有页面同时显示）、搜索回车过早无反应、离线时部分按钮未禁用、资产超限显示原始错误码。
- **未验收**：后台各页截图、用户真人操作、独立包重新导出。

详见 [docs/19](../../docs/19_admin_ui.md#真实后台接入claude2026-09-29未提交待-codex-复核)。

后台 UI 预览（Claude，2026-09-29，未提交，待 Codex 复核）：新增根目录 `ADMIN_PREVIEW.html`，双击打开，全部为演示数据，不连接真实服务。重点完成总览、房间、玩家三页，其余四页是标注为草图的导航页。三条常用操作从约 5 / 4 / 6 步缩短到 3 / 3 / 4 步，必要的确认和原因都保留。内置浏览器实测 31 项全部通过，另验证了真实键盘操作、760 像素宽和截图。用户本机浏览器的双击打开未验收。没有修改正式后台。步骤对照和检查结果见 [docs/19](../../docs/19_admin_ui.md#预览交付claude2026-09-29未提交待-codex-复核)。

用户同意继续后台 UI：GitHub 暂缓发布不再阻塞独立 UI 工作。当时安排 Claude 制作 `ADMIN_PREVIEW.html` 离线演示预览，用户确认预览后再接入真实后台（两步均已完成，见上两段）。随后基础音效、Linux 服务端调查，按小阶段逐项验收。此前“UI 暂不开始/发布后才进入 UI”为已被本决定替代的顺序，不是当前阻塞。此次仅更新 STATUS、docs/17、docs/19；未改功能、未运行服务或游戏测试，未提交推送。

GitHub 发布准备（Claude，2026-09-29，未提交）：Release 附件（12 个文件，tag `shooter-client-shooter-dev-002-src-0f559378dddc-4c2ef956`）与已提交的仓库副本、清单哈希全部一致；main 源码构建出的 `build_id` 与附件一致；没有秘密文件；发布说明已准备好。**用户确认暂不发布**，所以下载、直接启动和联机验收都没有执行，GitHub 获取流程仍为待验证。（当时写的“后台 UI 阶段暂不开始”已被随后用户的决定替代，UI 已开始。）详见 [docs/17](../../docs/17_framework_shooter_plan.md#暂缓任务github-获取验收)。

最新收口：用户按重启管理服务、重新生成 PlayerClient、直接双击 Client.exe 注册/登录/入房/退房的步骤试玩，反馈未发现可见问题。Codex 复核直接配置读取、内容摘要与附件生成代码；独立启动器专项 14/0、退出 0（`logs/client-launcher-883f852cbdfd43abad7f880906b10839/`）。独立隔离构建两次，两种游戏 build_id 均稳定；仓库客户端与当前源码 build_id 一致，Release 与仓库副本的 generated_files 哈希全部匹配，检查退出 0（索引在 `logs/codex-client-final-a449f131fba94438b1af26273b8b4f16/`）；git diff --check 退出 0。Claude 的 28/0 联机回归未由 Codex 重跑。用户授权本轮提交并推送 main；Release 未发布，GitHub 下载、跨设备、DTLS 原因和旧独立包仍未验收/解决。下次优先执行 docs/17 的“GitHub 获取验收”任务，不重复已完成的直接启动实现。

客户端交付收尾（Claude，基于 `main` `f91e6cc`，未提交，待 Codex 复核），详见 [docs/17](../../docs/17_framework_shooter_plan.md#客户端交付收尾实施2026-09-28)。隔离回归 `tests/test_player_client.ps1` 28/0、退出 0，证据在 `logs/player-client-90442badd27f4874bae0f6acef4eb661/`。
- **直接双击 `Client.exe`**：显式 `--connection-config` 仍然优先；没有传入时，导出版读取可执行文件同目录的 `connection.json`，源码版仍读项目内的发布文件。已测：无参数、从无关工作目录、在中文加空格的路径下启动，完成注册、登录、入房、退房；经 `explorer.exe` 模拟双击时窗口正常出现，独立探针确认游戏没有挂任何控制台。
- **构建标识与服务器绑定**：`build_framework.ps1` 用 `tools/content_digest.ps1` 对准备好的工程内容算摘要，得到 `build_id=<源码清单 id>-src-<12 位>`。服务器索引、房间清单和导出客户端都来自同一目录，所以一致；改一行客户端代码，标识就变，改动后的客户端被未改动的服务器以 BUILD_MISMATCH 拒绝。重复构建得到相同标识。没有改协议字段，也没有改独立包构建。
  - 影响：代码改动后重启 `StartManagement.cmd`，需要重新运行 `PreparePlayerClient.cmd`；之前生成的客户端（`shooter-dev-002`，没有后缀）连不上重启后的服务器。
- **GitHub 附件**：`PreparePlayerClient.cmd -RepositoryCopy` 在同一次导出中同时生成本地目录、`clients/shooter-windows/` 和 Release 附件目录 `artifacts/player-clients/release-<tag>/`（12 个文件，含 Client.exe），旁边附清单 `.json` 和 `-SHA256SUMS.txt`。
  - 当前 tag 为 `shooter-client-shooter-dev-002-src-0f559378dddc-4c2ef956`，共 109,654,328 字节。
  - Godot 导出的 `Client.pck` 不是逐字节确定的，所以 tag 对应某一次具体导出；配对靠 `build_id`。
  - Release 尚未创建；真实下载和全新目录验收都待 Release 发布后进行。
- **未变**：DTLS -30464 仍是原因不明的已知问题；旧独立包启动方式仍未修复。本轮未做 UI、音效、Linux 或文件清理。

本轮提交前核验：Codex 独立运行 `tests/test_client_launcher.ps1` 14/0、退出 0（`logs/client-launcher-2bdec546bc1c46ce9bbc57f98a52425f/`）；重新导出到隔离产物目录并同步仓库副本，退出 0，tag `shooter-client-shooter-dev-002-95c33788`，未替换用户 PlayerClient。仓库副本只提交公开客户端文件，不包含 EXE、本机连接配置或证书，Release 尚未创建，克隆后暂不能直接下载运行。此前真实联机和控制台隔离测试沿用 Claude 报告，Codex 未重跑；DTLS 未复现和旧独立包启动方式仍是限制。下次任务见 docs/17 顶部“客户端交付收尾”：直接 EXE 启动体验、构建标识方案与 GitHub 获取验收；不是开始 UI/音效/Linux。

2026-09-28 客户端位置调整与人工反馈：用户再次反馈启动游戏、入房、退房看起来正常；未确认其他用例。默认生成目录现为根目录 `PlayerClient/`（完整独立目录，进入后双击 StartGame.cmd），根 StartPlayerClient.cmd 同步指向它，PreparePlayerClient.cmd 生成后打开它。临时构建与 previous 备份仍留在 artifacts；显式 OutputRoot 的隔离测试行为保留。已重新生成根目录客户端（shooter-dev-002，tag `shooter-client-shooter-dev-002-2dc08b12`），生成退出 0，CheckClient 退出 0；入口/目录路径与 Git 忽略检查通过，git diff --check 退出 0。未重启服务、未修改真实库、未删除原 artifacts 玩家目录；未对本次新目录重新运行图形界面或联机测试。地址仍为 127.0.0.1，只适用于本机。PlayerClient 含本机连接配置，不纳入 Git；仓库分发副本 clients/shooter-windows 与 GitHub 发布另行维护，不据此声称 GitHub 已可下载。

Claude 最新退出排查交接：报告已隔离复现控制台 Ctrl+C 导致 Operator 强制退出，并修改源码启动与新客户端启动方式；报告 detached_launch 13/0、room_exit_logs 17/0、client_launcher 14/0、player_client 20/0。Codex 本轮未独立复跑或完成该改动的全面复核，这些数字按 Claude 报告记录；DTLS -30464 仍未复现、原因未确认，旧独立包启动方式尚未更新。上述客户端重新生成已带入当前 RunGame.ps1。

用户最新人工验收：使用一个账号完成注册并进入房间；未多开，未进行双人对战或跨设备验收。用户报告退房时服务器报错。Codex 只读检查发现：`artifacts/framework-6e8a5b2ccec7444ebbf9ae3f5322c529/shooter/server.log` 有 `TLS handshake error: -30464`，堆栈落在 `room_runtime.gd:123`；`data/framework/logs/operator.log`、`stderr.log` 有未等待 Thread 完成和退出资源泄漏/静态字符串错误；`managed-host.log` 记录房间正常走到 STOPPED。日志缺少逐条时间戳，未证明这些错误由退房触发，也未证明无害。未重启或修改运行服务/真实数据。下一项交 Claude：使用独立数据、端口、公开配置与构建目录，分别复现单人退房、关闭客户端、停止宿主、停止 Operator，记录时间/退出码/堆栈；确认原因后修复并跑相关回归，不能吞日志或关闭 DTLS。新客户端安全替换等 20/0 报告尚未由 Codex 完整复核。

便捷入口：新增根目录 `StartPlayerClient.cmd`，转调已生成的 `artifacts/player-clients/shooter-windows/StartGame.cmd`；缺失时提示先运行 PreparePlayerClient。只检查入口目标存在和 `git diff --check`，未实际打开游戏窗口，未重建客户端。未提交或推送。

Codex 玩家客户端复核（2026-09-28，待 Claude 修正）：已阅读生成器、启动脚本和隔离测试；三个 PowerShell 文件语法解析无错误，抽查 `logs/player-client-40f0ef066f064566b0ec33a57c562217/` 的成功/错版报告及 Operator 11/0 收尾记录。未独立重跑真实联机，也未操作当前服务器。暂不提交发布，需处理：① 生成器仅凭目标目录存在 `client-version.json` 就递归删除整个目录，且自定义 Destination 缺少范围约束；改为受控输出目录、保留旧目录并可回退，覆盖前识别用户新增文件，补失败保留与越界拒绝检查。② 测试会覆盖共享 `artifacts/client` 再恢复，不能称为与当前服务完全隔离；改用专属公开配置输出，避免中断或并发时污染正常发布文件。③ 新生成目录与旧 GitHub 候选目录仍是两套不同构建，发布前统一生成来源与版本，不能让 GitHub 下载继续指向旧客户端。上述为代码复核发现，当前用户尚未进行新版图形界面试玩或跨设备验收。

复核修正（Claude，2026-09-28，未提交，待 Codex 复核）：上述三项已处理，隔离验收 `tests/test_player_client.ps1` 20/0、退出 0，证据在 `logs/player-client-0972f570501e429aad94dfc66d8f71b3/`。① 输出只允许写入 Git 忽略的 `artifacts`、`logs` 或固定的 `clientsshooter-windows`，越界或经链接的路径直接拒绝；新版本先在同一目录下暂存，完整生成后再替换；替换前按 `client-version.json` 的 `generated_files` 逐个比对哈希，发现新增或改动的文件就停止，旧目录不动；旧目录移入 `previous` 保留，替换失败自动回退（已用注入失败验证）。② Operator 新增可选参数 `--public-client-dir`，默认仍为 `artifacts/client`；测试把公开配置发布到自己的目录，测试前后比对共享的 `artifacts/client` 与游戏索引，均未改动，不再覆盖后恢复。③ 删除基于旧 ZIP 的 `publish_shooter_client.ps1`；`PreparePlayerClient.cmd -RepositoryCopy` 用同一次导出同时生成本地目录和仓库目录 `clients/shooter-windows`（后者不含连接配置，附 FetchClient），两者 build、Client.pck 哈希和 Release tag 相同，测试已核对。仓库目录已按当前服务器重新生成，tag 为 `shooter-client-shooter-dev-002-22250f37`，旧目录保留在 `artifacts/player-clients/previous-repository/`。

玩家客户端入口（Claude，2026-09-28，未提交，待 Codex 复核）：新增根目录 `PreparePlayerClient.cmd`（`tools/prepare_player_client.ps1`）。它从 `StartManagement.cmd` 当前服务器所用的射击工程导出 `Client.exe` + `Client.pck`，附上服务器发布的公开 `connection.json` / `server.crt`，生成 `artifacts/player-clients/shooter-windows/`（约 104.6 MiB）。整个目录发给朋友后，朋友只需双击 `StartGame.cmd`。版本校验保留不变：客户端带的就是服务器自己的 build_id / compatibility_id / game_protocol。隔离验收 `tests/test_player_client.ps1` 12/0、退出 0：全新目录中两个导出客户端完成真实注册、登录、进入同一射击房间并互相可见；另一个 build_id 被改过的客户端被服务器以 BUILD_MISMATCH 拒绝。真人图形界面试玩和另一台电脑的局域网连接尚未验证。GitHub 发布另行完成（下面的 `clients/shooter-windows/` 方案）。

GitHub 获取方案（Claude，2026-09-28）：`Client.exe` 为 104.2 MiB，超过 GitHub 普通文件上限，所以不进 Git，改作 GitHub Release 的原文件附件；LFS 有计费风险，没有启用。仓库目录 `clients/shooter-windows/` 现在与本地客户端同源生成（见“复核修正”）。方案见 [docs/17](../../docs/17_framework_shooter_plan.md#独立射击客户端实施2026-09-28)。尚未创建 Release，GitHub 下载流程为待验证。

第一阶段收口：用户已基本验收路线图与文档，清理候选尚未确认；Codex 已完成脚本语法、节点/文件引用与差异范围的静态复核。本轮将第一阶段成果整理为本地提交，未推送。下一小阶段交接见 [docs/17](../../docs/17_framework_shooter_plan.md#下一阶段实施建议与验收门槛)：先核实主线整理条件，再由 Claude 主要实现独立射击客户端；任务尚未自动发送。下方“未提交/待复核”为此前交接时点，具体以 Git 状态及本段收口记录为准。

用户通过 `grilling` 确认三阶段顺序：项目分析/清晰文档/离线路线图 → 主线整理与独立射击客户端、后台 UI、基础音效 → Linux 完整服务器与后台，同时保留 Windows 一键运行。详细要求和可转交的 [Claude 第一阶段任务单](../../docs/17_framework_shooter_plan.md#claude-phase1) 已记录；主要实现、测试和整理交 Claude，Codex 负责复核。

第一阶段（Claude，2026-09-28，未提交，待 Codex 复核）已交付：`ROADMAP.html` 项目地图、[项目分析](../../docs/01_scope_architecture.md#项目分析2026-09-28)、[清理候选表](../../docs/17_framework_shooter_plan.md#清理候选表)、[下一阶段实施建议与验收门槛](../../docs/17_framework_shooter_plan.md#下一阶段实施建议与验收门槛)，以及本文件和 README 的精简。没有改功能代码、协议、数据库或启动/构建脚本；没有删除任何文件或分支；没有连接 Linux。检查结果见下方“最新有效验证范围”末行。第二阶段待用户验收第一阶段后再安排。

Codex 规划轮记录（原文保留）：规划文档检查：`git diff --check` 退出 0；PowerShell 检查新增导航锚点、交接关键路径及替换字符，退出 0。Git 提示未来检出可能转换 LF/CRLF，未修改全局配置。首次读取未显式指定 UTF-8 导致终端显示乱码，已按 UTF-8 重读，未因此改写原文。这些只算文档检查。本轮只改 README、本文件和 docs/17；开始时工作区干净，HEAD 为 `b0a707d`。新规划尚未提交、未发送给 Claude，路线图尚未制作；未运行游戏/浏览器测试、未连接 Linux、未改分支或数据。下方 09-27 的“未推送”等交接描述属于旧时点，第一阶段将按实际 Git 状态归整，不代表当前同步状态。

## 当前已实现

- **独立管理服务（Operator）**：回环 HTTP 中文后台，持有 SQLite 账号与资产库；通过认证的回环 TCP 启动、停止、重启、维护游戏宿主；宿主停止后后台继续运行。停服默认公告 60 秒；崩溃后确认旧进程退出、端口可重绑才重启，10 分钟最多 3 次。
- **账号**：邀请码注册、用户名密码登录（PBKDF2-SHA256，60 万次迭代）、单玩家会话、改昵称/密码（8–128 字符）；管理员重置、停用/恢复、踢出，并有持久审计。测试阶段可由管理员永久删除玩家账号：两库分步执行、作业记录可恢复，Operator 收尾完成才报告成功，比赛结果和审计保留匿名代号，后台列出可能仍含该账号的旧备份（提交 `96d25d1`）。账号请求与结果签名密钥经标准输入交给助手，不写临时文件。
- **永久资产**：金币、经验与等级、非堆叠所有权、按游戏分开的默认配置；独立或 shared 资产空间；购买、选择与流水同事务，幂等重试不重复扣款；成绩与奖励同事务结算。比赛临时经济与永久钱包分开。
- **存储**：PowerShell 助手 + 系统 `winsqlite3.dll`。资产读取、购买、选择和会话校验由每库一个常驻存储进程处理（客户端实测购买约 0.1 秒），失败时回退一次性助手；`ROOMKIT_STORAGE_MODE=oneshot` 可整体切回旧路径。其余操作仍走一次性助手（每次约 1.0–1.2 秒）。
- **运维**：在线备份（每 30 分钟，保留 48 份）、恢复前备份、恢复后撤销会话；进程身份核验，只回收本次创建且已核验的进程。
- **房间**：每房一个 Godot 进程；WSS 大厅 + DTLS/ENet；房间实际绑定 UDP 后才 READY；可信清单可声明通用整数 `room_rules`，宿主只校验范围。
- **横版射击示例**（`shooter-dev-002` / `shooter-v2` / `game_protocol=2`）：自由混战，三把枪，服务器权威即时命中，死亡后开背包选枪并手动复活，整局结算发奖；房间可设每局时长、获胜击杀数、复活等待。
- **取石子示例**：当前第二玩法，共用同一账号和资产服务，可购买并选用玉石主题。
- **新游戏接入**：`tools/new_game.ps1 -Managed -GameId <id>` 生成自带 SDK 0.5.0、账号客户端、独立房间、资产目录/策略和结果 Schema 的工程；宿主核心和 SDK 里没有射击或取石子的分支。
- **源码启动器**：`StartShooterClient.cmd` / `StartManagedTurns.cmd` 以可见窗口启动，窗口稳定出现才报告成功，每次启动单独保存日志。

## 当前交付物

| 交付物 | 状态 |
|---|---|
| 源码入口 `StartManagement.cmd` / `StartShooterClient.cmd` / `StartManagedTurns.cmd` / `StopManagement.cmd` | 当前推荐，包含 `b0a707d` 的全部功能 |
| 最新独立包 `artifacts/RoomKit-0.5.0-framework-windows-aa019dbc45f9461099ad5a8136b1e4a1.zip`（索引 `artifacts/framework-release.json`，SHA256 `e5d1cfb7c91975815bfda57cda85cd3e4f26d313780f7cb6ec947332ec44f48b`） | 2026-09-27 构建，含测试账号删除及收尾修正、常驻存储、8 字符密码。全新解压后 `tests/test_framework_release.ps1` 44/0、退出 0，覆盖原生启动、房间与基本联机；不含包内删除操作，新包旧路径与人工试玩未验证。旁边的解压目录含测试数据，分发只用 ZIP |
| 玩家客户端 `PreparePlayerClient.cmd` → `artifacts/player-clients/shooter-windows/`（匹配源码服务器 `shooter-dev-002`） | 2026-09-28；复核修正后隔离验收 20/0；已为当前服务器重新生成（对外地址为 127.0.0.1，只能本机使用）；真人图形界面试玩待验证 |
| GitHub 仓库目录 `clients/shooter-windows/`（`PreparePlayerClient.cmd -RepositoryCopy` 生成，tag `shooter-client-shooter-dev-002-22250f37`） | 与本地客户端同源；Git 中约 0.37 MiB（不含 Client.exe）；Release 未创建 |
| `ROADMAP.html` | 2026-09-28 新增的项目地图，双击打开，不需要后台或网络 |
| 早期无账号演示入口（仓库根 `StartPanel.cmd`、`StartPlay.cmd`、`StartTurns.cmd`、`StartDemo.cmd`、`ShowResults.cmd`）及 0.1.0 包 | 保留但不推荐，见 [早期入口](../../docs/archive/early_entrypoints.md)；已列入清理候选 |

更早的独立包（`bbc5f4dd…`、`12253e0a…`、`a5eb4e45…`、`fc3df1a4…`、`f4f40384…`）的构建来源与测试记录见 [历史归档第〇节](../../docs/archive/status_history.md)。

## 最新有效验证范围

所有结果都只在同一台 Windows 电脑上取得；计数是断言数，不是玩家数。完整命令、失败复测和证据目录见 [历史归档第〇节](../../docs/archive/status_history.md)。

| 范围 | 最新结果（日期） | 证据汇总 |
|---|---|---|
| 账号删除（两种存储模式） | `run_account_deletion.gd` 83/0；`test_account_deletion.ps1` 52/0（真实 Operator、房间、两个 WSS 客户端）（09-27） | `logs/deletion2-acceptance-summary.txt` |
| 账号 / 资产 / 结算 / 后台 HTTP / 契约 | accounts 85/0、assets 83/0、result_rewards 74/0、admin_http 143/0、managed_contracts 286/0、account_recovery 30/0、asset_audit 14/0（09-27） | 同上 |
| 存储 | resident_store 34/0、asset_snapshot 40/0、grant_storage 24/0；客户端实测购买中位 97 ms（旧路径 3730 ms）（09-27） | 同上；`logs/resident-acceptance-summary.txt` |
| 运维与生命周期 | operator_maintenance 35/0、`test_operator.ps1 -Lifecycle` 29/0（09-27） | `logs/deletion2-acceptance-summary.txt` |
| 真实多进程联机 | `test_framework_clients.ps1 -Visual` 47/0（两种玩法、300 秒射击局结算）（09-27）；容量 174/0（16 人满房，09-27） | 同上；`logs/resident-acceptance-summary.txt` |
| 其他专项 | room_rules 18/0、managed_template 74/0、asset_response_loss 25/0、unit 320/0、shooter 83/0、managed_registry 77/0（09-26/09-27） | 历史归档第〇节 |
| 后台页面函数（Node 替身，不是浏览器验收） | 12/0、12/0、10/0、9/0（09-27） | `logs/deletion2-acceptance-summary.txt` |
| 独立包 | 全新解压 44/0（09-27） | `logs/deletion2-review-final-package-test.txt` |
| 人工 | 用户从源码试玩射击、买枪切枪“确实很快”、删除账号正常（09-27，无操作记录）；09-22 有完整人工浏览器与原生客户端记录 | 历史归档 |
| 第一阶段文档与地图（09-28） | 见文末“第一阶段检查” | — |

## 未运行 / 未验收

- 第二台实体设备的局域网联机、Linux 完整宿主（测试机已登记未连接）、公网与公网 WSS、长期满载压测、24 小时备份保留周期。
- 常驻存储进程数小时以上的耐久与内存观察；房间内（死亡背包）购买和复活前资产刷新的单独计时。
- 独立射击客户端：GitHub Release 实际上传和下载（`FetchClient.cmd` 在 Release 不存在时下载失败，并清理了残留文件）、另一台电脑上的真人登录与入房、新包发布后重新生成客户端目录的流程。
- 最新独立包（`aa019dbc…`）的人工浏览器操作、原生客户端试玩、包内删除端到端，以及新包的旧存储路径。
- 新后台表单（房间规则、8 字符密码、删除对话框）的真实浏览器点击；托管模板的图形界面；真人操作手感。
- 账号删除：删除时房间正在进行、之后才提交结果的完整真实对局；outbox 中已有待处理/已拒绝结果文件时的残留报告；大量账号或大审计文件下的耗时；磁盘满等真实系统级写入失败（测试用只读属性模拟）。
- `tools/run.ps1 -Mode all` 中与近期改动无关的模式、`test_managed_shutdown.ps1`、`test_operator_schedules.ps1` 未在 09-27 重跑。
- 断电、磁盘满、真实网络丢包/延迟、证书轮换、外部身份服务。

## 已知问题与限制

1. **仅限 Windows**：账号、资产、结果存储和进程身份核验依赖 PowerShell 助手与 `winsqlite3.dll`，Linux 上返回 `UNSUPPORTED_STORAGE`。替换边界见 [项目分析](../../docs/01_scope_architecture.md#项目分析2026-09-28)。
2. **仍有慢操作**：注册、登录（另有约 1.9 秒 PBKDF2，有意保留）、登出、结算、grant、邀请码和后台写操作仍走一次性助手，每次往返约 1.0–1.2 秒。常驻进程每个约 0.1 GB 内存，空闲 5 分钟退出，重启约 0.6 秒。
3. **客户端测试驱动偶发失败**：`test_framework_clients.ps1`、`test_framework_capacity.ps1` 写命令文件偶发 `Access is denied`，开火循环偶尔 35 秒内打不死对手；原样重跑都通过，驱动未改。
4. **临时请求文件的剩余范围**：资产、结果和维护请求仍用私有目录下的短期请求文件（不含口令、token 或签名密钥）。用户真实数据目录 `data/framework/` 下有 09-26 残留的 `account-request-*.json`（104 字节）和两个 `helper-*.json`，未读取、未删除。
5. **射击网络模型只按局域网设计**：每秒 20 次完整状态，只有显示平滑，没有客户端预测和命中回溯；公网手感未评估。
6. **容量与耐久**：16 人满房只持续 17.5 秒；托管宿主没有长期测试。
7. **原因未查明的现象**：09-22 一个可视化夹具中途消失；一次管理员意外退出登录，根因未确认。
8. **预期诊断输出**：`Exponent too high`、`mbedtls -0x6c00`、load 模式多一行 `SECURE_RESULT`，都不是失败。
9. `tools/run.ps1 -Mode all` 只含早期基础回归，遇到第一项失败即停；账号、管理、射击和托管专项需按 [docs/22](../../docs/22_framework_operations.md#测试入口) 单独运行。
10. **结果授权没有回收**：每开一间房新增一条授权且从不删除，同一资产库累计开到第 257 间房时建房失败（256 是累计上限，不是并发人数）。回收策略与迟到结算窗口仍是规划。
11. **同一解压目录重复跑包测试不稳定**：曾两次 6/1，全新解压则 44/0；验包时用干净解压副本。
12. **后台离线提示引用旧入口**：`host/admin.html` 断线提示仍让用户运行 `StartPanel.cmd`（在源码里那是早期面板，当前入口是 `StartManagement.cmd`）；留到第二阶段 UI 修复。

## 工作区与交接

- `b0a707d` 及之前的提交已推送到 `origin/codex/shooter-framework`（09-27 各轮记录里的“未推送”指当时）。`main` 停在 `5f7b7aa`，`codex/m4-results` 停在 `1a8bec5`；主线整理放在第二阶段。
- 当前未提交：Codex 规划轮修改的 README、本文件、docs/17；Claude 第一阶段修改的 README、本文件、docs/01、docs/17、docs/22（仅锚点）、docs/archive/README.md、docs/archive/status_history.md，新增 `ROADMAP.html`、`docs/assets/roadmap/roadmap-data.js`。
- 环境：Windows 10.0.26200；Godot `4.7.2.stable.steam.ed1daf0bf`；Git `2.55.0.windows.3`；`winsqlite3.dll` 3.51.1。Linux 笔记本 SSH 目标记录于 [docs/10](../../docs/10_environment.md)，未连接。

## 第一阶段检查（2026-09-28）

用户人工反馈：除“筛选清理候选并决定删除哪些”之外，其余建议步骤基本已验收，包括本机双击路线图、开发顺序视图、资产搜索与详情、查看 STATUS。未报告问题；浏览器版本和逐项操作记录未提供，不扩展为所有浏览器或所有交互逐项通过。清理候选尚未确认，不授权删除文件或分支。

Codex 独立静态复核：改动范围为文档与路线图页面/数据，未见功能源码或启动脚本改动；Node 检查页面脚本语法、39 个节点的唯一 ID 与分类引用、127 个文件路径，退出 0（未复查这些路径的标题锚点）；`git diff --check` 退出 0。未独立运行浏览器、Godot 或复跑 Claude 的全部链接/历史迁移检查。以下表格为 Claude 的检查记录，用户补验单独列明。

只做文档与静态页面检查，没有跑 Godot 回归（本阶段未改功能代码）。

| 检查 | 结果 |
|---|---|
| 相对链接与锚点：全部受版本控制的 Markdown、`ROADMAP.html` 与 `docs/assets/roadmap/roadmap-data.js`，共 523 处（接受标题锚点和 `<a id>`） | 0 失效，退出 0 |
| 路线图数据：39 个条目的模块/阶段/状态引用、重复 ID、引用路径是否存在 | 0 问题 |
| 历史迁移：整理前 STATUS 第 11–343 行共 251 行非空原文逐行在归档中找到；归档原有内容无丢失 | 0 缺失 |
| `git diff --check` | 退出 0 |
| 浏览器交互（内置浏览器，经本机临时静态服务器 `http://127.0.0.1:28999/`） | 两种视图切换、搜索、状态筛选、模块筛选、键盘展开/收起、复制路径、清空按钮、`/` 与 `Esc` 快捷键、无结果提示与重置、深浅色、375 px 窄屏无横向滚动、控制台无错误，均通过；截图确认文字可读、无遮挡。发现并修正两处：长搜索词与 `/` 提示重叠；窄屏下吸顶工具栏过高 |
| 真实浏览器 `file://` 双击打开 | Claude 未运行：内置浏览器以静态快照打开、Chrome 扩展未连接。随后用户反馈除清理候选步骤之外，其余步骤基本已验收，补充本机双击使用反馈；不是 Claude/Codex 的自动浏览器测试 |

<a id="status-20261001-l3"></a>
## 2026-10-01 L3 阶段交付前的 STATUS 全文

2026-10-01 Linux L2 收尾与 L3 同机验收交付时从 `STATUS.md` 第 3 行起逐字迁出；只降一级标题并把相对链接改为从本目录出发。各段“当前”“下一步”指写入时。

### 当前安排（Codex，2026-10-01）

Linux Operator 第一切片的代码与原始验收证据复核通过；未独立重跑 Linux。下一轮由 Claude 连续完成 L2 收尾及 L3 同机闭环：恢复/资源限制→正式启动与真实宿主→账号资产维护→60分钟有限耐久和 Windows 回归，阶段结束集中交付，不逐小项等待用户。完整交接、停点和验收范围见 [连续任务单](../17_framework_shooter_plan.md#linux-batch-current)。跨机/公网不在本轮；实验继续暂停，真实数据和旧标记保留，不提交推送。下方各轮暂停/待复核属于历史，当前安排以本段为准。

### Claude：Linux Operator 第一切片验收（2026-10-01，未提交，待 Codex 复核）

- **Linux 实机第二轮** `20260930232030-ec349a`（全新源码和运行目录）：**22 步全部通过，退出码 0**。
  - 纯校验（含真实符号链接）25/0。
  - 8 种非法参数全部以退出 64 被拒，没有创建任何东西，也没有端口监听。
  - 隔离 Operator 19/0，注入 6/0：私有目录和权限、宿主启停、程序不存在、启动超时、停止重试、交接失败、控制断开后宿主自行退出；真实托管宿主明确报 `RECOVERY_UNSUPPORTED`，没有绕过。
  - 残留检查：进程、28391/28300/28301 端口监听、权限、启动配置和宿主标记、`data/framework` 与 `artifacts/client`，全部通过。
  - `run_unit` 318/0。
- **第一轮** `20260930230000-20f6ae`：22 步中 2 步失败，已保留记录。
  - 测试写的游戏索引是 644，已修。
  - 宿主没真正启动时，带 RPC 令牌的启动配置留在 `run/`：这是 Operator 在两个平台都有的缺陷，已修。
- **Windows 回归**：Operator 日程调度 52/0、投影 9/0、鉴权错误 6/0；unit 320/0、真实启动器 64/0、集成 133/0、托管关停 55/0、日志专项 14/0、替身引擎拒绝测试 41/0。真实数据和旧 `operator.json` 没有变化。
- **未运行**：Linux 上经 Operator 做备份、恢复、结算、删除；完整托管宿主（大厅和房间）；跨机连接；真实 Operator 进程被外部杀掉。
- 详见 [docs/17 Linux Operator 第一切片结果](../17_framework_shooter_plan.md#linux-operator-第一切片结果claude2026-10-01未提交待-codex-复核)。

### 2026-10-01 误启动真实 Operator：暂停验收并保留现场

Claude 报告语法检查误将 host/operator.gd 无参数运行，05:45:34–05:45:51 启动真实 Operator（PID 49928），随后强制结束。Codex 只读核查：PID 不在、无 Godot 进程、28291 无监听；accounts.sqlite/assets.sqlite 的修改时间分别为 05:45:40/05:45:48，operator.json 为 05:45:51 且仍指向 49928；公开 connection.json/server.crt 为 05:45:49。发布证书与当前服务证书 SHA256 一致，不代表已核对启动前副本。

原始输出在 logs/l2b3-review/check-operator.stdout（包含 OPERATOR_READY，无 OPERATOR_DELETION 事件），对应 stderr 为 0 字节。operator-audit.jsonl、maintenance-audit.jsonl、account-deletions.jsonl 在事件之后均无新增记录，最近记录分别为 09-30 18:53:35、09-30 18:53:34、09-27 23:26:22。未发现完成续删的日志证据，但不能据此排除数据库内部部分写入；未打开数据库，未核对数据库删除作业表，缺少启动前副本，数据差异未知。SQLite 崩溃恢复不等于撤销已提交写入。

本轮未删除标记、未恢复数据库、未启动任何服务、未连接 Linux。先保留现场；后续由 Claude 对离线副本检查删除作业/完整性（副本需私有权限，禁止输出身份和凭据），补齐语法检查及隔离验收的防误启动措施后，再恢复 Linux Operator 验收。未提交推送。

**Claude 事件收尾（2026-10-01，未提交，待 Codex 复核）**：原数据库和 `operator.json` 保持原样，没有恢复或删除。
- **离线副本**：`data/incident-20261001-copy-48daf417eb6e/`，只有当前用户可访问；两个库的哈希与原文件一致。
- **汇总结果**（`logs/incident-20261001/inspect-summary.txt`，只有计数和固定名称）：
  - 两个库 `integrity_check` 和 `quick_check` 都是 ok。
  - 删除作业 2 条，都已完成并关闭，**没有未完成项**。
  - 事件窗口内没有新建的审计、账号、会话、邀请、删除记录，各表最新时间都早于事件。
  - 无法确认的：启动时是否删过已过期的会话（被删的行不留痕迹）；公开 `connection.json`/`server.crt` 重写前的内容。
- **防误启动**：
  - `tools/check_scripts.ps1` 只用 `--check-only` 做语法检查，已验证不会执行脚本；检查服务入口后，真实数据的文件和哈希都没变。
  - `tools/run_isolated_test.ps1` 只运行测试脚本；Operator 或托管宿主类测试必须显式给出隔离的数据目录、非 28291 的面板端口、非 `artifacts/client` 的公开目录，否则拒绝（退出 64），已逐项验证。
  - `tests/run_posix_operator.gd` 自身也检查这些参数。
- 详见 [docs/17 事件收尾](../17_framework_shooter_plan.md#incident-20261001)。Linux Operator 验收仍暂停，等 Codex 复核。

**Claude 防误启动边界补强（2026-10-01，未提交，待 Codex 复核）**：
- `tools/run_isolated_test.ps1` 先规范化路径再检查：拒绝 `..` 段、符号链接和目录联接；只放行 `tests/` 下的脚本。
- 服务识别顺着 `extends`（引号路径、相对路径、`class_name`）和 `preload`/`load` 一直找到底，无法识别的基类直接拒绝。
- 每次运行必须用一个新建在 `data/` 内的隔离目录。服务类测试的数据目录、游戏索引、公开目录、日志和运行日志都必须在其中，面板端口必须显式给出且不是 28291。
- `tests/run_posix_operator.gd` 的自检也同步改了。
- 替身引擎拒绝测试 `tests/test_isolated_runner.ps1` **30/0**，每项都核对了拒绝原因，全程没有启动真实引擎或服务入口。测试前后真实数据和 `host/` 文件的哈希都没变。
- 原数据库和 `operator.json` 继续保持原样。

**Claude 防误启动第二轮补强（2026-10-01，未提交，待 Codex 复核）**：
- **重复参数**：同名参数一律拒绝，所以“共享索引 + 隔离索引”这种写法无法通过。
- **按参数名检查路径**：四个路径参数按名字检查，空值、相对路径、只有文件名都拒绝；调用方不能自带 `--isolation`。
- **Linux 完整路径**：检查每个路径参数的完整目标路径有没有经过符号链接。写游戏索引前还要确认没有链接、目标不存在、上级目录存在，而且只写校验过的那个路径（规则在 `tests/support/operator_isolation.gd`）。
- **测试结果**：替身引擎拒绝测试 **38/0**；纯校验测试 Windows 20/0（链接用例未运行），本机 WSL 25/0（含真实符号链接）。全程没有启动服务，真实数据和 `host/` 文件的哈希都没变。


**最新复核（2026-10-01）：Windows 恢复补修通过，可继续 Linux Operator 隔离适配。** 捕获身份时只有助手超时/失败才允许一次只读重试，真正身份不符仍拒绝；总等待可能增加。基线与修复前高压核验均 24/30、修复后两轮 30/30（Claude 原始输出已核对）；Codex 独立 run_recovery 24/0、进程退出 0，证据 logs/recovery-codex-review/。早先无诊断的失败仅推测同因，不宣称已直接证明。

### 当前下一步

1. Claude 按 docs/17 当前交接实现 Linux Operator 私有目录、启动配置和宿主启停，先隔离回环测试。
2. 进程日志恢复与资源限制仍需补齐，不能跳过后宣称完整后台已支持；随后才安排跨机联机。
3. 实验继续暂停。本轮恢复修复及复核文档尚未提交推送，未连接 Linux、未修改真实数据。

以下为修补前失败证据，保留历史，不再视为未调查：

本轮独立证据：logs/l2b2-codex-final/unit.txt 为 UNIT_RESULT 320/0、进程退出 0；recovery.txt / recovery-errors.txt 为 SECURE_RESULT 5/4，外层 verified recovery host old 失败，后续 READY/端口/退出断言失败。恢复进程已结束，但当前轮未成功取得其数值退出码，不将工具外层退出 0 当作测试通过；随后通过 Win32_Process 核对没有 Godot 进程残留，未执行批量清理。Claude 5 次不稳定记录继续保留在 logs/l2b2-review/；没有基线对照，原因未明。

分工、证据等级、设备使用顺序及可转交消息集中在 [协作总览](../17_framework_shooter_plan.md#coordination-current)。用户不用自行判断两个 AI 的测试是否等价。

### 三条工作线

| 工作线 | 负责人 | 当前事实 | 下一动作 |
|---|---|---|---|
| P：PowerShell 正式存储及 Linux 接入 | Claude 实现，Codex 复核 | L1 脚本互开已验证；L2-A 有限定范围的通过记录；B1 正常链路及补修证据已复核 | 保留官方引擎，进入隔离房间生命周期 |
| B1 独立复验 | Codex | 已实机完成：16 步中仅既有 unit 限制失败，SSH/测试退出 1；正常两种存储模式通过 | 旧快照复验与最新补修复核分开记录，缺陷已收口 |
| G：原生 SQLite 导入崩溃实验 | 另一 AI | 最新转述称已准备判空补丁，未安装/编译；源码哈希、补丁和当前进程未由 Codex 实机核对 | 等主线释放设备；先复核原始证据，再讨论编译与对照 |

### 最新有效验证范围

| 证据 | 已知结果 | 不能据此推定 |
|---|---|---|
| Claude Linux B1 最终轮，Codex 已读本地原始输出 | 一次性 48/0（注入 2/0），常驻 67/0（注入 5/0），替身 shell 27/0，SIGPIPE 拒绝 2/0，所有权 55/0、真实子程序 67/0；16 步失败 1 步 | 不是 Codex 独立 Linux 重跑，不是完整服务器通过 |
| 同轮 Linux unit | 292/1，房间管理器的平台限制；汇总保持非零 | 不能删除这项失败来声称全绿 |
| Codex 超时故障注入 | Windows 真实子进程/管道，仅替换 Linux 启动入口并注入终止失败；150 ms 截止后 828 ms 仍 pending，断言失败；随后确认清理 | 未在 Linux 实机复现，不是自然发生的 kill 失败 |
| Codex Windows 回归 | 规则 55/0、unit 320/0、常驻存储 34/0 | 不证明 Linux 超时缺陷修好 |
| Codex 独立 Linux 复验（10-01） | 一次性 48/0 + 注入 2/0，常驻 67/0 + 注入 5/0，助手 27/0，SIGPIPE 拒绝 2/0，所有权 55/0、67/0；unit 292/1；16 步失败 1 步 | 原源码包重跑，非新增测试设计；不证明 kill 失败边界已修好 |
| Claude B1 超时补修（10-01，未提交，待 Codex 复核） | Linux 改为非阻塞管道和调用线程内的有界循环，不再依赖 kill 成功；停不掉时返回 `HELPER_UNFINISHED`、记录和管道保留并登记待回收（上限 4 个，满后 `HELPER_BACKLOG_FULL`）；常驻 worker 阻塞时不启第二个。Linux 实机 `20260930182509-d7d0cd`：替身 shell 27/0 + 注入 14/0（挂起、400 KiB 不读、错误输出不关，均约 0.5 秒返回），一次性 48/0 + 注入 2/0，常驻 67/0 + 注入 5/0，所有权 55/0、67/0，SIGPIPE 拒绝 2/0，收尾检查通过；unit 292/1，16 步失败 1 步。Codex 截止注入改接新代码后在 Windows 通过。Windows 回归 unit 320/0、常驻存储 34/0、账号 85/0、资产 83/0、集成 133/0 等 | kill 失败只是注入，不是自然实机失败；完整后台、房间、联机，以及 Linux 上的删除、结算、恢复都未测 |
| Claude 绝对截止与原子预算补修（10-01，未提交，待 Codex 复核） | 每轮循环和标准错误排空都检查截止时间，迟到的回复不接受；启动前在锁内预留名额，进行中加待回收合计不超过 8，满额时不启动进程。Linux 实机 `20260930185629-ebc89a`：替身 shell 35/0 + 注入 17/0（12 个并发：峰值 8 个子进程、4 个被拒；停不掉时 8 个待回收，全部在约 0.85 秒内返回），一次性 48/0 + 注入 2/0，常驻 67/0 + 注入 5/0，收尾检查通过；unit 292/1，16 步失败 1 步。Windows 替身管道探针：新代码 3/0，旧代码 0/3；回归 unit 320/0、常驻存储 34/0、账号 85/0、资产 83/0 等 | 真实管道的持续输出测试区分不了新旧代码（旧代码也能过）；kill 失败只是注入；完整后台、房间、联机未测 |
| Claude L2-B2 第一小项：Linux 房间生命周期（10-01，未提交，待 Codex 复核） | RoomManager 在 Linux 上接通创建、启动、注册、UDP 实际绑定后 READY、心跳、停止、确认退出、端口回收；运行目录 700、启动文件 600；工作线程启动改用一次性交接，失败时认领并停掉房间，认领不了就保留房间和端口；停不掉时重试且不释放资源；Operator 托管宿主改用交接凭据。Linux 实机 `20260930193037-54ca61`：13 步全部通过、退出 0；集成 133/0（22 个真实子进程），房间专项 22/0 + 注入 5/0，所有权 55/0、67/0，UDP、进程、启动文件无残留，**`run_unit` 318/0**（房间管理器平台限制已解除）。Windows：unit 320/0、集成 133/0、真实启动器 64/0、limits 8/0、托管关停 55/0 | Windows `run_recovery` 不稳定（5 次中 2 次在外层启动恢复宿主一步失败，未与基线对照、未归因）；Linux 上的进程日志和单房间内存上限明确拒绝；Operator、托管宿主、大厅、结算、跨机联机都没在 Linux 上跑 |
| Claude Windows 恢复回归调查（10-01，基于 `9d82d20`，未提交，待 Codex 复核） | 两个隔离副本（b9aa587 / 9d82d20）加完全相同的诊断补丁交替对照：正常负载 22/22 对 22/22，大数据目录 8/8 对 8/8；主仓库 12/12。定位：Windows 启动后的身份核验是两级 PowerShell，外层截止 10 s，高负载下会超时，被判为 `PROCESS_IDENTITY_UNVERIFIED`；压测中基线 24/30、修复前 24/30、修复后 30/30 和 30/30。修复：保留 `HELPER_TIMEOUT`，助手级失败时只读重试一次核验，带回脱敏诊断，没有延长超时。修复后回归：unit 320/0、真实启动器 64/0、集成 133/0、limits 8/0、`run_recovery` 24/0、常驻存储 34/0、账号 85/0 | 正常运行中的原始失败没有直接抓到诊断，归因依据的是压测复现和基线对照；持续极端负载下两次核验都超时仍会失败（不杀进程）；Linux 未跑 |

证据：

- [Claude 最终 Linux 输出](../../logs/l2b1-linux/run-20260930171501-208b39.txt)。
- [Claude 超时补修 Linux 输出](../../logs/l2b1-linux/run-20260930182509-d7d0cd.txt)、Windows 回归与截止注入在 `logs/l2b1-fix-review/`；说明见 [docs/17 管道超时补修结果](../17_framework_shooter_plan.md#管道超时补修结果claude2026-10-01未提交待-codex-复核)。
- [Claude 绝对截止与预算补修 Linux 输出](../../logs/l2b1-linux/run-20260930185629-ebc89a.txt)；新旧对照和 Windows 回归在 `logs/l2b1-budget-review/`；说明见 [docs/17 绝对截止与原子预算补修结果](../17_framework_shooter_plan.md#绝对截止与原子预算补修结果claude2026-10-01未提交待-codex-复核)。
- 恢复回归调查：`logs/recovery-bisect/`（基线/当前隔离副本、各次原始输出与退出码、核验压测、修复后回归）；说明见 [docs/17 恢复回归调查结果](../17_framework_shooter_plan.md#恢复回归调查结果claude2026-10-01未提交待-codex-复核)。
- [Claude L2-B2 房间生命周期 Linux 输出](../../logs/l2b2-linux/run-20260930193037-54ca61.txt)；Windows 回归与 `run_recovery` 各次输出在 `logs/l2b2-review/`；说明见 [docs/17 L2-B2 第一小项结果](../17_framework_shooter_plan.md#l2-b2-第一小项结果linux-房间生命周期claude2026-10-01未提交待-codex-复核)。
- [Codex 超时失败](../../logs/l2b1-codex-review-9a80562ebb904089a307732024ed94d8/review_timeout.txt)、[Windows 常驻回归](../../logs/l2b1-codex-review-9a80562ebb904089a307732024ed94d8/run_resident_store.txt)。
- [Codex 独立 Linux 输出](../../logs/codex-l2b1-7f1a0ba8/verification-retry-02.txt)、[汇总](../../logs/codex-l2b1-7f1a0ba8/independent-result.txt)。成功启动入口为 RetryVerification.cmd；原源码包未改，仅收窄外层环境扫描。该运行号已使用，不重复双击。

这些 logs 是本机证据，不随 Git 分发；完整历史与旧证据索引见 [归档](../archive/status_history.md#status-20261001)。

前次整理的文档检查：5 份文档的 128 个本地链接路径均存在，4 个新/保留的入口锚点存在，旧 STATUS 除相对链接调整外完整归档；git diff --check 通过。未逐项重验全部历史标题锚点；当时没有运行功能测试，后续实机复验见上表。

独立复验启动尝试（2026-10-01）：用户已暂停实验并在交互终端输入密码，但 SSH 返回 255，verification.txt 为空，未收到远端测试结果；具体错误只显示在原终端，待取得后再判断，不能归因为密码错误。随后只读连接探测确认 SSH 可达且主机指纹匹配；不代表认证成功。该次没有有效结果；用户再次输入密码后 retry-02 已完成复验，结果见上表。

### 当前已实现

Windows 上已具备管理后台、邀请码账号、按游戏隔离的永久资产、房间生命周期、结算、备份恢复及测试账号删除；示例为射击与取石子。已加入独立客户端直接启动、内容摘要配对、新后台与基础音效。用户已反馈后台登录/建房、独立客户端入退房、基础音效等试玩正常；这些反馈不扩展为完整跨设备验收。

Linux 已安装官方 Godot 与 PowerShell，完成构建摘要、存储脚本、进程/权限和部分 Godot 存储接入验证。完整 Operator、房间、跨机闭环仍未完成。

### 当前交付物

| 入口或产物 | 用法与限制 |
|---|---|
| StartManagement.cmd / StopManagement.cmd | Windows 源码后台启动/停止；当前推荐 |
| PreparePlayerClient.cmd → PlayerClient/ | 生成完整玩家目录，直接双击 Client.exe；源码更新后需重新生成并与服务配对 |
| StartPlayerClient.cmd / StartShooterClient.cmd | 已生成客户端入口 / 源码客户端入口 |
| clients/shooter-windows/、旧 Release 附件、独立 ZIP | 未随 Linux 工作重新生成；旧版本和证据见归档，不作为最新源码交付。Release 仍暂缓 |
| ROADMAP.html | 离线项目地图；当前执行状态以本文及 docs/17 顶部为准 |

### 未运行 / 未验收

- Linux 完整后台、房间、跨机联机；Linux 删除/结算/恢复专项；Codex 对最新补修的独立 Linux 实机重跑（Claude 已跑）。
- G 实验修补引擎的编译、首次导入对照和完整业务验证；实验目录与当前运行状态的独立核对。
- 公网外部设备验收、TUN 共存、长期负载与耐久、最新交付包重建、GitHub 实际获取。
- 历史专项未运行范围不因本轮整理消失，详见归档。

### 已知问题与限制

- B1 截止/预算缺陷已收口；8 为在途与待回收合计上限，4 为阻止新启动的阈值，常驻 worker 每库单独管理。并非保证任意操作严格在零误差的毫秒截止内结束。
- Linux 运行前须满足 SIGPIPE 启动防护、锁定引擎提交与私有路径规则；Windows 启动方法不能原样照搬。
- 一次性存储调用仍慢，常驻热请求快；当前测量不保证未来小云服务器性能。实验与主线可能有时间重叠，耗时需要空闲时重测。
- G 原型首次导入崩溃尚未修复验收；不能用第二次成功或候选补丁替代首次通过。
- 历史客户端测试有写命令文件 Access is denied 等偶发失败；未因本轮整理修复。

### 工作区与交接

本地 main / HEAD 为 b9aa587e5a5d9051360f6550c1f6ed8aec2db65d（本轮核实）；远端本轮未 fetch，不能据此声称同步。L2-A/B1、G 原型和驱动等仍未提交，主要由 Claude 维护；Codex 本轮整理文档，生产代码未改。没有提交推送。

Linux 地址、工具路径与隔离区域见 [环境现状](../10_environment.md#linux-current)。同一工作区单方写入；同一笔记本只运行一条验收或编译任务。主线不读实验目录；若需实验核对，应另列只读范围，不隐含在主线扫描里。

### 第一阶段检查（2026-09-28）

文档与路线图的历史自动检查、用户反馈和清理候选未验收范围已完整迁入 [历史归档](../archive/status_history.md#status-20261001)。

本轮 Codex 补充验收：真实启动器 test_launcher_real.gd 64/0、退出 0，句柄数 318 → 318；输出 logs/recovery-codex-review/launcher-corrected.txt。首条命令误写为不存在的 run_launcher_real.gd，退出 1；纠正入口后才执行专项，错误输出保留，不计产品失败。本轮未独立重跑高压矩阵或 Linux。

#### Codex 事件收尾复核（2026-10-01）：防护仍需补修

已阅读 logs/incident-20261001/inspect-summary.txt 和检查脚本：Claude 的副本检查报告两库完整性 ok、2 条删除作业均 done/closed、无未完成项。此为证据复核，Codex 未重新打开数据库；不能证明已过期会话未被清理，也没有启动前数据差异证据。

防误启动暂不通过：tools/run_isolated_test.ps1 在规范化前按字符串前缀允许 tests/，且仅用单层 extends 正则识别服务。Codex 将 Script 设为 tests/../host/operator.gd、Godot 设为不存在的 Z:\ROOMKIT_NONEXISTENT_ENGINE.exe，实际到达第 53 行 Start-Process 而非拒绝（退出 1，找不到引擎）；没有启动 Godot。需先规范化路径、拒绝链接绕行，避免用单层源码正则作为隔离依据。

tests/run_posix_operator.gd 仅检查 --games 存在，随即以 WRITE 打开其值；没有限制为本次隔离目录，因此可覆盖共享 artifacts/framework-games.json。--public-client-dir 也需完整路径边界检查，不能仅判断参数存在或与 artifacts/client 字面相等。请统一将测试数据、索引、公开配置及日志输出限制在本次隔离范围，覆盖路径穿越、链接、共享索引和间接继承入口的拒绝用例。Linux 验收继续暂停；原数据和标记保留，未提交推送。
#### Codex 防误启动补强二次复核（2026-10-01）

独立执行 powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/test_isolated_runner.ps1：ISOLATED_RUNNER_RESULT passed=30 failed=0，进程退出 0，全程替身引擎。未启动真实 Godot，未打开数据库，未连接 Linux。

仍需补齐三处边界：
1. 重复参数：两层校验将参数折叠成字典，仅检查最后值；run_posix_operator 随后逐条处理所有 --games 并 WRITE。前置共享索引、后置隔离索引即可绕过。Codex 用不存在的 Z:\ROOMKIT_NONEXISTENT_ENGINE.exe 验证，runner 输出 service_like=True 后到达 Start-Process 第142行，退出1（找不到引擎），未按64拒绝。仅创建 data/codex-guard-092398450fe242c5998bdf9f63f8031b 隔离目录。应拒绝重复参数，再以同一份校验后的参数执行。
2. Windows runner 只对含斜杠的参数值校验路径；必需路径参数可传空字符串/纯文件名而跳过检查。必须按参数名无条件验证必需路径，明确相对路径解析基准。
3. Linux 自检只对 isolation 根调用 _has_link，未检查 games 等完整子路径；且未要求 games 不存在，随后直接 WRITE。须在写索引前验证完整路径无链接、目标未存在，避免已有隔离目录内的链接或旧索引被覆盖。此项为代码审阅发现，未在 Linux 实机复现。

请用替身或纯校验探针覆盖三类反例；不以真实服务证明拒绝。Linux Operator 验收仍暂停。原数据/标记不动，未提交推送。
#### Codex 防误启动三项补修复核（2026-10-01）：可恢复限定实机验收

已核对重复参数拒绝、按名称检查路径，以及 Linux 完整目标链接检查/已存在索引拒绝。Operator 测试现在只向校验返回的 games 路径写一次。独立执行 tests/test_isolated_runner.ps1：38/0，退出0，替身引擎；证据 logs/incident-codex-final/runner.txt。通过 tools/run_isolated_test.ps1 执行 tests/run_operator_isolation_rules.gd：20/0、Linux链接用例未运行1项，退出0；证据 data/codex-isolation-rules-2e459b94501941eba4edafb3ae5849ea/rules.stdout 与 rules.stderr。未启动 Operator/宿主或打开真实数据库。WSL 25项输出仅阅读 Claude 证据，不作为 Codex 独立 Linux 实机通过。

本次防误启动补修允许进入下一门禁：Claude 在笔记本全新源码/运行目录中先执行纯校验（含真实符号链接及非法参数拒绝），通过后仅运行 Linux Operator 第一切片和必要 Windows 回归。实验继续暂停，不用 sudo、不改防火墙、不启动完整联机，不修改真实数据/陈旧 operator.json，不提交推送。保留 RECOVERY_UNSUPPORTED 等未实现限制。静态扫描是防误操作工具，不是对任意测试代码的安全沙箱；运行前仍检查测试入口和实际隔离参数。完整宿主后续使用独立大厅/控制/房间端口。

<a id="status-20261001-l3-closeout"></a>
## 2026-10-01 注销收尾前的 STATUS 第一屏

收尾结果交付时从 `STATUS.md` 逐字迁出（降一级标题、链接改为从本目录出发）。

### 最新结论：L3 同机功能已交付，耐久仍未通过（2026-10-01，未提交）

按 [连续任务单](../17_framework_shooter_plan.md#linux-batch-current) 推进，阶段终点仍需耐久收尾。详细结果、命令和证据见 [docs/17 阶段交付](../17_framework_shooter_plan.md#l3-stage-delivery)。

**Codex 当前决定**：允许仅对已知旧会话注销做有限补发，Claude 连续修复后复验 Linux C/D/E（含完整60分钟）及受影响的 Windows 回归；具体上限、旧令牌安全边界和测试见 [收尾任务](../17_framework_shooter_plan.md#l3-logout-closeout)。Codex 已核对最终 Linux 原始日志，未独立重跑 Linux；另用 Windows 真实 Godot + 假存储/假通道确认“注销失败仍丢弃内存清理责任”缺陷，探针 **1/2、引擎退出1**，不是真实联机测试。证据 `data/codex-l3-logout-review-b7ba44f1d1a84b22af250bf3797fd346/logout.stdout`，未启动真实服务/数据库。

- **Linux 笔记本最终轮** `20261001060258-bdccea`：45 步中 44 步通过；**60 分钟耐久 1 步失败**（78 个周期中 75 个通过）。
  - 通过：进程日志与跨运行只读恢复、房间内存上限、Linux 维护（指标、备份、恢复）、真实托管宿主、账号删除与迟到结算、正式入口 `tools/roomkit_linux.sh`（隔离实例，只绑 127.0.0.1）、两个真实无窗口客户端完整对局与签名结算、备份恢复、停止重启后数据保留、杀掉本轮创建并核验的 Operator 后宿主和房间自行退出并只读恢复、无残留、无误杀、无秘密残留，unit 318/0。
  - 失败：耐久后段有 3 个周期因 `ALREADY_LOGGED_IN` 失败。推断原因（未证实）：CPU 93–100% 时，存储助手偶发拒绝，玩家退出时的会话注销丢失，会话一直残留；管理请求也有 2 次被拒，导致 2 个房间没关掉。注销补发范围已由上面的收尾任务明确，尚未实现/复验；历史提议见 [原待决事项](../17_framework_shooter_plan.md#l3-decisions)；已加只记操作名和错误码的诊断日志。
- **Windows 回归**：见 docs/17 阶段交付的最终源码回归表。
- **未运行**：Windows 客户端连 Linux（下一阶段，需要防火墙决定）、公网、导出包、长期或云端容量。
