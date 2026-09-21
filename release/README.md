# RoomKit 0.1.0 Windows candidate

解压到当前 Windows 用户可以写入的目录。需要 Windows PowerShell 5.1、系统 winsqlite3.dll 和可运行 Godot 4.7.2 的电脑；不需要安装 Godot 编辑器或数据库服务。宿主只监听本机回环地址。

- 双击 StartRoomKit.cmd：打开两个回合游戏窗口。轮到自己时取 1 或 2 颗石子。
- 方块移动：PowerShell 运行 `./Run.ps1 -Game blocks`，点中玩家窗口后用 WASD 或方向键移动。
- 双击 StopRoomKit.cmd：请求当前包的宿主正常关闭；也可以直接关闭两个玩家窗口。
- 双击 CheckRoomKit.cmd：校验包内文件摘要。摘要用于检测改变，不是代码签名。
- `./Run.ps1 -Test`：两个服务器、四个加密客户端自动操作、重入和保存结果，成功显示 GAMES_RESULT failed=0。
- `./Manage.ps1 -Operation status`：查看监听端口与遗留进程日志数量。`results` 查看互动试玩的成绩；`backup` 产生新的 SQLite 在线备份。

宿主日志在 logs/，互动试玩数据在 data/showcase-results/。run/ 与 data/ 仅授权当前 Windows 用户。不要把这些目录发给别人；其中包含本机证书私钥、待补存结果和内部授权。自动测试使用独立数据目录，成绩不会写入互动试玩库。

一个包一次运行一个宿主，控制端口固定 28290。所有证书均本地生成且客户端固定验证，未加入系统信任。当前身份是本机自动配发的稳定用户标识，未接入外部账号服务。不能把本包当成公网部署包。

更新时先停止宿主并确认退出，执行 backup；将新包解压到另一个新目录并校验/测试，保留旧包及其 data/ 用于回退。不要覆盖运行中的 EXE/PCK，不要手工删除 processes.json 中身份不明的隔离项。当前没有自动数据库升级或账号迁移器；更换包路径前先核对数据恢复政策，详见源码 docs/15_release_operations.md。

此包为 Windows 本机发布候选；Linux 完整宿主、跨电脑网络、长时间满载与公网部署不在已通过范围内。源码与详细测试边界见仓库 STATUS.md。
