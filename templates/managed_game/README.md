# 账号与资产新游戏模板（SDK 0.5）

这是生成后可独立运行的 Godot 工程，包含自己的 SDK、Schema、房间程序、资产策略和账号客户端，不依赖射击、取石子或人物基类。生成命令在 RoomKit 仓库执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\new_game.ps1 -Managed -GameId my_game
```

生成器打印新工程目录；`artifacts/managed-template.json` 和新工程内 `managed-games.json` 是相同的受信注册索引。不加 `-Managed` 继续生成早期开发身份模板，两个索引互不覆盖。

## 注册与项目边界

由运行 RoomKit 的本机管理员将索引交给 Operator 的 `--games=<索引绝对路径>`，或将索引的游戏条目合入其受信游戏索引。注册条目包含 `project`、`manifest`、`name`、`asset_catalog`、`asset_policy`、`result_schema`；路径仅由本机管理员提供，不能从玩家请求读取。多个项目可共用同一个 Operator，不修改 host/core 或 SDK。

`game/room.gd` 是托管房间入口。宿主负责创建进程、签发准入、传入一次性启动配置；不要手工复用启动秘密。`game/adapter.gd` 接收经服务端确认的资产，再将当前游戏 `badge` 默认配置写入权威快照。`game/world.gd` 只演示这个配置的同步，没有比赛或角色规则。

`asset_catalog.json` 使用唯一的 `schemas/asset_catalog.schema.json`。生成器将其游戏和独立空间名称替换为 `GameId`。新账号 0 金币；`standard` 免费拥有，`cobalt` 花费 25 金币解锁；选择 `badge=cobalt` 是单独交易。可由后台给测试账号增加金币。默认配置按游戏隔离。大厅允许购买和选择，房间内只读；具体条件属于 `game/asset_policy.gd`。更复杂游戏自行实现上下文、阶段切换和 `asset_refresh_requested` 回调，SDK 不解释这些条件。

等级阈值与当前框架示例一致，便于多个项目登记到同一 Operator。共享空间必须统一商品和规则；不同目录使用相同商品 ID 时必须有相同定义。永久资产由服务端 SQLite 保存，游戏进程不打开数据库；比赛临时经济应放在自己的房间状态或可选 `MatchWallet`，不复用永久余额。

注册同时提供项目专属 `schemas/template_result.schema.json`，示例 payload 为 `{"counter":1}`。本模板没有真实对局，因而不会自行提交成绩或发奖励。需要结算时，在项目适配器调用 `result_requested.emit(match_key, status, payload)`，并为注册条目添加自己的 `reward_script`；不要在核心增加游戏分支。

## 运行账号客户端

先启动该索引对应的 Operator，在本机后台完成管理员初始化、创建邀请码、启动宿主，并创建此游戏的 `sandbox` / `empty` 房间，容量 1–16。房间 READY 后才可入房。使用 Operator 生成的公开 WSS 连接配置和证书，私钥、数据库及管理员账号均不交给客户端。

`client.gd` 是可执行的最小接入程序，便于替换成自己的游戏界面。它使用 `AccountClient`，读取本机私有 `--settings` JSON，不从命令行读取密码。文件格式如下；占位内容需由本机提供，不能直接运行：

```json
{
  "connection_config": "公开 connection.json 的绝对路径",
  "username": "本机测试账号",
  "password": "本机私有口令",
  "display_name": "模板玩家",
  "invite_code": "有效邀请码",
  "register": true,
  "room_id": "已 READY 的房间 ID",
  "report_path": "本机测试报告的绝对路径"
}
```

也可把公开配置直接放入 `connection` 对象，字段为 `url`、`ca_certificate`、`server_hostname`；内联证书路径使用绝对路径。`connection_config` 内相对证书路径按该公开配置目录解析。私有设置文件应位于仅当前用户可读的目录，不能提交 Git、发给其他玩家或将内容打印到日志。它保留在调用者指定的位置，使用后由调用者清理。

```powershell
& 'Godot可执行文件绝对路径' --headless --path '新工程绝对目录' --script res://client.gd -- --settings='私有设置绝对路径'
```

没有 `control_directory` 时，程序注册（可选）、登录、读取永久资产、进入可选的 `room_id` 并等待自己的权威徽标快照，再离房/退出登录，输出 `MANAGED_TEMPLATE_CLIENT_RESULT ok=true`、退出 0。已有账号需设置 `register=false`。成功报告只包含玩家身份 ID、自己的资产、公开房间快照及阶段，不含密码、邀请码或 session token。

## 持续交互和测试

在私有设置增加 `control_directory`，并事先创建该目录，客户端就会保持运行，默认最长五分钟，可用 `timeout_ms` 调整到最多十五分钟。`MANAGED_TEMPLATE_CLIENT_READY` 表示实际登录并完成可选入房；报告的 `phase` 为 `LOBBY` / `IN_ROOM`。后续每个唯一 id 写入新的 `*.command.json`，例如：

```json
{"id":"buy_1","action":"purchase","item_id":"cobalt","operation_id":"buy_1"}
```

支持 `read`、`purchase`、`select`（`slot`、`item_id`、`operation_id`）、`join`（`room_id`）、`leave`、`logout`、`login`、`close`。`logout` 保留程序，`login` 用私有设置中的同一账号重新登录。不要同时登录同一玩家账号。购买结果不确定时，保留原 `operation_id` 再查询/重放；新 id 用于新的业务操作。命令文件 id 每次唯一，业务 `operation_id` 可以用于重放同一事务。

报告包含 `registration:{attempted,ok,code}`、`results:[{id,action,ok,code,state?}]`、`assets` 和 `world:{revision,players:[{user_id,display_name,badge,asset_revision}]}`。已有账号未尝试注册时 `registration.attempted=false`，不影响登录结果。房间快照来自实际服务器；购买/配置只在收到成功结果后更新资产。结束时发送唯一 `close` 命令并等进程退出 0；超时退出为失败。此命令目录是本机接入工具，不能直接暴露为远程管理接口。

模板的运行证据以 RoomKit 的最新 STATUS 和专项测试结果为准。生成或语法检查成功不等于真实 WSS/ENet 联机通过，也不代表另一台设备已经验收。
