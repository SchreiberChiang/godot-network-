# 方块漫游

在仓库根目录双击 StartPlay.cmd，自动打开两名玩家窗口。点击窗口后用 WASD/方向键移动，橙色是自己。点退出房间可回大厅并重新入房；关闭两个窗口后自动清理。

服务器按20Hz固定步长计算位置，客户端只提供方向。10Hz广播位置，不含客户端预测/插值、物理碰撞或角色资源。没有依赖用户旧工程。

room.gd 是 SDK 子类入口；adapter.gd 接收 GameAdapter 回调；game.gd 提供游戏自己的权威状态、输入与两端一致的 RPC。唯一字段定义位于根目录 schemas/blocks_*.schema.json。

tools/build_games.ps1 生成独立开发工程；tools/run.ps1 -Mode games 同时启动本例和石子游戏验证隔离。详细结果见 STATUS.md。
