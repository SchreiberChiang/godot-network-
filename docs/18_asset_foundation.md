# S0/S3 内部资产基础：已实现接口与测试边界

本文件记录 `docs/17_framework_shooter_plan.md` 最初 S0/S3 的内部资产基础。下文关于“后续网络接入”的描述属于该阶段历史；当前账号、可操作后台、房间许可与背包已经集成，网络协议见 docs/21_managed_protocol.md，实际验收及缺项见 STATUS。本阶段的纯规则检查仍不能替代真实联机验收。

## 契约与调用

- `schemas/asset_catalog.schema.json`：版本 1 的可信部署配置。`spaces` 定义商品，`games` 选择空间、允许物品、默认配置槽。空间切换必须在服务停止写入后进行；同一运行实例不要热改服务的 catalog。
- `schemas/asset_state.schema.json`：永久状态。`credits`/`experience`、非堆叠 `owned`、按 game_id 隔离的 `profiles`、乐观并发 `revision`。默认免费物品在读取时投影，首次成功交易写入；读取本身不制造交易。
- `schemas/asset_command.schema.json`：内部命令 `purchase`、`select`、`adjust`。价格只来自可信目录；调整需要独立管理员入口与原因。客户端不能指定 space_id、价格或任意状态。
- 目录例子在 `examples/asset_catalog.example.json`；射击和取石子各有自己的策略，核心不认识枪械、主题或死亡。

2026-09-22 补齐等级表：目录可提供 `level_thresholds`，数组第一个值必须为0，其后严格递增，最多1000项，阈值为0至10亿的整数。第n项是到达等级n所需的累计经验，达到最高阈值后等级封顶，经验仍按原资产上限累计。当前例子采用 `[0,100,250,500,1000,1750,2750,4000,5500,7500,10000]`。整份目录共享同一经验表，独立或共享空间都由服务端计算等级；客户端显示服务返回值，不自行推算。旧v1目录可以省略此可选字段，此时保持等级1，表示没有启用等级成长。非法表返回原有 `INVALID_ASSET_CATALOG`，不覆盖已生效目录。数据库只保存经验，不增加另一个可直接篡改的等级列。

`host/core/asset_service.gd` 的 `initialize(directory, configuration)` 打开本项目私有 data 下的 `assets.sqlite`；`read(user_id, game_id)` 查询永久资产；`perform(identity, game_id, command, policy, trusted_context)` 调用服务端规则后提交购买/选择；`adjust(administrator, user_id, game_id, command)` 提交管理调整。这些是**进程内部的受信任接口**，不是对客户端开放的授权 API。调用者必须先认证身份并取得当前服务端上下文；不能把网络传入的 identity/context/admin 字段直接传进去。

服务当前使用同步的有界数据库助手，接到宿主时必须放到有界工作线程，不阻塞网络轮询。返回 `{ok, state, code}` 或 `{ok:false,code}`。幂等重试返回 `DUPLICATE` 和**原交易后的状态**，它可能早于当前状态；界面整合时不能用旧 receipt 覆盖更新版本，需按 revision 或重新查询。

内部 `request_id` 是持久操作键，不是现有大厅传输层 request_id；未来网络接入需要将大厅幂等键映射到此操作键。唯一范围是 `(目标 user_id, request_id)`，指纹含 actor_id、game_id、space_id 和完整规范化命令；换游戏/空间/内容复用同一个键会冲突。

## 数据库与事务

共享 SQLite 助手升级为 user_version=2。初始化可从新库或 v1 升级，保留原 results/launches；新增 asset_states 和 asset_receipts，默认没有迁移旧账号。初始化拒绝未知版本；不降级。旧版程序不应打开已经升级的库，回退需用升级前备份。

`asset.commit` 是固定 SQL 的内部 CAS 操作：`BEGIN IMMEDIATE` → 检查原请求回执 → 对照 expected_revision → 写新状态 → 写命令/actor/时间/前后状态回执 → COMMIT。任一步失败 ROLLBACK。查询、回执、提交、审计都通过宿主助手，不暴露 SQL 接口。两个并发写者读到同一版本，只允许一个提交，另一个返回版本冲突；服务不会自动重跑过期游戏许可。

当前上限：余额/经验 10 亿、单次调整绝对值 100 万、所有权 128 项、每游戏 16 配置槽、目录 128 游戏/空间、回执 10 万条。达到回执上限拒绝新交易，不自动删除回执破坏幂等保证。审计内部查询只返回该玩家最近 100 条；正式后台分页/归档后续实现。

`sdk/roomkit/server/match_wallet.gd` 则是完全独立的、可选的比赛内存钱包。一个实例绑定 launch_id/match_id，余额变更具有实例内幂等保护；close 清空并禁止后续写入。它不读写 SQLite，不向账号兑换或发永久奖励，也不实现战术射击规则；新的比赛必须创建新实例。默认 16 名成员、1 万次成功操作，额度耗尽显式拒绝。该类不要求任何游戏启用。

## 错误与兼容

| 错误码 | 处理含义 |
|---|---|
| INVALID_ASSET_CATALOG / UNKNOWN_ASSET_SPACE / INVALID_DEFAULT_ITEM | 部署目录无效，不启用新配置 |
| INVALID_ASSET_COMMAND / UNKNOWN_GAME / UNKNOWN_ITEM / INVALID_CONFIGURATION | 请求、目录或配置槽不允许 |
| AUTH_FAILED / ADMIN_REQUIRED / ASSET_OPERATION_DENIED | 身份缺失、非管理员或游戏策略拒绝 |
| ITEM_NOT_OWNED / ALREADY_OWNED / INSUFFICIENT_CREDITS | 不满足所有权/余额条件；不扣款 |
| ASSET_LIMIT_EXCEEDED / STORAGE_CAPACITY_EXCEEDED | 显式容量边界；不静默丢弃 |
| REQUEST_CONFLICT | 同操作键内容不同，不能以同键重试新操作 |
| ASSET_VERSION_CONFLICT | 别的操作已提交；重新读取并重新校验游戏状态后再尝试 |
| STORAGE_UNAVAILABLE | 无法确认提交状态；按原操作键重试以确认，不能直接换键再次扣款 |
| MATCH_CLOSED | 临时钱包已结束，不能继续操作 |

现有游戏、控制和大厅线协议版本不变，新增内部契约均为版本 1；新增可选 SDK 类不改变原 API。待 S2/S3 实际接入认证和网络操作时再统一升级 SDK 与兼容标识，不能仅修改文档声称旧客户端支持新接口。

## 本机测试

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode unit
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode assets
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode persistence
```

unit 包括纯规则、策略和临时钱包测试。assets 运行 Godot＋真实 Windows SQLite 助手，分别检查 v1 保留迁移、重复交易、所有权与配置持久化、不同用户/空间隔离、共享钱包且默认配置按游戏分离、两个独立助手并发 CAS、备份和 SQL 触发器注入后的事务回滚。失败触发器仅安装到本次独立测试库，不改变用户数据。persistence 回归原结果保存与真实房间 outbox 生命周期。

assets 不启动射击房间或联机玩家；所谓丢响应是提交成功后主动重试，不是网络丢包注入；所谓死亡许可是传入受信任的测试上下文，不是真实角色状态。非射击主题目前验证内部服务复用，完整客户端接入尚未完成。测试日志与数据均在忽略的 logs/data 下，最终数量和退出码见 STATUS。
