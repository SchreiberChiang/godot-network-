# Windows 本机发布候选：使用与维护

本轮交付 RoomKit 0.1.0 Windows candidate，SDK 源码版本 0.4.0。框架本机闭环可用，发布门禁仍有未通过项，不能把候选包视为公网正式版。所有代码来自当前仓库。

## 给使用者

构建后读取 `artifacts/delivery.json`：`zip` 是独立程序压缩包，`template_zip` 是 SDK 与新工程模板，`unpacked` 是已经重新解压验证的目录。ZIP 不进入 Git；源码和构建脚本进入 Git。解压后双击 StartRoomKit.cmd 打开两个取石子窗口；StartRoomKit.cmd -Game blocks 切换方块。StopRoomKit.cmd 正常退出，CheckRoomKit.cmd 校验摘要。完整操作见包内 README.md。

源码试玩保留 StartPlay.cmd、StartTurns.cmd、ShowResults.cmd。源码需要本机 Godot 编辑器；独立 ZIP 只需可运行 Godot 4.7.2 的 Windows、系统 PowerShell 5.1 与 winsqlite3.dll。控制端口 28290 限定一个托管宿主，WSS 大厅临时分配回环端口，UDP 池默认 28100—28131。无服务安装、无注册表/系统证书修改、无自动下载。

## 可重复构建与验证

在仓库 PowerShell 执行：

```powershell
./tools/run.ps1 -Mode all
./tools/test_helpers.ps1
./tools/build_release.ps1
./tools/package_release.ps1
$delivery = Get-Content -Encoding UTF8 -Raw ./artifacts/delivery.json | ConvertFrom-Json
./tools/test_release.ps1 -Bundle $delivery.unpacked
./tools/new_game.ps1 -GameId my_game
```

默认引擎为 `D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`；构建脚本使用同目录 editor_data/export_templates/4.7.2.stable 中的正式模板。每次产生独立目录，不覆盖正在运行的构建。Windows EXE/PCK 使用固定 MainLoop 类及空主场景；正式模板不能依赖编辑器的 --script/--path/--main-pack 覆盖入口。

构建还产生 `artifacts/release.json` 的 validation 目录：LauncherCheck.exe 是正式模板的十轮句柄检查；PortableCheck.x86_64 是 Linux 协议/玩法检查。Linux 检查不包含 Linux 宿主、SQLite 或玩家联机。WSL 下把 F: 路径转换为 /mnt/f/ 后执行 `chmod +x PortableCheck.x86_64`、`./PortableCheck.x86_64 --headless`。不下载或修改已安装引擎。

SDK 模板只带 SDK、Schema、空 GameAdapter 与自己的房间/客户端入口。新游戏通过清单和可信产物登记接入，不需要编辑 host/core。模板真实启动/入房/离房由 `run.ps1 -Mode template` 验证；不包含完整玩法或 Godot 编辑器插件面板。

## 安全与资源政策

演示和导出默认使用 WSS + ENet DTLS；客户端固定验证本机自签证书及 localhost 主机名，无不安全回退。证书保存在私有 data 下，未加入系统信任。身份提供方 authenticate 返回稳定 user_id、display_name、role 和 expires；当前实现使用本地预配随机凭据，仅保存 SHA-256 摘要，可替换为其它提供方。不是第三方账号登录系统。SDK 拒绝在明文 WS 上传送该凭据；无 TLS 的大厅不能挂身份提供方。过期会话被拒绝并断开。同用户第二连接拒绝；管理员可停房，普通玩家仅可停自己创建的房间。

房间启动/终止、资源采样及结果写库在有界工作队列或线程执行。启动同时最多两个；结果队列最多64；历史房间最多4096；大厅最多64连接，TLS握手5秒、未认证会话10秒、每连接每分钟240请求。进程/SQLite助手执行期限10秒，只通过持有的原进程句柄结束超时助手。宿主初始化目录授权、启动 PowerShell 自身及离线管理操作仍有同步开销，不能承诺主线程任何时刻都绝不阻塞。

演示逐房轮询工作集，默认超过512 MiB停止房间；这是采样后的应用层限制，不是操作系统硬内存配额，没有硬CPU配额。每秒检查一间，16房可能约16秒轮到一次。未配置该项的基础夹具不启用监控。SQLite每库256个授权、10000个结果、每房128个待发送结果上限沿用；没有自动保留/归档政策，到顶明确拒绝。

托管宿主先占用固定控制端口，再加载进程日志；第二宿主不能改写日志。启动前记录保留端口，捕获身份后补完整记录。崩溃重启不认领、不终止上次运行的进程；旧房控制失联自退，读取精确旧身份并确认退出、UDP可绑定才解除隔离。启动记录缺失身份时继续隔离，不根据“端口暂时空闲”猜测安全。未知项需要人工核实，不能直接清空日志。

## 数据、升级和故障排查

互动试玩库为 data/showcase-results/results.sqlite，签名 outbox、启动授权、私钥也在私有 data 目录。备份包含内部授权，不能公开上传。结果补存只恢复已落盘有效记录，不恢复对局。SQLite Schema user_version=1，未知版本拒绝；无自动旧库迁移器。

更新步骤：停止并确认进程退出；在线备份并保存日志；把新包解压到新目录，校验摘要并先跑 -Test；保留旧目录作为回退。当前恢复路径包含绝对 outbox 路径，不能只复制一个 results.sqlite 就宣称完整迁移。需要跨目录迁移时，先完成旧目录补存并核对结果、保持旧目录可用；本版未验收任意跨机器数据迁移。

| 现象 | 检查 |
|---|---|
| CONTROL_UNAVAILABLE | 当前包是否已经运行，28290 是否被占用；status 只报告端口观察，不能证明进程身份 |
| START_TIMEOUT / AUTH_FAILED | logs 中对应房间与客户端日志、构建标识、私有证书、系统时间；禁止关闭证书校验绕过 |
| ROOM_MEMORY_LIMIT | 房间工作集记录与配置阈值；先定位玩法占用 |
| RECOVERY_REQUIRED / PORT_QUARANTINED | 私有启动日志及旧进程身份；保留隔离，不能盲目杀 PID |
| STORAGE_CAPACITY_EXCEEDED | 授权/结果上限；备份并规划保留策略，不删除未知业务数据 |
| 校验失败 | 使用新目录重新解压可信原包；摘要只检测变化，不等同于签名发布 |

未通过门禁：Linux完整宿主、跨机器/LAN/公网、外部身份提供方、证书轮换、干净另一台机器、实际网络丢包/延迟、最坏玩法/带宽/全局容量边界、长期运行、断电和磁盘满。16+4名客户端与100轮都是本机有限实验。最新具体计数、失败和命令以 STATUS.md 为准。

实现依据：[Godot 4.7.2 启动入口](https://github.com/godotengine/godot/blob/4.7.2-stable/main/main.cpp)、[ENetConnection DTLS](https://docs.godotengine.org/en/stable/classes/class_enetconnection.html)、[StreamPeerTLS](https://docs.godotengine.org/en/stable/classes/class_streampeertls.html)。
