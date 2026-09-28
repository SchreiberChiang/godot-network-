# 当前状态：通用管理服务、账号、资产与射击示例

更新：2026-09-28。分支 `codex/shooter-framework`，提交 `b0a707d`，已与 `origin/codex/shooter-framework` 一致；工作区另有第一阶段未提交的文档改动（见文末）。本文件只放当前结论、未验收项、已知问题和证据位置；逐轮过程和完整验证表见 [STATUS 历史归档](docs/archive/status_history.md)。怎样启动见 [README](README.md)，模块和开发顺序一览见根目录 **`ROADMAP.html`**（双击打开）。

## 当前下一步（2026-09-28）

第一阶段收口：用户已基本验收路线图与文档，清理候选尚未确认；Codex 已完成脚本语法、节点/文件引用与差异范围的静态复核。本轮将第一阶段成果整理为本地提交，未推送。下一小阶段交接见 [docs/17](docs/17_framework_shooter_plan.md#下一阶段实施建议与验收门槛)：先核实主线整理条件，再由 Claude 主要实现独立射击客户端；任务尚未自动发送。下方“未提交/待复核”为此前交接时点，具体以 Git 状态及本段收口记录为准。

用户通过 `grilling` 确认三阶段顺序：项目分析/清晰文档/离线路线图 → 主线整理与独立射击客户端、后台 UI、基础音效 → Linux 完整服务器与后台，同时保留 Windows 一键运行。详细要求和可转交的 [Claude 第一阶段任务单](docs/17_framework_shooter_plan.md#claude-phase1) 已记录；主要实现、测试和整理交 Claude，Codex 负责复核。

第一阶段（Claude，2026-09-28，未提交，待 Codex 复核）已交付：`ROADMAP.html` 项目地图、[项目分析](docs/01_scope_architecture.md#项目分析2026-09-28)、[清理候选表](docs/17_framework_shooter_plan.md#清理候选表)、[下一阶段实施建议与验收门槛](docs/17_framework_shooter_plan.md#下一阶段实施建议与验收门槛)，以及本文件和 README 的精简。没有改功能代码、协议、数据库或启动/构建脚本；没有删除任何文件或分支；没有连接 Linux。检查结果见下方“最新有效验证范围”末行。第二阶段待用户验收第一阶段后再安排。

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
| `ROADMAP.html` | 2026-09-28 新增的项目地图，双击打开，不需要后台或网络 |
| 早期无账号演示入口（仓库根 `StartPanel.cmd`、`StartPlay.cmd`、`StartTurns.cmd`、`StartDemo.cmd`、`ShowResults.cmd`）及 0.1.0 包 | 保留但不推荐，见 [早期入口](docs/archive/early_entrypoints.md)；已列入清理候选 |

更早的独立包（`bbc5f4dd…`、`12253e0a…`、`a5eb4e45…`、`fc3df1a4…`、`f4f40384…`）的构建来源与测试记录见 [历史归档第〇节](docs/archive/status_history.md)。

## 最新有效验证范围

所有结果都只在同一台 Windows 电脑上取得；计数是断言数，不是玩家数。完整命令、失败复测和证据目录见 [历史归档第〇节](docs/archive/status_history.md)。

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
- 最新独立包（`aa019dbc…`）的人工浏览器操作、原生客户端试玩、包内删除端到端，以及新包的旧存储路径。
- 新后台表单（房间规则、8 字符密码、删除对话框）的真实浏览器点击；托管模板的图形界面；真人操作手感。
- 账号删除：删除时房间正在进行、之后才提交结果的完整真实对局；outbox 中已有待处理/已拒绝结果文件时的残留报告；大量账号或大审计文件下的耗时；磁盘满等真实系统级写入失败（测试用只读属性模拟）。
- `tools/run.ps1 -Mode all` 中与近期改动无关的模式、`test_managed_shutdown.ps1`、`test_operator_schedules.ps1` 未在 09-27 重跑。
- 断电、磁盘满、真实网络丢包/延迟、证书轮换、外部身份服务。

## 已知问题与限制

1. **仅限 Windows**：账号、资产、结果存储和进程身份核验依赖 PowerShell 助手与 `winsqlite3.dll`，Linux 上返回 `UNSUPPORTED_STORAGE`。替换边界见 [项目分析](docs/01_scope_architecture.md#项目分析2026-09-28)。
2. **仍有慢操作**：注册、登录（另有约 1.9 秒 PBKDF2，有意保留）、登出、结算、grant、邀请码和后台写操作仍走一次性助手，每次往返约 1.0–1.2 秒。常驻进程每个约 0.1 GB 内存，空闲 5 分钟退出，重启约 0.6 秒。
3. **客户端测试驱动偶发失败**：`test_framework_clients.ps1`、`test_framework_capacity.ps1` 写命令文件偶发 `Access is denied`，开火循环偶尔 35 秒内打不死对手；原样重跑都通过，驱动未改。
4. **临时请求文件的剩余范围**：资产、结果和维护请求仍用私有目录下的短期请求文件（不含口令、token 或签名密钥）。用户真实数据目录 `data/framework/` 下有 09-26 残留的 `account-request-*.json`（104 字节）和两个 `helper-*.json`，未读取、未删除。
5. **射击网络模型只按局域网设计**：每秒 20 次完整状态，只有显示平滑，没有客户端预测和命中回溯；公网手感未评估。
6. **容量与耐久**：16 人满房只持续 17.5 秒；托管宿主没有长期测试。
7. **原因未查明的现象**：09-22 一个可视化夹具中途消失；一次管理员意外退出登录，根因未确认。
8. **预期诊断输出**：`Exponent too high`、`mbedtls -0x6c00`、load 模式多一行 `SECURE_RESULT`，都不是失败。
9. `tools/run.ps1 -Mode all` 只含早期基础回归，遇到第一项失败即停；账号、管理、射击和托管专项需按 [docs/22](docs/22_framework_operations.md#测试入口) 单独运行。
10. **结果授权没有回收**：每开一间房新增一条授权且从不删除，同一资产库累计开到第 257 间房时建房失败（256 是累计上限，不是并发人数）。回收策略与迟到结算窗口仍是规划。
11. **同一解压目录重复跑包测试不稳定**：曾两次 6/1，全新解压则 44/0；验包时用干净解压副本。
12. **后台离线提示引用旧入口**：`host/admin.html` 断线提示仍让用户运行 `StartPanel.cmd`（在源码里那是早期面板，当前入口是 `StartManagement.cmd`）；留到第二阶段 UI 修复。

## 工作区与交接

- `b0a707d` 及之前的提交已推送到 `origin/codex/shooter-framework`（09-27 各轮记录里的“未推送”指当时）。`main` 停在 `5f7b7aa`，`codex/m4-results` 停在 `1a8bec5`；主线整理放在第二阶段。
- 当前未提交：Codex 规划轮修改的 README、本文件、docs/17；Claude 第一阶段修改的 README、本文件、docs/01、docs/17、docs/22（仅锚点）、docs/archive/README.md、docs/archive/status_history.md，新增 `ROADMAP.html`、`docs/assets/roadmap/roadmap-data.js`。
- 环境：Windows 10.0.26200；Godot `4.7.2.stable.steam.ed1daf0bf`；Git `2.55.0.windows.3`；`winsqlite3.dll` 3.51.1。Linux 笔记本 SSH 目标记录于 [docs/10](docs/10_environment.md)，未连接。

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
