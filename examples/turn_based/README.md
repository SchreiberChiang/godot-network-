# 第二玩法

M3 已实现“十二颗石子”：至少两名成员轮流取1或2颗，取完最后一颗得分并开始下一局。无角色、CharacterBody、武器或碰撞依赖。

在仓库根目录双击 StartTurns.cmd，自动打开两个窗口。按钮仅在当前玩家回合启用。退出后可重新入房；本例分数只属于当前房间成员，离房会丢弃，不是账号积分。

room.gd 为 SDK 子类入口；adapter.gd 实现 GameAdapter 回调；game.gd 同时包含两端一致的 RPC 声明与服务端权威规则。输入和快照以根目录 schemas/turns_*.schema.json 为唯一字段来源。tools/build_games.ps1 会将本目录构建成只含此游戏和 SDK 的独立开发工程。

自动验证：tools/run.ps1 -Mode games。详细说明与限制见 docs/12_m3_games.md、STATUS.md。
