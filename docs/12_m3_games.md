# M3 本地双玩法实施

2026-09-20，用户在 M2 完成后继续授权。本轮按 docs/06 推进最小方块移动与无角色/无武器的回合取石子游戏；不接旧项目，不部署公网。AGENTS/CODEX_START 的 M0/M1 范围是首次任务。

先实现项目自己的适配器、输入/快照契约和界面，再分别生成独立开发工程，运行两游戏同时开房、真实客户端操作、跨游戏拒绝、退房和回收测试。host/core 与 sdk/roomkit 本轮不修改。各游戏的房间子类将已认证 user_id 映射为传输 peer_id 给适配器；游戏自己维护输入和权威状态。

独立产物是携带固定 SDK 源码的 Godot 开发工程，不等同于专用服务器可执行文件导出。生成在 artifacts/ 内，不读取其它项目。引擎继续使用已验证的 Godot 4.7.2 Steam。

## 本机操作

双击根目录 StartPlay.cmd 打开“方块漫游”的两个窗口，点击窗口后用 WASD/方向键移动；另一个窗口会收到服务器位置。双击 StartTurns.cmd 打开“十二颗石子”，轮到自己时点击“取 1 颗”或“取 2 颗”，最后一颗得分并进入下一局。每次都启动两个游戏的独立房间进程，所选游戏启动两个玩家窗口；不需要手动启动宿主。

“退出房间”保留大厅身份，按钮变成“重新入房”。关闭两个窗口后宿主自动停止本次房间；会话最长30分钟。两个启动器请依次运行，以便清楚对应窗口和日志。StartDemo.cmd 保留原来的 M2 自动文字测试。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode games
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode games -Visual
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\play.ps1 -Game blocks
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\play.ps1 -Game turns
```

games 模式自动构建两个独立目录、各开一房并启动四名测试玩家。-Visual 使用真实图形窗口与 OpenGL 渲染，截图保存到 logs/games-<本次编号>/。play.ps1 的 -Smoke 只用于短时打开真实窗口并自动调用关闭处理程序；不等于手动鼠标/键盘测试。

## 构建和边界

tools/build_games.ps1 每次创建 artifacts/games-<唯一编号>/blocks 与 turns，不覆盖正在运行的构建。每个目录只包含当前游戏的 game/、当前游戏清单、共享客户端外壳、原样 SDK 和对应 Schema，无 host/、另一游戏代码或私有配置。artifacts/games.json 只是本机管理员产物映射；客户端不能改变它来要求宿主启动任意程序。游戏源文件在 examples/blocks、examples/turn_based，第三个游戏照此提供 room/adapter/game/manifest，再加入构建与注册配置。

两个 room.gd 继承同一 SDK 运行时，只在子类中将已经 IN_ROOM 的身份映射到 peer；adapter.gd 通过 GameAdapter 回调创建/移除成员。玩法 RPC 位于 /root/GameWorld，两端使用完全相同的 game.gd。该节点可先存在，但只有 GameAdapter 准入后记录的 peer 才能执行输入。没有增加 SDK 的统一移动/战斗接口，也没有引入 CharacterBody 或角色基类。

当前房间子类会读取 SDK 0.2.0 的 members 字典完成映射，因此锁定此源码版本；未来 SDK 改变这项内部表示时须复验该小型桥接。清单容量上限16，当前真实测试仅每房2人，不声称16人已通过。

## 玩法协议

唯一字段定义在 schemas/blocks_input.schema.json、blocks_state.schema.json、turns_input.schema.json、turns_state.schema.json；结构样例见 examples/gameplay_messages.example.json，单元逐条验证。game_protocol=1；两个兼容标识分别 blocks-v1、turns-v1。更改任一游戏 RPC 或状态结构必须更新自己的兼容标识和 Schema，不改变另一游戏。

| 游戏 | 输入 | 权威处理 | 同步 |
|---|---|---|---|
| 方块 | sequence、x/y方向（-1至1） | 宿主房间20Hz固定步长；向量归一化，速度180单位/秒；位置限于画布；250ms没输入则停止；每人每秒最多60条有效检查 | 10Hz状态，tick判新旧；ENet channel 1 unreliable_ordered |
| 石子 | turn、take（整数1或2） | 核实peer对应身份、当前回合、至少两人和剩余数量；重复/迟到操作拒绝；末颗计1分，重置12颗进入下一局 | 变更及每0.5秒状态；ENet channel 1 reliable |

输入拒绝不修改玩法状态、不返回任意字符串；rejected 为服务端诊断计数。大厅错误仍沿用 M2 的 BUILD_MISMATCH 等错误码。方块没有碰撞/预测/插值，回合分数仅保留在本次房间内，离房再入视为新成员，分数重置；不提供账号积分持久化。

## 验证和限制

tests/test_games.gd 检查未准入/离房输入、非有限数、越界、身份注入、陈旧序号、斜向速度、输入超时、输入频率、回合越权、重复选择、积分和成员退出。tests/run_games.gd 使用真实子进程验证两游戏同时READY、进程/端口/launch独立、四名客户端各自在自己的游戏内操作、跨游戏拒绝、退房重入身份保持、最后全部回收。

自动操作是代码产生的输入；图形测试实际调用 OpenGL 渲染并保存视口像素，重入测试调用与按钮相同的处理程序。没有用桌面自动化实际点击键盘或鼠标。没有测试公网、Linux、浏览器、服务器可执行文件导出、16人或压力容量；不是完整游戏或正式发布包。具体本轮成功/失败证据见 STATUS.md。
