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

公网试玩收到人工通过反馈，同时朋友与本人单人入房都报告移动像掉帧；本人还报告枪口旋转卡顿，并观察底部 FPS 约 120、感觉没有下降。未采集连续画面帧时间或网络时序，因此更偏向显示同步问题，根因仍未最终确认。输入目标 30 Hz、服务器模拟目标 60 Hz、快照目标 20 Hz；实际频率受设备和网络影响。自己的位置也等待服务器状态再做 50 ms 过渡，没有本地预测；当时枪口方向直接随快照变化，没有角度插值；本轮候选见下节。渲染 FPS 高不代表人物和枪方向也按同样频率更新。

源码新增底部独立诊断行，将画面与网络分开观察：FPS 看平均显示频率，最近一秒最慢帧用相邻客户端显示处理调用的单调时间差记录停顿，首帧只建立基线；不用可能被截顶或平滑的引擎 `delta`。ENet RTT 是房间连接的往返估计，更新间隔是相邻严格增长 tick 的本机接收间隔，“未更新”是距离最后一次状态推进的本机时间。重复/旧/非法状态不推进诊断；没有有效样本或没有房间连接时显示“—”，鼠标悬停可看定义。这些值不等于单程延迟、GPU 耗时或丢包率。

本次只更新源码，正在试玩的 `427e6a0cf8a8` 服务端与玩家目录保持原样，尚不显示新指标。呈现代码也参与构建摘要，采用新源码时须重新生成匹配的服务器/客户端；不能只换一侧或把旧客户端当作新功能验收。

下一次短验先观察：FPS/最慢帧异常时查渲染和客户端主线程；帧率稳定但状态间隔或等待明显增大时查网络和服务器更新。枪口自身的低频呈现可以独立改善；本地瞄准、他人角度插值、缓冲插值与自己的移动预测分别设验收，不凭这次反馈一起改同步协议。诊断本身不宣称卡顿已修复。

<a id="aim-smoothing-candidate"></a>
## 枪口呈现候选补丁（2026-10-02，未合并）

固定基准 `4e49aa1f6845bba010a17c7a8d9e896767356011`，独立分支 `codex/aim-smoothing-dot`。本轮只在 dot 云端电脑的新克隆验证，不操作用户设备、现有服务或当前玩家目录；交付可应用补丁，不推送、不合并。

### 原因与实现

基准代码在客户端目标 30 Hz 发送鼠标方向，服务端目标 20 Hz 回传完整状态，`draw_on` 直接使用回传的 `aim_x/aim_y`。因此画面即使约 120 FPS，转枪也只有约 20 次/秒的新方向；已有 50 ms 插值仅覆盖位置。这是确定的呈现限频，不能据此排除用户环境里的帧时间或网络问题。

- 自己的枪：在每个客户端显示处理帧读取鼠标，直接显示同一帧原有输入向量的归一化结果，无额外平滑尾巴。原有 30 Hz 发送门槛、瞄准原点、零向量回退、焦点/背包/忙碌时的操作限制全部保留。
- 他人的枪：独立角度轨道，以 50 ms 为目标时长沿最短圆弧插值；中途快速反向从当前已显示角度接续。跨 ±180° 不绕远路，重复目标不重置计时，断流只走到最后目标。
- 首次出现、死亡/复活、死亡计数改变（覆盖丢失死亡快照）、传送、移除和换房清理角度状态。角度时钟不重启原有位置插值。
- `handle_input`、`advance`、`_move/_move_step`、`_fire`、伤害/出生、RPC 声明、`send_input/send_respawn`、快照字段、弹迹几何保持原代码；服务器判定、协议、移动规则不改。客户端只读呈现仍不预测命中。

### 误差的准确含义

本地显示即时响应会领先服务器收到的输入，也会领先较早射击的回传弹迹。没有用当前枪口重画服务器弹迹，不能宣称任何时刻方向都完全重合。

