# RoomKit：独立的本地房间框架

从零开发的多游戏房间框架：一个独立管理后台，加上邀请码账号和永久资产，每个房间是一个独立的 Godot 进程。当前示例有横版射击和取石子。当前主线 `main`；实际通过、失败和未验收的项目只看 [STATUS](STATUS.md)。Windows 本机功能与 Linux 源码服务已有验收；Linux 独立服务器普通目录也已构建和隔离运行。当前跨机业务用源码 SDK 夹具验证，真实 Client.exe 的双人短入退房另列结果，未运行本版 FullRound。旧版朋友公网连通已有反馈；显示改进与快照 v3 已交配套新版，用户简单试玩反馈无问题，高延迟玩家专项仍待参与。其它发行版、云端与导出包长期耐久仍未验收。

**想先了解项目有什么、做到哪一步：双击根目录 `ROADMAP.html`**（项目地图，不需要启动后台或联网），可以按模块或开发顺序查看、搜索、筛选并展开详情。
**开发统一在本目录 `main` 和「完成 RoomKit M0 与 M1」会话。** 其他 14 个会话已归档；候选提交继续保留，17 个工作树已压缩归档，需要继续某项时先恢复对应目录。恢复位置与剩余保护项见 [收拢记录](docs/17_framework_shooter_plan.md#consolidation-20261003)，归档不代表候选已合并或通过验收。

**看玩家卡顿报告：双击 [NETWORK_REPORT.html](NETWORK_REPORT.html)**，选择玩家客户端 `client-data/reports/` 中的一至八个 JSONL，比较延迟、快照停顿和慢帧，查看卡顿标记前后 15 秒。完全离线，不上传；只分享 reports，不要分享整个 client-data。Windows Edge 真实 file:// 和两份隔离联机报告已验，口径与限制见 [使用说明](docs/assets/network-report/README.md)。

**离线比较人物移动：双击 `PreviewMovement.cmd`**，旧版和新版同屏显示；TAB 切换稳定更新、抖动和断流，Space / B 切换强调行，ESC 退出。它使用固定旧提交与当前游戏的真实显示算法、同一合成轨迹，不启动服务器。新版减少快照抖动造成的短暂停顿，会增加少量显示落后；机制及测量见 [移动比较](docs/25_shooter_room_rules.md#movement-candidate-result)。

资源管理器里各文件夹的用途见 [根目录 20 个文件夹说明](docs/01_scope_architecture.md#root-folders)；最新人工回收与保留项见 [进度复核](docs/17_framework_shooter_plan.md#progress-review-20261003)，此前清理和恢复说明见 [清理记录](docs/17_framework_shooter_plan.md#cleanup-review-20261002)。

**分支和本地目录看这里：[主线与工作目录](docs/17_framework_shooter_plan.md#worktree-mainline-20261002)。** 日常仍用此项目根目录；转枪、移动及快照 v3 已交配套联网新版，双击根目录 **PreviewAim.cmd** 可离线看旧/新转枪（TAB 切换、ESC 退出）。

**当前 Linux 新版试玩：双击 `PlayLinuxPackage.cmd`**，用原管理员账号在后台点“启动服务器”，再打开新版客户端 StartGame.cmd。旧账号、资产和证书保留；两平台 DTLS、Linux 源码 4/8 人与真实 Windows EXE→Linux 双人短验通过，真人公网/画面手感另验。给朋友用 `artifacts/friend-clients/snapshot-v3-20261003/RoomKit-player-snapshot-v3.zip`，不要发自己的 client-data。玩家“标记卡顿”后点“提交报告”，在本机准备到 `3455859197@qq.com` 的邮件，由玩家确认发送，不占游戏服务器的报告中转带宽。实际收信待确认，见 [交付与限制](docs/17_framework_shooter_plan.md#snapshot-v3-delivery-20261003)。

配套交付与 Linux 离线更新首版已完成，实际范围见 [交付说明](docs/17_framework_shooter_plan.md#deployment-stage-result)。[2–8 人小规模联机稳定性](docs/17_framework_shooter_plan.md#snapshot-v3-delivery-20261003) 已分别记录 Windows 登录/重连/备份重叠和 Linux 源码严格 4/8 人通过；八份独立成品与 Linux 备份重叠另验。[阶段 6](docs/17_framework_shooter_plan.md#stage6-result) 已完成依赖准备、7 天授权回收与生成物保留规则，并在 Mint/WSL2 各验一次短闭环。[朋友公网试玩](docs/17_framework_shooter_plan.md#friends-public-preparation) 已收到人工通过反馈。诊断和枪口呈现已进主线，快照 v3 同源交付与简单试玩已完成，下一步先复用赛车候选做本地单车完整一圈；职责与完成门槛见 [当前检查点](docs/17_framework_shooter_plan.md#next-checkpoints-20261003) 和 [赛车阶段](docs/17_framework_shooter_plan.md#racing-offline-plan-20261003)。正式部署到独立游戏服务器，机器尚未选定；本地公网实例只用于开发/试玩。

## 准备服务器和玩家目录

**统一管理入口已接入**：Windows 用 `RoomKit.cmd start|status|stop|check`，Linux 用 `bash RoomKit.sh start|status|stop|check`（每次选一个动作）。入口自动识别源码/对应系统的导出包；不带动作只显示帮助。原有双击快捷入口继续可用，当前 Linux 试玩仍用 `PlayLinuxPackage.cmd`。默认实例、状态判断和验证范围见 [统一入口](docs/22_framework_operations.md#unified-entry)。

**新客户端网络诊断已交付**：底部显示可靠发送丢包估计，右下角“网络详情 / 报告”查看 RTT、波动、收发与快照时序，并标记卡顿。导出版设置/报告保存在旁边的 `client-data/`，更新时保留；只分享 `reports` 里的脱敏日志。Linux 试玩已换为配套版本 `e1bbf7b65cc9` / 协议 3，仍用 PlayLinuxPackage.cmd；给朋友也需发完整新版目录，详见 [当前 v3 交付](docs/17_framework_shooter_plan.md#snapshot-v3-delivery-20261003) 与 [诊断说明](docs/25_shooter_room_rules.md#client-diagnostics)。

在这台 Windows 构建机双击 **PrepareDeployment.cmd**，默认生成 Linux 服务器与匹配的 Windows 玩家客户端；Windows 服务器用 `PrepareDeployment.cmd -ServerPlatform Windows`。**OpenDeployment.cmd** 随时打开最近生成的干净目录，其中 `Server/` 给服务器机器，`PlayerClient/` 给玩家。各自的启动、配置和停止步骤都在目录说明里，不需要多层寻找包号。

Linux 可以在本机独立启动，无需台式机保持开机；Windows SSH 入口仅用于远程管理。Windows 包带引擎；Linux 包也带引擎，可用随包 **PrepareEnvironment.sh** 准备缺少的 pwsh 7.6.6。系统 SQLite、ICU、OpenSSL 仍须可用，缺少时检查会报出，不能据此承诺任意新系统都能一键运行。

Linux 换版本时先停止旧实例，再在新包用 **UpdateRoomKit.sh** 做离线复制、校验与确认，账号和资产保留；撤销仅适用于尚未确认且没有数据变化的候选。步骤及限制见 [更新说明](docs/17_framework_shooter_plan.md#deployment-stage-result)。新登记的构建与交付历史默认按用途保留两份，当前可用交付及必要恢复输入受保护；业务备份/迁移快照不按此规则删除。Windows 数据迁移与启动失败后的自动回退尚未实现。

## 环境

- Windows 10/11，自带 Windows PowerShell 5.1 和系统 `winsqlite3.dll`；不需要 Node、数据库服务或其它后端。
- 源码运行前可双击 **CheckEnvironment.cmd**，只检查，不下载或开服；Windows 导出包继续用 **CheckFramework.cmd**。
- 查看项目占用可双击 **[CheckProjectSpace.cmd](CheckProjectSpace.cmd)**：只读列出本仓库、登记的工作树、RoomKit 命名用户目录与磁盘剩余空间，不删除文件、不启动服务。大小为逻辑字节；详细 JSON 用 `CheckProjectSpace.cmd -Json`，统计不完整时退出 2。结果与范围见 [空间体检](docs/17_framework_shooter_plan.md#project-space-check)。
- 从源码运行需要 Godot **4.7.2**。默认路径：

  ```text
  D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe
  ```

  脚本可以用 `-Godot '完整路径'` 指定其它可执行文件，但换版本后要重新验收。

## 从源码启动（推荐）

已生成的独立射击客户端可直接双击根目录 **`StartPlayerClient.cmd`**；首次生成或更新仍用 `PreparePlayerClient.cmd`。入口只启动游戏，不重建客户端、不重启服务器；发给朋友仍复制完整玩家目录。

1. 双击 **`StartManagement.cmd`**，浏览器会打开 <http://127.0.0.1:28291/>。首次运行时设置管理员账号；管理员只能管理后台，不能作为玩家入房。
2. 在网页点“启动服务器”，然后在邀请码页创建邀请码。
3. 双击 **`StartShooterClient.cmd`**，用邀请码注册玩家账号并登录。再开第二个客户端，用另一个账号登录（同一账号不能同时在线）。在大厅或后台创建射击房间，两人加入后开始自由混战：左右移动/跳跃，鼠标瞄准射击；死亡后可打开背包选枪，再手动复活。客户端右上角可以静音、调节音效音量（`M` 键切换静音），设置会保存在本机。

   给朋友的独立客户端（无需安装 Godot）：服务器运行时双击 **`PreparePlayerClient.cmd`**，把生成的 `PlayerClient` 整个目录发给朋友，朋友双击 `StartGame.cmd`。给局域网朋友用之前，先在后台把对外 IP 设为本机局域网地址。GitHub 获取方式见 [docs/17](docs/17_framework_shooter_plan.md#独立射击客户端实施2026-09-28)（未发布）。
4. 取石子客户端用 **`StartManagedTurns.cmd`**，与射击共用同一套账号和资产服务。
5. 结束：网页上的“停止服务器”只停游戏宿主，后台保持运行；**`StopManagement.cmd`** 关闭整个管理服务。

私有数据在 `data/framework/`（账号库、资产库、配置、私钥），不会进入 Git 或玩家分发包。源码更新后按这个顺序重启：先退出旧客户端，然后 `StopManagement.cmd` → `StartManagement.cmd` → 在网页启动服务器并建房 → 重新打开客户端。账号和资产会保留。

管理后台的“玩家 → 详情 → 停用账号”会撤销玩家登录并保留账号与所有游戏资产；需要时用“恢复账号”。停用默认无限期，**不是删除数据**。用户已反馈新版后台登录、退出重登和建房正常；具体范围见 STATUS。

测试阶段要永久删除某个玩家时，用同一页面单独的“删除测试账号”：它清除该玩家在当前账号库和资产库中的账号与全部游戏资产，不可恢复；旧备份不改写，后台会列出并标注可能仍含该账号的备份。源码版已通过隔离测试，用户从项目目录启动并试玩后反馈删除正常。新独立 ZIP 已包含此功能，但自动包测试没有单独执行删除流程。说明见 [规划第七节](docs/17_framework_shooter_plan.md#七测试阶段账号删除2026-09-27已实现)。

新注册、改密及管理员重置的密码长度为 8–128 字符；已有密码继续有效。源码和最新独立 ZIP 均已包含。

房间规则设置、背包与复活、局域网配置、备份恢复、客户端窗口排查和命令行等价入口，见 [本机启动与验证](docs/22_framework_operations.md)。

## Linux 源码启动

需要 Godot 4.7.2 官方 Linux 版、pwsh 7.6.6 和系统的 `libsqlite3.so.0`、ICU、OpenSSL。在项目目录先运行 `bash PrepareEnvironment.sh check`；缺少程序时显式运行 `bash PrepareEnvironment.sh prepare`，它按固定官方哈希下载并准备到本项目的 `artifacts/environment/tools/`。已有官方归档可离线导入，详见 [依赖准备](docs/22_framework_operations.md#environment-and-retention)。工具选择顺序是 `ROOMKIT_GODOT` / `ROOMKIT_PWSH` 显式指定 → 项目内准备结果 → 原有 `~/roomkit/tools`。准备成功后：

```bash
bash tools/roomkit_linux.sh start     # 打印面板地址，默认 http://127.0.0.1:28491/
bash tools/roomkit_linux.sh status
bash tools/roomkit_linux.sh stop      # 只请求退出并等待，不发信号
```

依赖齐备后可直接克隆 GitHub 主线、在 Linux 本机准备游戏并启动，无需 Windows 预构建。`2076e1b` 在 Mint 22.3 与 WSL2 Ubuntu 24.04.3 的全新目录各完成一次双客户端短闭环 **29/0**，未沿用旧账号和配置；不代表零依赖安装或任意 Linux/云服务器已通过，见 [克隆验收](docs/17_framework_shooter_plan.md#fresh-clone-linux-wsl)。

每个实例的数据、游戏索引、公开配置和 HOME/XDG/tmp 都在 `data/instance-<名>/`（默认 `l3`），默认只绑定 127.0.0.1；端口可以用 `--panel-port`、`--lobby-port`、`--control-port`、`--udp-range`、`--bind` 指定，但只在实例第一次创建时生效。已在一台 x86_64 笔记本上完成同机及 Windows 客户端直连 Linux 的局域网自动验收；公网尚未验收，独立导出目录的入口见下一节。

此前的 Linux 联机客户端入口 **`OpenLinuxPlayerClient.cmd`** 保留为历史快捷方式，保留原 `PlayerClient`；旧试玩账号和连接配置已清除，须重新初始化实例并生成匹配的公开配置后才能使用。生成的程序和连接配置不进入 Git。历史验收见 [Linux 跨机试玩](docs/17_framework_shooter_plan.md#linux-lan)。

**从台式机打开此前 Linux 后台：双击根目录 `OpenLinuxManagement.cmd`，保持窗口打开。** 入口建立 SSH 转发并打开 <http://127.0.0.1:28491/>，关闭只断转发、不停服务；后台仅监听笔记本回环，不能直接用笔记本 IP:28491。入口不启动远程服务，也不指向本轮 29191 的短验实例。旧试玩账号及连接配置已按授权清除，历史 admin.json 不再有效；再次试玩需初始化实例并取得新的公开配置。说明见 [后台入口](docs/17_framework_shooter_plan.md#linux-management-entry) 和 [本轮边界](docs/17_framework_shooter_plan.md#fresh-clone-linux-wsl)。

## 独立 Linux 服务器目录（无需 Godot 编辑器）

本机朋友试玩入口 **`PlayLinuxPackage.cmd` / `StopLinuxPackage.cmd`** 已更新为阶段 7 配套版本（枪口、身体移动、诊断与快照 v3），后台通过 SSH 打开 <http://127.0.0.1:28691/>。原管理员、玩家账号和资产经官方升级保留：登录后台、启动游戏服务器，再用自动打开的玩家目录里的 `Client.exe`。朋友也需换完整新版玩家目录。路由器继续转发 TCP **28300**、UDP **28400–28431** 到笔记本 `192.168.10.105`；不转发后台或控制端口。旧版公网连接已有用户反馈，新版已通过跨机自动短验，真人手感及朋友公网另验。当前版本 `e1bbf7b65cc9` / 协议 3、路径和证据见 [v3 交付结果](docs/17_framework_shooter_plan.md#snapshot-v3-delivery-20261003)。用户简单试玩反馈无问题；高延迟专项与 QQ 实际收信仍待参与。Git 克隆不包含本机清单、程序、连接配置或密码。

Windows 构建入口：`powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_linux_server.ps1`。输出普通目录在 `artifacts/RoomKit-0.5.0-linux-x86_64-<编号>/`，整个干净目录复制到 Linux 即可；引擎已包含，缺少 pwsh 时用随包 `PrepareEnvironment.sh prepare`，不再下载 Godot 编辑器。系统库仍单独检查。基础依赖的历史验收见 [阶段 6](docs/17_framework_shooter_plan.md#stage6-result)，当前配套目录和实测范围见 [v3 交付](docs/17_framework_shooter_plan.md#snapshot-v3-delivery-20261003)。

在目录内依次运行 `bash PrepareEnvironment.sh check`（缺少时显式 `prepare`）→ `bash CheckPackage.sh` → `bash RoomKit.sh start --instance demo`；状态用 `bash RoomKit.sh status --instance demo`，停止用 `bash RoomKit.sh stop --instance demo`。默认只绑定回环，新实例的端口与对外地址可在首次启动时设置；重启沿用保存配置。后台通过本机浏览器或同号 SSH 转发访问。玩家仍使用版本匹配的 Windows 客户端。

**Linux 可以自己独立启动**，不用先开 Windows 台式机。复制干净普通包、准备依赖后，在 Linux 本机运行上面的命令，再用该 Linux 的浏览器打开打印的地址。台式机的 `PlayLinuxPackage.cmd` 只是此前已准备实例的远程快捷方式。全新电脑需选自己的平台包：Windows 包自带引擎并使用系统 PowerShell/SQLite；Linux 的准备入口可以补 pwsh，缺少系统库则报告。Mint 与 WSL2 已实测官方归档离线准备，不等于任意新系统、ARM 或在线下载均已验收。

运行会产生私有账号库、密钥与日志；给别人分发应使用 Windows 构建出的干净目录，不能复制已经运行过的目录。其它发行版、ARM、公网和开机服务另行验收。

## 独立 Windows 包（无需 Godot 编辑器）

运行 `tools/build_framework_release.ps1` 构建。最新 ZIP 和解压位置记录在 `artifacts/framework-release.json`。解压后按顺序：`CheckFramework.cmd` 校验 → `StartPanel.cmd` 打开管理后台 → 玩家用 `StartShooter.cmd` / `StartTurns.cmd` → 全部关闭用 `StopFramework.cmd`；`PublishClients.cmd` 生成给玩家的公开连接配置。只分发构建时的干净 ZIP，不要分发跑过测试的解压目录。

包默认使用常驻存储；需要回退时，在启动前设置环境变量 `ROOMKIT_STORAGE_MODE=oneshot`。最新包的名称、哈希、包含的功能和验收范围只看 [STATUS 当前交付物](STATUS.md#当前交付物)。

## 接入自己的游戏

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\new_game.ps1 -Managed -GameId my_game
```

生成的工程自带 SDK、账号客户端、房间程序、资产目录/策略和结果 Schema；不需要修改宿主核心。步骤和自动验证见 [新游戏接入](docs/24_managed_game_template.md)，SDK 接口见 [SDK README](sdk/roomkit/README.md)。

## 测试

基础回归：`powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode unit`。各模式的成功标记，以及账号、管理、射击、托管模板等专项命令，见 [docs/22 测试入口](docs/22_framework_operations.md#测试入口)。测试日志写在 `logs/`，它和 `data/`、`run/`、`artifacts/` 一样都不进入 Git。新登记的测试运行目录与构建历史默认每用途保留最近两份，轻量结果和哈希保留；测试源码不删，旧未登记目录、用户修改和必要恢复输入不会被自动认领清除。规则见 [保留策略](docs/22_framework_operations.md#environment-and-retention)。

## 文档导航

目前已完成项目地图、主线整理、独立客户端、后台 UI、基础音效与 Linux 独立目录，最新交付见 [Linux 服务器目录](docs/17_framework_shooter_plan.md#linux-server-directory)；当前目录与分工见 [主线与工作目录](docs/17_framework_shooter_plan.md#worktree-mainline-20261002)。见 [已确认规划](docs/17_framework_shooter_plan.md#next-plan)、[清理候选表](docs/17_framework_shooter_plan.md#清理候选表) 和 [下一阶段建议](docs/17_framework_shooter_plan.md#下一阶段实施建议与验收门槛)。

| 需要了解 | 文档 |
|---|---|
| 模块、状态与开发顺序一览 | `ROADMAP.html`（双击打开） |
| 项目分析：模块耦合、Windows 依赖、跨平台边界、性能待测项 | [01 项目分析](docs/01_scope_architecture.md#项目分析2026-09-28) |
| 当前状态、验证范围、已知问题 | [STATUS](STATUS.md) |
| 启动、数据维护、局域网、测试与人工验收夹具 | [22 本机启动与验证](docs/22_framework_operations.md) |
| 分支范围与阶段规格 | [17 框架与射击计划](docs/17_framework_shooter_plan.md) |
| 跨游戏术语与后续方向 | [CONTEXT](CONTEXT.md)、[17 后续方向（第五节）](docs/17_framework_shooter_plan.md) |
| 管理后台与 HTTP 接口 | [19 管理后台](docs/19_admin_ui.md) |
| 后台改版界面预览（演示数据，不连接服务；正式后台已接入该布局） | `ADMIN_PREVIEW.html`（双击打开） |
| 射击玩法与房间规则 | [20 射击示例](docs/20_shooter.md)、[25 房间规则](docs/25_shooter_room_rules.md) |
| 账号/资产/管理协议与错误码 | [21 托管协议](docs/21_managed_protocol.md)（契约唯一来源为 `schemas/`） |
| 资产基础 | [18 资产基础](docs/18_asset_foundation.md) |
| 版本与决策 | [07 版本与决策](docs/07_versions_decisions.md)、[CHANGELOG](CHANGELOG.md) |
| 架构与代码目录 | [01 范围与架构](docs/01_scope_architecture.md)；原始设计 [00](docs/00_greenfield_start.md)、[02](docs/02_contracts.md)、[03](docs/03_sdk_integration.md)、[04](docs/04_data_security.md)、[05](docs/05_deployment_operations.md)、[06](docs/06_roadmap_acceptance.md) |
| 环境记录 | [10 环境](docs/10_environment.md) |
| 协作规则 | [AGENTS.md](AGENTS.md)；首轮 M0/M1 任务原文 [CODEX_START](CODEX_START.md)（历史） |
| 历史过程、早期演示入口、设计包记录 | [归档目录](docs/archive/README.md) |

早期无账号演示入口（仓库根目录的 `StartPanel.cmd`、`StartPlay.cmd`、`StartTurns.cmd`、`StartDemo.cmd`、`ShowResults.cmd`）和 0.1.0 候选包仍然保留，但不推荐使用，说明见 [早期入口](docs/archive/early_entrypoints.md)。注意：仓库根目录的 `StartPanel.cmd` 是早期只读面板，与独立包里同名的管理后台入口不是同一个东西。
