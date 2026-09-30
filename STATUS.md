# 当前状态：RoomKit（2026-10-01）

**当前交付（2026-10-01）：Linux 房间生命周期第一小项已实现，保存为开发检查点；Windows 恢复测试未通过，不能作为发布候选。** 已读 Claude Linux 原始汇总：13 步通过、退出 0，integration 133/0（22 个子进程）、房间专项 22/0+注入5/0、unit 318/0。Codex 本轮没有 SSH 重跑 Linux；独立 Windows unit 320/0，启动器恢复测试复现失败（见下）。

## 当前下一步

1. Claude 先调查 Windows run_recovery：在隔离快照对照改动前 b9aa587 与当前代码，定位外层宿主启动/身份核验失败。不得靠延长等待或反复重跑抹掉失败。
2. 恢复问题明确并复核后，继续 Linux Operator 私有目录、宿主停止/交接、进程日志与恢复策略、资源限制；先隔离完整后台，再 Windows 客户端跨机联机。
3. SQLite 实验继续暂停。当前仅提交推送开发检查点，不发布 Release、不重建或替换真实服务/客户端。

本轮独立证据：logs/l2b2-codex-final/unit.txt 为 UNIT_RESULT 320/0、进程退出 0；recovery.txt / recovery-errors.txt 为 SECURE_RESULT 5/4，外层 verified recovery host old 失败，后续 READY/端口/退出断言失败。恢复进程已结束，但当前轮未成功取得其数值退出码，不将工具外层退出 0 当作测试通过；随后通过 Win32_Process 核对没有 Godot 进程残留，未执行批量清理。Claude 5 次不稳定记录继续保留在 logs/l2b2-review/；没有基线对照，原因未明。