- 静止、已处理同一输入的基础步枪：显示方向与该枪射线方向误差为 0°（断言 <0.001°）；这是特定同输入场景，不是快速瞄准的普遍零偏差承诺。
- 合成 120 Hz 渲染、720°/秒匀速转向，保留 30 Hz 输入、60 Hz 权威步进/冷却和 20 Hz 快照。在该采样相位下，无注入延迟时“开枪当时的当前显示方向 vs 服务器实际射线”最大约 18°；注入 50 ms 单程时约 42°。权威射线首次随状态到达客户端时，与那一刻的新显示方向最大分别约 42°、102°。这是离散延迟夹具，不是真实公网延迟测试或通用上界。
- 瞬间反向 180° 时，新显示枪口与旧已确认射线可差 180°；这是不同时刻的比较，不能混称同一输入的射击偏差。服务器弹迹起终点逐项保持不变。
- 坐标分别定义：枪身旋转支点为 `render_position + (0,-5)`；画出的步枪枪口尖端再沿显示方向前进 29 px；权威射线起点为 `server_position + (0,-5)`。静止时支点与射线起点重合，枪口尖端天然相差 29 px。既有位置过渡的 12 px 位移夹具中，支点差 12 px，-35° 同方向枪口尖端与射线起点相距约 20.37 px。这不是本补丁引入的新射击原点。
- 冲锋枪/霰弹枪仍有服务器散布。人物移动而鼠标静止时，由于输入原点继续使用权威位置，仍可能产生随快照变化的方向阶梯；本轮没有移动预测，也没有为消除该现象偷偷改射击向量。

### 实际验证与退出码

环境：Debian 13 x86_64，Godot `4.7.2.stable.official.ed1daf0bf`、pwsh 7.6.6；复用之前项目内已校验工具，HOME/XDG/tmp 全部在新克隆的 `data/aim-environment/`。未安装系统软件。日志为 `logs/aim-smoothing/`，不含交付包中的账号/凭据。

| 检查 | 实际结果 | 退出码 |
|---|---|---|
| `tests/run_aim_smoothing.gd` | 59/0；快转、角度边界、生命周期、30/60/120/240 Hz、泛用外壳与误差夹具 | 0 |
| `tests/run_shooter.gd` | 83/0 | 0 |
| `tests/run_unit.gd` | 319/0；负面传输用例输出 `Exponent too high` 警告 | 0 |
| `tests/run_portable.gd` | 229/0；同一负面用例警告 | 0 |
| `tests/run_client_network_stats.gd` | 30/0；含真实回环 ENet 诊断 | 0 |
| `tests/run_framework_feedback.gd` | 8/0 | 0 |
| `tests/run_client_sound.gd -- --work=<隔离目录>` | 41/0；无声卡听感验收 | 0 |
| `tests/run_managed_contracts.gd` | 292/0 | 0 |
| 官方 Linux 入口 + `linux_l3_acceptance.ps1 -Phase prepare` | 两轮各 6/0 | 两轮 0 |
| 两个真实无窗口 SDK 客户端业务短验 | 两轮各 27/0；WSS 登录、资产、DTLS 入退房、输入、重登 | 两轮 0 |
| 最终官方停止/状态/资源检查 | 不运行；本轮 TCP/UDP 监听及自有引擎/助手均为 0 | 各 0 |

120 Hz 是确定性时间步夹具；暖机后的一秒内，直接读取快照方向只有 20 次变化，逐帧本地与远端插值方向各变化 120 次。该数字不是云端 GPU 或显示器实测 FPS。单元/可移植套件覆盖有重叠，不相加宣称唯一用例数。除上述两个负面测试警告，最终定向输出无脚本错误。

最短复跑方式（在可写的隔离工程内设置 HOME/XDG、`ROOMKIT_GODOT` 后）：

```bash
"$ROOMKIT_GODOT" --headless --path . --script res://tests/run_aim_smoothing.gd
"$ROOMKIT_GODOT" --headless --path . --script res://tests/run_shooter.gd
"$ROOMKIT_GODOT" --headless --path . --script res://tests/run_unit.gd
```

