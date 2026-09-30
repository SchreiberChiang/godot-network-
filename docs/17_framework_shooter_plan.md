# 通用框架与横版射击分支实施计划

<a id="next-plan"></a>
## 已授权下一步：补测性能并评估原生 SQLite 小原型（Codex，2026-09-30）

用户已同意本任务的第三方扩展下载及隔离测试，并要求先整理提交、推送，再交 Claude 实施。授权仅限隔离评估：项目测试目录与 Linux `~/roomkit/`，假数据，不修改正式存储后端。此前“待确认下载”的描述是授权前记录。交接的确定提交号由 Codex 完成提交后补充。

**L1 复核结论**：存储脚本兼容性范围认可；不表示 Linux Godot 接入或完整服务器通过。已读两个生产脚本差异、Linux 原始输出及 Windows 回归证据；Codex 独立重跑 Windows 便携存储专项 49/0、not_run=2、退出 0（未跑 POSIX 权限与外来库），证据 `logs/l1-codex-review-b57a318667eb4fcf99efd5adf6cb6125/windows-slice.txt`。失败注入独立重跑 6/0、退出 0，四份 Shell 脚本语法检查退出 0。Linux 58/0 与双向互开结论来自 Claude 交付日志，本轮没有连接设备或重跑 Linux 测试；修改后的安装脚本尚未在设备上完整重跑。

**性能口径修正**：
- 原计划第 6 节的内存门槛是“管理服务、宿主加一个房间，总内存不超过 Windows 基线加 20%”，不是“两份存储 worker 加总”。完整 Linux 服务尚未运行，因此这个门槛目前未测，不能据 worker 数字判定整个服务未达标。
- 448 MB 和 257 MB 是两个 worker **分别运行、退出后**采到的 WorkingSet 加总，属于工作集估计；不能当作同时运行时的独占物理内存，更不能直接证明总内存多 74%。保留原始测量，补充 Linux PSS/USS、Windows 私有内存及各自工作集，明确不同指标不直接等价。
- Linux 一次性助手 2.1–3.1 秒超过 2 秒门槛，这是实测问题。密码派生与进程启动分别计时；Windows 含密码的调用也超过 2 秒，不以削减 PBKDF2 次数通过门槛。
- 常驻请求 p50 12–25 ms 达到既定 p50 门槛；会话 p95 54.1 ms 保留，不能把 p50 达标说成所有请求都小于 50 ms。完整客户端延迟与多人排队未测。

**下一项交 Claude**：先补准确内存和重复测量，并按冷启动门槛未达标的规则评估方案 G；仅做隔离小原型，不先重写正式存储或约 1100 行业务。原生扩展下载已获用户授权，Codex 本轮没有下载或安装，Claude 按本任务核实并执行即可，不重复索要同一授权。