分工、证据等级、设备使用顺序及可转交消息集中在 [协作总览](docs/17_framework_shooter_plan.md#coordination-current)。用户不用自行判断两个 AI 的测试是否等价。

## 三条工作线

| 工作线 | 负责人 | 当前事实 | 下一动作 |
|---|---|---|---|
| P：PowerShell 正式存储及 Linux 接入 | Claude 实现，Codex 复核 | L1 脚本互开已验证；L2-A 有限定范围的通过记录；B1 正常链路及补修证据已复核 | 保留官方引擎，进入隔离房间生命周期 |
| B1 独立复验 | Codex | 已实机完成：16 步中仅既有 unit 限制失败，SSH/测试退出 1；正常两种存储模式通过 | 旧快照复验与最新补修复核分开记录，缺陷已收口 |
| G：原生 SQLite 导入崩溃实验 | 另一 AI | 最新转述称已准备判空补丁，未安装/编译；源码哈希、补丁和当前进程未由 Codex 实机核对 | 等主线释放设备；先复核原始证据，再讨论编译与对照 |

## 最新有效验证范围

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

证据：

- [Claude 最终 Linux 输出](logs/l2b1-linux/run-20260930171501-208b39.txt)。
- [Claude 超时补修 Linux 输出](logs/l2b1-linux/run-20260930182509-d7d0cd.txt)、Windows 回归与截止注入在 `logs/l2b1-fix-review/`；说明见 [docs/17 管道超时补修结果](docs/17_framework_shooter_plan.md#管道超时补修结果claude2026-10-01未提交待-codex-复核)。
- [Claude 绝对截止与预算补修 Linux 输出](logs/l2b1-linux/run-20260930185629-ebc89a.txt)；新旧对照和 Windows 回归在 `logs/l2b1-budget-review/`；说明见 [docs/17 绝对截止与原子预算补修结果](docs/17_framework_shooter_plan.md#绝对截止与原子预算补修结果claude2026-10-01未提交待-codex-复核)。
- [Claude L2-B2 房间生命周期 Linux 输出](logs/l2b2-linux/run-20260930193037-54ca61.txt)；Windows 回归与 `run_recovery` 各次输出在 `logs/l2b2-review/`；说明见 [docs/17 L2-B2 第一小项结果](docs/17_framework_shooter_plan.md#l2-b2-第一小项结果linux-房间生命周期claude2026-10-01未提交待-codex-复核)。
- [Codex 超时失败](logs/l2b1-codex-review-9a80562ebb904089a307732024ed94d8/review_timeout.txt)、[Windows 常驻回归](logs/l2b1-codex-review-9a80562ebb904089a307732024ed94d8/run_resident_store.txt)。
- [Codex 独立 Linux 输出](logs/codex-l2b1-7f1a0ba8/verification-retry-02.txt)、[汇总](logs/codex-l2b1-7f1a0ba8/independent-result.txt)。成功启动入口为 RetryVerification.cmd；原源码包未改，仅收窄外层环境扫描。该运行号已使用，不重复双击。

这些 logs 是本机证据，不随 Git 分发；完整历史与旧证据索引见 [归档](docs/archive/status_history.md#status-20261001)。

前次整理的文档检查：5 份文档的 128 个本地链接路径均存在，4 个新/保留的入口锚点存在，旧 STATUS 除相对链接调整外完整归档；git diff --check 通过。未逐项重验全部历史标题锚点；当时没有运行功能测试，后续实机复验见上表。

独立复验启动尝试（2026-10-01）：用户已暂停实验并在交互终端输入密码，但 SSH 返回 255，verification.txt 为空，未收到远端测试结果；具体错误只显示在原终端，待取得后再判断，不能归因为密码错误。随后只读连接探测确认 SSH 可达且主机指纹匹配；不代表认证成功。该次没有有效结果；用户再次输入密码后 retry-02 已完成复验，结果见上表。

## 当前已实现

Windows 上已具备管理后台、邀请码账号、按游戏隔离的永久资产、房间生命周期、结算、备份恢复及测试账号删除；示例为射击与取石子。已加入独立客户端直接启动、内容摘要配对、新后台与基础音效。用户已反馈后台登录/建房、独立客户端入退房、基础音效等试玩正常；这些反馈不扩展为完整跨设备验收。

Linux 已安装官方 Godot 与 PowerShell，完成构建摘要、存储脚本、进程/权限和部分 Godot 存储接入验证。完整 Operator、房间、跨机闭环仍未完成。

## 当前交付物

| 入口或产物 | 用法与限制 |
|---|---|
| StartManagement.cmd / StopManagement.cmd | Windows 源码后台启动/停止；当前推荐 |
| PreparePlayerClient.cmd → PlayerClient/ | 生成完整玩家目录，直接双击 Client.exe；源码更新后需重新生成并与服务配对 |
| StartPlayerClient.cmd / StartShooterClient.cmd | 已生成客户端入口 / 源码客户端入口 |
| clients/shooter-windows/、旧 Release 附件、独立 ZIP | 未随 Linux 工作重新生成；旧版本和证据见归档，不作为最新源码交付。Release 仍暂缓 |
| ROADMAP.html | 离线项目地图；当前执行状态以本文及 docs/17 顶部为准 |

## 未运行 / 未验收

- Linux 完整后台、房间、跨机联机；Linux 删除/结算/恢复专项；Codex 对最新补修的独立 Linux 实机重跑（Claude 已跑）。
- G 实验修补引擎的编译、首次导入对照和完整业务验证；实验目录与当前运行状态的独立核对。
- 公网外部设备验收、TUN 共存、长期负载与耐久、最新交付包重建、GitHub 实际获取。
- 历史专项未运行范围不因本轮整理消失，详见归档。

## 已知问题与限制

- B1 截止/预算缺陷已收口；8 为在途与待回收合计上限，4 为阻止新启动的阈值，常驻 worker 每库单独管理。并非保证任意操作严格在零误差的毫秒截止内结束。
- Linux 运行前须满足 SIGPIPE 启动防护、锁定引擎提交与私有路径规则；Windows 启动方法不能原样照搬。
- 一次性存储调用仍慢，常驻热请求快；当前测量不保证未来小云服务器性能。实验与主线可能有时间重叠，耗时需要空闲时重测。
- G 原型首次导入崩溃尚未修复验收；不能用第二次成功或候选补丁替代首次通过。
- 历史客户端测试有写命令文件 Access is denied 等偶发失败；未因本轮整理修复。

## 工作区与交接

本地 main / HEAD 为 b9aa587e5a5d9051360f6550c1f6ed8aec2db65d（本轮核实）；远端本轮未 fetch，不能据此声称同步。L2-A/B1、G 原型和驱动等仍未提交，主要由 Claude 维护；Codex 本轮整理文档，生产代码未改。没有提交推送。

Linux 地址、工具路径与隔离区域见 [环境现状](docs/10_environment.md#linux-current)。同一工作区单方写入；同一笔记本只运行一条验收或编译任务。主线不读实验目录；若需实验核对，应另列只读范围，不隐含在主线扫描里。

## 第一阶段检查（2026-09-28）

文档与路线图的历史自动检查、用户反馈和清理候选未验收范围已完整迁入 [历史归档](docs/archive/status_history.md#status-20261001)。
