# 新游戏接入：账号、资产与托管房间

2026-09-26。当前源码分支 `codex/shooter-framework` 的接入说明；实际通过和未运行项以 [STATUS](../STATUS.md) 为准。9月22日的独立验收ZIP不包含本次模板更新。

## 先自动验证

在 RoomKit 项目目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test_managed_template.ps1
```

它在本项目私有测试目录复制当前源码，生成两个不同 GameId 的新工程，启动真实管理服务、宿主、独立房间和客户端。测试注册、登录、后台发币、购买/重试、默认配置、房间内操作限制、退出重登和进程/端口回收。测试不会替换日常启动器使用的游戏索引或账号库，不需要下载引擎或新后端；默认使用 README 记录的本机 Godot 4.7.2。

输出 `MANAGED_TEMPLATE_RESULT passed=... failed=0` 且进程退出0才算通过。具体记录在本次打印的 `logs/managed-template-<编号>/result.json`，私有账号数据位于 `data/test-managed-template-<编号>/`。这是本机无界面多进程验证，不是另一台设备或导出客户端验收。

## 创建自己的工程

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\new_game.ps1 -Managed -GameId my_game
```

生成器打印工程路径并写入 `artifacts/managed-template.json`。生成目录自带 SDK、协议、`game_manifest.json`、账号接入程序 `client.gd`、`game/room.gd`、`game/adapter.gd`、资产目录/策略和结果 Schema。以它为新玩法的起点，不需要复制射击游戏代码。不加 `-Managed` 时仍生成早期开发身份模板。

模板演示两个徽标：免费 `standard`，25金币解锁 `cobalt`。解锁与选择分别提交；已确认的默认徽标随准入进入房间快照。房间内允许查看资产，拒绝购买和选择。这些条件在游戏自己的 `game/asset_policy.gd` 中，框架不认识徽标、枪械或死亡。模板没有对局和奖励，不会伪造结算。

## 手工启动模板后台

先用 `StopManagement.cmd` 关闭日常后台，避免占用相同端口。以下命令在 RoomKit 根目录的 PowerShell 执行，后台保持在该终端运行；按顺序在另一个终端或浏览器操作。

```powershell
$engine = 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
& $engine --headless --path . --script res://host/operator.gd -- --games=res://artifacts/managed-template.json --data-root=res://data/my_game_operator --panel-port=28292
```

出现 `OPERATOR_READY port=28292` 后，打开 <http://127.0.0.1:28292/>。该数据目录使用自己的新账号库；在网页初始化管理员、启动服务器、创建邀请码，再创建 `my_game` 的 `sandbox` / `empty` 房间。仅回环管理界面；玩家监听地址可在停服时通过配置页调整。

新工程 `README.md` 给出了私有客户端设置文件的格式及运行方法。`client.gd` 是供开发者替换的命令驱动接入程序，没有射击客户端那样的图形界面。公开连接文件由后台生成到 `artifacts/client/connection.json`；账号密码仅放私有设置文件，不填进命令行、不进入Git或公开分发。

结束时先在网页停止游戏服务器，再在 RoomKit 根目录另一个 PowerShell 运行：

```powershell
[IO.File]::WriteAllText((Join-Path (Get-Location).Path 'data/my_game_operator/operator-stop.request'), 'stop')
```

等待后台终端退出0。上述后台采用独立目录，日常 `StopManagement.cmd` 只管理默认的 `data/framework/`，不能用它关闭本例。

## 同时登记多个游戏

受信索引遵循 `schemas/managed_game_registry.schema.json`，以 GameId 为键。将生成工程 `managed-games.json` 的完整游戏条目合入要启动的索引，并将此索引通过 `--games` 交给管理服务。每个条目声明工程、清单、名称、资产目录、资产策略、结果Schema，以及可选奖励脚本；路径仅供本机管理员配置，玩家和网页请求不能加载脚本或可执行路径。

更改游戏集合前需停止整个管理服务。在已有数据目录中，同步修改 `config.json` 的 `asset_spaces`，键必须与新索引完全一致；值为该游戏资产目录声明的默认空间，或 `shared`。保留已有游戏的选择，只给新增游戏补默认值；删除索引条目不会删除其旧数据库记录。配置不一致时启动明确失败，不会自动合并钱包、迁移资产或清空账号。

同一管理服务中的目录共用等级阈值表；共享空间中的同名商品必须定义一致。冲突时拒绝配置，不能按加载顺序覆盖价格。普通项目只需修改自己的玩法/目录/策略和受信索引；宿主核心与SDK保持通用。

已有射击/取石子旧索引可通过 `examples/framework/services.json` 补足服务声明，生成的新索引会显式写出这些字段。此兼容仅面向该源码的本地配置，不表示旧独立包支持新注册机制；需要新导出后单独验收。

注册配置在启动时检查，错误记录为 `OPERATOR_FAILED code=...`：

| 错误码 | 检查方向 |
|---|---|
| `INVALID_GAME_REGISTRY` | 索引结构、游戏ID、SDK版本、模式人数或部署占位符不合法 |
| `GAME_SERVICE_MISSING` | 受信服务文件不存在或路径无效 |
| `INVALID_GAME_SERVICE` | 策略/奖励接口、构造方式或结果Schema基本格式不合法 |
| `INVALID_ASSET_CATALOG` | 项目资产目录及其游戏绑定无效 |
| `ASSET_CATALOG_CONFLICT` | 相同商品定义或等级阈值冲突 |
| `INVALID_CONFIG` | 私有运行配置与当前注册表不一致 |

这些是本机启动错误，不是新增玩家消息。脚本和结果Schema仍属于管理员信任的代码，不提供第三方代码沙箱或完整JSON Schema元校验。策略可依赖随项目一起部署的相对脚本；其中 `res://` 指管理服务工程的资源根，不会切换为玩家客户端工程。不要给普通玩家提供编辑注册路径的接口。
