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

公网试玩收到人工通过反馈，同时朋友与本人单人入房都报告移动像掉帧；本人还报告枪口旋转卡顿，并观察底部 FPS 约 120、感觉没有下降。未采集连续画面帧时间或网络时序，因此更偏向显示同步问题，根因仍未最终确认。输入目标 30 Hz、服务器模拟目标 60 Hz、快照目标 20 Hz；实际频率受设备和网络影响。自己的位置也等待服务器状态再做 50 ms 过渡，没有本地预测；枪口方向直接随快照变化，没有角度插值。渲染 FPS 高不代表人物和枪方向也按同样频率更新。

源码新增底部独立诊断行，将画面与网络分开观察：FPS 看平均显示频率，最近一秒最慢帧用相邻客户端显示处理调用的单调时间差记录停顿，首帧只建立基线；不用可能被截顶或平滑的引擎 `delta`。ENet RTT 是房间连接的往返估计，更新间隔是相邻严格增长 tick 的本机接收间隔，“未更新”是距离最后一次状态推进的本机时间。重复/旧/非法状态不推进诊断；没有有效样本或没有房间连接时显示“—”，鼠标悬停可看定义。这些值不等于单程延迟、GPU 耗时或丢包率。

本次只更新源码，正在试玩的 `427e6a0cf8a8` 服务端与玩家目录保持原样，尚不显示新指标。呈现代码也参与构建摘要，采用新源码时须重新生成匹配的服务器/客户端；不能只换一侧或把旧客户端当作新功能验收。

下一次短验先观察：FPS/最慢帧异常时查渲染和客户端主线程；帧率稳定但状态间隔或等待明显增大时查网络和服务器更新。枪口自身的低频呈现可以独立改善；本地瞄准、他人角度插值、缓冲插值与自己的移动预测分别设验收，不凭这次反馈一起改同步协议。诊断本身不宣称卡顿已修复。

## 通用边界与兼容

可信游戏清单可声明 `room_rules`：整数选项的标题、最小值、最大值、默认值。契约在 `schemas/room_rules.schema.json`；管理界面按元数据生成表单，通用注册表校验名称/类型/范围并补全默认值。只有射击适配器把秒数转成玩法毫秒数、解释 `kill_limit`；host/core 和通用 SDK 不认识枪械、死亡或击杀。

`room.create` 和 `room.recreate` 新增可选 `rules`，旧请求省略时使用默认值；旧无规则游戏保持原行为。`room.stop` 不接受规则。`INVALID_REQUEST` 表示请求结构/类型不满足 Schema，`INVALID_OPTIONS` 表示游戏未声明该选项或超出游戏范围；`INVALID_MANIFEST` 表示可信默认值/上下界非法。

射击状态增加 `kill_limit`，旧客户端严格 Schema 无法接收，所以示例升级为 `shooter-dev-002`、`game_protocol=2`、`compatibility_id=shooter-v2`。管理服务、生成游戏工程和客户端需一同重启/重建。SDK 仍为 0.5.0，此次没有修改通用联网 RPC。旧导出 ZIP 没有更新，不能用旧 ZIP 验收新功能。

## 验证

<a id="aim-presentation-candidate"></a>
### 枪口显示对照候选（2026-10-02）

基准 `4e49aa1` 的枪口直接跟随服务器快照。`codex/aim-smoothing-local` 候选让自己的枪口每帧读取鼠标，沿用 30 Hz 输入的权威位置作为方向起点；不修改快照，不提高发包频率，也不改服务器命中或弹迹。鼠标贴住该起点时，与原输入同样回退向右。失去焦点、开弹窗、忙碌、死亡或离房时停用本机呈现覆盖。

其他玩家在 50 ms 内沿最短角度转向；未变化的目标不重新计时，新目标从当前显示角度开始。生命、死亡次数、局数或超过 100 像素的位移变化时复位，离场删除轨迹；同 tick 的合法复活/离场同样处理。网络没有新状态时停在最后方向，不做外推。人物位置的现有 50 ms 插值不变。

本机显示可先于服务器确认的方向；实弹/命中仍按服务器收到的输入计算，转枪与点击之间仍受原有输入采样和网络延迟影响。此候选不宣称消除人物卡顿、提高网络性能或实现客户端移动预测。

隔离专项 `tests/run_aim_presentation.gd`：15 组、94/0；射击83/0、诊断30/0、反馈8/0，实际退出0且stderr空。`tests/run_aim_preview.gd` 的真实OpenGL合成状态对照中，20 Hz 快照的2.5秒内方向变化由51次变为298次（渲染约120Hz），两次最终运行无stderr；截图检查通过，不是公网或真人验收。首版预览有配置路径错误，保留失败输出，不计为通过。入口 `PreviewAim.cmd` 只启动此离线夹具。

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