1. 保留当前 L1 与此前未提交文件，核实 `main` 基准、差异归属；单方写入，不提交推送。复用笔记本已安装的 Godot/pwsh，不改真实服务、`data/framework/`、正式客户端、防火墙、TUN、SSH 配置或系统包。
2. 同一设备至少三轮记录负载及测试进程范围，分开测启动/编译、PBKDF2、运行中 p50/p95。同时保持两个 worker 运行再采样 Linux `/proc/<pid>/smaps_rollup` 的 RSS/PSS/私有页，记录退出后情况；Windows 对照记录 WorkingSet/PrivateMemory。若权限或指标不可用，标为未测，不用两个孤立采样之和冒充独占内存。完整宿主门槛留待 L3，不为测量提前跨入进程重构。
3. 原型候选为 [godot-sqlite](https://github.com/2shady4u/godot-sqlite)：维护者文档列有 Windows/Linux 和参数绑定 API。下载时核实固定版本、来源、许可、附件哈希及 Godot 4.7.2 的实际加载；仅放项目和 Linux `~/roomkit/` 内的隔离原型目录，不自动接入主工程/构建/客户端，不声明尚未测试的版本兼容性。若无法取得可核验附件，报告阻塞，不另装编译器或新增后端运行时。
4. 原型复用新生成的假库，验证参数绑定与 Unicode、`BEGIN IMMEDIATE`/提交/回滚、购买 request_id 重放及冲突、余额版本校验、锁等待、崩溃后重新打开、实际 SQLite 备份恢复途径。每个连接串行使用；原型应说明数据库工作如何避开 Godot 主线程，不能用主线程卡顿换取低单次延迟。扩展或 SQL 原始错误不得泄露参数和凭据。
5. 原生库原型与 pwsh 使用同样的假数据和负载对照冷启动、运行中 p50/p95、锁等待及进程内存。Godot 总内存减去同配置空进程基线，区别新增开销与总量。密码逻辑继续使用现有实现；PBKDF2 全量迁移、删除/结算/备份语义迁移成本只列清单，不做完整账号重写。扩展不提供所需可靠备份或线程支持时如实记录，不用 JSON 导出替代 SQLite 备份验收。
6. 修正测试库复制后的权限：包括外来库、导入/恢复副本和导出库；验证创建后及复制后权限，失败时明确拒绝继续使用。只处理此次隔离假库，不改真实备份。补充源归档解压失败、摘要失败等基础步骤的汇总失败注入，保留已有 unit 平台失败。
7. 交付一个简短 P/G 对照表、可执行命令、退出码、证据、迁移成本和建议；更新本节/STATUS/环境记录。未获得实际原型结果前，不承诺内存降低比例、不切换生产后端、不进入 L2/L3。若 G 的收益不足以抵偿迁移成本，可保留已验证的 P 方案，并写明小服务器的实际资源需求。

## 当前交接：Linux 安装验证复核与 L1 存储切片（Codex，2026-09-30）

已核对 Claude 的原始输出 `logs/linux-setup/run-20260930121157-ab0563.txt`、安装脚本、便携驱动和生产构建文件清单。本轮没有连接 Linux、重新安装或重跑 Linux 测试；Linux 结论来自交付证据。Codex 在 Windows PowerShell 5.1 重跑便携驱动，11/0、not_run=0、退出 0，两个工程摘要与 Linux 输出一致；证据在 `logs/linux-review-11dcba4d4c3a466a91b6015380006c6f/windows-digest.txt`。安装脚本 `bash -n` 退出 0，仅证明语法。Linux 单元测试 292/1 保留为失败，完整服务器仍未通过。

**复核发现**：`tools/linux_isolated_setup.sh` 打印各测试的退出码，却没有汇总成脚本退出码；测试失败后也会到达 COMPLETE 标记并返回 0。此次汇报明确保留了失败，没有把它说成全通过，但后续自动化不能用这个退出码判断验收。

**交给 Claude 的下一任务单**（主要实现与测试；完成后交 Codex 复核，暂不提交推送）：

1. 先核实 `main` 的 HEAD 与未提交文件，基准目前为 `c96e848`。保留本轮安装验证的五个文件及 Codex 文档补充；同目录实行单方写入。远端未同步，不用旧 origin/main 代替本地源码。Linux 已有 Godot 和 pwsh，复用其明确版本目录，不重新安装。改动源码传到新的隔离目录，记录完整提交号、补丁清单和传输哈希，不能把未提交修改称为原提交内容。
2. 先修测试驱动的汇总：摘要或任一测试失败、超时或出现脚本错误，都应留下逐项结果并使整体返回非零；COMPLETE 只表示执行结束。已知 `UNSUPPORTED_PLATFORM` 单独注明，不能改成通过。用轻量的失败注入检查退出码，无需为此重装依赖或重复所有 Godot 测试。
3. 存储范围只到共用 SQLite 绑定、平台路径/编码和隔离验证驱动。Windows 保持 PowerShell 5.1 + `winsqlite3.dll`，Linux 使用已安装的 pwsh + `libsqlite3.so.0`；账号和资产继续共用同一套 SQL、事务及业务规则。`account_store.ps1` 当前从资产脚本提取绑定，修改时同步核对该入口。不能只替换库名就声称完成；验证数据库路径、参数绑定、文本编码和备份句柄在两端的实际行为。
4. 在 Windows 与 Linux 的全新假数据目录对照：管理员初始化、邀请码注册、登录、会话校验、错误密码拒绝；资产购买/选择、重复请求仅扣一次、内容冲突拒绝、回执和余额一致；SQLite 备份、恢复和重新打开。增加中文与空格路径、Unicode 资产文本。双方交换的只允许是新生成的测试库，验证双向打开和登录；固定测试盐及迭代数对照 PBKDF2 结果，保持既有密码规则与安全成本。
5. 敏感请求继续走 stdin 或进程内对象，不退回密码/会话/密钥临时文件或命令行；Linux 测试目录及数据库设置仅当前用户可访问的权限，不用 sudo。重跑 Windows 受影响的账号、资产、结算、删除与备份专项；按改动依赖选择，不为最小切片重复全部房间容量测试。记录单次调用、注册/登录耗时及实际内存，区分冷启动与运行中数据，不承诺尚未测得的性能。
6. 不实现 Linux Godot 仓储接入、常驻进程管理、Operator、完整服务器或开房；不移除房间管理器的平台限制。现有 worker 如用于直接存储验证，必须隔离启动并正常收尾，不能绕过进程身份检查启用生产常驻服务。不动真实服务、`data/framework/`、正式客户端、旧附件、防火墙、TUN、系统配置或 SSH 密钥，不增加后端运行时。依赖缺失或平台测试失败时记录具体边界，不扩大范围。更新本节、环境记录与 STATUS，交付差异、命令、退出码、证据和未运行项。

本任务单是下一阶段安排，不表示存储切片或 Linux 完整服务器已经实现。SSH 继续密码登录，需要用户输入时集中给出命令，不重复请求已经授权的依赖安装。

### L1 存储切片结果（Claude，2026-09-30，未提交，待 Codex 复核）

**范围**：
- 只到共用 SQLite 绑定、平台路径和编码，以及隔离验证驱动。
- 没有实现 Linux 上的 Godot 仓储接入、进程管理、Operator 或完整服务器；房间管理器的平台限制没有动。
- 没有安装或下载任何东西，没有用 sudo，没有改防火墙，没有动真实服务、`data/framework/` 和正式客户端，没有提交推送。

**1. 测试驱动汇总（已修）**
- 新增 `tools/linux_test_lib.sh`：逐步记录结果；任何一步失败、超时，或者退出码为 0 但输出里有 `SCRIPT ERROR`，整体都返回非零。已知的 `UNSUPPORTED_PLATFORM` 只加标注，仍算失败。`COMPLETE` 只表示执行到了末尾。
- `tools/linux_isolated_setup.sh` 已改用它。这个脚本改完后没有在设备上重跑，按要求不为此重复全部 Godot 测试。
- 失败注入自测 `tests/linux_test_lib_selftest.sh`：注入失败命令、超时、隐藏的脚本错误、已知限制，以及“失败后后续步骤仍要执行”。Windows Git Bash 上 6/0，Linux 实机上 6/0。

**2. 存储改动**（只改了 `tools/sqlite_store.ps1` 和 `tools/account_store.ps1`）
- **SQLite 绑定**：
  - C# 源码仍留在 `sqlite_store.ps1` 的原位置。账号脚本、维护脚本和十几个测试夹具都靠正则从这里提取，所以提取入口不变。
  - Windows 继续用 `winsqlite3.dll`。在其他系统上，类的静态构造函数会注册一个解析器，把同一个导入名指向系统的 `libsqlite3.so.0`。解析器 API 只存在于新版 .NET，所以通过反射调用，这样源码在 PowerShell 5.1 下仍能编译。
  - SQL、事务、`busy_timeout`、WAL 和 `synchronous=FULL` 都没有改动。
- **备份路径**：目标路径检查改用平台分隔符；文件名只在 Windows 上不区分大小写。
- **JSON 解析**：PowerShell 7 默认把像日期的字符串转成 DateTime，5.1 不会。不处理的话，昵称等字段写成日期样子时，两个平台的行为会不同。两个脚本都加了 `ParseJson`，在 7 上带 `-DateKind String`，两边都保持为文本。
- **密码派生**：.NET 10 把 `Rfc2898DeriveBytes` 的构造函数标为过时，.NET Framework 又没有静态的 `Pbkdf2`。改为运行时选择可用的入口，不产生编译期引用。算法仍是 PBKDF2-HMAC-SHA256，密码按 UTF-8，60 万次，输出 32 字节；存储格式不变。
- **敏感数据**：请求仍然只走 stdin 或进程内对象，没有新增密码、会话或密钥的临时文件和命令行参数。

**3. 隔离对照**
- **驱动**：`tests/storage_slice_portable.ps1`，同一份脚本在 Windows PowerShell 5.1 和 Linux PowerShell 7.6.6 上运行。它直接调用生产用的存储脚本，不经过 Godot；用的是全新的假数据目录，目录名带中文和空格。

| 项目 | Windows | Linux |
|---|---|---|
| 运行时 | PowerShell 5.1，.NET Framework 4.8 | PowerShell 7.6.6，.NET 10.0.12 |
| SQLite | `winsqlite3.dll` 3.51.1 | `libsqlite3.so.0` 3.45.1 |
| 驱动结果 | 49/0（权限和对方库 2 项未运行）；带 Linux 库时 57/0（权限 1 项未运行） | 58/0，未运行 0 |
| 退出码 | 0 | 0（汇总 4 步，失败 0） |

- **两边都通过的内容**：
  - 绑定：参数绑定能原样往返中文、emoji、引号和像 SQL 的文本；SQLite 按字符计数正确；中文加空格的路径能打开；备份句柄写出的副本能重新打开并通过完整性检查。
  - 密码：PBKDF2 对固定盐和含中文的固定测试口令，结果与 Node 独立算出的已知答案逐字节相同。
  - 账号：管理员初始化，重复初始化被拒；邀请码注册，重复用户名、无效邀请码、用完的邀请码被拒；错误密码被拒；登录、会话校验；已有会话时再次登录被拒；日期样子的昵称保持为文本；输出是纯 ASCII 的 JSON。
  - 资产：发放、购买扣款；同一请求重复提交时返回原回执且只扣一次；同一请求号但内容不同被拒；基于旧版本的提交被拒；跳版本被拒；选择装备；快照和回执；三条回执记录；中文命令文本原样保留；完整性检查通过。
  - 备份恢复：资产和账号备份；拒绝覆盖已有文件，拒绝写到数据库目录之外；备份后修改状态，再恢复并重新打开，余额和会话都回到备份时的状态。
  - 常驻工作进程：隔离启动后，资产读取 30 次、会话校验 20 次全部成功；关闭输入后自行退出，退出码 0；结束后没有残留进程。
- **Linux 权限**：测试目录是 700，数据库和备份是 600。
- **双向互开**（交换的只有本驱动新生成的测试库）：
  - Windows 生成的库在 Linux 上通过完整性检查，能用原口令登录，昵称、余额和中文回执一致，能继续提交，旧的购买请求仍然幂等；
  - Linux 生成的库在 Windows 上同样全部通过。Linux 库通过 ssh 输出带回，两端哈希一致。
- **构建摘要**：在新的源码快照上重跑便携驱动，11/0，射击 `de37edca7f1d`、取石子 `772421bf94d2`，没有变化，因为存储脚本不在构建输入里。

**4. 源码与证据**
- Linux 源码目录是 `~/roomkit/src/c96e848b7b21-worktree-1b02768baf5e/`，内容是本地提交 `c96e848` 加未提交改动的工作区快照，不是原提交本身。
  - 快照的 Git 树是 `1b02768b…`，共 366 个文件，全部 LF，传输包 SHA256 是 `b06b67ad…a11c93`。
  - 相对提交的改动清单在 `logs/l1-storage-linux/bundle-20260930124548-a50b91-manifest.json`。
  - 上一次的原提交目录没有动。
- Linux 原始输出：`logs/l1-storage-linux/run-20260930124548-a50b91.txt`；设备上的输出在 `~/roomkit/runs/20260930124548-a50b91/`。
- Windows 输出：`logs/l1-storage-windows/slice-final.txt`，带 Linux 库的那次是 `slice-foreign-860e11.txt`；各回归的日志在同一目录。
- Linux 运行命令（由用户输入密码执行一次）：把 `logs/l1-storage-linux/bundle-…tar` 通过 ssh 管道传入，解压到 `~/roomkit/incoming/<运行编号>/` 后执行 `run.sh`。

**5. Windows 回归**（都在存储脚本改动之后运行，全部退出 0）

| 测试 | 结果 |
|---|---|
| `run_assets` | 83/0 |
| `run_accounts` | 85/0 |
| `run_asset_snapshot` | 40/0 |
| `run_result_rewards`（结算） | 74/0 |
| `run_grant_storage` | 24/0 |
| `run_resident_store` | 34/0 |
| `run_account_deletion` | 83/0 |
| `test_operator_maintenance.ps1`（备份恢复） | 35/0 |
| `run_account_recovery` | 30/0 |

**6. 耗时和内存**（各平台单次运行。Linux 设备是 i5-5200U，上面还有其他程序在跑，所以这些数字只是这台设备的实测，不代表目标云服务器）

| 项目 | Windows（PS 5.1） | Linux（PS 7.6.6） |
|---|---|---|
| 一次性调用，不含密码（初始化、提交、会话校验、备份） | 0.53–0.76 秒 | 2.1–2.4 秒 |
| 一次性调用，含密码派生（注册、登录） | 2.6–2.7 秒 | 2.2–3.1 秒 |
| PBKDF2 60 万次（进程内） | 约 1.9 秒 | 约 0.49 秒 |
| 常驻进程首次应答（冷启动） | 0.53 / 0.75 秒 | 2.3 / 2.4 秒 |
| 常驻进程运行中，资产读取 | 中位 10.5 ms，p95 11.2 ms | 中位 12.1 ms，p95 29.3 ms |
| 常驻进程运行中，会话校验 | 中位 15.2 ms，p95 44 ms | 中位 25.3 ms，p95 54.1 ms |
| 常驻进程内存（资产 / 账号） | 113 / 144 MB | 207 / 241 MB |

以下为 Claude 的初步对照；完整服务内存门槛的口径修正见本节顶部 Codex 复核：
- **达标**：常驻请求中位数不超过 50 ms。
- **不达标**：
  - 一次性调用不超过 2 秒：Linux 是 2.1–3.1 秒，其中约 2 秒是 pwsh 启动和编译绑定的冷启动开销；
  - 存储 worker 工作集估计：两份独立采样加总 448 MB，Windows 是 257 MB，差约 74%；不是完整服务或独占内存的测量，原定完整服务内存门槛尚未验证。
- 冷启动门槛未达到，需要评估方案 G（把 SQLite 放进 Godot 进程）；完整服务内存门槛仍未测。本轮没有做任何优化，也不承诺优化后的数字；Codex 建议补测并做隔离小原型，详见顶部任务单。

**7. 发现的问题和已知差异**
- **权限**：.NET 的 `File.Copy` 会保留源文件的权限位。运行结束后，测试目录里有 2 个文件不是仅属主可访问，就是带过去的 Windows 测试库的副本。以后在 Linux 上做恢复或导入时，必须显式设置权限，不能只靠 umask。
- **存储文本的字节差异**（语义相同）：
  - PowerShell 5.1 的 `ConvertTo-Json` 会把 `'`、`<`、`>`、`&` 转义成 `\u00XX`，7 不会；
  - 普通哈希表的属性顺序在两种运行时下可能不同。
  - 影响的是审计前后值、奖励命令这类由脚本自己生成的 JSON 文本；解析后的内容一致，双向互开测试通过。
  - 客户端提交的资产正文是原样存储的，不受影响。
- **SQLite 版本不同**（3.51.1 和 3.45.1）：目前用到的功能在两边都可用，双向互开通过。以后如果用到新版本才有的特性，要重新核对。

**未运行 / 未验证**：
- Linux 上通过 Godot 调用存储（`bounded_helper`、`resident_store.gd`）；结算、账号删除、维护脚本的备份恢复（`operator_maintenance.ps1` 仍含 Windows ACL）；进程管理、Operator、房间和联机。
- 并发写入和长时间运行。
- 独立包没有重新构建。存储脚本仍在它的文件清单里，文件名没有变。
- `linux_isolated_setup.sh` 改完汇总后没有在设备上重跑。

**下一步建议**：先由 Codex 和用户就第 6 点的两项不达标做决定，再进入 L2（进程与运维）或方案 G 评估。

## 已授权下一步：Claude 安装 Linux 测试依赖并隔离验证（2026-09-30）

用户已明确同意：Codex 整理本地提交、不推送；Claude 在 `zhao@192.168.10.105` 的 `~/roomkit/` 内安装官方 Godot、PowerShell 7、放入该本地提交的源码并运行隔离测试。SSH 保留密码登录，需要时由用户输入；不配置 authorized_keys、不使用 sudo、不改防火墙、不复制真实数据库。本节替代前面“只读/等待安装同意”的当前执行限制，历史记录保留。

Claude 接手执行：

1. 核实交接的本地 HEAD、工作区及已完成的设备检查。不重做已知调查；仅补查 Node 是否已有、系统 SQLite 版本等必要缺项。严格保留 SSH 主机校验，不输出密码，不扫旧项目。
2. 从官方发布页核实 Godot 4.7.2 stable Linux x86_64 与 PowerShell 7 当前 LTS 的准确版本、文件名、大小和校验材料，下载后校验。若指定 Godot 发布或匹配校验材料不可取得，记录阻塞，不能悄悄换版本；PowerShell 不使用预览版。只写 `~/roomkit/tools/` 下独立版本目录，不覆盖现有同名内容；不改全局 PATH/登录配置、不安装导出模板或 Node。若系统依赖实际缺失，报告而非使用 sudo。
3. 源码必须来自本次本地提交：远端尚未推送，不能 clone 远端后假称拿到最新版。使用该提交的 git archive 或等效明确文件清单，传入 `~/roomkit/src/<完整提交号>/`，记录提交号及传输包 SHA256；排除真实运行数据、私钥、凭据、旧 artifacts、logs、PlayerClient。输出及测试库写独立测试目录，不覆盖历史结果。
4. 先验证引擎/pwsh 版本，然后实跑 PowerShell 摘要的便携合成夹具，复现 `05f794ef76f0`。原测试脚本依赖 Windows 构建时，只做必要的便携测试驱动，不删断言、不修改生产算法以迎合结果。有 Node 才做独立参考对照，不为参考测试另装 Node。真实 prepared game 摘要需比较相同输入，不拿仓库根目录冒充。
5. 按兼容范围运行纯 GDScript 测试，按测试实际参数设置独立目录；Windows 专用测试不能假装在 Linux 通过。记录命令、版本、退出码、断言计数、错误输出与未运行项。出现缺少 Windows 助手等预期平台阻塞时定位到边界并停止该项，不扩大成全量存储/进程重构。
6. 本次仅依赖安装、源码复制、摘要及纯逻辑验证。账号存储最小切片、进程管理实现、常驻服务、自启动、防火墙和跨机联机留到下一任务。不重启 Windows 真实服务，不重新生成任何正式客户端，不推送或发布。
7. 交付依赖位置、源码提交、摘要对照、测试报告和下一次最小实现任务；更新现有环境记录、STATUS 和本节。需要密码时给用户一组清晰命令或让用户接手，避免每条检查单独要求输入。Codex 复核后再推进 L1 存储切片。

### 安装与隔离验证结果（Claude，2026-09-30，未提交，待 Codex 复核）

**边界**：
- 只写了笔记本的 `~/roomkit/`。
- 没有用 sudo，没有改 PATH、登录配置或防火墙，没有配置 authorized_keys，没有常驻服务，没有复制真实数据。
- SSH 保持主机校验和密码登录，密码由用户输入。
- Windows 上的真实服务和所有正式客户端都没有动，没有推送。

**过程**：
1. 从官方发布页核实了版本、文件名、大小和校验材料：
   - Godot 是 `4.7.2-stable` 的 `Godot_v4.7.2-stable_linux.x86_64.zip`（77,860,424 字节，官方 `SHA512-SUMS.txt`）；
   - PowerShell 是 `v7.6.6` 的 `powershell-7.6.6-linux-x64.tar.gz`（75,876,271 字节，官方 `hashes.sha256`）；
   - 官方 `tools/metadata.json` 把 v7.6.6 同时列为 Stable 和 LTS，不是预览版。
2. 第一次运行时，笔记本连不上 GitHub（curl 连接超时、0 字节），脚本停在下载这一步，没有安装任何东西。随后用户在笔记本的浏览器里从同样的官方地址下载，脚本把文件复制到 `~/roomkit/downloads/`，哈希与官方值一致后才安装。
3. 源码来自本地提交 `c96e848b7b216ec1273edf77cca9e94155fe6e11`，用的是 `git -c core.autocrlf=false archive`，也就是提交里存储的 LF 形式，相当于 Linux 上的检出。共 360 个文件，传输包 SHA256 是 `df5b6e8b…3e6f89`，两端一致；里面没有数据、日志、artifacts、PlayerClient、密钥或连接配置。

**安装位置**（细节见 [环境记录](10_environment.md#linux-测试机依赖安装2026-09-30claude)）：
- `~/roomkit/tools/godot/4.7.2-stable/`，版本 `4.7.2.stable.official.ed1daf0bf`；
- `~/roomkit/tools/pwsh/7.6.6/`，7.6.6 Core，.NET 10.0.12；
- `~/roomkit/src/<提交号>/`。

合计 485 MB。

**摘要对照**（Linux 实机，由 `pwsh` 实际运行提交里的生产脚本 `tools/content_digest.ps1`；驱动是 `tests/content_digest_portable.ps1`）：

| 项目 | Windows（PowerShell 5.1） | Linux（PowerShell 7.6.6） |
|---|---|---|
| 合成夹具基准值 | `05f794ef76f0` | `05f794ef76f0` |
| 射击工程（同一提交、同一份源文件清单） | `de37edca7f1d`（49 个文件含 CRLF） | `de37edca7f1d`（0 个文件含 CRLF） |
| 取石子工程 | `772421bf94d2`（46 个文件含 CRLF） | `772421bf94d2`（0 个文件含 CRLF） |
| 驱动结果 | 11/0 | 11/0，退出 0 |

- 驱动覆盖：LF、CRLF、混合、反序四种形式；`.godot` 缓存；代码和二进制变化；二进制里的 CR LF；路径分隔符。
- 两个工程树在 Linux 上是用驱动里的明确源文件清单组装的，清单与 `build_framework.ps1` 复制的文件相同；没有用仓库根目录冒充。
- 笔记本自带 Node v18.19.1，独立参考实现在 LF 夹具上也得到 `05f794ef76f0`。它只作旁证。
- 结论：构建摘要在 Windows 的 CRLF 检出和 Linux 的 LF 检出之间一致，已有实机证据。范围只到摘要算法；`build_framework.ps1` 本身还不能在 Linux 上运行。

**纯 GDScript 测试**（Linux headless，Godot 4.7.2；每项的输出和引擎日志都在笔记本的 `~/roomkit/runs/20260930121157-ab0563/`）：

| 测试 | Linux | Windows 参考 | 说明 |
|---|---|---|---|
| `run_shooter` | 83/0，退出 0 | 83/0 | 一致 |
| `run_framework_feedback` | 7/0，退出 0 | 7/0 | 一致 |
| `run_client_sound` | 41/0，退出 0 | 41/0 | 一致 |
| `run_room_disappear_regression` | 16/0，退出 0 | 16/0 | 一致 |
| `run_managed_contracts` | 286/0，退出 0 | 286/0 | 一致 |
| `run_unit` | 292/1，退出 1 | 320/0 | 不通过，是预期中的平台边界 |

- `run_unit` 唯一的失败是 `tests/test_manager.gd:34` 的 “sim manager initialized”：`room_manager.gd` 在非 Windows 平台直接返回 `UNSUPPORTED_PLATFORM`。这套测试之后的约 28 项检查因此没有执行，不能算通过。按任务要求，定位到这个边界后就停止了，没有改代码。
- 所有测试的脚本错误和引擎错误都是 0 条；结束后没有残留的 Godot 或 pwsh 进程。
- 测试在源码目录的 `run/` 下生成了 2 个文件。

**未运行 / 未验证**：
- 账号和资产存储、进程管理、Operator、宿主、房间、跨机联机，全部没有在 Linux 上运行。
- `build_framework.ps1`、`test_content_digest.ps1`、`test_player_client.ps1` 等含 Windows 路径的脚本没有运行。
- 没有安装导出模板，没有读取或修改 ufw 规则。

**本轮新增文件**（未提交）：`tests/content_digest_portable.ps1`（便携摘要驱动）、`tools/linux_isolated_setup.sh`（安装和隔离测试脚本）。

**下一次最小实现任务**（L1.2–L1.4，Codex 复核后再做）：
1. `sqlite_store.ps1` 的 SQLite 绑定按平台选库名（Linux 用 `libsqlite3.so.0`，已确认存在，版本 3.45.1；Windows 保持 `winsqlite3.dll`），路径判断改用平台分隔符。Windows 分支的行为不变，并重跑 Windows 存储专项。
2. 在笔记本的隔离测试库上，用 `pwsh` 直接调用存储助手，跑注册、登录、会话校验、资产读取、同一操作编号重复提交、备份恢复；结果与 Windows 逐项对照。要注意 Windows 上是 PowerShell 5.1 / .NET Framework，Linux 上是 7.6 / .NET 10，两种方言的差异在这一步暴露。
3. 固定密码和盐，对照 PBKDF2 结果；两个平台生成的测试库互相打开并做完整性检查。
4. 这一步不涉及进程管理，`room_manager.gd` 的平台限制留给 L2。笔记本不能直接访问 GitHub，后续需要的文件都要经局域网传过去，或者由用户在浏览器里下载。

## 当前交接：Claude 执行 Linux 只读设备检查（2026-09-30）

Codex 已阅读摘要实现和独立 Node 参考，独立执行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/test_content_digest.ps1`，55/0、not_run=0、退出 0，基准值 `05f794ef76f0`；证据 `logs/content-digest-73efe55342f347f8adc1c2b1f33b34b5/`。本机复核未发现阻塞问题，但 Linux 实机一致性仍未验证。用户明确 Linux 检查与测试交 Claude。

### 现在执行的范围

1. 先核实本仓库分支、HEAD 和未提交文件，读 AGENTS、STATUS、本节与 `tools/linux_device_check.sh`。保留所有现有成果，不提交推送、不改真实服务和客户端。
2. 仅对已指定设备 `zhao@192.168.10.105` 执行只读检查脚本，使用 SSH 标准主机身份校验，不关闭校验、不打印或保存密码。能用现有认证就继续；若需用户输入密码或确认未知主机身份，提供准确命令让用户接手，不尝试猜密码。不扫描设备上的旧项目。
3. 将脱敏输出保存在本仓库 logs 的独立文件；在现有环境文档和 STATUS 摘要记录系统架构、资源、现有 Godot/pwsh/SQLite 及缺项。完成标记不等于所有检查通过；逐项区分不可用、权限不足和成功。
4. 本次不下载、不安装、不复制项目或数据库、不改防火墙。按实机结果给下一次最小依赖安装清单：具体版本、官方来源、校验方法、用户目录和磁盘预算；不要未看架构就预定 x64。无需再泛泛讨论全框架换语言。
5. 若已有 Node/pwsh，也先报告可用性。摘要实际对照还需传入同一份干净构建输入；不能直接以仓库根目录摘要对比 prepared game 摘要。后续用隔离合成夹具和明确源文件清单验证，生产 PowerShell 摘要必须实跑，Node 参考单独通过不能替代它。当前完整测试脚本含 Windows 路径及构建调用，不能原样在 Linux 失败后删除断言；另做最小便携驱动或先适配测试入口。

交付只需设备事实、缺项和下一次具体任务。随后由 Codex 复核依赖与进程安全方案，再让 Claude 做 L1。此前“本轮不连接设备”的 L0 限制仅属于已完成的准备阶段，本次可做上述只读检查；安装和远程写入仍不在本任务内。

### 设备检查结果（Claude，2026-09-30，未提交，待 Codex 复核）

**过程**：
- 这台 Windows 电脑原先没有保存该设备的主机身份。我用批处理模式连接，被主机校验拒绝；没有关闭校验，也没有替用户接受指纹。
- 用户本人确认指纹、输入密码后运行了脚本，输出末尾有完成标记。
- 原始输出在 `logs/linux-device-check/check-20260930.txt`。里面只有局域网地址，没有密码、MAC 地址或主目录内容。
- 没有安装、写入或复制任何东西，也没有读取防火墙规则（需要 root）。

**设备事实**（逐项状态见 [环境记录](10_environment.md#linux-测试机只读检查2026-09-30claude)）：
- 系统：Linux Mint 22.3（基于 Ubuntu），内核 7.0.0-34，glibc 2.39，**x86_64**。
- 资源：i5-5200U，2 核 4 线程；内存 7.7 GB，可用约 5.3 GB；磁盘可用 378 GB。
- 已有：`libsqlite3.so.0`、libicu 74、libssl 3、git、curl、wget、tar、unzip、python3、sha256sum；内核支持 pidfd，`/proc` 可读。
- 没有：Godot、导出模板、PowerShell 7、dotnet（不需要）。
- 未知：Node（脚本没有检查）、SQLite 的具体版本、ufw 的规则。
- 需要留意：
  - ufw 在运行，跨机联调时要放行端口，这一步需要 sudo；
  - 网络是无线网卡；
  - Linger 为 no，用户退出登录后用户级服务会停止；
  - 打开文件数上限是 1024；
  - 检查时负载约 1.9、交换分区已用约 0.9 GB，说明设备上有其他程序在运行，测量内存和延迟时要先记录基线。

**下一次最小安装清单**（都需要用户同意；全部放在用户目录，不需要 sudo，不装系统包）：

| 依赖 | 版本与文件 | 官方来源 | 校验方法 | 位置 | 磁盘预算 |
|---|---|---|---|---|---|
| Godot 编辑器二进制 | 4.7.2 stable，linux x86_64 | godotengine/godot 的 GitHub Release `4.7.2-stable` | 用该 Release 附带的 SHA512 校验文件核对；`--version` 应显示 `4.7.2.stable.official.ed1daf0bf` | `~/roomkit/tools/godot/` | 约 0.2 GB（估计） |
| PowerShell 7 | 当前 LTS 的 `linux-x64.tar.gz`；具体版本号以官方发布页为准，我没有联网核实 | PowerShell/PowerShell 的 GitHub Release | 用 Release 页公布的 SHA256 核对；`pwsh --version` | `~/roomkit/tools/pwsh/` | 约 0.2 GB（估计） |
| 项目源码 | 一个已提交的版本 | 本仓库（`git archive` 或克隆） | 与 Windows 端对比提交号 | `~/roomkit/src/` | 小于 0.1 GB |

- 合计预算小于 1 GB，设备可用 378 GB。
- 系统已有 `libsqlite3.so.0`、libicu 和 libssl，所以不需要 sudo。
- 导出模板到 L4 才需要；防火墙放行到跨机联调时才需要。
- 两个文件名、大小和哈希要在下载时对照官方页面；上表的磁盘预算是估计值。

**下一次具体任务**（建议顺序）：
1. **先提交**：Codex 把现有成果提交。源码副本必须来自一个确定的提交，否则设备上的摘要无法与 Windows 对照。
2. **补一条只读检查**：确认 Node 是否存在。
   ```
   ssh zhao@192.168.10.105 "command -v node && node --version"
   ```
3. **安装**（需用户同意）：把 Godot 和 pwsh 下载到上表的目录，校验哈希后解压，不改 PATH，不改系统。
4. **摘要实机对照**：写一个最小的便携驱动，不复用含 Windows 路径的完整测试脚本。
   - 驱动在设备上生成与 Windows 相同的合成夹具，用 `pwsh` 实际运行生产用的 `tools/content_digest.ps1`，结果要等于基准值 `05f794ef76f0`；
   - 再对同一份干净的构建输入（明确的源文件清单）比较两个平台的摘要；
   - Node 参考实现只作旁证，不能代替 PowerShell 的实跑。
5. **Godot headless**：在设备上跑纯 GDScript 测试（`run_shooter`、`run_client_sound`、`run_room_disappear_regression`）；`run_unit` 中依赖 PowerShell 的部分逐项记录。
6. 之后按 L1.2 及以后的小任务推进。

## 当前交接：先修跨平台构建身份（Codex 复核 L0，2026-09-30）

L0 文件与脚本已复核。只读检查脚本去掉了对整个 HOME 的 find，改为只查 PATH 和约定 RoomKit 工具目录；`bash -n` 退出 0，仅为语法验证，未连接 Linux。完成标记只说明脚本跑到末尾，不代表每项检测成功。进程安全方案仍有条件：锁必须覆盖所有回收路径，包括引擎内部；不能仅锁住项目自己的检查/kill 调用就断言 PID 不会复用，实施前须验证完整生命周期或采用稳定句柄机制。

下一项交 Claude：仅修构建摘要的跨平台确定性，先不安装 Linux 依赖。读取 `tools/content_digest.ps1`、`tools/build_framework.ps1`、`.gitattributes` 和已有客户端测试，保留当前未提交成果。当前摘要按原始字节算哈希，且 `.godot` 排除模式只匹配反斜杠，`Sort-Object -CaseSensitive` 也不能直接当作跨平台序数排序保证。

- 定义并记录规范化规则：相对路径统一 `/`，目录排除在两种分隔符下等价，使用明确序数排序；文本与二进制分别处理。可通过明确文本文件规则规范化换行，或先生成规范化构建树再哈希；禁止把二进制当文本处理、忽略真实代码或 Schema 的改变。不要为消除差异跳过版本校验。
- 独立夹具覆盖 LF/CRLF、相同文本不同检出形式、路径与枚举顺序、`.godot` 缓存、实际代码修改、二进制修改；相同逻辑输入摘要一致，实际内容变化必须改变摘要。Linux 实机还没跑时，不能把本机模拟称为跨平台验证通过。
- 修改只限摘要/构建相关、必要 Git 文本属性、针对性测试及文档。不重写整个工作区换行、不覆盖 PlayerClient/仓库客户端/旧附件、不操作真实服务。新摘要可能改变 build_id，交付新版重启重导步骤，保留旧产物与清晰版本状态。
- 完成后交 Codex 复核，暂不提交推送；届时再一起整理前序 UI/音效/入房修复与本次摘要成果的提交。设备只读检查可随后执行，安装与平台实现独立安排。

### 构建身份修复结果（Claude，2026-09-30，未提交，待 Codex 复核）

只改了 `tools/content_digest.ps1`，新增 `tests/test_content_digest.ps1` 和独立参考实现 `tests/content_digest_reference.cjs`。没有重写工作区换行，没有再改 `.gitattributes`（上一轮的 `*.sh` 一行保留），没有动真实服务、共享游戏索引、PlayerClient、仓库客户端副本和旧附件。版本校验没有放宽。

**规范化规则**（版本标记 `roomkit-content-digest-v2`，写在摘要文件头部，由测试固定）：
1. **范围**：根目录下所有文件都参与，只排除两类：接收结果的两份清单（`game_manifest.json`、`game/game_manifest.json`），以及名字恰好是 `.godot` 的目录里的内容（引擎缓存）。目录排除按路径段判断，`\` 和 `/` 两种分隔符等价；`project.godot`、`a.godot/`、`.godotx/` 不会被误排除。
2. **路径**：相对路径一律用 `/`，文件名大小写保持原样。
3. **文本**：只有扩展名在固定列表里、且不含 NUL 字节的文件算文本。列表是 `.gd .json .godot .tscn .tres .cfg .md .txt .gdshader .csv .svg`。只对文本把 CR LF 替换成 LF，按字节处理，不解码。单独的 CR、行尾空格、BOM、文件末尾有没有换行，都算内容。
4. **二进制**：其余文件都按原始字节计算哈希，包括未知扩展名和含 NUL 的“文本名”文件。
5. **排序与输出**：条目格式是 `路径=SHA256`，按序数排序（UTF-16 码元，`StringComparer.Ordinal`，不受区域设置影响）；版本行加各条目用 LF 连接，以 UTF-8 编码计算 SHA256，取前 12 位小写十六进制。

**验证**（`tests/test_content_digest.ps1`，55/0，退出 0，证据在 `logs/content-digest-6bc91f4c342f4b748c144d7fe63ac34f/`）：
- **相同输入，摘要一致**：
  - 合成夹具的 LF、CRLF、逐文件混合、反序创建四种形式摘要相同，固定的基准值是 `05f794ef76f0`；
  - 条目枚举顺序打乱后结果不变；
  - 反斜杠路径和正斜杠路径得到相同的条目；
  - 排序结果是 `B.gd,Z.gd,a-b.gd,a.gd,a_b.gd,sub.gd,sub/z.gd`，确认是序数排序；
  - 摘要与按文档公式手工计算的结果相同。
- **独立实现**：Node 参考实现按规则另写，不是从 PowerShell 翻译的。它在 LF 和 CRLF 夹具上都得到相同摘要。
- **缓存和清单**：根目录和嵌套的 `.godot` 目录被忽略；两份清单被忽略；其他位置的同名清单文件算内容。
- **真实变化必须改变摘要**：游戏代码改一个字符、SDK、Schema、游戏配置、`project.godot`、行尾空格、单独的 CR、末尾换行、BOM、新增文件、删除文件、改名、只改大小写，全部改变摘要。
- **二进制不规范化**：二进制改一个字节会改变摘要；已知二进制和未知类型文件里的 CR LF 都算数据；文本名但含 NUL 的文件按二进制处理。
- **真实工程**：
  - 用当前工作区构建到私有索引，射击为 `shooter-dev-002-src-de37edca7f1d`，取石子为 `turns-managed-dev-001-src-772421bf94d2`；
  - 把准备好的工程分别转成纯 LF 和纯 CRLF 的副本（射击 65 个、取石子 63 个文本文件），摘要都不变，Node 参考实现结果一致；
  - 两个工程里目前没有按二进制处理的文件；
  - 共享游戏索引前后的哈希相同。
- **回归**：`tests/test_player_client.ps1` 28/0（`logs/player-client-eb36031d26794a1c85c6408cbde6dc80/`）。
  - build_id 与工程内容绑定，重复构建结果相同；
  - 双客户端入房、退房正常；
  - 改过代码的客户端得到不同的 build_id，仍被 BUILD_MISMATCH 拒绝；
  - 共享的公开配置和索引没有改动。

**边界和未验证项**：
- 以上都在这台 Windows 电脑上完成，属于对检出形式的模拟，**不是 Linux 实机验证**。
- 下一步要在 Linux 上跑：同一个提交检出后，摘要要与 Windows 相同；合成夹具要复现基准值 `05f794ef76f0`。可以用 `pwsh` 跑测试脚本，也可以只用 Node 参考实现。
- `tools/build_framework.ps1` 本身还用着反斜杠路径，Linux 上的构建入口属于后续平台实现，本轮没有改。
- 摘要只保证身份一致。导出的 `Client.pck` 字节仍会随换行和导出过程变化，配对依据是 build_id。

**版本状态**：

| 对象 | build_id | 说明 |
|---|---|---|
| 当前源码（新摘要规则） | `shooter-dev-002-src-de37edca7f1d` | 重启管理服务后生效 |
| 正在运行的服务、共享索引、用户的 `PlayerClient/` | `675fa4d8063e` | 旧规则算出的值，三者互相匹配，仍然可用，本轮未动 |
| 仓库副本 `clients/shooter-windows/`、Release 附件 | `0f559378dddc` | 早已过期，未动 |

**用户上线步骤**（任选时间；不做的话，现有服务和客户端照常工作）：
1. 在后台停止游戏服务器，运行 `StopManagement.cmd`，再运行 `StartManagement.cmd` 并启动游戏服务器。服务端的 build_id 会变成 `…de37edca7f1d`。
2. 运行 `PreparePlayerClient.cmd` 重新生成 PlayerClient。旧目录会自动移到 `artifacts/player-clients/previous/` 保留。发给朋友的客户端也要换成新版，旧版会被提示版本不匹配。
3. 进一次房间，确认正常。

## 后续开发安排（2026-09-30，以本节为当前顺序）

目标：Linux 跑完整后台与服务器，Windows 保留一键开发与玩家客户端；近期先服务 2–8 人熟人试玩，不新增玩法，不解决 Windows TUN 共存。Claude 负责主要实现和测试，Codex 负责方案与差异复核、验收整合。每阶段独立交付，上一阶段通过再推进；未实际运行的平台不能标为通过。

| 阶段 | 交付 | 通过条件 |
|---|---|---|
| L0 当前成果收尾与设备准备 | 明确 UI、音效、非回环入房修复的差异与证据，整理提交候选；Linux 只读检查命令与依赖清单 | 未提交文件归属明确，功能/真人反馈/未验证分开，设备未知项有准确检查方法 |
| L1 跨平台存储最小切片 | 优先验证 PowerShell 7 + 系统 SQLite 候选，仍维护一套存储语义 | 隔离库注册、登录、资产幂等、备份恢复通过；密码哈希及两平台库互读一致；实测延迟与内存 |
| L2 Linux 进程与运维适配 | 安全启动/停止、端口回收、权限、指标和启动脚本 | 正常退出、异常退出、超时回收、宿主重启均有证据；解决 PID 复用竞态，不能先检查再 kill 就宣称安全；Windows 回归不退化 |
| L3 完整服务器与一键入口 | Linux 启动后台、账号/资产服务、大厅、房间；Windows 客户端接入 | 隔离环境完成登录、建房、双客户端入房、结算到账、重启后数据保留；Windows 本机入口仍可用 |
| L4 用户验收与交付 | 一个服务端入口、匹配的 Windows 玩家目录、简短说明 | 先 Windows → Linux 局域网，再按需要公网外部设备验收；届时重新核对转发目标与证书，不沿用 Windows 已通过结论 |

### Claude 当前任务单：只完成 L0

- 目录本仓库，预期 `main` / `bf21fe0`，接手核实，保留全部未提交 UI、音效、入房修复及文档。先读 AGENTS、README、STATUS、本节和已有 Linux 调查；同目录单方写入，不覆盖他人工作。
- 检查现有差异，重点复核合法地址契约与保留席位撤销修复、日志是否泄密、客户端版本与已导出物的关系。复用有效测试证据，不再次全量跑数小时回归；发现具体问题再做对应验证。本任务不改功能。
- 在现有 STATUS/docs/17 内整理提交候选分组与最小剩余验收项：后台、音效、入房修复；明确源码、PlayerClient、仓库副本及 Release 状态不同。不提交或推送，不清理旧包/日志，不把用户暂停公网排查记为未修好房间生命周期。
- 准备 Linux 只读检查命令，目标仅 `zhao@192.168.10.105`：系统/架构、内存/磁盘、Godot、pwsh、libsqlite3、用户权限与防火墙概况；列出需要下载/安装的准确依赖、来源和预期用户目录。本轮先交检查脚本与清单，不连接设备、不安装、不复制真实数据库。
- 将 L1 写成可执行的小任务：优先验证方案 P，保留方案 G 为门槛不满足时的备选，不先重写存储。进程安全需单独明确可靠机制及验证方式，不把 Windows 句柄语义照搬 Linux。
- 交付简短汇报：当前可冻结哪些成果、具体缺项、下一次设备验证怎么运行。更新 STATUS，保留失败/未运行项；不继续扩充历史叙事。本轮不做 TUN、路由器、真实服务操作、Linux 功能实现或新玩法。

L0 交付后由 Codex 复核并整理现有成果的提交，再进入设备检查与 L1。依赖安装和真实数据迁移仍按实际方案确定，不把本路线表当作已完成或全量变更授权。

### L0 交付（Claude，2026-09-30，未提交，待 Codex 复核）

本轮没有改功能、没有连接设备、没有安装、没有提交推送，也没有动真实服务和数据。新增的只有只读检查脚本 `tools/linux_device_check.sh`、`.gitattributes` 里的一行（`*.sh text eol=lf`）和文档。

**1. 差异复核结论**
- **地址契约**：`room.reserve` 回复中的 `host` 现在是严格的 IPv4（每段 0–255，最长 15 个字符），与后台配置“只接受 IPv4 字面量”一致；域名、IPv6、越界地址仍被拒绝。它只是连接地址，票据、DTLS 证书和 build 校验都没有变。
- **保留席位撤销**：只对已有 attempt 的座位发送 `admission.revoke`；`RESERVED` 座位只在本地释放，释放后票据无法再被消费（`TICKET_EXPIRED`）。
- **日志**：三侧诊断只输出固定枚举、普通协议词、计数和计时。已有证据中出现的长十六进制串只有 room id。
- **本轮重跑的专项**：入房回归 16/0、音效 41/0、后台页面 Node 44/0（`logs/l0-review-83cd609de75e4d4ca54264c90d4f3f6e/`）。其余结果沿用各节已有证据，没有重跑全量。
- **版本关系**（本轮实测）：

| 对象 | build_id | 状态 |
|---|---|---|
| 当前工作区源码（构建到私有索引） | `shooter-dev-002-src-675fa4d8063e` | 基准 |
| 真实服务使用的共享索引 `artifacts/framework-games.json` | `675fa4d8063e` | 与源码一致 |
| 用户的 `PlayerClient/`（2026-09-30 生成） | `675fa4d8063e` | 与源码一致 |
| 仓库副本 `clients/shooter-windows/`（已提交） | `0f559378dddc` | 过期，连不上当前服务 |
| Release 附件目录（两份，未发布） | `0f559378dddc` | 过期；Release 仍未创建 |
| 独立 ZIP 包 | 未重新构建 | 不含新后台、音效和入房修复 |

**2. 复核中发现的问题：build_id 依赖换行符**
- `content_digest.ps1` 按原始字节计算摘要。当前工作区的构建输入里，56 个文件是 CRLF，16 个是 LF，还有 1 个混合（`examples/framework/sound.gd`）；Git 索引里全部是 LF，本机 `core.autocrlf=true`。
- 后果：同一个提交在另一台机器上检出，或者在本机重新检出，文件字节都可能不同，build_id 随之改变。Linux 检出是 LF，所以 Linux 服务端从源码构建的 build_id 会与 Windows 导出的客户端不同，结果是 BUILD_MISMATCH。
- 本轮没有改：改动任何字节都会让正在运行的服务和用户的 PlayerClient 失配。
- 建议在 L3 之前单独处理，二选一：计算摘要时把文本文件的换行统一成 LF；或者用 `.gitattributes` 固定换行。两种做法都会让 build_id 变一次，需要重启服务并重新生成客户端。这一项必须在“Linux 服务端 + Windows 客户端”联调之前完成。

**3. 提交候选分组**（由 Codex 整理提交；`README.md`、`STATUS.md`、本文件含多组内容，需要按块拆分或放进文档提交）

| 组 | 文件 | 作者 | 证据 | 最小剩余验收 |
|---|---|---|---|---|
| A 后台 UI | `host/admin.html`、`tests/test_admin_auth_errors.cjs`、`ADMIN_PREVIEW.html`、`tests/run_admin_ui_fixture.ps1`、`docs/19_admin_ui.md`、README 的预览入口一行 | Claude；`[hidden]` 登录修复和对应检查行是 Codex | 浏览器验收 28/0、Node 44/0、`admin_http` 143/0（在最后一处 CSS 调整之前）；用户真人确认建房、退出、重新登录 | 深色和窄窗口截图；独立包重新导出 |
| B 基础音效 | `examples/framework/sound.gd`、`client.gd`、`view.gd`、`examples/shooter/game.gd`、`tools/build_framework.ps1`、`tests/run_client_sound.gd`、README 的静音说明一句 | Claude | 专项 41/0（Codex 重跑一致）、规则 83/0、玩家客户端 28/0；用户转交的三步试听标注已人工验收 | hit 是场景受击声，不是个人命中确认（已记录）；`test_framework_clients.ps1` 未跑 |
| C 入房修复与诊断 | `schemas/lobby_response.schema.json`、`host/managed_lobby.gd`、`host/core/room_manager.gd`、`sdk/roomkit/server/room_runtime.gd`、`sdk/roomkit/client/room_client.gd`、`tests/run_room_disappear_regression.gd`、`tests/run_room_disappear_probe.ps1`、`tests/run_room_udp_probe.gd` | Claude | 修复前 3 次复现，修复后同配置通过；专项 16/0、unit 320/0、契约 286/0、停机 55/0、玩家客户端 28/0。真实服务：Codex 记录房间不再因控制故障停机；用户反馈关闭 TUN 后本人和朋友都能入房 | 公网外部设备的独立证据（已暂停，待 Linux 后再测）；TUN 共存未解决，它属于网络环境问题，不算房间生命周期未修好；客户端 `AUTH_FAILED` 同时表示 ENet 连接失败和认证失败，日志还不能区分；同一构建的房间共用 `server.log` |
| D 文档与 L0 | `STATUS.md`、`docs/17`、`tools/linux_device_check.sh`、`.gitattributes` | Claude、Codex | 链接检查 0 失效 | — |

说明：
- `tests/run_admin_ui_fixture.ps1` 在 C 组加了 `-Bind`、`-AdvertisedHost` 参数，C 组的复现脚本依赖它，所以 A 必须先于 C 提交，或者两组一起提交。
- 提交后仓库副本 `clients/shooter-windows/` 会与源码不符。要不要用 `PreparePlayerClient.cmd -RepositoryCopy` 重新生成（会产生新的 Release 附件目录），由 Codex 和用户决定；建议等第 2 点的换行问题处理之后再生成，避免连续变两次。

**4. Linux 只读检查**
- **脚本**：`tools/linux_device_check.sh`。
  - 只读：不安装，不写文件，不使用 sudo，只输出到标准输出；不打印环境变量、MAC 地址或主目录里的文件内容。
  - 纯 ASCII、LF 换行。已在本机 Git Bash 里试跑到结束；很多 Linux 命令在那里不存在，正好走到了脚本的兜底分支。
- **检查内容**：系统与 glibc、CPU 和内存、磁盘与 inode、用户与组、是否有 sudo 程序（不调用）、内核版本与 `/proc` 可读性（进程安全的前提）、Godot 与导出模板、`pwsh` 和 `dotnet`、libicu 和 libssl、`libsqlite3`、IPv4 地址与默认路由、防火墙服务是否在运行（规则需要 root，不读取）、RoomKit 默认端口是否被占用、常用工具。
- **运行方式**（在 Windows 项目根目录用 cmd 执行；脚本通过管道送过去，不复制任何文件；只连接 `zhao@192.168.10.105`）：
  ```
  ssh zhao@192.168.10.105 "bash -s" < tools\linux_device_check.sh > logs\linux-device-check.txt
  ```
  PowerShell 5.1 不支持 `<` 重定向，请用 cmd。需要输入密码时由用户本人执行。输出末尾应出现 `ROOMKIT_LINUX_CHECK_COMPLETE`。
- **依赖清单**（都未下载；版本和文件名以官方发布页为准，下载后校验哈希；下面的目录是建议值，全部在用户目录内，不需要 sudo）：

| 依赖 | 用途 | 来源 | 建议位置 | 备注 |
|---|---|---|---|---|
| Godot 4.7.2 stable Linux x86_64 编辑器二进制 | 运行 Operator、宿主、房间和测试（`--headless`） | godotengine/godot 官方 Release `4.7.2-stable` | `~/roomkit/tools/godot/` | 提交哈希应为 `ed1daf0bf`，与 Windows 相同 |
| Godot 4.7.2 导出模板 | 只在 L4 导出独立包时需要 | 同上 | `~/.local/share/godot/export_templates/4.7.2.stable/` | L1–L3 不需要 |
| PowerShell 7 LTS `linux-x64.tar.gz` | 方案 P 的存储助手 | PowerShell/PowerShell 官方 Release | `~/roomkit/tools/pwsh/` | 需要系统的 libssl；没有 libicu 时设置 `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` |
| `libsqlite3.so.0` | 存储 | 发行版自带（Debian/Ubuntu 的包是 `libsqlite3-0`） | 系统库 | 通常已安装；缺失时才需要 sudo，届时单独征求同意 |
| 项目源码 | 运行 | 本仓库的某个提交（`git clone` 或 `git archive`） | `~/roomkit/src/` | 不含 `data/`、`logs/`、`artifacts/`；不复制真实数据库 |
| 防火墙放行 | 仅 L4 跨机时需要 | — | — | 需要 sudo，届时单独确认 |

**5. L1 小任务**（方案 P；方案 G 只在门槛不满足时评估；不先重写存储）
1. **L1.0 设备检查**：运行上面的脚本，把结果写进 [环境记录](10_environment.md)。通过标准：系统、内存、`libsqlite3.so.0` 和内核版本都已知。
2. **L1.1 Godot headless**：在设备上用干净的源码副本跑 `run_unit.gd`、`run_shooter.gd`、`run_client_sound.gd`、`run_room_disappear_regression.gd`。通过标准：结果与 Windows 相同（320、83、41、16）。`run_unit` 里依赖 PowerShell 的套件如果在 Linux 上失败，逐项记录，不算通过。
3. **L1.2 SQLite 绑定抽象**：`sqlite_store.ps1` 的库名和路径分隔符改为按平台选择，Windows 分支的字节级行为不变。通过标准：Windows 上的存储专项（`run_assets.gd`、`run_accounts.gd`、`run_asset_snapshot.gd`、常驻探针）全部不退化。
4. **L1.3 Linux 存储切片**：在隔离测试库上用 `pwsh` 跑账号（注册、登录、会话校验）、资产（读取、快照、同一操作编号重复提交）和备份恢复。通过标准：与 Windows 的逐项结果一致。
5. **L1.4 跨平台一致性**：通过标准有三条。
   - 固定密码和盐，PBKDF2-SHA256 做 60 万次，结果在两个平台逐字节相同；
   - Windows 生成的测试库在 Linux 上通过完整性检查并能读取，反方向也一样；
   - 备份在另一个平台上能恢复。
6. **L1.5 测量**：常驻工作进程的内存、首次应答时间、请求 p50/p95、一次性助手耗时。门槛沿用“调查结果与推荐”第 6 节，达不到时申请评估方案 G。
7. 每个小任务单独交付，证据分平台记录。Linux 上没有运行的项目不写通过。

**6. 进程安全机制**（L2 实施；这里只确定方向和验证方式，不照搬 Windows 的句柄语义）
- **已读到的引擎事实**（Godot 4.7.2 `os_unix.cpp`，由摘要工具阅读，需要在设备上验证）：
  - 不忽略 `SIGCHLD`，也不调用 `waitpid(-1)`，子进程只会被针对它自己 PID 的 `is_process_running`、`get_process_exit_code`、`kill` 回收；
  - 子进程启动时调用 `setsid()`，所以宿主退出不会连带结束房间。
- **方向**，按优先级：
  1. **协作退出优先**：房间通过控制通道收到 `room.stop`，或者因为宿主失联而自行退出；存储工作进程在标准输入关闭时退出。强制结束只是兜底。
  2. **只结束自己的直接子进程**：同一个 PID 的“检查是否在运行”和“结束”放在同一把锁里，任何其他代码路径都不对这个 PID 调用会回收的函数。原因是未回收的子进程即使已经退出也仍占着 PID（僵尸状态），在这个前提下信号只会到达原进程或它的僵尸。它依赖上面的引擎事实，不能只靠“先检查再结束”就宣称安全。
  3. **不结束非子进程**：宿主重启后留下的旧房间沿用现有策略，只核对身份、隔离端口、等待它自行退出（房间在宿主失联约 15 秒后会自己退出）。如果以后确实需要结束非子进程，再评估 pidfd（`pidfd_open` + `pidfd_send_signal`，需要内核 5.3 及以上，检查脚本会报告内核版本）。
- **验证方式**：
  - 在设备上确认：子进程退出后、我方调用回收函数之前，`/proc/<pid>/stat` 显示状态为 `Z`，证明 PID 仍被占用；
  - 用假的进程适配器做单元测试，断言“已回收之后不再调用 kill”，以及所有调用都经过同一把锁；
  - 反复启动和退出的压力测试，加上超时回收和宿主异常退出场景。
  - 以上全部要有证据之后才能标为通过。

## 当前顺序调整（2026-09-30）

用户暂停 Windows 公网联机与 TUN 共存排查，待 Linux 服务端实现后再测。关闭 TUN 后本人和朋友均可入房是用户反馈；开启 TUN 加 DIRECT 仍失败，共存方案未解决。保留排查证据，不继续要求关闭 TUN、改规则或测试路由排除。下一步回到 Linux 最小切片的设计复核和准备，具体依赖安装、远程设备变更及真实数据迁移不因本条自动获批。后续由 Claude 主要实施，Codex 复核，Windows 本机运行能力继续保留。

## 历史任务：空房间就绪后消失（已交付修复，TUN 排查暂缓）

用户真实问题：配置公网地址后大厅可连，但无人加入的房间也在几秒至十几秒内消失；尝试入房会回登录。工作目录本仓库、main，接手核实基准及已有 UI/音效未提交改动，保留他人改动，同目录单方写入。Linux 调查暂缓，不安装依赖、不连接笔记本、不发布或提交推送。

Codex 已核实真实 managed-host.log 四次 STARTING → READY → FAILED / CONTROL_UNAVAILABLE，房间日志只有引擎启动信息。控制连接代码固定回环地址，不能直接归咎于公网 UDP。当前 artifacts/framework-games.json 对应工程的 room_runtime、control/envelope Schema 和 protocol 与源码哈希相同。独立夹具使用同一公网 advertised_host、独立端口/库，空房间观察约 40 秒正常；证据与诊断脚本失败记录见 STATUS。隔离测试仍使用不同端口及 loopback game_bind，未覆盖真实环境全部差异，也未验证公网游戏流量。

1. 先读真实日志和相关源码，不读取密码、私钥、token 内容，不改 data/framework、不停止真实服务。核对实际生成工程与正在运行的宿主是否同源、进程启动方式、心跳和控制超时、共享文件/结果队列及真实与隔离配置差异。不要通过放宽认证、延长全部超时或吞掉错误来掩盖问题。
2. 在宿主控制连接拒绝/断开，以及 room_runtime 主动关闭各分支补充最小脱敏诊断：时间、room/launch 标识、固定原因枚举、消息类型、传输错误码、心跳间隔。禁止记录控制消息全文、凭据、签名密钥、玩家私密载荷。区分传输关闭、Schema 拒绝、身份不匹配、序列错误、房间自身超时；不改线上协议。测试诊断不泄露秘密。先在隔离实例覆盖相关失败分支。
3. 用独立目录、端口、游戏索引和假账号复现空房间；先覆盖绑定地址差异，再查具体断开路径。调查客户端为何回登录，区分房间连接失败与大厅/账号会话失效。未复现就明确报告，不宣称已修复；若需要用户重启获取新日志，交付准确的停止、重建/启动、创建空房间步骤，说明 SDK 修改会影响 build_id，需重导客户端。不得偷偷重启真实服务。
4. 找到根因后修复并做针对性回归，至少验证空房间持续就绪、两个真实客户端进出房间、错误版本仍被拒绝。公网验证须另有实际外部设备证据。更新 STATUS，交 Codex 复核，给用户最多三条操作。

### 诊断与修复（Claude，2026-09-30，未提交，待 Codex 复核）

**结论**：已在隔离环境复现并修复。两个现象来自同一条链；公网 UDP 和版本不匹配都不是原因。
1. 大厅回复 `room.reserve` 时，Schema 要求 `host` 必须等于常量 `127.0.0.1`（`schemas/lobby_response.schema.json`，托管大厅的 Schema 引用它）。只要 `advertised_host` 设成局域网或公网地址，客户端就会把这条入房回复判为非法，自己关闭大厅连接，然后回到登录页。这就是“入房回登录”。
2. 大厅在连接断开的清理中，对该玩家的所有座位发送 `admission.revoke`，包括刚预留、还没有 attempt 的 `RESERVED` 座位，此时 `attempt_id` 为空字符串。房间收到后，控制 Schema 校验失败（要求 `minLength: 1`），于是主动停机，并发出 `room.stopped`。
3. 宿主当时仍认为房间处于 READY，把 `room.stopped` 当成协议违规，拒绝后记为 `FAILED / CONTROL_UNAVAILABLE`。这就是“房间就绪后消失”，与真实日志中的四次记录一致。
4. 之前的隔离实验都用回环地址，或者没有人点入房，所以一直没有触发。真实日志中那几个“无人加入的房间”，推测是有人点了入房，尝试失败后房间随之消失（推测，真实环境没有对应的入房时间戳）。

**诊断（已脱敏，线上协议不变）**：
- **宿主**：`room_manager.gd` 的每条断开和拒绝路径都带上固定原因，输出一行 `ROOM_CONTROL_CLOSED`，写入 `managed-host.log`。
  - 字段：时间、room、launch 前 8 位、原因枚举、消息类型（只收录普通协议词）、传输错误码、状态、心跳计数、距上次心跳的毫秒数、房间存活时间。
  - 原因枚举：`TRANSPORT_CLOSED`、`TRANSPORT_ERROR`、`WRITE_FAILED`、`SCHEMA_REJECTED`、`IDENTITY_MISMATCH`、`REGISTER_REJECTED`、`READY_REJECTED`、`HEARTBEAT_SEQUENCE`、`UNEXPECTED_STOPPED`、`RESULT_REJECTED`、`HANDLER_REJECTED` 等。
  - `ROOM_STATE` 行增加了时间戳。
- **房间**：`room_runtime.gd` 的每条主动停机路径输出一行 `ROOM_SHUTDOWN`，写入房间日志。
  - detail 枚举：`CONTROL_SCHEMA`、`CONTROL_IDENTITY`、`CONTROL_TRANSPORT`、`CONTROL_CLOSED`、`HOST_SILENT`、`HOST_STOP`、`UNKNOWN_CONTROL_TYPE`、`STARTUP_TIMEOUT`、`DTLS_SETUP_FAILED`。
  - 附带：心跳间隔、已发心跳数、成员数、距上次收到宿主消息的毫秒数。
- **客户端**：`room_client.gd` 输出三类行。
  - `CLIENT_LOBBY_CLOSING`：客户端主动关闭，并说明是 Schema 不符还是意外回复，以及回复类型；
  - `CLIENT_LOBBY_CLOSED`：关闭码和原因；
  - `CLIENT_ROOM_JOIN_FAILED`：失败码、阶段，以及大厅连接是否仍然打开。这样“房间连接失败”和“大厅或会话失效”可以区分开。
- **不记录**：消息全文、token、票据、签名密钥和玩家载荷。扫描了所有证据，长十六进制串只有 room id（后台本来就显示）。
- **限制**：同一构建的所有房间共用 `server.log`，新房间会覆盖旧房间的日志。宿主那一行会长期留在 `managed-host.log`，单靠它就能区分断开原因。

**修复**（没有放宽认证，没有延长超时）：
- **Schema**：`host` 从常量 `127.0.0.1` 改为严格的 IPv4 字面量（最长 15 个字符，每段 0–255），与后台配置只接受 IPv4 的规则一致。域名、IPv6 和越界地址仍然被拒绝。`host` 只是连接地址，票据校验、DTLS 证书和 build 校验都没有变。示例 `m2_messages.example.json` 中的 `127.0.0.1` 仍然有效。
- **大厅**：`managed_lobby.gd` 新增 `_revoke_seat`，只对已有 attempt 的座位发送 `admission.revoke`；`RESERVED` 座位只在本地释放。释放后，这张票据无法再被消费（返回 `TICKET_EXPIRED`），已验证。
- **没有改的**：宿主把房间主动发出的 `room.stopped` 记为 `CONTROL_UNAVAILABLE`，这个行为保留；现在可以从 `UNEXPECTED_STOPPED` 加上房间那一行看出真实原因。

**隔离证据**（都是独立数据、端口和游戏索引，`game_bind`/`lobby_bind` 为 `0.0.0.0`，通告本机局域网地址；复现脚本 `tests/run_room_disappear_probe.ps1`，夹具新增 `-Bind`、`-AdvertisedHost` 参数，默认值不变）：
- **修复前**（连续 3 次复现）：
  - 空房间闲置 45 秒、已登录客户端在大厅轮询 40 秒、随机 UDP、无 DTLS 的 ENet、错误主机名或不受信任的 DTLS 握手，房间都保持 READY（`logs/admin-ui-c8fcb10bed8348ae95615dff4dee06ec/`）。
  - 真实客户端按局域网地址入房后，客户端显示“连接已关闭或登录已失效，请重新登录”，房间变为 `FAILED/CONTROL_UNAVAILABLE`（`logs/admin-ui-6a83ecf6fd214247bb72f5d1fe48009c/`、`logs/admin-ui-1430e2d3f20f4885b6203f8edc088a6c/`）。
  - 房间日志：`ROOM_SHUTDOWN detail=CONTROL_SCHEMA type=admission.revoke`；宿主日志：`ROOM_CONTROL_CLOSED reason=UNEXPECTED_STOPPED type=room.stopped`；客户端日志：`CLIENT_LOBBY_CLOSING reason=schema type=room.reserve`（`logs/admin-ui-ec037fee6cb645e0ab031a1691cf7f64/`）。
- **修复后**：同样的配置下，真实客户端入房（`已进入房间`）后正常退房（`left_room`）。房间在入房、退房、之后的观察期和四类 UDP 流量期间一直保持 READY（`logs/admin-ui-e7ddf5901da542c6a350d7beaab7351e/disappear/`）。
- **回归**：
  - 新增 `tests/run_room_disappear_regression.gd` 16/0：局域网和公网 IPv4 通过、非法地址被拒、`RESERVED` 座位不发送 revoke、释放后票据失效、`ADMITTING` 座位仍然 revoke 且通过房间 Schema、空 attempt 会被房间拒绝。
  - `run_unit` 320/0；`run_managed_contracts` 286/0。
  - `test_managed_shutdown.ps1` 55/0。它从共享索引只读复制当前房间工程，所以测的是新宿主配旧房间代码。
  - `run_shooter` 83/0；`run_client_sound` 41/0。
  - `test_player_client.ps1` 28/0：双客户端互见、进出房间、错误版本仍被拒绝；新 build_id 为 `shooter-dev-002-src-675fa4d8063e`（`logs/player-client-c852204b442a4ffbab29088591ed6db1/`）。
  - 所有隔离 Operator 的 stderr 中 ERROR/WARNING 均为 0 条。

**未验证**：
- 公网：没有外部设备，公网入房仍需实测；
- 真实服务：没有重启，也没有取新日志；
- `test_framework_clients.ps1`：会读取真实服务正在用的索引，没有跑；
- 独立包、仓库客户端副本、Release 附件和用户的 PlayerClient 都没有重新生成。

**用户操作**：
1. 后台停止游戏服务器 → `StopManagement.cmd` → `StartManagement.cmd` → 启动游戏服务器。重新构建后 build_id 会变化。
2. 运行 `PreparePlayerClient.cmd` 重新生成 PlayerClient，发给朋友的也必须是新版。旧客户端会被版本检查拒绝，而且它自带的旧 Schema 仍会拒绝非回环地址。
3. 创建房间，从外部设备按公网地址入房。如果还有问题，把 `data/framework/logs/managed-host.log` 里的 `ROOM_` 行发来。

Linux 调查复核提醒：先检查进程存活、再按 PID kill 仍存在 TOCTOU 竞态，不能作为不误杀的证明；后续需稳定进程句柄（如 pidfd）或等效受控生命周期设计及实测。PowerShell 7 方案暂为候选，尚未选定或安装。

## 2026-09-28 已确认的下一阶段规划

### 2026-09-29 顺序调整（用户已同意）

GitHub Release 暂不发布，获取验收保持待办，不再作为后台 UI 的前置条件。接下来依次：① Claude 制作独立离线后台预览，任务见 [docs/19](19_admin_ui.md)，用户看布局；② 预览确认后接入现有后台并完成隔离操作验收；③ 基础音效小阶段；④ Linux 完整服务端选型与兼容性调查。每阶段单独交付，不同时启动多个实现任务。GitHub 发布可在用户需要分发时插入；Linux 仍是后续主要技术目标，不提前增加新游戏玩法。

进展（2026-09-29）：①② 已由 Claude 完成，正式后台已接入新布局，目前在收尾复核阶段，见 [docs/19 当前任务](19_admin_ui.md#当前任务后台改版收尾2026-09-29交-claude)。Codex 复核通过后进入③音效。原来“本次只安排第①步、任务单尚未发送”的说明已经过时。③ 基础音效已由 Claude 实现，待 Codex 复核（见下方“基础音效实施”）。

### 当前任务：基础音效（2026-09-29，交 Claude）

交付复核：基础音效已实现，Codex 隔离重跑专项 41/0。hit 当前定义为场景受击声，不是个人命中确认；两人时也可能由自己受伤触发，不能宣传为“我打中了对方”。需要个人命中反馈时单独设计权威伤害事件及去重，不在当前收尾中扩协议。

### 下一任务：Linux 完整服务端可行性调查（交 Claude，先调查后实施）

先读 AGENTS、STATUS、docs/01 与本计划，核实当前 main 和未提交 UI/音效改动；同目录仅 Claude 写文档，保留其他改动。先在本仓库只读梳理存储助手、进程启动与身份校验、目录权限、证书、构建/安装脚本的 Windows 依赖。给出维持现有 Godot/协议/账号资产语义的跨平台方案比较、推荐方案及最小验证切片，尤其说明常驻存储的替代技术、部署内存成本、Windows 一键启动如何保留、备份与重建测试库边界。不要未经测量承诺性能提升，不先做全框架换语言。

本任务只更新本计划及 STATUS，不改功能、不安装新运行时、不重建库、不连接 Linux、不提交推送。Linux 测试机已有记录为 `ssh zhao@192.168.10.105`；设备检查列为下一步，不把已知 SSH 地址当作连通或兼容通过。交付一个推荐方案、主要风险和下一次可执行验证清单，供 Codex 复核后安排远程验证。GitHub 发布继续暂缓。

#### 调查结果与推荐（Claude，2026-09-29，未提交，待 Codex 复核）

**范围**：只读了源码与脚本，读了 Godot 4.7.2 的 `drivers/unix/os_unix.cpp`（公开源码），并在本机隔离环境做了一次内存测量。没有改功能，没有安装任何东西，没有连接 Linux 笔记本；数据库没有重建，真实服务也没有碰。本机没有 PowerShell 7（`pwsh`），只有 Windows PowerShell 5.1；系统 `winsqlite3.dll` 的版本是 3.51.1。本节补充 [docs/01 的跨平台边界](01_scope_architecture.md#跨平台需要替换的边界) 和上面第六节的存储方案 A/B/C，不重复其中内容。

**1. Windows 依赖清单**（Godot 侧有 8 个调用文件，共 18 处直接依赖 Windows 或 `powershell`）

| 领域 | 现在的实现 | Linux 上的问题 | 可移植的替代 |
|---|---|---|---|
| 存储（资产、账号、结果、删除） | `sqlite_store.ps1`（299 行）、`account_store.ps1`（517 行）内嵌 C#，用 `DllImport("winsqlite3.dll")` 调 SQLite；常驻工作进程 `storage_worker.ps1`，另有一次性助手 | 没有 `powershell.exe` 和 `winsqlite3.dll` | 见第 2 节 |
| 密码 | .NET `Rfc2898DeriveBytes`（PBKDF2-SHA256，60 万次） | 在 PowerShell 7 / .NET 8 上可用 | 已有 GDScript 探针，结果与 .NET 逐字节一致（约 1.7 秒，Windows） |
| 备份、恢复、指标 | `operator_maintenance.ps1`（308 行）：SQLite backup API、完整性检查、`File.Replace`；CPU 和内存读 CIM `Win32_*` | CIM 不存在 | 备份部分跟随存储方案；指标读 `/proc/meminfo`、`/proc/stat`，磁盘用 Godot `DirAccess.get_space_left()` |
| 进程身份（房间、宿主） | `process_launcher.gd` 在非 Windows 上直接返回 UNSUPPORTED；`process_identity.ps1` 用 CIM 核对父进程、可执行文件、命令行标记和创建时间，再按持有的句柄 TerminateProcess | CIM 和句柄都不存在 | GDScript 直接读 `/proc/<pid>/stat`（ppid、starttime）、`/proc/<pid>/cmdline`（`--launch-id` 标记）和 `/proc/<pid>/exe`，不用再启动外部进程 |
| 私有目录 | `protect_data.ps1`、`protect_runtime.ps1`：ACL 只留当前用户、拒绝重解析点 | 没有 Windows ACL | `FileAccess.set_unix_permissions` 设为 0700 或 0600，用 `DirAccess.is_link` 拒绝符号链接，再核对属主 |
| 路径 | 各脚本约 90 处用 `+'\'` 前缀判断和不区分大小写的比较 | 分隔符是 `/`，文件系统区分大小写 | 改用 `DirectorySeparatorChar`；Linux 上按区分大小写比较 |
| 启动、构建、导出 | `.cmd` + PowerShell，Windows 导出模板，`Start-Detached` | 全部需要对应的 Linux 版本 | 写 `.sh` 入口，之后可选 systemd 用户服务；Windows 的 `.cmd` 不动 |
| 可以直接移植 | 证书（Godot `Crypto` 生成）、WSS、ENet/DTLS、Schema、SDK、游戏、停机请求文件 | 理论上可以移植（09-21 在 WSL 上跑过 215 项检查，但那不是宿主验证） | Linux 上需要实测 |

**2. 常驻存储的替代方案**（前提：不改数据库文件格式、SQL、事务和幂等语义）

| 方案 | 做法 | 优点 | 缺点和风险 |
|---|---|---|---|
| **P：Linux 用 PowerShell 7 复用现有助手（推荐的第一步）** | 同一套 `.ps1` 和内嵌 C#，只把平台相关部分抽出来：SQLite 库名（Linux 用 `libsqlite3.so.0`）、路径分隔符、ACL、CIM。Windows 继续用 5.1，不用安装 | 存储语义只有一份实现，现有语义测试可以直接在两边对照；改动量最小 | Linux 需要装 `pwsh`（可以不用 sudo，解压到用户目录），这是一个额外运行时，要用户同意；5.1 和 7 两种方言必须同时兼容；Linux 上的内存、冷启动和一次性助手耗时都还没测 |
| G：GDExtension SQLite 放进 Godot 进程，存储逻辑改写成 GDScript（即第六节的方案 C） | 去掉所有 PowerShell 存储进程 | 常驻进程最少，两个平台用同一条路径 | 要下载并分发第三方原生库，每个平台一份（之前已暂缓，需用户同意）；约 1100 行存储、账号、删除、备份逻辑要重写，资产幂等和删除语义的迁移风险最大；密码派生慢约 1 秒以上（1.7 秒对比 .NET）；与 4.7.2 的兼容性也要验证 |
| 不推荐 | Linux 上改用 Python 再写一份（两份实现，语义容易分叉）；Go 或 Rust 助手（AGENTS 禁止擅自引入）；调用 `sqlite3` 命令行（没法安全绑定参数） | — | — |

**推荐**：
- 平台层（进程身份、目录保护、指标）在 Linux 上直接用 GDScript 读 `/proc` 和文件权限，不再为这些启动外部进程。
- 存储层先走方案 P，得到一个能运行、语义不变的 Linux 服务端，再用第 5 节的门槛实测。只有 P 在 Linux 上的内存或耗时达不到门槛，才启动方案 G 的评估。

我倾向 P，理由是：在现有语义不变的前提下，P 是唯一能让资产、账号、删除和备份只维护一套实现的路线；G 的收益（省下常驻进程的内存）只有等 P 的实测出来之后才能量化。这里不承诺任何性能提升。

**3. 调查中发现的风险：Linux 上结束进程**
- Godot 4.7.2 在 Unix 上的行为：`is_process_running` 内部调用 `waitpid(WNOHANG)`，子进程一旦退出就会被回收，退出码缓存在 `process_map` 里；`OS.kill` 直接对这个 PID 发 SIGKILL。
- 现有代码在 Linux 上是安全的，但功能不全：`bounded_helper.gd` 和 `resident_store.gd` 的结束路径都受 `_handle_release_verified()` 限制，它要求 Windows 加 4.7.2 的特定构建。所以在 Linux 上，常驻工作进程会自动关闭，退回一次性模式；一次性助手超时后也不会被结束，也就是超时并没有真正执行。
- 移植时的陷阱：Windows 规则是“正在运行，或者已经有退出码，就调用 `OS.kill`”，依赖的是“持有句柄，PID 就不会被复用”。照搬到 Linux，子进程被回收后 PID 可以复用，就可能 SIGKILL 到一个无关进程。
- Linux 版应该这样做：只在同一把锁下、刚确认进程还在运行时才发信号。尚未回收的子进程不会让出 PID，所以这样是安全的；已经退出的进程不再调用 kill，也不需要，因为已经被回收了。
- 这条规则要写进 Linux 平台层的测试，并且作为启用 Linux 常驻存储和超时的前提。

**4. 内存基线（Windows 实测，隔离环境，1 次采样，单位是工作集 / 私有内存）**
- 只有 Operator（管理服务）：287 / 202 MB。其中 Godot 管理服务 97 / 50 MB，两个常驻存储 PowerShell 各约 90–100 / 71–84 MB。
- 游戏服务器运行：557 / 389 MB。多出的是托管宿主（94 / 47 MB）和两个短时 PowerShell（约 81–91 MB，来自进程身份核对的一次性助手）。
- 再加一个就绪的射击房间：548 / 350 MB，房间进程约 94 / 46 MB。每多一个房间预计再加一个同样大小的 Godot 进程（推算，未测多房）。
- 证据：`logs/admin-ui-2d98e12ebc1049c48474fbc965245b48/memory/`（`memory.csv` 和测量脚本 `measure_memory.ps1`）。测的是 Godot 编辑器二进制；导出模板和 Linux 上的数值都没测。
- 结论：PowerShell 进程占到基线的约三分之一到一半。Linux 上改用 `/proc` 做进程核对，就能去掉那对短时进程；常驻存储的两个进程只有方案 G 才能去掉。以后换 1 GB 小云服务器之前，必须先在 Linux 上实测。

**5. Windows 一键运行、备份和测试库边界**
- **Windows 不退化**：所有新代码按 `OS.get_name()` 分派，Windows 分支保持现有代码和测试不变。`StartManagement.cmd` 等入口不动；每个阶段都要重跑 Windows 回归（admin_http、玩家客户端、存储专项）。
- **数据库**：SQLite 文件和 WAL 格式跨平台通用，备份继续用 SQLite backup API 加完整性检查。验收要求：两个平台之间能互相恢复备份，但只能用测试生成的合成库。
- **测试库**：Linux 上所有测试都在项目内的 `data/test-*` 隔离目录重建。验证阶段不把用户的 `data/framework/` 复制到 Linux。真实数据库迁移到 Linux 要作为单独步骤，由用户授权，并且先备份。

**6. 下一次可执行的验证清单**（每一步都要事先得到用户同意；第 0 步只读）
0. **设备检查**（只读）：确认 SSH 连得上，记录发行版和 glibc 版本、CPU 和内存、磁盘空间，确认 `libsqlite3.so.0` 是否存在、有没有 `pwsh` 或 Godot，确认防火墙状态。结果写进 [环境记录](10_environment.md)。
1. **Godot 4.7.2 Linux headless**：需要下载官方 Linux 二进制，要同意。把当前提交的干净副本（不含 `data/`、`logs/`）放到笔记本上，跑 `run_shooter.gd`、`run_unit.gd`、`run_client_sound.gd` 等纯 GDScript 测试。
2. **方案 P 最小切片**：`pwsh` 装在用户目录，要同意。用一个小测试入口，在全新测试库上跑注册、登录、`asset.commit` 同一操作编号重复提交、备份和恢复，并做对照：
   - 同一组固定密码和盐，PBKDF2 结果与 Windows 相同；
   - 两个平台生成的库可以互相打开，完整性检查通过；
   - 常驻工作进程能按预期复用，有超时和回退；
   - 这一步只动存储助手的平台抽象，需要另开实施任务。
3. **测量**：`pwsh` 常驻工作进程的内存、首次应答时间、单次请求 p50/p95、一次性助手耗时，以及 GDScript PBKDF2 在 Linux 上的耗时。建议的门槛（验收用，不是承诺）：
   - 常驻请求 p50 不超过 50 ms；
   - 一次性助手不超过 2 秒，也就是不比 Windows 慢；
   - 管理服务、宿主加一个房间，总内存不超过 Windows 基线加 20%。
   - 达不到时，申请评估方案 G。
4. **平台层实施**：Linux 进程身份（`/proc`，遵守第 3 节的结束规则）、目录保护、指标，以及 `.sh` 启动入口；Windows 回归不退化。
5. **跨机闭环**：Windows 客户端连 Linux 服务端，完成注册、登录、开房、对战、购买、退房和重启后数据保留，要有截图和日志；局域网 UDP 端口和防火墙规则写进文档。

**主要风险**：
- 5.1 和 7 两种 PowerShell 方言的兼容维护；
- Linux 上 PID 复用（第 3 节）；
- 笔记本上的 Godot 4.7.2 和导出模板，以及 `libsqlite3.so.0` 的可用性；
- DTLS -30464 可能在跨机时出现；
- 引入 `pwsh` 或 GDExtension 都需要用户决定；
- 独立 ZIP 包的 Linux 版本还没有规划，要排在源码运行验证之后。

### 基础音效原任务范围（已交付，保留记录）

后台已由用户真人确认建房等操作、退出和重新登录正常；Codex 抽查房间截图与隐藏样式，重跑四项页面测试 44/0。以下为音效实施时的范围。工作目录为本仓库，`main` 基准 `bf21fe0`；接手重新核实 Git，保留尚未提交的后台、预览、夹具和文档。同目录由 Claude 单方写入，Codex 等交付复核。

- 先读 AGENTS、README、STATUS、本节及客户端事件链。实现开枪、命中、死亡、购买成功、按钮反馈五类音效，以及可保存的音量和静音设置。只改客户端/具体游戏展示层、必要的资源打包、测试和文档；不改 host/core、通用 SDK、玩法、认证、协议或数据库。
- 优先自制简短合成音效或许可明确的免费素材；保留生成源或来源与许可说明。控制音量和连射叠加，限制同时播放数量；headless 服务端不创建音频播放节点。不做背景音乐。
- 基于真实事件触发：购买失败不能播放成功声音，重复响应不能重复播放；命中使用服务器确认，死亡每次只触发一次；同一点击避免重复按钮音。缺少可靠事件时先报告最小方案，不擅自扩协议。
- 隔离验证设置持久化、静音、失败与重复事件、连射资源上限，运行受影响的射击及完整客户端测试。无窗口测试不等于听感验收，无法实际监听时明确记录未验收。
- 音效改变源码摘要及客户端版本。用独立游戏索引、连接目录和输出目录生成匹配测试端；不覆盖当前 PlayerClient、仓库客户端、既有 Release 附件，不操作真实服务或 data/framework。交付准确的停服、重启、重新生成 PlayerClient 步骤，不放宽版本检查。
- 更新 STATUS 和本节；提供一个入口及最多三条听音试玩步骤，报告文件、命令、退出码、失败和未运行项。不做 Linux、发布、提交或推送。交 Codex 复核。

#### 基础音效实施（Claude，2026-09-29，未提交，待 Codex 复核）

**结构**：没有改 host/core、SDK、玩法规则、认证、协议或数据库。
- **`examples/framework/sound.gd`**（新增，示例客户端外壳）：
  - 五种音效在启动时由代码合成（频率、噪声比例、衰减都写在文件里），不用任何音频文件，也就没有外部素材的来源或许可要记录；
  - 固定 8 个播放器组成的池，每种音效有并发上限（开枪 3、命中 2、死亡 2、购买 1、点击 1），还有最小间隔（开枪 40 ms、点击 60 ms 等）；槽位满时重启最老的那个声音，而不是叠加；
  - 没有窗口的客户端（`--headless`）不创建音频节点，只保留计数；房间服务端根本不加载这个脚本；不做背景音乐。
- **设置**：音量（默认 70%）和静音保存在 `user://audio_settings.json`，Windows 上位于 `%APPDATA%\Godot\app_userdata\RoomKit Game\`。
  - 不放在 PlayerClient 目录里：否则重新生成客户端时，它会被当成“用户新增文件”而拒绝替换。
  - 写入时先写临时文件再改名，文件损坏就回到默认值。
  - 拖动滑块只改音量，松开时才写一次文件。
  - 测试可以用 `--audio-settings=<路径>` 指定独立位置。
- **界面**（`view.gd`）：
  - 顶部加了“音效 开 / 已静音”按钮和音量滑块，`M` 键切换静音；
  - 所有按钮在 `_button()` 里统一接一次点击音，每次点击只接一个信号，再加 60 ms 间隔，不会重复。
- **射击事件**（`examples/shooter/game.gd`，只在客户端接收快照的路径上）：
  - 新增展示信号 `presentation_cue`，由 `presentation_cues(旧快照, 新快照, 已见的射击编号)` 推导：
    - **开枪**：服务器快照里新出现的射击编号，按“同一时刻、同一枪口”合并，霰弹枪 6 颗弹丸只响一次；
    - **命中**：存活玩家的生命值被服务器下调；
    - **死亡**：从存活变成阵亡，或死亡计数增加；致命一击只响死亡，不再响命中。
  - 进房后的第一帧、重复或相同的快照、过期快照都不会出声。
  - 本地玩家自己受伤或阵亡时音调降低。
- **购买**（`client.gd`）：只在 `retry_asset` 收到服务器确认、资产通过校验、且操作是购买时才播放。
  - 同一个 `operation_id` 只播一次。
  - 购买失败、超时待确认、响应格式不对、保存默认配置，都不会播放成功音。
- **打包**：`tools/build_framework.ps1` 把 `sound.gd` 加进复制清单；独立包构建会复制构建目录里的全部 `.gd`，所以不用再改。

**已知限制**：快照里没有“谁打中谁”的信息，所以“命中”表示任何一次被服务器确认的伤害。两人对战时就等于自己打中了对方；三人以上时，别人之间的互射也会响。要做到只在自己命中时响，最小方案是在射击快照的 shot 里加上 shooter 字段，这属于协议改动，本轮没有做，等决定。

**验证**（均为隔离环境）：
- `tests/run_client_sound.gd`（新增，无窗口）41/0，退出 0，证据在 `logs/client-sound-ba7aac34027c447882e5a69bdae13f14/`。
  - 覆盖：默认值、设置保存与重读、损坏文件、静音和零音量不出声、连射 1 秒内 25 次（间隔不小于 40 ms）、同时最多 3 个开枪声和 7 个声音（上限 8）、立即重复点击不重复出声、有窗口时 8 个播放器且静音全部停止；
  - 真实权威射击快照：一枪一次开枪加一次命中、重复快照和过期快照静默、致命一击只响死亡且只响一次、阵亡期间和复活时静默、霰弹枪只响一次；
  - 购买：被拒、超时、确认后只响一次、同一操作重复确认不再响、响应格式不对、保存默认配置。
  - 同一目录下有 `cue-*.wav` 五个试听文件。
- `tests/run_shooter.gd` 83/0；`tests/run_framework_feedback.gd` 7/0；`tests/run_shooter_visual.gd` 用真实渲染器跑通，60 FPS。
- `tests/test_player_client.ps1` 28/0，退出 0，证据在 `logs/player-client-4136d40bd34f468dabbb90c4812b3844/`。
  - 用自己的游戏索引、Operator、公开配置目录和输出目录，从当前源码导出客户端，完成真实注册、登录、双人入房互见、退房、双击启动。
  - 新 build_id 为 `shooter-dev-002-src-97b98fb2f74e`；改过代码的客户端仍被 BUILD_MISMATCH 拒绝。
  - 三个客户端和 Operator 的 stderr 中 ERROR/WARNING 均为 0 条；共享的 `artifacts/client` 和游戏索引都没有改动。
- `--check-only`：受影响的 6 个脚本都能解析。
- 客户端登录界面截图（带音量控件）在 `logs/client-sound-3daf048c9f8d4576ba037358b7739037/client-login.png`。
- 测试中修正：
  - 合成代码里有一个变量类型无法推断，导致 `sound.gd` 编译失败，而 `client.gd` 预加载它，所以整个客户端都会起不来。新测试第一次运行就发现了，已修。
  - 测试自己的播放器池释放过早，产生泄漏警告；改为等音频线程处理完再释放，产品代码没有改。
  - 脚本编辑在 `view.gd` 里留下 3 行只有 LF 的换行，已统一成 CRLF。build_id 按文件原始字节计算，所以统一后又变了一次，玩家客户端测试随后重跑，28/0。上面的 build_id 和证据目录都是最终字节下的结果；第一次运行 `logs/player-client-95328043206f4bf2ae6d7158d61dc14e/` 得到的也是 28/0，但对应的是旧字节。另外，工作区换行方式（autocrlf）也会影响 build_id，这个行为以前就存在。

**未运行 / 未验收**：
- 听感：没法实际监听，音量平衡和音色都没有验收。
- `tests/test_framework_clients.ps1`：它读取真实服务正在用的共享 `artifacts/framework-games.json`，为了不动真实服务没有跑。
- 独立 ZIP 包没有重新构建。
- 仓库副本 `clients/shooter-windows/`、既有 Release 附件和用户的 `PlayerClient/` 都没有重新生成，仍是 `0f559378dddc`，与新源码不再匹配，需要单独安排。

**上线步骤**（版本检查不放宽）：
1. 管理后台先停止游戏服务器，再运行 `StopManagement.cmd` 关闭管理服务。
2. 运行 `StartManagement.cmd`，它会从源码重新构建，得到新的 build_id。
3. 启动游戏服务器后运行 `PreparePlayerClient.cmd`，重新生成 `PlayerClient`。旧客户端会被以“版本不匹配”拒绝，这是预期行为。

### 暂缓任务：GitHub 获取验收

直接 EXE 启动、内容摘要版本配对和 Release 附件准备已实现，用户已人工试玩，状态及验证边界见 STATUS。下一次由 Claude 先核对最新 main、仓库 client-version.json 与对应 Release 附件清单/哈希，准备简短发布说明，明确“需要服务器提供公开配置、当前仅 Windows、尚未跨设备验证”。本轮授权提交推送源码，不包括发布 Release；下一次确认具体发布后再上传现有原文件附件，不重新导出造成 tag/哈希漂移。

发布前核对（Claude，2026-09-29，`main` = `origin/main` = `bf21fe0`，未发布）：
- 附件：`artifacts/player-clients/release-shooter-client-shooter-dev-002-src-0f559378dddc-4c2ef956/` 共 12 个文件，大小和 SHA256 与清单 JSON、已提交的 `clients/shooter-windows/` 全部一致（`Client.exe` 不进 Git，其余 11 个已跟踪），0 处不一致。
- 版本：用当前 main 源码重新构建，`build_id` 仍为 `shooter-dev-002-src-0f559378dddc`，与附件一致。
- `Client.exe` 与本机官方模板 `windows_release_x86_64.exe` 逐字节相同（`d34d36f3…`）。
- 秘密扫描：只有两处误报——`SetServer.ps1` 里检测私钥的代码行，以及 `Client.exe` 中 mbedtls 内置的 PEM 头字符串；没有连接配置、证书、数据库或密钥文件。
- 发布说明已写好：`artifacts/player-clients/release-…-4c2ef956-NOTES.md`，写明需要服务器提供公开配置、当前仅支持 Windows、尚未跨设备验证。
- 用户确认暂不发布。Release 未创建，下载、直接启动和联机验收都没有执行，GitHub 获取流程仍为待验证。发布时直接上传上述现有文件，不重新导出。

发布后在全新隔离目录分别验证 Git 克隆 + FetchClient 和浏览器获取附件：校验全部文件、确认不带服务端秘密、直接 EXE 启动；使用隔离服务器提供公开配置完成真实登录/入房/退房。不能只看下载成功就宣称联机通过。输出一个下载入口、最多三步玩家说明和真实证据；用户真实服务/数据不动，不做 UI、音效、Linux 或清理。完成后由 Codex 复核，再进入后台 UI 小阶段。

### 下次交给 Claude：客户端交付收尾（2026-09-28 收口）

从最新 main 核实基准、AGENTS 与工作区后实施；主要工作交 Claude，Codex 复核。用户已反馈单账号启动、入房、退房正常，本次收录当前成果，未宣称跨设备或 GitHub 下载通过。

1. 优化独立客户端直接启动：导出程序在未提供命令行配置时，读取可执行文件同目录的 connection.json；显式参数仍优先，源码入口兼容。缺配置给清楚提示，不关闭 WSS/DTLS 或版本校验。验证从不同工作目录、中文/空格目录直接运行 Client.exe 可注册/登录/入房/退房，且不依赖 PowerShell 窗口。StartGame.cmd 保留为兼容入口；先验证引擎的控制台行为，不凭隐藏窗口推定进程生命周期安全。
2. 收口源码 build_id 固定的问题：给出可重复、与对应服务端绑定的构建标识方案，保证不兼容的旧客户端能被拒绝；避免只改客户端标签。先审查设计再做涉及协议或服务器构建的更改。
3. 同源生成 PlayerClient 与仓库分发副本，检查不携带运行数据和秘密；准备 GitHub Release 的精确附件清单与哈希。Release 发布是独立动作，本轮代码推送不等于允许自动发布附件；发布后才做真实下载与全新目录验收，不将缺失的 Client.exe 或 LFS 指针当完整交付。
4. 原因不明的 DTLS -30464 保持已知问题，不屏蔽日志；旧独立服务器 ZIP 的启动修复另列未完成。暂不做后台 UI、音效、Linux、文件清理或全量游戏回归。

交付只给用户一个直接启动入口和最多三步验收；测试使用隔离数据/公开配置/端口，保留原有未提交改动，不操作用户真实服务或数据，不自行提交推送。

客户端入口补充（2026-09-28）：按用户要求，PreparePlayerClient 默认生成完整根目录 `PlayerClient/`，打开该目录后运行 StartGame.cmd；也可用根 StartPlayerClient.cmd。该目录含本机公开连接配置，Git 忽略；仓库副本与 GitHub 获取流程仍单独验收。此前记录中的 artifacts/player-clients/shooter-windows 是旧默认位置，不再作为当前操作入口；备份和临时产物仍位于 artifacts。

#### 客户端交付收尾实施（2026-09-28）

Claude 实施，基于 `main` `f91e6cc`，未提交，待 Codex 复核。回归 `tests/test_player_client.ps1` 28/0，证据在 `logs/player-client-90442badd27f4874bae0f6acef4eb661/`。

**1. 直接双击 Client.exe**
- `examples/framework/client.gd`：显式 `--connection-config` 优先。没有传入时，导出版（非编辑器）读取 `OS.get_executable_path()` 同目录的 `connection.json`；源码版读取 `res://artifacts/client/connection.json`（源码入口一直显式传参，行为不变）。找不到配置时提示“应与 Client.exe 在同一文件夹”。WSS、DTLS、版本校验都不变。
- Godot 模板会自动加载同名的 `Client.pck`，所以双击即可运行。
- 控制台行为已实测，没有凭隐藏窗口推定：经 `explorer.exe` 启动（父进程没有控制台）时窗口正常出现；另起一个探针进程调用 `AttachConsole(pid)`，结果失败，说明游戏没有挂任何控制台，关闭任何黑色窗口都不会影响它。`StartGame.cmd` 保留作兼容入口。
- 测试覆盖：客户端 a 不带任何参数、工作目录设为系统临时目录、客户端目录路径含中文和空格（`RoomKit 玩家 客户端-<id>`），完成注册、登录、入房、退房；客户端 b 仍用显式参数，两人互相可见。

**2. 构建标识（设计）**
- **问题**：源码清单的 `build_id` 固定为 `shooter-dev-002`，代码改了也不变，旧客户端会被当作兼容版本放行。
- **方案**：`tools/build_framework.ps1` 准备好每个游戏工程后，用 `tools/content_digest.ps1` 计算内容摘要（排除 `.godot/` 和两个清单文件；按相对路径排序，拼接“路径=SHA256”后再做 SHA256，取前 12 位），写成 `build_id=<源码 id>-src-<摘要>`，同时写入索引和两个清单文件。
  - 服务器大厅（`lobby_server.gd` 逐字比对 `build_id`）、房间进程和导出客户端都读取同一目录，所以必然一致；任一运行文件变化，标识就变。
  - 没有改协议字段或 schema（`build_id` 本来就是长度不超过 128 的字符串），没有改只让客户端带标签，独立包构建（自带随机 id）也不变。
- **验证**：
  - 两次构建标识相同；
  - 标识等于对工程重新计算的摘要，房间清单与索引一致；
  - 在工程副本的 `client.gd` 末尾加一行注释，摘要随之改变，由此导出的客户端被未改动的服务器拒绝（“客户端与服务器版本不匹配”）。
- **代价**：代码更新后重启 `StartManagement.cmd`，需要重新运行 `PreparePlayerClient.cmd`，旧客户端会被明确拒绝。

**3. 同源生成与 Release 附件**
- `-RepositoryCopy` 在同一次导出中生成三份：
  - 本地目录（含本机连接配置）；
  - `clients/shooter-windows/`（不含连接配置，附 FetchClient）；
  - `artifacts/player-clients/release-<tag>/`：平铺的附件目录，文件与仓库副本完全一致，含 `Client.exe`；旁边附 `release-<tag>.json`（tag、build_id、每个附件的大小和 SHA256）和 `release-<tag>-SHA256SUMS.txt`。
- 三处都经过私有文件扫描（数据、运行、日志、备份目录，`.key`/`.sqlite`/`.db`/token，私钥），测试核对附件清单、哈希与仓库副本一致。
- **Godot 导出不是逐字节确定的**：同一源码两次导出的 `Client.pck` 哈希不同，所以 tag（`<build_id>-<pck 前 8 位>`）对应某一次具体导出。客户端与服务器配对靠 `build_id`；FetchClient 只下载 Client.exe（官方模板，哈希固定）。
- **当前准备好的附件**：tag 为 `shooter-client-shooter-dev-002-src-0f559378dddc-4c2ef956`，12 个文件共 109,654,328 字节，由当前源码生成到 `artifacts/player-clients/`。仓库副本已同步为这次导出。

**Release 发布与验收步骤（单独授权后执行；本轮没有推送或发布）**：
1. 提交并推送包含 `clients/shooter-windows/` 的提交，确认其中 `client-version.json` 的 `release_tag` 与附件目录名一致。
2. 在 GitHub 网页新建 Release，tag 取上面的 `release_tag`，目标为该提交；把 `release-<tag>/` 里的 12 个文件逐个上传，不要打包，不启用 LFS。
3. 核对 Release 页面的文件名和大小与 `release-<tag>.json` 一致。
4. 在全新目录验收：
   - (a) 克隆仓库，进入 `clients/shooter-windows`，运行 `FetchClient.cmd`，确认下载后通过校验，`CheckClient.cmd` 通过；
   - (b) 另开一个空目录，只用浏览器下载全部附件，`CheckClient.cmd` 通过；
   - 两种方式都用 `SetServer.cmd` 放入服务器的公开文件后双击 `Client.exe`，登录并入房。服务器必须运行同一份源码（`build_id` 相同）。
5. 下载验收完成前，GitHub 获取流程一律标为“待验证”。

**限制**：
- 双击测试里获取窗口标题时返回空字符串，窗口句柄存在，所以只断言窗口出现，不断言标题；
- 已知 DTLS -30464 问题、旧独立包启动方式未修复，维持原状；
- `artifacts/player-clients/` 里还留着一个早先的附件目录（`…-4dce1b3d`），它是我在更新 README 前生成的，已被 `…-4c2ef956` 取代；按“只列不删”规则保留。

本节通过 `grilling` 逐轮确认，是当前开发顺序；下文早期 S0–S5 与逐轮记录保留各自时点含义。实际完成和验证范围仍以 [STATUS](../STATUS.md) 为准。用户确认本次先记录规划、安排第一阶段；并非本次就实施三个阶段。

| 顺序 | 交付目标 | 用户怎样验收 |
|---|---|---|
| 1：看懂项目 | 项目分析、清晰文档、离线交互路线图、清理候选清单 | 双击网页，搜索账号/房间/资产/游戏接入，查看用途、状态与详情；切换开发顺序视图 |
| 2：整理主线和试玩体验 | 当前成果成为 GitHub 主线；按确认清单清理；独立射击客户端；管理 UI 与基础音效 | 朋友可直接运行客户端；后台关键操作清楚且步骤更少；试听和静音 |
| 3：跨平台完整服务器 | Linux 完整后台和服务器，Windows 仍可一键完整运行 | Linux 测试机运行真实服务器，Windows 客户端完成登录、开房、游戏与持久化闭环 |

### 已定产品要求与边界

- **地图**：项目内双击打开的独立网页，无需先启动后台；积木地图为主，另有开发顺序视图。支持搜索、筛选、展开详情；先通俗说明，再展开技术细节、实现文件、验收证据。不做可编辑任务管理系统。明确区分已实现、已验证、待验证和规划，标注核对基准。
- **维护方式**：README 只放当前入口和导航，STATUS 保存当前结论与证据索引，稳定机制留在专题，旧过程进入现有归档。地图引用这些来源，避免第三套手工维护的测试数字。代码调查重在真实耦合、性能和接入障碍，不做纯风格重构或凭行数拆文件。
- **主线与清理**：希望当前 `codex/shooter-framework` 的成果成为真正主线；旧分支、示例、入口、文件先列清单、说明依赖与替代入口，再决定删除。不得把当前取石子示例当成废弃内容。分支切换/删除、默认分支变更本轮不执行。
- **玩家客户端**：先做 Windows 射击客户端，独立目录正常放在项目里并纳入 Git，不压缩；玩家直接双击，不装 Godot。不依赖服务端目录，不带账号库、私钥或管理员凭据。既方便用户发送完整目录，也方便朋友从 GitHub 获取。后续其他游戏复用交付流程。
- **二进制交付待设计**：当前导出 Client.exe 约 104 MiB，超过 GitHub 普通 Git 的 100 MiB 单文件限制；本机已有 Git LFS，但仓库未配置。第二阶段比较并验证实际获取方式，不把 LFS 指针或源码下载等同于完整可执行目录，不启用付费额度。用户要求不压缩。
- **后台 UI**：清爽现代、信息清楚、减少操作步骤；保留启停、房间、玩家、资产、维护与危险操作的权限和必要确认，不靠去掉安全检查减少步骤。
- **基础音效**：开枪、命中、死亡、购买、按钮反馈，带音量和静音。音效属于客户端/游戏展示，不进入通用核心；本次没有要求背景音乐、脚步或换弹系统。素材来源与可分发许可需记录。
- **跨平台**：Linux 跑完整服务器与后台，玩家先用 Windows；Windows 完整运行能力保留。Linux 笔记本先作兼容性测试机，以后再考虑小型云服务器。设备信息见 [环境记录](10_environment.md)，本轮不连接。允许评估内部技术替换，安装启动尽量脚本自动化；尚未选语言、存储库或决定整体重写，选型后先明确范围再实施。
- **数据与通用性**：现有账号资产都是测试数据，用户可在具体实施前确认重建，本轮不删库。继续坚持可选账号/房间/资产、共享身份而各游戏资产默认隔离；赛车和合作种田是未来边界，不在本阶段开发。
- **协作**：Claude 承担主要实现、批量文档整理、构建与测试；Codex 负责范围、关键设计复核和验收整合。同目录单方写入；小阶段只给用户一个入口与几条验证步骤，不新增费用。下方任务单需由用户转交，未自动发送给 Claude。

<a id="claude-phase1"></a>
### Claude 第一阶段任务单：项目地图与文档整理

**交接基准**：`F:\文档\GodotGame\Net\RoomKit`，分支 `codex/shooter-framework`，基准 `b0a707daef53642cd9ac2f3b4a7b6c94f23d8133`。交接前工作区干净；本次 Codex 只修改本计划、根 README 和 STATUS，作为待保留的未提交规划。接手时重新检查 Git 状态与 AGENTS；发现其他改动先辨认负责人，不覆盖。

**执行任务**：

1. 只读核对现有代码、文档、测试证据和入口。按账号、房间与进程、资产与结算、存储、运维、SDK/游戏接入、具体游戏建立简明项目分析。列出真实 Windows 依赖、跨平台需替换的边界与性能待测项；推测明确标注，不据此重构。
2. 整理现有文档：消除重复的“最新包”、过期提交状态、已实施章节仍称未实施等矛盾；核对入口与文件链接。当前读者先看到怎样启动、目前有什么、接下来做什么。原有失败/未运行记录与证据不能丢，迁移进现有归档并保留索引；不制造新一叠编号文档。
3. 新增根目录 `ROADMAP.html`，作为唯一双击入口。可用 `docs/assets/roadmap/` 保存本页专用静态资源，但必须支持 `file://`，不依赖 fetch 本地 JSON、CDN、构建服务器或后台服务。模块视图、开发顺序视图、搜索、筛选、详情展开均可用；提供相对源码/文档链接或可复制仓库路径。页面首屏只放简明信息，细节按需展开。实现后在 README 导航。
4. 在本节后维护清理候选表：具体路径/分支、用途、仍被谁引用、保留或替代办法、删除风险与建议。只列候选，不删除示例、脚本、产物或分支。路线图可展示候选，但以文档表为准。
5. 为下一阶段整理简短实施建议与验收门槛，包括 Git 主线整理、独立客户端实际下载流程、后台 UI、音效、Linux 调查顺序；不开始这些功能。

**允许修改**：现有 Markdown 文档及 `docs/archive/`、`ROADMAP.html` 和本页专用静态资源；需要导航时更新 README。只读调查源码和构建脚本。不要修改功能代码、协议、数据库、现有启动/构建脚本或 AGENTS；不连接 Linux、不操作运行中的服务、不清理磁盘、不重建包、不提交或推送。

**初步调查线索，接手后重新核实**：

- 根 `StartPanel.cmd` 是早期面板，独立包同名入口却是当前管理后台；源码当前入口为 `StartManagement.cmd`。后台断线提示存在旧入口引用，记录留给 UI 阶段修复。
- `examples/blocks`、`examples/showcase`、旧宿主与模板仍被测试/构建引用；`examples/turn_based` 是当前第二玩法，不可按“旧文件”直接删除。
- `docs/19_admin_ui.md` 被复制为包内指南，挪动前需查构建依赖。`artifacts/framework-games.json` 等索引有启动用途，不能整目录清空。
- 256 是累计启动授权上限，不是并发人数；7 天迟到结算与授权回收仍属规划。常驻存储已有实测改善，不再把每次启动 PowerShell 当成所有操作的现状。

**验收与交付**：

- 文档/本页静态资源的相对路径与链接检查，历史迁移完整性检查，`git diff --check`；给出命令和退出码。无需为文档改动跑全量 Godot 回归。
- 用真实浏览器通过本地文件入口检查两种视图、搜索、过滤、展开、清空搜索、无结果提示和键盘操作；查看截图确认文字可读、没有遮挡。未能运行浏览器时明确写“未进行视觉/交互验收”，不能用 Node 或静态检查替代。
- 抽查节点状态与对应代码/证据，核对页面没有声称 Linux/跨设备已通过。给出修改清单、通过/失败/未运行、清理候选和最多 5 条用户查看步骤。
- 更新 STATUS 当前摘要与证据位置，保持简短，不把执行过程逐轮追加回去。完成后交 Codex 复核，用户验收第一阶段，再安排第二阶段。

<a id="cleanup-candidates"></a>
### 清理候选表

2026-09-28 第一阶段只读核对（基准 `b0a707d`）。**只列候选，不删除**；是否执行由用户在第二阶段逐项确认。“引用者”来自对 `tools/`、`tests/`、`host/`、`release/`、`templates/` 与文档的搜索，删除前需要重新核对。`ROADMAP.html` 的“清理候选”只做展示，以本表为准。

| 候选（路径/分支） | 用途 | 仍被谁引用 | 保留或替代办法 | 删除风险 | 建议 |
|---|---|---|---|---|---|
| 根目录 `StartPanel.cmd`（`tools/panel.ps1`、`tools/open_panel.ps1`） | 早期无账号宿主 + 只读状态面板 | `tools/run.ps1 -Mode panel`（`tests/run_panel.gd`）；`host/admin.html` 离线提示错误地让用户运行它；文档 16、归档 | 当前后台入口是 `StartManagement.cmd`；独立包里的同名 `StartPanel.cmd` 是另一个文件，指向当前后台 | 中：与包内入口同名，删除/改名前必须先改后台提示和 README | 第二阶段先修后台提示；再决定删除或改名为明确的“早期面板”入口 |
| 根目录 `StartPlay.cmd`、`StartTurns.cmd`、`StartDemo.cmd`、`ShowResults.cmd`（`tools/play.ps1`、`tools/results.ps1`、`tools/results.gd`） | 早期方块/取石子双窗口演示、M2 文字演示、早期成绩库查看 | 文档 11–13、归档；`play.ps1` 启动 `examples/showcase/host.gd` | 当前玩法入口为 `StartShooterClient.cmd`、`StartManagedTurns.cmd` | 低：入口脚本本身无测试依赖；底层示例代码仍被测试使用 | 可在第二阶段删除入口并在归档保留说明；底层代码按下两行单独判断 |
| `examples/showcase/`、`examples/blocks/` | 早期演示宿主与方块示例 | `tools/build_games.ps1`（`tools/run.ps1` 的 games/load/recovery/panel 模式先调用它）、`tests/run_games.gd`、`tests/test_games.gd`、`tests/fixtures/load_client.gd`、`release/host.gd`、`tools/play.ps1` | 若要删除，需先把基础回归改用当前示例（取石子/射击） | 高：直接删除会让 `tools/run.ps1` 基础回归失败 | 暂保留；第二阶段评估是否迁移测试后再删 |
| `release/`、`tools/build_release.ps1`、`tools/package_release.ps1`、`tools/test_release.ps1` | 早期 0.1.0 Windows 候选包 | `release/host.gd` 继承 `examples/showcase/host.gd`；文档 15、归档；未被 `tools/run.ps1` 模式调用 | 当前独立包为 `tools/build_framework_release.ps1` | 低到中：只影响早期包的重建能力 | 可与 showcase 一起在第二阶段删除，并在归档说明历史包位置 |
| `templates/game/`（非托管模板）与 `tools/run.ps1 -Mode template` | 早期开发身份模板 | `tools/new_game.ps1`（未带 `-Managed` 时）；`tests/run_template.gd` 读取该模板生成的 `artifacts/template.json` | 当前推荐 `new_game.ps1 -Managed`（`templates/managed_game/`） | 中：去掉后 `new_game.ps1` 默认分支和 template 模式要一并修改 | 保留到第二阶段决定是否让 `-Managed` 成为唯一路径 |
| 历史专题 `docs/09`、`11`–`16` | M1–M5 阶段说明、早期发布与面板 | README、归档、构建（`docs/19` 被复制进包，不在此列） | 已在归档说明索引 | 低：纯文档，但多处链接指向它们 | 可移入 `docs/archive/` 并修链接；本阶段不移动 |
| `docs/23_branch_files.md` | 分支修改文件完整清单 | README 之外少量文档；每轮都要手工维护 | Git 历史本身可给出修改清单 | 低 | 建议第二阶段停止维护或改为归档快照，减少重复维护 |
| **不列入删除**：`examples/minimal/`、`host/lobby_server.gd`、`host/development.gd`、`examples/turn_based/`、`docs/19_admin_ui.md`、`CODEX_START.md`、`tests/perf/` | — | `minimal` 被 `new_game.ps1` 与 `development.gd` 读取；`managed_lobby.gd` 继承 `lobby_server.gd`；`managed_host.gd` 调用 `development.gd`；取石子是当前第二玩法；`docs/19` 被复制为包内 `ADMIN_GUIDE_ZH.md`；`CODEX_START.md` 被 AGENTS 引用 | 保留 | — | 保留 |
| 本机 `artifacts/`（Git 忽略，约 7.7 GB） | 旧 ZIP 与解压目录（7 个 0.5.0 包及各自解压目录、3 个 SDK 0.4.0 模板 ZIP）、27 个 `framework-<id>` 构建目录、46 个 `games-<id>`、14 个 `framework-release-work-<id>`、包测试解压目录等 | `framework-release.json`、`framework-games.json`、`games.json`、`client/` 等索引被启动脚本和 Operator 读取；当前 ZIP `…aa019dbc…` 及其测试证据被 STATUS 引用 | 保留索引、当前 ZIP、STATUS 引用的证据；其余可逐项清理 | 中：整目录清空会破坏启动；解压目录含隔离测试数据，不能分发 | 第二阶段生成逐项清单（路径、大小、是否被索引/STATUS 引用）后由用户确认 |
| 本机 `data/test-*`、`data/*-test-*` 等测试目录（约 300 MB 中的大部分） | 各测试生成的隔离数据库与日志 | 部分被 STATUS/归档作为证据路径引用 | `data/framework/`（用户真实数据）与 `data/cleanup-history-*`（旧证据归档）必须保留 | 中：误删 `data/framework/` 会丢失用户账号和资产 | 只清理未被引用的 `test-*` 目录，逐项确认；`data/framework/` 下的残留请求文件由用户决定 |
| 分支 `codex/m4-results`（`1a8bec5`） | M4 阶段分支 | 无；它是当前分支的祖先 | 内容已完全包含在 `codex/shooter-framework` | 低 | 第二阶段主线整理后可删除（本地与远端需用户确认） |
| 分支 `main`（`5f7b7aa`） | 当前默认分支，落后 17 个提交 | GitHub 默认分支 | `main` 是当前分支的祖先，可快进到当前成果 | 中：涉及默认分支与远端 | 第二阶段按“下一阶段实施建议”处理，不删除 |

<a id="next-phase-advice"></a>
### 下一阶段实施建议与验收门槛

#### 下一小阶段交接：先整理主线，再做独立射击客户端

2026-09-28 交接更新：用户已同意推进；本地 `main` 已快进包含 `74f3413`，当前工作目录已切换至 `main`。Claude 接手独立客户端时从最新 `main` 核实基准；旧分支只保留历史，不再从旧分支继续写入本目录。未删除任何清理候选。本次未改游戏代码，未重跑游戏回归。

第一阶段用户已基本验收，清理候选未确认。Codex 先把第一阶段文档与地图提交；后续主线操作前重新检查本地/远端提交、工作区和祖先关系，不沿用旧提交数量。不删旧分支，不强推；远端更新另行执行并报告。

Claude 的下一项主要实现任务为独立射击客户端，接手时以本轮文档提交为起点重新核实。先只读检查现有导出模板和客户端目录，提出纳入 Git 的稳定目录及大文件获取方案，再实现可重复导出/更新流程。用户要求是可发完整目录、GitHub 也能方便取得、无需安装 Godot、不压缩、不新增费用；不能只上传 LFS 指针后宣称交付成功。优先复用现有构建，不同时推进后台改版、音效或 Linux。

客户端任务允许修改相关构建/发布脚本、客户端启动与公开连接配置处理、仓库内分发目录、必要的项目级 Git 属性/忽略规则及文档；不得携带测试账号数据、私钥或管理员凭据，不改认证/资产协议，不读改 `data/framework/`。大文件方案尚未确定，不能预先启用付费存储或把本条视为推送授权。

验收采用全新目录，确认玩家不依赖本仓库父目录或 Godot 安装，能启动、配置目标服务器、登录并入房；构建检查与实际玩家操作分别记录。GitHub 获取流程尚未实际下载验证时，必须标为待验证。提交/推送/主线变更由 Codex 整合，不让双方同时写同一目录。完成后交付修改清单、目录体积、测试证据和最多 5 条用户试玩步骤。该任务单尚未自动发送给 Claude。

#### 玩家客户端入口（2026-09-28）

用户要求：继续使用 `StartManagement.cmd`；新增“准备玩家客户端”入口，自动生成与当前服务器匹配的客户端和公开连接配置；朋友只双击 `StartGame.cmd`；保留版本校验；先用隔离测试完成真实登录和入房，GitHub 发布以后单独做。

**实现**：
- 根目录 `PreparePlayerClient.cmd` 调用 `tools/prepare_player_client.ps1`：
  - 读取 `artifacts/framework-games.json` 中当前服务器的射击工程，确认其清单与索引一致；
  - 复制到临时目录后用本机 Godot 导出 `Client.pck`，`Client.exe` 用 4.7.2 官方发布模板；
  - 用 `SetServer.ps1` 校验并写入 `artifacts/client` 中的公开 `connection.json` / `server.crt`；
  - 检查私有文件后，替换 `artifacts/player-clients/shooter-windows/`，并在资源管理器中打开。
- 对外地址是回环地址时给出提示：发给朋友前，要先在后台把对外 IP 设为局域网地址。
- 目录中含 `client-version.json`（build_id、compatibility_id、game_protocol、文件 SHA256）、`CheckClient`、`SetServer` 和中文 README。
- 版本校验沿用服务器原有检查，没有跳过或放宽。
- `examples/framework/client.gd` 新增仅在 `--autoplay=<私有 JSON>` 时启用的测试流程：调用和按钮相同的注册、登录、入房函数，报告中不写密码。
- `tests/test_operator.ps1` 新增可选参数 `-GamesIndex`，默认行为不变。

**复核修正（2026-09-28）**：按 Codex 意见处理了三项，最新隔离验收 20/0，证据在 `logs/player-client-0972f570501e429aad94dfc66d8f71b3/`：
- **输出目录**：只写入 `artifacts` 或 `logs`（参数 `-OutputRoot`），仓库副本只允许写入固定的 `clientsshooter-windows`（`-RepositoryCopy`）；越界或经链接的路径拒绝。新版本先在 `.staging-*` 完整生成；替换前按 `client-version.json` 中的 `generated_files` 比对，发现新增或改动的文件就停止并列出，旧目录不动；旧目录移入 `previous`（仓库副本移入 `previous-repository`）保留，替换失败自动回退。`-TestFailAt swap` 仅供测试注入失败。previous 不会自动清理，每份约 105 MB。
- **测试隔离**：`host/operator.gd` 新增可选参数 `--public-client-dir`（默认仍为 `res://artifacts/client`），`tests/test_operator.ps1` 新增 `-PublicClientDir`。测试使用自己的游戏索引和公开配置目录，前后比对共享的 `artifacts/client` 与 `artifacts/framework-games.json`，都没有改动。
- **统一来源**：删除基于旧 ZIP 的 `tools/publish_shooter_client.ps1`，本地目录和仓库目录来自同一次导出。Release tag 为 `shooter-client-<build_id>-<Client.pck 哈希前 8 位>`，因为源码版 build_id（`shooter-dev-002`）在代码更新时不变，用 pck 哈希区分。
- **20 项检查**：
  - 隔离 Operator 使用专属公开配置目录；越界输出和越界仓库副本被拒；
  - 同一次导出生成两份目录，build、pck 哈希、tag 一致；仓库副本不含连接配置；两份目录都没有私钥或数据库；
  - 重新生成时旧目录进入 previous；用户新增或改动文件时拒绝替换，目录保持原样；注入替换失败后回退，没有暂存残留；
  - 全新目录自检通过；两名玩家真实注册、登录、入房并互相可见；版本不符被拒；
  - Operator 正常关闭；共享文件没有改动。
- **已知限制**：源码版服务器的版本校验只比对 build_id 等字段，而 `shooter-dev-002` 在射击代码改动时不会变化，所以旧客户端连到代码已更新的源码服务器时不会被拒。这是原有的清单机制，本轮没有改协议；更新代码后请重新生成客户端。

**首次隔离验收（已被上面取代）** `tests/test_player_client.ps1`（2026-09-28，12/0，退出 0，证据 `logs/player-client-40f0ef066f064566b0ec33a57c562217/`）：
- 用当前源码生成独立游戏索引，启动独立数据目录、独立端口的 Operator，以及真实宿主和 READY 射击房间；
- 生成客户端，复制到系统临时目录（仓库外），`CheckClient` 通过；
- 两个导出的 `Client.exe`（无窗口模式）用邀请码注册、登录，进入同一房间，在房间快照里互相可见；
- 从改过 build_id 的工程副本导出的客户端被拒绝，提示“客户端与服务器版本不匹配”；
- Operator 正常关闭。测试期间被隔离 Operator 覆盖的 `artifacts/client` 已恢复，并逐字节比对一致。
- 测试没有读写 `data/framework/`，也没有碰用户正在运行的服务器。

**已为用户生成**：基于 21:50 启动的服务器，得到 `artifacts/player-clients/shooter-windows/`（109,645,254 字节，build `shooter-dev-002`，`wss://127.0.0.1:28300`，只能本机使用），`CheckClient` 通过。

**未验证**：
- 真人图形界面点击试玩；
- 另一台电脑的局域网连接（需在后台设置对外 IP 并放行防火墙）；
- 服务器程序或射击代码更新后旧客户端被拒（机制与上面的反向测试相同，未另测）。

#### 独立射击客户端实施（2026-09-28）

Claude 实施，基于 `main` `f318c10`，未提交，待 Codex 复核。没有改游戏、认证或资产代码，没有碰 `data/framework/`，没有启用付费服务，也没有提交或推送。

**大文件核实**（2026-09-28 查阅 GitHub 文档）：
- 普通 Git 文件超过 100 MiB 会被拒收；
- Git LFS 免费额度是存储和流量各 10 GiB/月，下载源码压缩包也计入流量。预算设为 0 时超额会被阻止，未设预算时会计费；
- Release 附件单个文件要求小于 2 GiB，不限流量。

`Client.exe` 就是 Godot 4.7.2 官方 `windows_release_x86_64` 模板，109,268,480 字节（104.2 MiB），放不进普通 Git。每次下载约消耗 LFS 流量 0.1 GiB，免费额度一个月只够约 95 次，还有超额计费风险，所以不用 LFS。

**方案**：
- 仓库跟踪 `clients/shooter-windows/` 中除 `Client.exe` 以外的文件（约 0.37 MiB）：`Client.pck`、启动脚本、`SetServer` / `FetchClient` / `CheckClient`、`README.md`、`client-version.json`。
- `Client.exe` 作为 Release `shooter-client-<包 id 前 8 位>` 的原文件附件，不压缩。
- 朋友有三种获取方式：
  1. 克隆仓库后运行 `FetchClient.cmd`，它按 `client-version.json` 里的大小和 SHA256 校验；
  2. 在 Release 页面把全部附件下载到同一文件夹；
  3. 直接复制整个目录。
- `.gitignore` 排除 `Client.exe`、`connection.json`、`server.crt`、`server-config/` 和下载残留文件；`.gitattributes` 把 `*.exe`、`*.pck` 标为二进制。

**生成方式（已被取代）**：原先由 `tools/publish_shooter_client.ps1` 从独立包 ZIP 取客户端；复核后该脚本已删除，改由 `PreparePlayerClient.cmd -RepositoryCopy` 生成，见上方“复核修正”。
- 文件直接从 ZIP 读取，按包内 `checksums.json` 校验后才写入，不从可能含测试数据的解压目录复制，也不重新导出。因此客户端与该包的服务器属于同一次构建（`build_id` 必须一致）。
- 玩家辅助脚本的源文件在 `tools/shooter_client/`。
- 脚本最后会检查目录里不含 data/run/logs/备份、`.key`/`.sqlite`/token 或 admin/secret 字样的文件，并对所有 PowerShell 文件做语法解析。
- 以后每发布新包，重新运行这个脚本、提交目录，并用新 tag 上传 Release。

**设置服务器**：`SetServer.cmd` 接收服务器主机运行 `PublishClients.cmd` 后得到的 `connection.json` 和 `server.crt`（可把文件夹拖到它上面，或放进 `server-config/`）。
- 只允许 url、ca_certificate、server_hostname、managed、secure_enet 这几个字段；url 必须是 `wss://主机:端口`。
- 证书中出现私钥时拒绝。
- 没有新增图形界面。
- `PublishClients.cmd` 只在独立包根目录里，仓库根目录没有。客户端必须搭配同一个包的服务器：源码版 `StartManagement.cmd` 的射击版本号是 `shooter-dev-002`，和独立客户端对不上，不能配对。

**Release 发布步骤**（尚未执行，需要用户或 Codex 授权推送后再做，GitHub 网页即可，不需要 `gh`）：
1. 推送包含 `clients/shooter-windows/` 的提交；
2. 新建 Release，tag 取 `clients/shooter-windows/client-version.json` 的 `release_tag`（当前为 `shooter-client-shooter-dev-002-22250f37`），目标为该提交；
3. 上传 `Client.exe` 和目录中其余全部文件作为附件，不要打包成 zip；
4. 在新目录里跑一遍获取方式 1 和 2。

**测试（2026-09-28，本机）**：

| 项目 | 结果 |
|---|---|
| `publish_shooter_client.ps1` 从 `aa019dbc…` 包生成目录 | 通过，`SHOOTER_CLIENT_READY`，109,641,709 字节 |
| 复制到仓库外的全新临时目录后运行 `CheckClient` | 通过，4 个文件校验一致，服务器未设置 |
| 用本机开发服务器发布的公开 `connection.json` + `server.crt` 运行 `SetServer` | 通过，退出 0；再次 `CheckClient` 显示已设置 |
| 在证书中加入私钥标记后运行 `SetServer` | 按预期拒绝，退出 1 |
| 全新目录中的导出 `Client.exe --headless --ui-smoke` | 退出 0，`login_ready=true`：配置和证书被接受，不依赖仓库或 Godot 安装；未连网 |
| 删除 `Client.exe` 后运行 `CheckClient` / `FetchClient` | 正确报告缺失，退出 1；Release 尚不存在，下载失败（“连接被意外关闭”），未留下 `.partial` |
| `git status --ignored` | `Client.exe` 被忽略，其余文件可纳入 Git |

**待验证**：
- Release 上传后按获取方式 1 和 2 实际下载；
- 在另一台电脑（或本机新目录）连接正在运行的服务器，真人完成登录并入房；
- 由 Windows 智能屏幕或杀毒软件造成的首次运行提示（exe 没有代码签名）。

以下是第二、三阶段的建议顺序与门槛，本阶段没有开始这些工作。

1. **Git 主线整理**（第二阶段第一步）：`main` 是当前分支的祖先，可以直接快进到当前成果，不需要合并提交。建议：用户确认后把 `main` 快进到第二阶段起点的提交并推送，GitHub 默认分支保持 `main`；之后按清理候选表逐项处理。门槛：`git merge-base --is-ancestor` 检查通过；推送后远端 `main` 与本地一致；README 的分支说明同步更新；旧分支删除单独确认。
2. **独立射击客户端的实际获取流程**：先实测 3 种方式（Git LFS 免费额度内的直接克隆、GitHub Release 附件、拆分/精简导出使单文件低于 100 MiB），记录每种方式朋友实际需要的步骤、下载体积与是否得到可直接双击的完整目录。门槛：在一个全新目录（不含服务端数据）中按记录的步骤获取后，双击即可连接到测试服务器并登录；目录中没有账号库、私钥或管理员凭据；不启用付费额度，不压缩。
3. **后台 UI**：先把现有页面操作按“启停、房间、玩家、资产、维护、危险操作”列出步骤数，再重排信息与流程；同时修正离线提示中的旧入口。门槛：关键操作步骤数有前后对比；危险操作仍有权限检查和确认；页面函数 Node 测试与 `admin_http` 回归通过；用真实浏览器截图完成人工点击验收。
4. **基础音效**：放在客户端/游戏展示层（`examples/framework/` 或游戏目录），不进入宿主核心或 SDK；先选可分发许可的素材并记录来源。门槛：开枪、命中、死亡、购买、按钮五类声音可听到；音量与静音设置可保存；许可清单入库；射击回归与完整客户端测试通过。
5. **Linux 调查顺序**（第三阶段）：① 在 Linux 测试机上确认 Godot 4.7.2 headless 与导出模板可运行；② 选定存储访问层替换方案并用现有 `schemas/`、`tests/run_accounts.gd` 等语义测试对照；③ 实现进程身份与目录保护的 Linux 版本；④ 编写 Linux 启动/安装脚本；⑤ Windows 客户端连接 Linux 服务器完成登录、开房、游戏与持久化闭环。门槛：同一套 Godot 回归在 Linux 通过；Windows 一键运行回归不退化；跨机闭环有截图与日志证据；数据库文件可在两平台之间备份恢复。

---

2026-09-21，用户确认并授权实施。分支 `codex/shooter-framework`，起点 `1a8bec5`。这是开发规格，不是完成报告；实际结果见 ../STATUS.md。仅使用当前仓库，不读取、迁移或修改旧游戏。

## 一、架构边界

1. 通用框架：稳定账号、认证、房间进程与席位、永久资产及默认配置、结果/奖励事务、后台与审计。
2. 可选类型模块：有真实复用需要时提取射击/伤害等能力，不预先造空模块。核心不反向引用该层。
3. 具体游戏/模式：地图、物品属性、允许操作的条件、出生/死亡、回合、胜负和奖励计算。框架只调用注册规则，不识别“死亡”或“维修区”。

依赖方向是游戏 → 可选模块/SDK → 通用契约。类型模块不得成为所有游戏的必需依赖；赛车和取石子不需要武器、人物或射击状态。

永久资产和比赛资产必须分开：账号金币、所有权、经验和默认配置由持久服务保存；比赛金钱和临时装备由比赛实例持有，按 match_id/launch_id 隔离并随模式重置。不能把同一个余额包装成两种 UI。比赛检查点和崩溃续赛不是第一版承诺。

配置槽由游戏定义，保存 item_id，不保存客户端声称的伤害或任意可执行内容。默认配置按游戏隔离，即使两个游戏共享钱包，也不能互相覆盖配置。房间根据已确认所有权和版本生成当前实际装备。

## 二、用户确认的产品范围

### 管理与账号

- Windows 本机单管理员后台，只监听回环；玩家使用局域网加密连接。沿用 Godot/GDScript、PowerShell、SQLite，不新增 Node/Go 后端。
- 后台独立常驻，可启动/停止/重启游戏宿主、维护模式、创建/关闭/禁止加入/重新创建房间。后台启动不弹玩家窗口，宿主停止不关闭后台。
- 停服默认 60 秒公告与拒绝新入房，随后保存已确认数据、断开成员、确认退出并回收；立即停止有操作确认。
- 管理员与玩家都能开房；默认每个玩家一个活动房间，总上限可配。
- 邀请码＋用户名密码注册，邀请码有次数/期限/撤销。支持改昵称/密码、退出；同一玩家账号一个有效会话，新重复登录拒绝。管理员使用独立身份，管理员再次成功登录会轮换其旧会话；玩家不可升级为后台管理员。
- 后台查账号、重置密码、踢人、封禁/解封；重置或封禁撤销旧会话。密码使用平台成熟的加盐密码派生实现，不存明文，不接邮件/短信。
- 状态展示 CPU/内存/数据盘空间、房间、在线玩家、错误；采集缺失明确标不可用。日志和审计仅限本项目，不提供任意 SQL/shell/文件浏览。

### 永久资产与配置

- 后台可查看/调整金币、经验、所有权和默认配置；等级由经验表计算。变更均有原因、操作者、前后值和结果。
- 每个游戏选择独立或命名的共享资产空间。共享空间统一商品、货币和经验规则；服务器解析空间，客户端无权指定。
- 开发时停服切换空间；分别保存数据，切回能恢复原空间，不自动合并或复制。
- 首版永久物品为非堆叠解锁权。升级、配件、消耗品与外观商店演示后移，后续通过带版本的项目 Schema 扩展，不做任意 JSON 写入接口。
- 历史开发身份的结果保留，不按昵称自动关联新账号。真实支付、交易和拍卖不在范围内。

### 横版射击示例

- 新建 2D 横版平台射击，小地图、左右移动/跳跃/鼠标瞄准/射击；简单图形，无旧资源。
- 自由混战，两人开始，5 分钟一局。服务器判定移动、射速、命中、伤害、死亡和出生。即时命中、无限备用弹药；暂不做换弹、技能或命中回溯。
- 三把枪：基础步枪初始免费拥有，冲锋枪/霰弹枪默认 100/200 金币解锁；枪械属性只在示例定义。
- 新账号 0 金币。完整对局参与至少 60 秒奖励 20 金币，每次有效击杀额外 5 金币；整场结算后统一到账，中止对局不发正常完局奖励。管理员可发放测试金币。
- 大厅和死亡期间可打开背包、解锁和选择武器；存活时不能打开，服务端同样拒绝修改。
- 解锁不自动选择。选择成功自动保存默认配置，用于本次复活和以后入房；存活时不因后台或配置更新而立即换枪。
- 死亡等待至少 3 秒后手动复活，允许在此期间慢慢选枪。复活必须等此前正在处理的选择结束；配置失效时退回基础枪并提示。

### 运维

- 默认每 30 分钟备份，保留 48 份自动备份；手动备份另存。恢复需停服，先做恢复前备份，恢复后撤销旧会话。
- 宿主崩溃后确认旧进程与端口安全再重启，10 分钟内最多 3 次。主动停服不重启，失败超限留告警。不凭旧 PID 认领/终止进程，不恢复未完成对局。
- 不安装开机服务、不自动改防火墙、不部署公网；提供公开连接配置/证书，私钥和凭据不进入客户端分发包。

## 三、交易与授权接口决策

- 资产请求通过保持在线的大厅连接处理；服务端根据席位确定玩家所在位置。大厅操作调用游戏的大厅规则，在房间内则经过当前已认证房间的规则检查。
- 许可绑定 user_id、game_id、room_id、launch_id、成员代次与操作编号，不接收客户端“已死亡”的断言。离房/重连使旧许可失效。
- 同玩家资产操作和游戏状态转换排序；规则在提交前确认，复活不越过待完成的选枪。断线或超时后允许用原操作编号查询数据库已提交结果，禁止盲目重复扣费。
- 解锁扣款、所有权新增、版本与审计流水同事务；幂等 key 复用不同内容拒绝。默认选择事务再次校验所有权；购买与选择分别有独立结果。
- 持久状态采用版本检查，过期版本返回冲突，重新读取后重试。游戏进程不直接打开数据库。只有宿主/管理服务信任边界内的交易服务能提交写入。
- 商品/资产/配置/交易 Schema 放 schemas/，对应例子在 examples/。新增接口要有错误码与兼容说明，不让设计草案冒充已上线协议。现有大厅未知消息仍拒绝。

## 四、阶段与完成门槛

| 阶段 | 交付 | 验收 |
|---|---|---|
| S0 | 分支、架构/契约、资产空间和临时经济边界 | Godot 契约/规则测试；持久适配一旦实现，须真实 SQLite 验证 |
| S1 | 独立后台、宿主启停、状态/管理命令 | 浏览器启动真实宿主，停止后后台继续在线；进程确认与回收 |
| S2 | 注册/登录/邀请码/管理权限/会话 | 两个真实客户端、重复登录/封禁/失效/限流 |
| S3 | 永久钱包、所有权、配置、后台操作、房间许可 | 并发消费、幂等、响应丢失、跨用户/房间拒绝、空间切换 |
| S4 | 横版射击大厅/背包/死亡/复活/结算 | 两名真实玩家完整循环；存活伪造请求拒绝；取石子主题使用同接口且不改核心 |
| S5 | 备份/恢复/重启、SDK模板/独立包 | 故障注入、真实导出、浏览器与客户端视觉检查；第二台设备单独验收 |

后续战术模式只预留边界：准备/购买/战斗/回合结算、队伍、观战与局内经济均由可选模式实现。本轮不实现攻防目标、角色技能、排位、反作弊产品或断线续赛。

每阶段更新 STATUS：完成、失败、未运行分别记录；本机多进程不等于跨电脑联机，静态/逻辑测试不等于可玩射击已交付。

## 五、2026-09-27 后续方向（已确认，仅规划）

这部分是用户与 Codex 使用 `grilling` 梳理取舍、使用 `domain-modeling` 固定术语后的**未来方向**，不是已实现功能或对外发布承诺。术语见 [CONTEXT](../CONTEXT.md)，当前代码和验证范围见 [STATUS](../STATUS.md)。本轮只记录，不改功能。

- **近期体验与渠道**：先在现有 Windows 电脑上给 2–8 位熟人用下载客户端和邀请码试玩；后台尽量一键管理。小阶段交付一个启动入口和简短试玩步骤。云服务器以后按成本、兼容性选择；第二台设备、Linux、公网和正式运营仍未验收。
- **通用定位**：先服务自己的多款游戏，未来提供给其他开发者自行部署。账号、房间、资产与运维是可选服务，玩法和游戏存档由游戏负责；不要求所有游戏采用射击式对局、统一钱包或强制登录。具体先做自己的第二款游戏还是开发者接入体验，尚未定顺序。
- **优先示例**：赛车参考《漂移风暴》的最多 8 人小房间实时竞速；首版永久资产只考虑车辆解锁与默认车辆，漂移、氮气、赛道、成绩由赛车项目定义。射击与赛车共用账号身份，资产默认隔离；没有确认共享好友、通用货币或跨游戏交易。
- **不同形态的边界检验**：未来还可能做“动森＋种田”式合作游戏，固定朋友共用一个游戏存档。单人可离线玩，联机时再登录；作物按真实时间继续生长，农场金币、作物和背包属于游戏存档。将来希望房主不在线时朋友也能继续玩，但此项后置；存档托管、同步和冲突处理均未设计或实现。未确定玩家间赠送、交易或摆摊，不预置网游经济。
- **下一小阶段验收重点**：稳定开房与回收。当前的 256 条限制是同一结果库**累计启动授权**的上限，并非 256 间并发房或 256 名玩家；授权在停房后不清理，累计第 257 次建房会失败。已选定“房间结束后最多 7 天补交迟到结果”的产品方向；具体清理条件必须先证明不会丢失未完成结算，再设计和测试。此轮没有实施回收。
- **密码体验**：用户选择将所有账号的最低密码长度从 10 改为 8，范围包括注册、登录、改密、管理员重置和相应界面、Schema、存储检查及边界测试。2026-09-27 已在源码工作区实施，真实账号、契约和后台 HTTP 回归通过；独立包已重建并通过常驻模式自动包测试。当前无第二因素，这一选择放宽了密码强度，对外发布时应明确记录。
- **性能取舍**：存储单次往返约 1.0–1.2 秒，每次都启动外层和内层两个 PowerShell 进程。09-27 的购买基线需 3 次往返、约 3.1–3.3 秒；`asset.snapshot` 将购买和选择资产降为 2 次存储往返、约 2.2 秒，独立包已重建，但用户从源码试玩仍觉得慢。真实客户端请求还需一次约 1.2 秒的会话校验，端到端购买和切枪约 3.6 秒。后续按第六节决定先做常驻存储的有限试点；PowerShell 7 的并排安装不会自动改变现有调用。每房一个 Godot 进程和射击 20 Hz 全量状态同步的调整，应以目标设备的 CPU/内存、带宽和网络延迟测量为依据；不承诺尚未测出的提速比例。
- **测试投入**：每个小阶段跑相关回归和可试玩的最小闭环；完整 16 人容量、长对局与导出包验收放在发布前或触及其风险的改动后复验。256 条授权的边界测试用数据库预填记录，不会真的启动 256 间房。

## 六、常驻存储评估与第一阶段实施（2026-09-27）

起因：用户从源码试玩后反馈，买枪和切枪的体感没有明显改善。本节前半部分是当时的测量和风险评估（当时没有改生产代码）；方案 B 第一阶段随后已实施，结果见本节末“第一阶段实施结果”。测量脚本在 `tests/perf/`，原始数据在 Git 忽略的 `logs/`，都只在同一台 Windows 电脑上取得。

### 为什么存储层快了 1 秒，体感却不明显

Operator 处理玩家的每次资产请求（`asset.player`）时，会先调用 `accounts.authenticate` 校验会话，这本身就是一次约 1.2 秒的账号助手往返，然后才是资产的 1–2 次往返。客户端实测（`tests/perf/measure_asset_e2e.ps1`，真实 Operator、WSS，大厅内 3 个账号，`logs/asset-e2e-current-2.json`）：

| 客户端视角 | 中位数 | 组成 |
|---|---:|---|
| 购买 | 3623 ms | 会话校验 1 次 ＋ snapshot 1 次 ＋ commit 1 次 ＋ 约 0.2 秒网络/排队 |
| 切换默认武器 | 3616 ms | 同上 |
| 读取资产 / 重复购买 | 2415 / 2429 ms | 会话校验 1 次 ＋ 1 次 |

snapshot 改动之前，购买在游戏里要 4 次往返（约 4.7 秒），现在是 3 次（约 3.6 秒），只快了约 23%，所以体感不明显。死亡后复活前还会触发一次资产刷新（再加 1 次往返）。房间内的许可跳转没有单独测量。

### 候选方案实测

| 方案 | 单次存储调用 | 推算游戏内购买 | 说明 |
|---|---:|---:|---|
| 现状：外层有界助手 → 存储脚本 | 1092 ms | ≈3.6 s（实测） | 每次启动两个 PowerShell，并重新编译 C# |
| A1：去掉外层 PowerShell，由 Godot 按已持有的句柄自己执行超时 | 585 ms | ≈2.0 s | `tests/perf/storage_oneshot_variants.ps1`，7 次中位数 |
| A2：A1 ＋ 预编译 SQLite 绑定 DLL | 478 ms | ≈1.6 s | 同上；DLL 需要随包构建并校验哈希 |
| B：每个数据库一个常驻 PowerShell 5.1 工作进程 | 13.5 ms（snapshot）/ 16.7 ms（commit） | ≈0.25 s | `tests/perf/run_resident_probe.gd`，51/0；原样在进程内复用现有 `sqlite_store.ps1` |
| C：Godot 原生 SQLite 扩展（GDExtension） | 未测 | — | 需要下载并随包分发第三方原生库，尚未取得同意，没有试 |

方案 B 的其他实测：进程首次启动到第一次应答 628 ms，被强制结束后重启到第一次应答 614 ms；连续 440 次请求后内存没有增长（143 MB → 92 MB）；30 次读改写后回执链与版本完全正确。并发上，4 个线程各开一个工作进程时，中位数 35.6 ms，但 p95 达到 773 ms（多个进程争抢 SQLite 写锁）；4 个线程共用 1 个工作进程排队时，中位数 128 ms、p95 143 ms，没有尖峰，吞吐相近（约 31–35 次/秒）。所以方案 B 应该是“每个数据库一个串行工作进程”，而不是进程池。

登录和注册的主要成本是有意保留的 PBKDF2（60 万次迭代），任何存储方案都省不掉。实测 Godot 自带的 `Crypto.hmac_digest` 实现的 PBKDF2 通过公开测试向量，完整 60 万次的结果与现有 .NET 派生值逐字节一致，空闲时约 1.70 秒（.NET 约 1.87 秒）；也就是说，将来如果去掉 .NET，现有密码哈希仍可验证（`tests/perf/run_gd_pbkdf2_probe.gd`）。

### 迁移风险（方案 B）

- **进程生命周期**：工作进程卡死时，需要按已持有的句柄终止并重启（约 0.6 秒）。卡住期间，同一数据库的所有请求都要等，所以需要请求级超时和排队上限。
- **请求结果不明**：超时或崩溃时，正在执行的请求是否已经提交无法确定。资产（`request_id`）和结果（`result_id`）已经幂等，可以安全重试；`grant` 重复写入会返回 STORAGE_UNAVAILABLE，注册、创建邀请码、登录也不是幂等的，必须逐个设计“查询是否已完成”的补偿路径，不能盲目重发。
- **进程内状态残留**：原型是在同一进程里反复执行现有脚本。正式实现应把脚本改为接收请求对象的函数，并逐项确认没有跨请求残留的变量、事务或连接；这就是主要的改造量。
- **请求传递**：原型为了不改生产脚本，仍通过测试目录里的短期文件把请求交给 `sqlite_store.ps1`。正式实现必须在内存中传递，不能退回到账号和 grant 已经消除的临时文件。
- **资源占用**：每个工作进程约 90–140 MB。账号库和资产库各一个，约 0.2–0.3 GB。
- **不解决的问题**：仍然仅限 Windows（PowerShell 5.1 ＋ winsqlite3），Linux 宿主问题不变；数据库文件格式不变，所以不涉及数据迁移，也可以直接回退到现有的一次性模式。
- **约束检查**：不引入新语言或新运行时，符合 AGENTS.md 的限制。

### 建议

先实施方案 B，只覆盖资产库的 `asset.snapshot`、`asset.commit`、`asset.read` 三个幂等操作，再加上会话校验（它只顺带清理过期会话，重复执行没有副作用）；保留现有一次性模式作为可切换的回退路径，并用本节的端到端测量、复核专项（`run_asset_snapshot.gd`）和并发测试做前后对照。登录、注册等非幂等写操作留在后面的阶段，先设计好补偿路径再迁移。方案 A1/A2 可以作为不改变进程模型的保底选项，但把购买降到约 1.6 秒，体感改善仍然有限。方案 C 对 Linux 更有利，但需要引入第三方原生库，要由用户决定是否下载和评估。

### 阶段决定（2026-09-27，Codex 复核）

按方案 B 开始有限实施：资产库的 `asset.read`、`asset.snapshot`、`asset.commit` 和账号库的 `session.authenticate` 各经所属数据库的一个串行常驻工作进程。不要把多个工作进程当作同一数据库的进程池。暂缓方案 C，不下载第三方原生库，也不决定整体换语言；Linux 适配留给后续独立阶段。

生产实现必须以内存中的有界请求/响应通信，不复用评估原型的临时请求文件；保留现有一次性路径作为明确可切换的回退。工作进程按持有的句柄管理，设请求超时和队列上限；失败或超时后的重试只限本阶段可安全重试的操作，`asset.commit` 必须沿用原 `request_id`，不能产生第二次扣款。新旧路径会同时访问同一数据库，需验证锁竞争、幂等、备份/恢复和工作进程崩溃后重新打开数据库。注册、登录、grant 和创建邀请码等非幂等写操作本阶段不迁移。

验收用同一份真实客户端计时脚本对照购买、切枪、资产读取，并跑资产并发/断线重试、账号会话、结果结算、完整客户端和独立包测试；明确报告客户端耗时、失败与未运行项。原型的约 0.25 秒是推算，不能当作实施后的实测承诺。修改生产代码前核对当前未提交的 `asset.snapshot` 工作区差异，避免覆盖。

### 第一阶段实施结果（2026-09-27，Claude，已本地提交）

已按上述决定实施：`host/storage/resident_store.gd` 为每个数据库管理唯一的一个串行工作进程 `tools/storage_worker.ps1`；`SqliteRepository` 只把 `asset.read`、`asset.snapshot`、`asset.commit` 交给它，`AccountService` 只把 `session.authenticate` 交给它，其余操作不变。工作进程在进程内调用原有助手脚本，请求在内存中传递（助手新增只限进程内使用的 `-RequestJson` 入口）。Godot 持有进程句柄，队列上限 16，单次请求 10 秒超时，超时就按句柄结束进程；工作进程失败时，同一请求经旧的一次性路径再执行一次。`ROOMKIT_STORAGE_MODE=oneshot` 可以整体切回旧路径。Operator 启动后在后台预热两个工作进程，备份恢复前和退出时关闭它们。数据库格式、线上协议和错误码都没有改。

客户端实测（`tests/perf/measure_asset_e2e.ps1`，真实 Operator 和 WSS，大厅内 3 个账号；常驻与旧路径在同一时段交替各测两批）：

| 客户端视角 | 常驻（中位 / 最大） | 旧一次性路径（中位） |
|---|---:|---:|
| 购买 | 97 / 111 ms | 3730 ms |
| 切换默认武器 | 97 / 117 ms | 3746 ms |
| 读取资产 | 83 / 110 ms | 2525 ms |
| 重复购买 | 76 / 83 ms | 2498 ms |

存储层（`run_storage_timing.gd` 5 轮中位数）：购买 38 ms 对 2393 ms，会话校验 22 ms 对 1267 ms；没有迁移的注册、登录、登出、结算，两种模式耗时一致。原型推算的约 0.25 秒被实测的约 0.1 秒取代。房间内（死亡背包）路径和复活前的资产刷新也走同样的操作，但没有单独计时。验收明细见 STATUS。

## 七、测试阶段账号删除（2026-09-27，已实现）

用户纠正了上一轮的理解：停用账号并保留资产不满足测试阶段的需求。需要一个**真正删除指定玩家账号及其当前库中账号数据和全部游戏资产**的后台入口；现有 `account.ban/unban` 仍作为可恢复的停用功能，不能冒充删除。用户选择只处理当前运行数据库；项目内旧备份保留，但必须明确标记为可能含已删除账号，恢复它们会带回数据，后续单独处理。没有权限对用户已经复制到项目外的备份作保证。

实施前沿真实调用链核对 `accounts.sqlite` 的账号、会话、限流、审计，以及 `assets.sqlite` 的各资产空间状态、交易回执、比赛结果与离线 outbox。管理员自身不得删除；必须使用服务端查出的 `user_id` 定位，确认目标用户名，拒绝客户端自选数据库或 SQL。删除期间阻止新会话、新资产写入和迟到结算；跨两个数据库的操作需要可恢复的作业记录或等效机制，任何中途失败都不能报告成功。已经保存的其他玩家资产、结算和审计不能因删除一名玩家而丢失。若结果或审计中还有可识别的目标数据，须删去或去标识化，并保持结果去重、签名和审计可用；无法满足时明确阻止删除并报告原因，不能把仅删账号行称为“彻底删除”。

后台要把“停用”和“删除”做成不同操作，删除按钮显著提示不可恢复、当前库范围和旧备份残留，要求二次确认。协议变动同步 Schema、错误码、兼容说明和测试。用**隔离测试库与假用户**覆盖：多个游戏资产空间、在线/离线状态、管理员保护、旧 token、迟到结果、重复删除、跨库中途失败与恢复、其他玩家不受影响、备份恢复可能带回数据。上述规划轮用户暂缓验收，当时没有编写代码；随后用户要求 Claude 实施、Codex 复核，结果见下一小节。实际删除任何真实账号不在授权内，测试只使用隔离目录中的假账号。

### 实施结果（2026-09-27，Claude 实现、Codex 复核，提交 `96d25d1`）

入口是后台“玩家 → 详情 → 删除测试账号”，管理 API 为 `account.delete {user_id, confirm_username, reason}`。它与“停用账号 / 恢复账号”（`account.ban/unban`）是不同的按钮和 action；管理员账号没有删除按钮，服务端也拒绝（`ADMIN_SELF_PROTECTION`）。对话框写明不可恢复、只处理当前数据库、哪些旧备份可能仍含该账号，要求输入用户名并勾选确认，发送前还有一次浏览器确认。

两个数据库和 Operator 自己的文件之间没有共同事务，所以按固定顺序执行，并用账号库里的作业记录衔接：

1. **账号库 `account.delete_begin`**：用管理员 token 认证；`user_id` 只用来查账号，`confirm_username` 必须与服务端查出的用户名一致（不区分大小写），不一致返回 `DELETE_CONFIRMATION_MISMATCH` 且不改任何数据。通过后写入作业（`account_deletions`，状态 `assets_pending`），把账号置为无限期停用（原因固定为 `account_deletion_pending`）并删除全部会话。重复请求沿用同一作业。
2. **在线会话**：Operator 移除自己记录的该玩家 token，通知宿主关闭其大厅连接并撤销房间席位，最多等 5 秒确认状态里已不在线。数据库这边在第 1 步已经删掉会话，所以旧 token 从这一刻起全部失效。
3. **资产库 `asset.purge_user`**（一个事务）：删除该玩家在所有资产空间的状态和交易回执；比赛结果正文里的 `user_id` 换成匿名代号；其他玩家回执中以该玩家为操作者的 `actor_id` 同样替换；写入墓碑 `deleted_subjects`。可以重复执行。
4. **账号库 `local.deletion_finish`**：删除账号行、剩余会话和该用户名的登录限流记录；账号审计里目标或操作者为该玩家的行，标识换成代号，前后快照清空，原因改为 `redacted:account_deleted`，动作、时间、结果保留；其他审计行的原因和快照里出现的该 `user_id` 或用户名（不区分大小写）也换成代号。作业进入“等待 Operator 收尾”（`operator_pending`），此时仍保留 `user_id` 和用户名，因为下一步要用。
5. **Operator 收尾**：在主线程重写自己的操作审计（`operator-audit.jsonl`、`.previous`、`maintenance-audit.jsonl` 和内存副本），同样去标识化，写完再读回确认已不含 `user_id` 和用户名；重新取备份列表；扫描结果队列、日志和其他私有文件中的残留；把“可能含该账号的备份”写进删除日志并读回确认。任何一项失败都停在这里。
6. **账号库 `local.deletion_close`**：作业完成，清掉其中最后的 `user_id`、用户名和原因。

匿名代号是 `deleted_` 加 SHA-256(`user_id`) 的前 32 个十六进制字符。`user_id` 本身是随机值，但持有旧备份的人仍可以用原 `user_id` 算出代号并关联起来，这属于下面“旧备份”的范围。

**只有第 6 步成功才报告成功。** 第 1 步之后任何一步失败都返回 `ACCOUNT_DELETION_INCOMPLETE`（`payload.stage` 为 `assets` / `account` / `operator` / `close`，`payload.cause` 说明原因，例如 `AUDIT_WRITE_FAILED`、`JOURNAL_WRITE_FAILED`、`BACKUP_LIST_UNAVAILABLE`）。账号行还在时保持停用，后台显示“删除未完成”，不能被解封、改名或重置密码（`ACCOUNT_DELETION_PENDING`）。再次提交删除（账号行已删、只差 Operator 收尾时也可以，仍要输入正确的用户名），或重启管理服务（启动时先于 HTTP 服务处理所有未完成作业，包括只差收尾的），都会从中断处继续。

**删除原因**：管理员填写的原因里出现的 `user_id` 或用户名（不区分大小写）一律换成匿名代号：写入作业和审计前就替换；失败的删除请求记入审计时也替换；Operator 自己的审计行同样处理。第 3、4、5 步还会把其他地方的自由文本（其他账号的审计原因、其他玩家资产回执中的管理员原因、维护审计里的备份原因）里出现的该 `user_id` 和用户名换掉。昵称不在替换范围内，因为它可能是常见词，替换会误伤其他文本。

**迟到结算与写入**：墓碑写入后，任何人对该玩家的资产写入（玩家、管理员、重试）都返回 `ACCOUNT_DELETED`。新到的签名结果照常入库并给其他玩家发奖，已删除玩家那一份奖励被跳过（资产库回复带 `rewards_skipped`），存入的结果正文只含代号。`record_hash` 仍保存签名时的原值，所以旧结果和迟到结果的重试都还是 `DUPLICATE`，同一场比赛的冲突检查不变。房间结果队列里还没处理的文件（`outbox/*.json`）会经过同样的入库路径，处理后照常删除；已被拒绝的结果文件（`*.rejected.json`）和运行日志不改写，删除回复的 `residual_files` 会列出仍提及该 `user_id` 的文件。

**互斥**：同一时间只允许一个删除。删除进行中拒绝手动备份、恢复和配置修改（`MAINTENANCE_BUSY`），自动备份顺延 1 分钟，避免备份拍到两个数据库之间的中间状态。

**旧备份**：开始删除前先取备份列表，取不到就不开始。回复和删除日志列出所有创建时间不早于该账号注册时间的备份，它们可能含有该账号。删除日志 `account-deletions.jsonl` 放在数据目录里、不在数据库里，恢复备份不会覆盖它；备份列表因此给每个备份带上 `deleted_accounts` 计数，恢复对话框会提醒“恢复会把已删除的账号和资产带回来”。旧备份本身不改写；复制到项目外的备份无法处理。端到端测试实际恢复了一次删除前的备份，账号和资产确实回来了。

**数据表**：账号库新增 `account_deletions`，资产库新增 `deleted_subjects`，都用 `CREATE TABLE IF NOT EXISTS` 追加，`user_version` 不变（账号库 1、资产库 2），所以旧备份仍能恢复，恢复后第一次访问会自动补上这两张表。`account_deletions` 的 `username`、`closed` 两列是复核修正时加的；首版（未发布）建出的表会自动 `ALTER TABLE` 补列，其中已完成的作业视为已收尾。

**复核修正（2026-09-27，Claude，未提交）**：Codex 复核指出两点：两库完成后 Operator 的审计去标识化和备份标记若因退出或写入失败遗漏，重启无法补做；管理员原因可能含用户名或 `user_id`。现在按上面的第 4–6 步处理：作业在 Operator 收尾完成前不算完成，重启和重复请求都能补做；原因中的名字在各处替换。验收见 STATUS。

验收命令与结果见 [STATUS](../STATUS.md#最新有效验证范围)，协议与错误码见 [docs/21](21_managed_protocol.md#测试阶段账号删除)。