真实服务使用新实例 `aim-candidate`、`aim-confirm`，独占回环 TCP 30691/30700/30701、UDP 30740–30755；启动、准备、客户端和清理均在同一持有 shell 内完成。第一次资源扫描错误地把沙箱包装进程 PID 1 当作引擎，扫描退出 1；官方停止/状态已退出 0、监听为 0。改为核对 `/proc/<pid>/exe` 后重新验证。两次补跑启动因沙箱命令工作目录被现有源码进程防护误识别而安全拒绝（各退出 1，未启动服务）；改从父目录进入工程发起持有 shell，未修改或绕开保护代码，最终整轮清理退出 0。

其它失败保留：首次音效调用漏传 `--work`，退出 2；首版测试继承脚本使配置相对路径错误，虽汇总 50/0、退出 0，却有 JSON 错误，不计通过；改组合夹具后错误消失。新增时序夹具一次类型推断编译失败，退出 1，明确类型后最终 59/0。最初通用客户端改动会让取石子调用不存在的 `player_view`，审查中发现并改回能力判断，新增生产外壳用例覆盖。没有删除失败断言或吞错。

### 尚未验证与采用方式

未验证：真实图形画面/真人鼠标手感、真实 120 Hz 显示器、Windows 导出客户端、真实网络快速转向视觉、公网/跨设备/抖动丢包条件、长时间性能、重新打包部署。当前环境本轮没有图形显示会话，因此没有把无窗口数值测试称为图形验收。

呈现源码也参与游戏构建摘要。采用前在独立目录应用补丁、运行测试，再生成匹配的服务器和客户端，安排明确的更新窗口；不能直接覆盖现有玩家文件或只换一侧。建议短验：快速左右扫动与整圈、跨左侧边界、开枪时突转、移动且鼠标停在近处、死亡选枪后复活、退出再加入，观察枪口与较早弹迹的差别。移动时序优化保持独立后续任务。

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

<a id="aim-comparison-review"></a>
## 两版候选的本机复核（2026-10-02）

基准均为 `4e49aa1`；主线、真实服务和现有玩家目录不变。dot 原补丁 SHA256 为 `5597e38c72f5c95275bfbde526c01eec25dbd80b90e475d788b5b20c6bc37533`，原始应用 tree 为 `bd96ebcb13fc7298801c21cef5f93c74053dfdfc`（原样导入提交 `5f7eaca`）。65 个清单文件哈希一致。没有将复核入口的改动混入原补丁身份。

Codex 在本机独立跑 dot 的瞄准 59/0、射击 83/0、诊断 30/0、反馈 8/0，实际退出均 0，stderr 空。没有重跑 dot 云端的完整业务套件；云端结果与本机结果分别记录。

两份工作树增加同一份 `tests/run_aim_compare_preview.gd` 与 `CompareAim.cmd`，只兼容候选的不同呈现接口，不改候选实现。固定人物位置、20 Hz 合成快照，左侧鼠标瞄准、右侧合成转向；TAB 切换旧呈现/本候选，ESC 退出。它覆盖游戏绘制路径，不比较生产客户端的弹窗/焦点策略，不连接网络、不读取账号。

同一台 Windows、同一 Godot 4.7.2 真实 OpenGL 渲染，各约 2.5 秒：Codex 298 帧/298 次方向变化，dot 297 帧/296 次变化，退出均 0、stderr 空，截图已查看。帧数差不作为性能排名；这不是公网、导出包或真人手感验收。轻量证据与截图在 dot 复核工作树的 `logs/aim-compare/`、`logs/dot-review/`。

两版核心做法相同：本地逐帧瞄准、远端 50 ms 最短角度过渡、权威射击不变。防护和输入状态处理有差别，目前没有复核出必须退回的缺陷。dot 对快速转向的显示/权威射击时序偏差测量保留；既有位置缓冲与人物移动卡顿都未解决。

本地候选此前记录约 24 分钟交付，含多代理实现与复核，不能代表单个模型速度。dot 未提供可核对的任务起止时间，无法评定速度胜负；断言数量也不作为质量排名。等待用户比较两份入口的手感，再选方案合并与生成同版服务器/客户端。本机受保护的 6 个真实文件哈希与修改时间保持不变；没有 dot 工作树残留引擎进程。
