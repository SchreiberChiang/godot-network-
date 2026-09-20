# RoomKit 本地开发 SDK 源码

当前提供客户端 `client/room_client.gd`、房间运行时 `server/room_runtime.gd`、`server/game_adapter.gd` 和共享契约/传输代码。它们不引用具体游戏资源；暂未打包为可分发插件。

客户端将 RoomClient 加入 SceneTree，调用 `configure({url, game_id, build_id, compatibility_id, game_protocol})`，然后依次 `await open_session(display_name)`、`await create_room(options, idempotency_key)` / `await list_rooms()`、等待 READY、`await join_room(room_id)`、`await leave_room()`。退出时 `close()`。网络请求返回 `{ok, payload, code?}`；退出房间保留当前大厅会话。

可选 `prepare_scene` Callable 接收初始快照，允许异步加载并返回 bool。`join_progress` 报告 CONNECTING→AUTHENTICATING→LOADING→SYNCHRONIZING→IN_ROOM；只有 `room_joined` 才表示正式入房。`roster_changed` 提供新名单，`room_left` 表示离房。当前快照只含成员身份，不含装备或玩法状态。

单个客户端进程使用一个 RoomClient；SDK 设置 SceneTree 的默认 SceneMultiplayer、关闭自动 poll，并建立 `/root/NetRoom` 共享 RPC 节点，项目需保留该路径。不得同时添加第二套默认 MultiplayerAPI。当前 URL 仅支持本机 `ws://127.0.0.1:<port>`。

房间入口继承 `server/room_runtime.gd`，在 `_initialize()` 设置 `build_identity` 和 `adapter` 后调用 `super._initialize()`。适配器继承 GameAdapter，实现 `configure_room`、`on_player_admitted`、`on_player_left`、`on_shutdown_requested`。正式入房回调发生在票据认证、场景准备、初始名单确认以及宿主席位确认之后；业务身份使用 user_id。

可运行示例：`examples/minimal/multiplayer_room.gd`、`empty_adapter.gd` 和 `test_player.gd`。正常玩家只调用公开 SDK；非法票据测试刻意调用内部连接方法注入错误凭据，不属于游戏接入 API。启动 `StartDemo.cmd` 可自动执行两人流程。

Schema 文件必须随源码/导出包一起提供，目前只有开发工程运行验证。详见 `docs/11_m2_implementation.md` 和 `STATUS.md`。
