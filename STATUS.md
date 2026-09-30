# 当前状态：通用管理服务、账号、资产与射击示例

当前交接（2026-09-30）：已有 UI/音效/入房/构建摘要（`c96e848`）及 Linux 安装验证、L1 存储切片（`481f69f8892e4fcf89bd253fd863bd91bb8950e1`）已实际推送到 GitHub `main`，Git push 退出 0。下一步由 Claude 按 [已授权任务](docs/17_framework_shooter_plan.md#next-plan) 下载 godot-sqlite 做隔离小原型并补测性能，用户已批准。只用假数据，不切换正式存储后端，不动真实服务或防火墙。本轮提交前失败注入 6/0、退出 0，PowerShell/Shell 语法与 diff 检查通过；功能复测沿用下方独立 49/0 与 Claude 证据，没有重新跑 Linux 或完整服务器。交接记录作为后续文档提交，不改变成果基准。

L1 复核（Codex，2026-09-30）：脚本兼容性范围认可，Linux 完整服务器仍未实现。本轮独立 Windows 存储专项 49/0、not_run=2、退出 0，失败注入 6/0、退出 0；证据 `logs/l1-codex-review-b57a318667eb4fcf99efd5adf6cb6125/windows-slice.txt`。Linux 和双向互开结果来自下方交付日志，本轮未连接 Linux。一次性调用超 2 秒属实；448 MB 是两个 worker 独立采样工作集相加，原定“管理服务＋宿主＋一个房间”内存门槛尚未测。下一项建议由 Claude 补测并做原生 SQLite 隔离小原型，先评估、不重写正式存储；新依赖尚未下载，任务见 [当前建议](docs/17_framework_shooter_plan.md#next-plan)。本轮只改本文和 docs/17，未提交推送。

L1 存储切片（Claude，2026-09-30，未提交，待 Codex 复核）：只到共用 SQLite 绑定、平台路径和编码，以及隔离验证；没有实现 Linux 的 Godot 仓储接入、进程管理或完整服务器。没有安装，没有用 sudo，没有动真实服务和数据。详见 [docs/17 L1 存储切片结果](docs/17_framework_shooter_plan.md#l1-存储切片结果claude2026-09-30未提交待-codex-复核)。
- **改动**：`tools/sqlite_store.ps1`、`tools/account_store.ps1`。同一份绑定在 Windows 上用 `winsqlite3.dll`，在 Linux 上用 `libsqlite3.so.0`；备份路径检查按平台分隔符；JSON 里像日期的字符串在两个平台都保持为文本；密码派生改成两个运行时都能编译的写法，算法和参数不变。
- **对照**：同一个驱动 `tests/storage_slice_portable.ps1`，Windows（PowerShell 5.1）49/0，带 Linux 库时 57/0；Linux（PowerShell 7.6.6，.NET 10，SQLite 3.45.1）58/0。覆盖管理员初始化、邀请码注册、登录、会话、错误密码，资产幂等和冲突，备份恢复，中文加空格的路径，Unicode 文本，PBKDF2 已知答案。两个平台新生成的测试库能互相打开、登录并继续写入。
- **测试驱动**：汇总退出码已修，任何失败、超时或脚本错误都返回非零；失败注入自测在两个平台都是 6/0。
- **Windows 回归**：资产 83/0、账号 85/0、快照 40/0、结算 74/0、授权 24/0、常驻 34/0、删除 83/0、备份恢复 35/0、账号恢复 30/0。
- **性能待决**：Linux 一次性调用 2.1–3.1 秒超过 2 秒门槛；两个 worker 独立测量的工作集加总约 448 MB（Windows 257 MB），不能当成独占内存或整套服务总量。原定完整服务内存门槛尚未测。常驻请求中位数 12–25 ms 达标；会话 p95 54.1 ms。下一项建议补测并评估方案 G 小原型。
- **未运行**：Linux 上经 Godot 调用存储、结算、删除、维护脚本，并发和长时间运行，进程管理，完整服务器。

安装阶段复核（Codex，2026-09-30，历史）：Windows 便携摘要驱动 11/0、not_run=0、退出 0，证据 `logs/linux-review-11dcba4d4c3a466a91b6015380006c6f/windows-digest.txt`；Linux 单元 292/1 保留为失败。当时发现的测试汇总退出码问题已在 L1 修正并通过失败注入，安装脚本尚未在 Linux 完整重跑。

Linux 依赖安装与隔离验证（Claude，2026-09-30，未提交，待 Codex 复核）：只写了笔记本的 `~/roomkit/`；没有用 sudo，没有改防火墙，没有带真实数据；密码由用户输入。详见 [docs/17 安装与隔离验证结果](docs/17_framework_shooter_plan.md#安装与隔离验证结果claude2026-09-30未提交待-codex-复核)，原始输出在 `logs/linux-setup/run-20260930121157-ab0563.txt`。
- **安装**：Godot `4.7.2.stable.official.ed1daf0bf`，PowerShell 7.6.6（官方当前 LTS，.NET 10）。安装包由用户在笔记本浏览器里从官方地址下载，哈希与官方值一致后才安装。源码是本地提交 `c96e848` 的归档，两端哈希一致。
- **摘要实机对照**：由 Linux 上的 `pwsh` 实际运行生产摘要脚本，11/0。合成夹具复现了基准值 `05f794ef76f0`；射击 `de37edca7f1d`、取石子 `772421bf94d2`，与 Windows 完全相同。Windows 那边的文件是 CRLF，Linux 这边是 LF。
- **纯 GDScript 测试**：射击规则 83/0、客户端反馈 7/0、音效 41/0、入房回归 16/0、托管契约 286/0，都与 Windows 一致。`run_unit` 是 292/1，失败点是房间管理器在非 Windows 平台返回 `UNSUPPORTED_PLATFORM`，属于预期的平台边界，不算通过。
- **未运行**：Linux 上的存储、进程管理、Operator、房间和跨机联机。笔记本不能直接访问 GitHub。
- **下一步**：L1 存储最小切片。新增的 `tests/content_digest_portable.ps1` 和 `tools/linux_isolated_setup.sh` 还没有提交。

当前授权（2026-09-30）：用户同意本地提交现有成果、不推送；随后由 Claude 在 Linux 笔记本 `~/roomkit/` 内安装官方 Godot、PowerShell 7 和该提交源码，执行隔离测试。SSH 保留密码、不配置免密；不用 sudo、不改防火墙、不复制真实数据库。任务见 docs/17 顶部已授权任务，本轮未连接设备或安装。此前等待安装授权/只读阶段描述保留为历史；远端代码与旧发布候选尚未同步，部署必须取此次本地提交，不能直接用旧 origin/main。

Linux 设备只读检查（Claude，2026-09-30，未提交，待 Codex 复核）：用户本人确认主机指纹并输入密码后运行了 `tools/linux_device_check.sh`，脚本跑完。没有安装、写入或复制任何东西。结果见 [docs/17 设备检查结果](docs/17_framework_shooter_plan.md#设备检查结果claude2026-09-30未提交待-codex-复核) 和 [环境记录](docs/10_environment.md#linux-测试机只读检查2026-09-30claude)，原始输出在 `logs/linux-device-check/check-20260930.txt`。
- **设备**：Linux Mint 22.3，内核 7.0，glibc 2.39，x86_64；i5-5200U 2 核 4 线程；内存 7.7 GB（可用约 5.3 GB）；磁盘可用 378 GB。
- **已有**：`libsqlite3.so.0`、libicu、libssl、git、curl、tar、python3；内核支持 pidfd，`/proc` 可读；RoomKit 默认端口都空闲。
- **缺少**：Godot 4.7.2、PowerShell 7。两者都可以装在用户目录，不需要 sudo。
- **未知**：Node、SQLite 的具体版本、ufw 规则（ufw 在运行，读规则需要 root）。
- **下一步**：先提交现有成果，让源码副本有确定的提交；用户同意后安装 Godot 和 pwsh；然后在设备上用 `pwsh` 实跑摘要，对照基准值 `05f794ef76f0`。摘要的 Linux 实机一致性仍然没有验证。

摘要复核完成（Codex，2026-09-30）：已读 PowerShell 实现、Node 独立参考及测试，独立重跑 `tests/test_content_digest.ps1` 55/0、not_run=0、退出 0，基准值 `05f794ef76f0`；证据 `logs/content-digest-73efe55342f347f8adc1c2b1f33b34b5/`。共享游戏索引未变化；未重跑完整客户端，未连接 Linux。下一步交 Claude 按 docs/17 顶部任务执行指定笔记本的只读设备检查；任务未自动发送。当前未提交成果继续保留，未提交推送。

跨平台构建身份（Claude，2026-09-30，未提交，待 Codex 复核）：只改了构建摘要 `tools/content_digest.ps1`；规则、证据和上线步骤见 [docs/17 构建身份修复结果](docs/17_framework_shooter_plan.md#构建身份修复结果claude2026-09-30未提交待-codex-复核)。
- **规则**：路径统一用 `/`；`.godot` 目录在两种分隔符下都排除；按序数排序；只对固定扩展名且不含 NUL 的文本把 CRLF 统一成 LF；二进制按原始字节计算。版本校验没有放宽。
- **测试**：新增 `tests/test_content_digest.ps1`，55/0，合成夹具的基准值是 `05f794ef76f0`。LF、CRLF、混合、反序得到的摘要一致；代码、Schema、配置、二进制和文件名的变化都会改变摘要；独立的 Node 参考实现结果一致。真实的射击和取石子工程转成纯 LF 或纯 CRLF 后摘要不变。`test_player_client.ps1` 28/0，错误版本仍被拒绝。
- **版本**：新规则下源码的 build_id 是 `shooter-dev-002-src-de37edca7f1d`。正在运行的服务、共享索引和用户的 PlayerClient 仍是 `675fa4d8063e`，三者互相匹配，本轮没有动。仓库副本和 Release 附件仍是 `0f559378dddc`。
- **未验证**：Linux 实机。本机的结果只是对检出形式的模拟，不能算跨平台通过；下一步要在设备上复现基准值和同一提交的摘要。`build_framework.ps1` 里的反斜杠路径留给后续平台实现。
- **用户**：重启管理服务后 build_id 会变化，需要运行 `PreparePlayerClient.cmd` 重新生成客户端；不重启的话，现有服务和客户端照常工作。

L0 复核（Codex，2026-09-30）：已检查检查脚本、构建摘要和任务记录。脚本已收窄为 PATH 与已约定工具目录，取消 HOME 广泛扫描；本机 `bash -n`、`git diff --check` 均退出 0，未连接 Linux、未运行设备测试。版本摘要除换行外还需处理路径分隔符和确定性排序，下一任务已写入 docs/17 顶部交 Claude。进程锁的安全结论仍依赖所有回收路径均受控，未验明前不判通过。未修改真实服务/数据、未安装、未提交推送。

L0 交付（Claude，2026-09-30，未提交，待 Codex 复核）：没有改功能、没有连接设备、没有安装、没有提交推送。详见 [docs/17 L0 交付](docs/17_framework_shooter_plan.md#l0-交付claude2026-09-30未提交待-codex-复核)。
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
登录显示修复（Codex，2026-09-29）：用户反馈输入账号密码后仍停留登录页。隔离真实后台复现：认证成功后 `authView.hidden=true`，但 `.auth{display:grid}` 覆盖隐藏行为；已添加 `[hidden]{display:none!important}`，同时修复主界面及其他隐藏面板的显示。真实浏览器验证修复前复现、修复后登录显示总览、退出返回登录页；四项 Node 测试共 44/0（含新增结构防退化检查，非浏览器替代）。证据：[隔离后台截图](logs/admin-ui-b26d02ce107248e0b804bc3c9133cf6e/login-fixed.png)。未修改真实账号、未操作真实服务，未重跑 Godot 全量回归或独立包。后台在启动时读取 HTML，用户需正常停止并重新启动管理服务，再刷新页面。

更新：2026-09-28。当前主线 `main`，已从旧主线快进整合到 `74f3413`（包括第一阶段文档与路线图）。本轮只同步主线说明，其他分支保留；远端同步结果以 Git 核实为准。下方各轮提交和工作区描述保留当时含义。本文件只放当前结论、未验收项、已知问题和证据位置；逐轮过程和完整验证表见 [STATUS 历史归档](docs/archive/status_history.md)。怎样启动见 [README](README.md)，模块和开发顺序一览见根目录 **`ROADMAP.html`**（双击打开）。

## 当前下一步（2026-09-29）

空房间消失 / 入房回登录（Claude，2026-09-30，未提交，待 Codex 复核）：已在隔离环境复现、找到根因并修复，详见 [docs/17 诊断与修复](docs/17_framework_shooter_plan.md#诊断与修复claude2026-09-30未提交待-codex-复核)。
- **根因**：入房回复的 Schema 把 `host` 锁死为 `127.0.0.1`。通告地址一旦不是回环地址，客户端就会拒绝入房回复，关闭大厅连接并回到登录页。随后大厅清理时，对刚预留的座位发出空 `attempt_id` 的 revoke，房间校验失败后主动停机，宿主记为 `FAILED/CONTROL_UNAVAILABLE`。
- **修复**：`host` 改为严格的 IPv4 字面量；刚预留、还没有 attempt 的座位只在本地释放，不再发 revoke。认证和超时都没有放宽。另外增加了宿主、房间、客户端三侧的脱敏断开原因日志。
- **验证**：修复前连续 3 次复现，修复后同样配置下真实客户端能入房、退房，房间一直保持就绪。回归：新增专项 16/0，unit 320/0，托管契约 286/0，托管停机 55/0，射击规则 83/0，音效 41/0，玩家客户端 28/0（新 build_id 为 `shooter-dev-002-src-675fa4d8063e`）。
- **未验证**：公网外部设备、真实服务重启后的日志。用户需要重启管理服务，并重新生成 PlayerClient。

Linux 完整服务端可行性调查（Claude，2026-09-29，未提交，待 Codex 复核）：只读调查加一次本机隔离内存测量；没有改功能、没有安装、没有连接笔记本。详见 [docs/17 调查结果与推荐](docs/17_framework_shooter_plan.md#调查结果与推荐claude2026-09-29未提交待-codex-复核)。
- **推荐**：进程身份、目录保护和指标在 Linux 上用 GDScript 直接读 `/proc` 和文件权限；存储层先用 PowerShell 7 复用现有助手（方案 P），存储语义保持一份实现。只有实测达不到门槛，才评估 GDExtension SQLite（方案 G）。两种方案都要用户同意引入。
- **发现**：Godot 4.7.2 在 Unix 上检查进程是否在运行时会回收已退出的子进程，`OS.kill` 按 PID 发 SIGKILL。Windows 的“持有句柄再结束”规则不能照搬，否则可能误杀复用了 PID 的进程。现有代码已经被 Windows 限定条件挡住，所以 Linux 上常驻存储是关闭的，超时也不会真正结束助手。
- **内存基线**（Windows，隔离环境）：只有管理服务 287 MB 工作集；游戏服务器运行时 557 MB；加一个就绪房间 548 MB。PowerShell 进程约占三分之一到一半。证据在 `logs/admin-ui-2d98e12ebc1049c48474fbc965245b48/memory/`。
- **下一步**（需用户同意）：设备只读检查 → Linux 上的 Godot headless 测试 → 方案 P 最小存储切片，含跨平台库互开和 PBKDF2 对照 → 实测 → 平台层 → 跨机闭环。

基础音效（Claude，2026-09-29，未提交，待 Codex 复核）：开枪、命中、死亡、购买成功、按钮点击五种音效，全部在客户端由代码合成，没有外部素材；音量和静音保存在 `user://`，`M` 键切换静音。实施和证据见 [docs/17 基础音效实施](docs/17_framework_shooter_plan.md#基础音效实施claude2026-09-29未提交待-codex-复核)。
- **事件来源**：开枪、命中、死亡都从服务器快照推导，购买只在服务器确认后播放；失败、超时和重复响应都不出声。
- **测试**：新增 `tests/run_client_sound.gd` 41/0；射击规则 83/0；反馈测试 7/0；真实渲染跑通；隔离的玩家客户端联机测试 28/0，新 build_id 为 `shooter-dev-002-src-97b98fb2f74e`。
- **已知限制**：快照不带攻击者，三人以上时“命中”也会在别人互射时响，要改需要协议改动，待决定。
- **未验收**：听感；`test_framework_clients.ps1` 未跑（它读取真实服务的共享索引）；独立包、仓库副本、Release 附件和用户的 PlayerClient 都没有重新生成，仍是旧版本。
- **用户上线**：停止游戏服务器 → `StopManagement.cmd` → `StartManagement.cmd` → 启动游戏服务器 → `PreparePlayerClient.cmd`。

用户真人验收已确认创建房间等管理操作、退出后台和重新登录正常。Codex 本轮抽查房间截图、隐藏样式和浏览器结果文件，重跑四项 Node 测试 44/0；未重跑真实浏览器或 Godot 全量测试。下一项是 docs/17 的基础音效任务，交 Claude 实施；任务已落文档，尚未自动发送。未提交推送。

后台改版收尾（Claude，2026-09-29，未提交，待 Codex 复核）：已按 [docs/19 当前任务](docs/19_admin_ui.md#当前任务后台改版收尾2026-09-29交-claude) 完成，结果见该节下的“收尾结果”。
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

详见 [docs/19](docs/19_admin_ui.md#真实后台接入claude2026-09-29未提交待-codex-复核)。

后台 UI 预览（Claude，2026-09-29，未提交，待 Codex 复核）：新增根目录 `ADMIN_PREVIEW.html`，双击打开，全部为演示数据，不连接真实服务。重点完成总览、房间、玩家三页，其余四页是标注为草图的导航页。三条常用操作从约 5 / 4 / 6 步缩短到 3 / 3 / 4 步，必要的确认和原因都保留。内置浏览器实测 31 项全部通过，另验证了真实键盘操作、760 像素宽和截图。用户本机浏览器的双击打开未验收。没有修改正式后台。步骤对照和检查结果见 [docs/19](docs/19_admin_ui.md#预览交付claude2026-09-29未提交待-codex-复核)。

用户同意继续后台 UI：GitHub 暂缓发布不再阻塞独立 UI 工作。当时安排 Claude 制作 `ADMIN_PREVIEW.html` 离线演示预览，用户确认预览后再接入真实后台（两步均已完成，见上两段）。随后基础音效、Linux 服务端调查，按小阶段逐项验收。此前“UI 暂不开始/发布后才进入 UI”为已被本决定替代的顺序，不是当前阻塞。此次仅更新 STATUS、docs/17、docs/19；未改功能、未运行服务或游戏测试，未提交推送。

GitHub 发布准备（Claude，2026-09-29，未提交）：Release 附件（12 个文件，tag `shooter-client-shooter-dev-002-src-0f559378dddc-4c2ef956`）与已提交的仓库副本、清单哈希全部一致；main 源码构建出的 `build_id` 与附件一致；没有秘密文件；发布说明已准备好。**用户确认暂不发布**，所以下载、直接启动和联机验收都没有执行，GitHub 获取流程仍为待验证。（当时写的“后台 UI 阶段暂不开始”已被随后用户的决定替代，UI 已开始。）详见 [docs/17](docs/17_framework_shooter_plan.md#暂缓任务github-获取验收)。

最新收口：用户按重启管理服务、重新生成 PlayerClient、直接双击 Client.exe 注册/登录/入房/退房的步骤试玩，反馈未发现可见问题。Codex 复核直接配置读取、内容摘要与附件生成代码；独立启动器专项 14/0、退出 0（`logs/client-launcher-883f852cbdfd43abad7f880906b10839/`）。独立隔离构建两次，两种游戏 build_id 均稳定；仓库客户端与当前源码 build_id 一致，Release 与仓库副本的 generated_files 哈希全部匹配，检查退出 0（索引在 `logs/codex-client-final-a449f131fba94438b1af26273b8b4f16/`）；git diff --check 退出 0。Claude 的 28/0 联机回归未由 Codex 重跑。用户授权本轮提交并推送 main；Release 未发布，GitHub 下载、跨设备、DTLS 原因和旧独立包仍未验收/解决。下次优先执行 docs/17 的“GitHub 获取验收”任务，不重复已完成的直接启动实现。

客户端交付收尾（Claude，基于 `main` `f91e6cc`，未提交，待 Codex 复核），详见 [docs/17](docs/17_framework_shooter_plan.md#客户端交付收尾实施2026-09-28)。隔离回归 `tests/test_player_client.ps1` 28/0、退出 0，证据在 `logs/player-client-90442badd27f4874bae0f6acef4eb661/`。
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

GitHub 获取方案（Claude，2026-09-28）：`Client.exe` 为 104.2 MiB，超过 GitHub 普通文件上限，所以不进 Git，改作 GitHub Release 的原文件附件；LFS 有计费风险，没有启用。仓库目录 `clients/shooter-windows/` 现在与本地客户端同源生成（见“复核修正”）。方案见 [docs/17](docs/17_framework_shooter_plan.md#独立射击客户端实施2026-09-28)。尚未创建 Release，GitHub 下载流程为待验证。

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
| 玩家客户端 `PreparePlayerClient.cmd` → `artifacts/player-clients/shooter-windows/`（匹配源码服务器 `shooter-dev-002`） | 2026-09-28；复核修正后隔离验收 20/0；已为当前服务器重新生成（对外地址为 127.0.0.1，只能本机使用）；真人图形界面试玩待验证 |
| GitHub 仓库目录 `clients/shooter-windows/`（`PreparePlayerClient.cmd -RepositoryCopy` 生成，tag `shooter-client-shooter-dev-002-22250f37`） | 与本地客户端同源；Git 中约 0.37 MiB（不含 Client.exe）；Release 未创建 |
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
- 独立射击客户端：GitHub Release 实际上传和下载（`FetchClient.cmd` 在 Release 不存在时下载失败，并清理了残留文件）、另一台电脑上的真人登录与入房、新包发布后重新生成客户端目录的流程。
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
