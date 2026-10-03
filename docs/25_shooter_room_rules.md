# 射击显示与房间规则（2026-09-26）

## 本机使用

源码已更新，但已打开的进程不会热加载。先退出玩家窗口，双击根目录 `StopManagement.cmd`，等提示关闭完成，再双击 `StartManagement.cmd`，刷新网页并点击“启动服务器”。这会保留账号和已保存资产，结束当前未完成对局。随后重新双击 `StartShooterClient.cmd`。

在管理网页的“房间管理 → 创建房间”选择射击示例，可填写：

| 选项 | 范围 | 默认 |
|---|---|---|
| 每局时长 | 30–3600 秒 | 300 秒 |
| 获胜击杀数 | 0–1000，0 表示只按时间结束 | 0 |
| 复活等待 | 0–60 秒 | 3 秒 |
| 最大玩家数 | 1–16 人；至少两名玩家开始比赛 | 8 人（创建表单） |

时间到或任意一名玩家达到击杀目标即结束该局，然后开始下一局。这里的时长是每局比赛时长，不是服务器进程存活时间。已有房间点“规则 / 重建”，修改后确认；当前玩家会断开，未完成局不结算。非法规则会在关闭旧房间前被拒绝。玩家大厅的创建按钮使用游戏默认规则。规则按房间生效，不改其它房间，也不修改全局武器和永久钱包。

奖励仍要求本人实际参与至少 60 秒；短局/快速达到击杀数不会绕过限制。结果记录实际结束时长，而不是把提前结束的比赛写成完整配置时长。

## 移动与子弹

原实现将 20 Hz 的权威状态直接画在屏幕上，即使渲染为 60 FPS，人物位置也只每秒变化约 20 次。现按显示帧对人物坐标做 50 ms 平滑过渡；死亡、复活、传送立即切换，丢包时最多走到最后收到的位置，不无限预测。服务端追帧改为逐步时间戳，避免同一帧补步重复使用同一个毫秒时间。文本/列表刷新限制为 10 Hz，地图照常逐帧画，游戏底部显示真实渲染 FPS。

此前整条命中射线持续 160 ms，看起来像激光。现在是最长 18 像素、快速移动的短弹迹和短暂撞击亮点；同一枪不会在重复状态包中反复播放，断流也会自行消失。服务器仍使用即时射线判定命中；没有引入飞行时间、弹道下坠或提前预测伤害。

<a id="client-diagnostics"></a>
## 客户端卡顿诊断（2026-10-02）

**N1 扩展已接入源码**：底部新增“可靠发送丢包估计”，右下角“网络详情 / 报告”显示 RTT 波动、ENet 收发速率、连接阶段、快照间隔与等待时间。RTT 是往返估计；波动是 ENet 平滑绝对偏差，不是标准差；丢包只统计 ENet 的可靠发送估计，不代表所有 UDP 或下行快照丢失。刚连接显示“统计中”，等完整统计周期后才显示实测值；RTT 分位数至少需要 10 个秒样本。指标来自一个采集点，界面与日志共享缓存，换房/断线清零，不增加探测流量。

导出版数据在 **Client.exe 旁 `client-data/`**：音效设置在 `settings/audio.json`，脱敏每秒网络日志在 `reports/`，待确认交易另放 `pending/`。源码默认用项目 `data/client-local/source`。点“标记刚才卡顿”可在报告中标出时间，再点“打开报告目录”；只发送 `reports` 中的 JSONL，**不要发送整个 client-data**。报告不写账号、密码、令牌、票据、邀请码或完整配置；测试证明的是白名单和实际记录，不是承诺任意手动添加文件都已脱敏。

日志每会话最多 2 MiB、默认保留两份结束会话、总预算 16 MiB；多开分开记录，不删除另一活跃会话。目录不可写或容量不足时停止日志并提示，不影响游戏、不转存 C 盘；无法保存交易回执时则拒绝发起该交易。重新生成会把本地数据移到新客户端，迁移失败回退；旧版无服务器标记的回执需要本人确认归属，保留原操作编号，不自动重发。未知格式、重复键与冲突回执拒绝迁入并保留原件。

