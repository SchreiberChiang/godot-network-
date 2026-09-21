# 新玩法模板

这是独立Godot开发工程，已经包含固定版本的SDK与唯一Schema副本，不依赖RoomKit仓库中的玩法代码。

- `game_manifest.json`声明游戏、构建、版本及允许的模式/地图；`room.gd`是房间入口。
- 在`adapter.gd`实现玩家准入、离开及结束回调，按需要加载自己的场景。不要把peer_id当作user_id。
- 客户端使用`sdk/roomkit/client/room_client.gd`的configure、open_session、join_room、leave_room。示例`client.gd`从本机私有JSON设置中读取url和room_id；安全接入另需ca_certificate、secure_enet=true、credential。
- 新游戏由宿主管理员登记manifest和可信executable/args。远端创建请求不能提供程序路径。开发命令为Godot --headless --path 本目录 --script res://room.gd；控制启动参数由宿主生成，不能手工复用旧launch凭据。
- 完成一局时，适配器发出result_requested("round_1", "completed", payload)。宿主必须注册该game_id的结果Schema并启用ResultService；否则不声明结果已保存。
- 当前模板不带账号、玩法、美术或公网配置。升级SDK时整套替换sdk/、schemas/并更新build_id、compatibility_id，重新运行接入测试。

生成器的验收会把该目录作为独立房间启动，再用该目录的客户端与SDK实际入房/退房；详见宿主仓库的tools/run.ps1 -Mode template。
