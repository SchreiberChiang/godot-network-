# M4 第一部分：本地结果持久化

2026-09-21，用户继续授权开发。先完成SQLite结果幂等、房间持久outbox、宿主恢复重发及备份验证。M4的正式身份、WSS/ENet加密、完整资源治理与发布安全门禁本轮不宣称完成。没有读取或迁移旧数据。

Windows存储适配使用系统winsqlite3.dll，由宿主通过PowerShell原生API助手操作；没有额外数据库服务或第三方后端运行时。使用参数绑定、事务、WAL和synchronous=FULL；只在SQLite提交成功后确认。房间不直接访问数据库。

结果包含game/build/room/launch、match_id、result_id、final类型、版本、completed/aborted状态及玩法Schema约束的payload。同一result_id同内容返回DUPLICATE，不同内容RESULT_CONFLICT；同(game_id,match_id,final)换ID返回MATCH_RESULT_CONFLICT。此阶段只保存结果，不执行金币或奖励业务，不能宣称发奖已幂等。

启动前将绑定身份和独立签名密钥保存于SQLite，然后把每房outbox路径和密钥写进私有启动配置。房间先写签名outbox再发result.submit；确认result_id与记录摘要匹配才删除。未确认文件位于data/，不随run/清理。恢复只能导入持久启动记录认可的签名和玩法Schema；错误文件保留为.rejected.json，存储暂时不可用则保留待重试。

## 本机使用

双击StartTurns.cmd，在两个窗口轮流取石子直到一局结束，然后关闭窗口。双击ShowResults.cmd，查看已保存的局数、game_id、match_id、玩家与分数。数据库在data/showcase-results/results.sqlite；方块游戏尚不生成成绩。回合完成后立即排队保存completed结果；房间被要求停止且仍有玩家时可保存当前局aborted结果。客户端先离开再关闭宿主不会强行制造空局成绩，也不恢复已结束对局的实时分数。

tools/run.ps1 -Mode persistence运行独立测试库，不混入试玩数据。tools/results.ps1支持-Operation inspect/recover/backup及-Store res://data/目录；默认试玩库。inspect展示最近100条和总数，不输出签名密钥；backup通过SQLite在线备份API生成新文件，不覆盖现有文件。测试从备份打开独立数据库并验证内容及integrity_check，没有替换用户当前数据库。ShowResults.cmd也可传入上述参数。

## 限制与未完成

- Windows系统SQLite版本实测3.51.1。数据目录拒绝越界/重解析目录、设置当前用户ACL；同一Windows账号下的进程不是安全隔离边界，HMAC不防本机账号被控制。备份包含启动签名密钥，同样属于私有数据。
- 每库最多保留256个launch授权、10000条结果；每房待发上限128。到达上限明确失败、不删除旧记录；尚无自动保留策略。重复记录不增加结果计数。没有磁盘配额与完整资源治理，不承诺长期运行。
- SQLite调用为宿主同步PowerShell助手，每次启动/编译有延迟；SQLite忙等待上限1500ms不覆盖助手的全部执行。测试的总watchdog不能代替常驻宿主的异步存储及完整超时。故障压力与性能优化仍属后续工作。
- 房间先写临时文件、flush后rename，再经控制TCP发送；收到匹配ACK才删除。已实测进程被终止后的恢复，未实测机器断电、磁盘满、文件系统故障或杀进程恰好发生在临时文件写入中间。未成功enqueue的结果不能被称为已持久化；.tmp文件不自动导入。
- 恢复只处理已保存且签名有效的结果，不恢复游戏局面，不认领遗留进程。测试先等待旧房退出并验证UDP可绑定，再启动恢复宿主；尚未验证新宿主立即开房时的遗留实例隔离。
- 未做正式身份提供方、账号累计积分、奖励发放、管理员权限、公网WSS/ENet加密、Linux、专用服务器导出、16人或100轮压力。M4整体尚未完成。

协议例子、错误码和兼容标识分别见docs/02、docs/07及examples/result_messages.example.json。实际命令、通过/失败记录见STATUS.md。

参考：[Windows SQLite](https://learn.microsoft.com/en-us/windows/apps/develop/data-access/sqlite-data-access)、[SQLite事务](https://www.sqlite.org/atomiccommit.html)、[SQLite备份API](https://www.sqlite.org/backup.html)。