新同源候选为 `56f4b235deea`，Windows 客户端与 Linux 服务器包已生成，尚未切换现有试玩服务。下面初版诊断记录保留为历史；当前验收和未运行项见 [N1 主线结果](17_framework_shooter_plan.md#n1-mainline-acceptance)。

公网试玩收到人工通过反馈，同时朋友与本人单人入房都报告移动像掉帧；本人还报告枪口旋转卡顿，并观察底部 FPS 约 120、感觉没有下降。未采集连续画面帧时间或网络时序，因此更偏向显示同步问题，根因仍未最终确认。输入目标 30 Hz、服务器模拟目标 60 Hz、快照目标 20 Hz；实际频率受设备和网络影响。自己的位置也等待服务器状态再做 50 ms 过渡，没有本地预测；诊断基准 `4e49aa1` 的枪口方向直接随快照变化，现已接收下面的枪口呈现。渲染 FPS 高不代表人物和枪方向也按同样频率更新。

源码新增底部独立诊断行，将画面与网络分开观察：FPS 看平均显示频率，最近一秒最慢帧用相邻客户端显示处理调用的单调时间差记录停顿，首帧只建立基线；不用可能被截顶或平滑的引擎 `delta`。ENet RTT 是房间连接的往返估计，更新间隔是相邻严格增长 tick 的本机接收间隔，“未更新”是距离最后一次状态推进的本机时间。重复/旧/非法状态不推进诊断；没有有效样本或没有房间连接时显示“—”，鼠标悬停可看定义。这些值不等于单程延迟、GPU 耗时或丢包率。

本次只更新源码，正在试玩的 `427e6a0cf8a8` 服务端与玩家目录保持原样，尚不显示新指标。呈现代码也参与构建摘要，采用新源码时须重新生成匹配的服务器/客户端；不能只换一侧或把旧客户端当作新功能验收。

下一次短验先观察：FPS/最慢帧异常时查渲染和客户端主线程；帧率稳定但状态间隔或等待明显增大时查网络和服务器更新。枪口自身的低频呈现可以独立改善；本地瞄准、他人角度插值、缓冲插值与自己的移动预测分别设验收，不凭这次反馈一起改同步协议。诊断本身不宣称卡顿已修复。

<a id="aim-presentation-mainline"></a>
## 主线枪口呈现（2026-10-02）

主线接收本地候选 `d61f513`：自己的枪口在可操作时逐显示帧使用鼠标方向，取向原点与原来的 30 Hz 输入一致；其他玩家用独立的 50 ms 最短角度插值。转向不会重置人物位置过渡。失焦、背包/账号弹窗、busy、离房及关闭会停用本机方向覆盖；死亡、复活、换局、瞬移和离场重进会复位。重复相同快照不重启过渡，同 tick 的有效生命周期变化仍处理。

这些只影响客户端画法，不修改权威状态、30 Hz 输入、服务器命中和弹道、协议或身体移动。快速甩枪时，显示方向可能领先服务器处理的输入；真实弹迹仍画服务器确认结果，没有承诺枪口和上一发方向总是相同。人物移动卡顿、本地移动预测与输入确认不在本次实现中。

根目录 `PreviewAim.cmd` 提供离线合成场景，鼠标瞄准、TAB 切旧/新、ESC 退出，无需开服。主线隔离枪口专项 **94/0**，射击/诊断/反馈 **83/0、30/0、8/0**，实际退出 0、stderr 空；四脚本只解析通过。沿用的候选渲染比较不当作本轮新渲染结果。现有玩家目录与 Linux 服务器未重建，采用新功能仍须生成并更新同版配套目录后做真人短验。

用户随后反馈本人验证转枪“没问题”，作为此次呈现反馈记录；不据此增加未更新联网包、身体移动或公网同步性能的通过结论。

## 通用边界与兼容

可信游戏清单可声明 `room_rules`：整数选项的标题、最小值、最大值、默认值。契约在 `schemas/room_rules.schema.json`；管理界面按元数据生成表单，通用注册表校验名称/类型/范围并补全默认值。只有射击适配器把秒数转成玩法毫秒数、解释 `kill_limit`；host/core 和通用 SDK 不认识枪械、死亡或击杀。

`room.create` 和 `room.recreate` 新增可选 `rules`，旧请求省略时使用默认值；旧无规则游戏保持原行为。`room.stop` 不接受规则。`INVALID_REQUEST` 表示请求结构/类型不满足 Schema，`INVALID_OPTIONS` 表示游戏未声明该选项或超出游戏范围；`INVALID_MANIFEST` 表示可信默认值/上下界非法。

射击状态增加 `kill_limit`，旧客户端严格 Schema 无法接收，所以示例升级为 `shooter-dev-002`、`game_protocol=2`、`compatibility_id=shooter-v2`。管理服务、生成游戏工程和客户端需一同重启/重建。SDK 仍为 0.5.0，此次没有修改通用联网 RPC。旧导出 ZIP 没有更新，不能用旧 ZIP 验收新功能。

## 验证

引擎：`D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`，Godot 4.7.2；当前 Windows。本轮未联网下载依赖，也未操作用户现有房间。

实际命令（Godot 进程由 PowerShell 启动并等待退出，检查 stdout/stderr）：

```powershell
$Godot = 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
& $Godot --headless --path . --script res://tests/run_unit.gd
& $Godot --headless --path . --script res://tests/run_shooter.gd
& $Godot --headless --path . --script res://tests/run_managed_contracts.gd
& $Godot --headless --path . --script res://tests/run_managed_registry.gd
node tests/test_admin_room_rules.cjs
node tests/test_admin_asset_spaces.cjs
powershell -NoProfile -ExecutionPolicy Bypass -File tests/test_room_rules.ps1
& $Godot --path . --script res://tests/run_shooter_visual.gd -- --baseline --output=logs/shooter-visual-baseline
& $Godot --path . --script res://tests/run_shooter_visual.gd -- --output=logs/shooter-visual-smoothed
```

- 单元 320/0；射击 83/0（含击杀目标提前结束、实际时长、平滑、传送、弹迹过期/去重/换房重置）；管理契约 273/0；托管注册 77/0；均退出 0，`logs/rules-run_*.stdout`。
- 面板 JS 表单 10/0，旧资产空间回归 12/0，退出 0。运行生产函数配合 DOM/API 替身，不是浏览器点击验证。
- `test_room_rules.ps1` 18/0、退出 0；真实独立 Operator、Host、Room、两名注册玩家，经本机 WSS/DTLS/ENet 接收 30 秒/3 杀规则，完成实际 30 秒对局，非法重建保持旧 PID，合法重建退出旧进程并复用 UDP 端口。证据 `logs/room-rules-9eb8231a3e8b4f04927b1ee09f4392d8/result.json`，测试私有数据在 `data/room-rules-9eb8231a3e8b4f04927b1ee09f4392d8/`，用户账号未读取或修改。
- 真实 OpenGL / RTX 3080 渲染，合成 20 Hz 输入，六秒采样：直接画坐标约 59.83 渲染 FPS / 20 次位置变化每秒，平滑约 60 渲染 FPS / 59 次位置变化每秒。证据 `logs/shooter-visual-{baseline,smoothed}.{json,png}`。这是真实渲染加合成状态，不是用户现有对局的帧率测量，也不是联机延迟基准。
- 初次渲染夹具在退出时提前释放对象导致回调错误，已移到退出清理；一次换房测试因测试字典引用被清空而失败，已隔离测试输入，最终上述检查通过。没有删除失败断言。
- 未运行：真实浏览器新表单点击验收、真人操作手感、跨机器、Linux、公网、长期性能、新导出包。

## 本次修改文件

- 游戏与显示：`examples/shooter/{game.gd,adapter.gd,game_config.json,game_manifest.json,messages.example.json}`、`examples/framework/view.gd`。
- 通用选项传递与管理：`host/core/{game_registry.gd,room_manager.gd}`、`host/{managed_host.gd,operator.gd,admin.html}`。
- 契约与示例：`schemas/{room_rules.schema.json,game_manifest.schema.json,admin_request.schema.json,shooter_config.schema.json,shooter_state.schema.json}`、`examples/managed_messages.example.json`。
- 验证：`tests/{test_registry_ports.gd,test_shooter.gd,run_shooter.gd,run_shooter_visual.gd,run_managed_contracts.gd,test_admin_room_rules.cjs,test_room_rules.ps1}`。
- 文档：本文件、`STATUS.md`、`docs/{07_versions_decisions.md,21_managed_protocol.md,22_framework_operations.md,23_branch_files.md}`。前面轮次的未提交修改保持保留。

<a id="movement-baseline"></a>
## 人物移动基线与候选比较（2026-10-02）

入口：根目录 `PreviewMovement.cmd`。TAB 在稳定、抖动、断流间切换，Space / B 切换旧／新版强调，ESC 退出。四行分别为固定旧提交、当前 `game.gd` 的 `render_position`、共同最新权威位置、合成轨迹参考。参考行不是已实现的客户端预测，不承诺真实服务器位置可提前知道。启动器从 Git 提交 `bc4f75f77e5521795becc20d3f277a44fb279d97` 取原始字节并校验哈希；已有基准被修改则拒绝覆盖。只保留一份固定基准与一个复用运行目录。

可复用夹具是 `tests/support/movement_probe.gd`，无窗口入口为 `tests/run_movement_baseline.gd`。使用真实 Game 对象和经过 Schema 校验的快照；不连接网络、不启动房间或账号。轨迹为 120 px/s 匀速、20 Hz 快照，显示时钟固定 120 Hz，总长 3 秒，排除前 0.2 秒。抖动延迟循环为 0/15/35/5 ms，断流丢弃源时间 [1.0,1.25) 的快照。每个到达时刻拆分推进，避免把显示帧采样误差混入快照接收。

指标：移动帧比例、连续无位移最长时间、与同一时刻已知轨迹的平均/最大位置误差；等效平均落后 = 平均绝对位置误差 / 120 px/s。它不是 RTT，后续出现超前位置时也只能解释为绝对误差，不能当作带符号延迟。真实渲染预览的 FPS 与固定时钟测量分开报告。

改动前基准结果：稳定 100% 移动帧、最长停顿 0 ms、等效落后 50 ms；抖动 87.5%、16.7 ms、66.1 ms；断流 91.1%、250 ms、63.4 ms。9 项检查只验证夹具快照有效、结果范围和可重复，不代表同步体验通过。这个匀速夹具没有覆盖转向、跳跃、死亡复活、传送或真实公网；新候选的额外检查见下节。

运行示例（从项目根目录，隔离目录每次换新）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_isolated_test.ps1 -Script res://tests/run_movement_baseline.gd -Isolation data/test-movement-comparison-001 -Log data/test-movement-comparison-001/result -TimeoutSeconds 60
```

比较候选时，使用同一份夹具和固定旧脚本；先记录基准提交、候选提交和夹具 SHA256，再跑同一个入口。报告全部三种场景的停顿、位置误差与任何新增显示落后，不以移动帧比例单独决定胜负。

<a id="movement-candidate-result"></a>
## 身体移动呈现改进与边界（2026-10-02）

接收 10x dot 的身体呈现算法，Windows 独立工作树用项目 Godot 4.7.2 复验。只改 `examples/shooter/game.gd` 的呈现：最近六个推进快照的最大到达间隔决定新过渡的时长，范围为 50–100 ms；稳定 20 Hz 保持原来 50 ms。重复或旧快照不重新计时，死亡次数、生命状态、换局、离场重入和权威位置突变会复位。枪口插值仍独立，服务端运动、碰撞、命中、输入频率与协议不变。

这里的 100 ms 是单次过渡时长上限，**不是端到端延迟上限**。计时来自显示帧 delta，并非网卡收包时钟；帧卡顿、同帧批量处理和渲染帧量化会影响采样。没有预测或外推：断流时走到已确认位置后停住。改进不消除 150/250 ms 断流，也不改善 GPU 帧率。

| 同一主线夹具（120 px/s、120 Hz） | 旧版最长停顿 → 新版 | 旧版平均等效落后 → 新版 |
|---|---|---|
| 稳定 20 Hz | 0 → 0 ms | 50 → 50 ms |
| 到达抖动 | 16.7 → 0 ms | 66.1 → 79.9 ms |
| 250 ms 断流 | 250 → 250 ms | 63.4 → 63.4 ms |

候选自带的另一套夹具（235 px/s、40 ms 配置延迟）也在 4.7.2 复现：抖动最长停顿 33.3→0 ms，平均位置误差 26.10→30.16 px，等效增加 17.26 ms。两套夹具条件不同，只各自比较旧／新。停走、反向、跳跃采用位置误差，不把误差除速度解释为这些非匀速场景的延迟。

独立 `run_movement_frame_timing.gd` 14/0：名义 20 Hz 快照交替落在第 5／7 个显示帧，最长停顿 8.33→0 ms，等效增加 5.41 ms，停走后在 58.33 ms 内到达最后确认点；理想每六帧到包与旧版完全一致。这是确定性合成检查，不是实际网络时序测量。

候选生命周期专项 191/0、12 组比较通过；相关枪口 94/0、射击 83/0、诊断 30/0、反馈 8/0，均退出 0、stderr 空。真实渲染预览截图可读，窗口按键覆盖三场景及旧／新强调，8/0、退出 0、stderr 空；不把截图或按键通过当作真人手感验收。详细证据与驱动失败说明见 [本次整合](17_framework_shooter_plan.md#movement-integration-result)。

仍需短试玩：停走、反向、跳跃落地时的追随感，以及边移动边瞄准近处目标。瞄准方向按最新权威位置计算，枪口随显示身体绘制；身体落后会放大这两者的位置差，真实弹道继续按服务器结果。Linux 同补丁独立复验也已核对通过：191/0、12 组、9/9、94/0，各一次；配套交付与真实体验另列状态，不沿用旧枪口小试验冒充。

<a id="snapshot-v3"></a>
## 射击完整快照传输 v3（2026-10-03）

本节描述新源码协议，实际验收范围见 [主线记录](17_framework_shooter_plan.md#snapshot-capacity-20261003)。现有已发布试玩包不会因源码更新而自动升级；必须重新生成同源服务端和客户端。射击 `game_protocol=3`，源码兼容标识 `shooter-v3`，SDK/控制协议不变。大厅和房间仍校验构建、兼容标识及游戏协议，旧 v2 不应混用；各打包入口生成的最终兼容标识以包内清单为准。

玩法完整状态仍以 `schemas/shooter_state.schema.json` 为唯一语义契约，不裁掉玩家、弹迹或结算条目。只在游戏目录内编码，宿主核心和通用 SDK 不依赖此协议。输入、运动和命中判定不变。

- `world_chunk` 为 authority / call_remote / unreliable（无序）/ channel 1 RPC，参数是最多 1000 字节的 `PackedByteArray`。头部为九个 little-endian uint32：magic、version、flags、stream_id、serial、raw_size、encoded_size、count、index；唯一约束见 `schemas/shooter_snapshot_header.schema.json`，JSON 示例展示解码后的头部字段，并非可直接发送的完整包。
- 36 字节头部之后，每片最多 964 字节。正文是普通 Variant，必要时 Zstd 压缩；typed 容器先正规化，64 位整数保持精确。编码/解压最多 512 KiB、最多 544 片；在解码对象前校验容器、长度、UTF-8、有限数和类型，再校验状态 Schema。
- serial 在一个房间 stream 内递增。同 tick 的新 serial 可以更新状态，旧 serial/错误 stream/坏头/冲突分片被拒；只有完整、合法快照才能替换画面状态。不保证每一帧或每一片送达；缺片后依靠后续完整快照恢复。
- 发送只保留一个正在发送的帧和一个等待帧。新发布覆盖等待帧，不打断正在发送的帧；每次 flush 最多 128 片、每个客户端最多 16 片，相邻 flush 至少 8 ms，按客户端轮流发片，长暂停不积累补发额度。新加入者等待下一个完整帧，离开者立即移出接收名单；退出房间、重置和停服清空队列，停服后的成员清理不会重新启动发送。
- 接收侧最多三个未完成帧。寿命为 `max(250, (ceil(count/8)-1)*34+150)` 毫秒，上限 2500 ms；1 片为 250 ms、87 片为 490 ms、544 片为 2428 ms。按最多 16 人、每人每次至少 8 片及约 30 Hz 调度预留预算；这不是实际网络送达保证。生存时间从首片起算、重复片不续期，过期在下一次 `feed()` 时清理。断流期间缓存仍有数量/大小上限，但没有后台定时器主动清空。
- 发送期限比对应接收寿命短 100 ms，过期未发完的尾部被放弃，转向最新等待帧。大状态因此降低有效更新频率并增加延迟；极限 544 片、16 人、30 Hz 仅理论发送跨度约 2.23 秒，不能把安全容量上限称为适合正常对战的负载。

最初固定 250 ms 的设计与最大合法帧的分批预算冲突，因此在未发布的 v3 中改为有界、随片数增长的寿命。原来 87 片突发缺失发生在 2–4 ms 内，单纯延长寿命不能找回这些分片；发送节奏的独立效果需要真实网络及固定 250 ms 对照证明。

`SHOOTER_SNAPSHOT_ENCODE_FAILED` / `SHOOTER_SNAPSHOT_SERIAL_EXHAUSTED` 是本地固定诊断，不包含玩家数据或凭据，不是新增大厅错误码。无效编码不发送；serial 到 uint32 上限后拒绝继续，不能在相同 stream 回绕。客户端换房/会话重置会解除旧 stream 与显示、音效、诊断缓存的绑定。
