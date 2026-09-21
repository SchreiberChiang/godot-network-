# 本轮分支修改文件

2026-09-22，分支 `codex/shooter-framework`，相对本轮起点提交 `711a657`。完整功能范围见 [开发计划](17_framework_shooter_plan.md)，整体完成状态见 [STATUS](../STATUS.md)。

本清单同时包含已提交变更、当前工作区修改，以及尚未跟踪但需要纳入本分支的新文件；本轮提交后的文件仍在清单范围内。核对来源是 `git diff --name-only 711a657 --` 与 `git ls-files --others --exclude-standard` 的去重并集，再排除 `logs/`、`data/`、`artifacts/` 下的运行记录和产物。当前共 **120 个文件**，不按是否已暂存或提交拆分固定数量。日志、数据库、凭据和构建产物不计入文件清单。暂停时未完成的托管模板另存于STATUS记录的WIP快照，不计为交付源码。

## 完整文件清单

- [tests/fault_lost_response_host.gd](../tests/fault_lost_response_host.gd)
- [tests/fault_lost_response_lobby.gd](../tests/fault_lost_response_lobby.gd)
- [tests/run_asset_response_loss.gd](../tests/run_asset_response_loss.gd)
- [tests/test_asset_response_loss.ps1](../tests/test_asset_response_loss.ps1)

- [docs/01_scope_architecture.md](../docs/01_scope_architecture.md)
- [docs/02_contracts.md](../docs/02_contracts.md)
- [docs/03_sdk_integration.md](../docs/03_sdk_integration.md)
- [docs/06_roadmap_acceptance.md](../docs/06_roadmap_acceptance.md)
- [docs/07_versions_decisions.md](../docs/07_versions_decisions.md)
- [docs/17_framework_shooter_plan.md](../docs/17_framework_shooter_plan.md)
- [docs/18_asset_foundation.md](../docs/18_asset_foundation.md)
- [docs/19_admin_ui.md](../docs/19_admin_ui.md)
- [docs/20_shooter.md](../docs/20_shooter.md)
- [docs/21_managed_protocol.md](../docs/21_managed_protocol.md)
- [docs/22_framework_operations.md](../docs/22_framework_operations.md)
- [docs/23_branch_files.md](../docs/23_branch_files.md)
- [examples/account_login.example.json](../examples/account_login.example.json)
- [examples/account_register.example.json](../examples/account_register.example.json)
- [examples/account_response.example.json](../examples/account_response.example.json)
- [examples/admin_observability.example.json](../examples/admin_observability.example.json)
- [examples/asset_catalog.example.json](../examples/asset_catalog.example.json)
- [examples/framework/client.gd](../examples/framework/client.gd)
- [examples/framework/preview.gd](../examples/framework/preview.gd)
- [examples/framework/view.gd](../examples/framework/view.gd)
- [examples/managed_messages.example.json](../examples/managed_messages.example.json)
- [examples/result_rewards.example.json](../examples/result_rewards.example.json)
- [examples/shooter/adapter.gd](../examples/shooter/adapter.gd)
- [examples/shooter/asset_policy.gd](../examples/shooter/asset_policy.gd)
- [examples/shooter/game.gd](../examples/shooter/game.gd)
- [examples/shooter/game_config.json](../examples/shooter/game_config.json)
- [examples/shooter/game_manifest.json](../examples/shooter/game_manifest.json)
- [examples/shooter/messages.example.json](../examples/shooter/messages.example.json)
- [examples/shooter/rewards.gd](../examples/shooter/rewards.gd)
- [examples/shooter/room.gd](../examples/shooter/room.gd)
- [examples/shooter/test_runner.gd](../examples/shooter/test_runner.gd)
- [examples/turn_based/adapter.gd](../examples/turn_based/adapter.gd)
- [examples/turn_based/asset_policy.gd](../examples/turn_based/asset_policy.gd)
- [examples/turn_based/game.gd](../examples/turn_based/game.gd)
- [host/admin.html](../host/admin.html)
- [host/admin_http.gd](../host/admin_http.gd)
- [host/core/account_service.gd](../host/core/account_service.gd)
- [host/core/admission_store.gd](../host/core/admission_store.gd)
- [host/core/asset_catalog.gd](../host/core/asset_catalog.gd)
- [host/core/asset_rules.gd](../host/core/asset_rules.gd)
- [host/core/asset_service.gd](../host/core/asset_service.gd)
- [host/core/remote_results.gd](../host/core/remote_results.gd)
- [host/core/result_service.gd](../host/core/result_service.gd)
- [host/core/room_manager.gd](../host/core/room_manager.gd)
- [host/lobby_server.gd](../host/lobby_server.gd)
- [host/managed_host.gd](../host/managed_host.gd)
- [host/managed_lobby.gd](../host/managed_lobby.gd)
- [host/operator.gd](../host/operator.gd)
- [host/platform/process_launcher.gd](../host/platform/process_launcher.gd)
- [README.md](../README.md)
- [schemas/account_request.schema.json](../schemas/account_request.schema.json)
- [schemas/account_response.schema.json](../schemas/account_response.schema.json)
- [schemas/admin_request.schema.json](../schemas/admin_request.schema.json)
- [schemas/asset_catalog.schema.json](../schemas/asset_catalog.schema.json)
- [schemas/asset_command.schema.json](../schemas/asset_command.schema.json)
- [schemas/control.schema.json](../schemas/control.schema.json)
- [schemas/local_rpc.schema.json](../schemas/local_rpc.schema.json)
- [schemas/managed_lobby_request.schema.json](../schemas/managed_lobby_request.schema.json)
- [schemas/managed_lobby_response.schema.json](../schemas/managed_lobby_response.schema.json)
- [schemas/result_rewards.schema.json](../schemas/result_rewards.schema.json)
- [schemas/shooter_config.schema.json](../schemas/shooter_config.schema.json)
- [schemas/shooter_input.schema.json](../schemas/shooter_input.schema.json)
- [schemas/shooter_result.schema.json](../schemas/shooter_result.schema.json)
- [schemas/shooter_state.schema.json](../schemas/shooter_state.schema.json)
- [schemas/turns_state.schema.json](../schemas/turns_state.schema.json)
- [sdk/roomkit/client/account_client.gd](../sdk/roomkit/client/account_client.gd)
- [sdk/roomkit/client/room_client.gd](../sdk/roomkit/client/room_client.gd)
- [sdk/roomkit/README.md](../sdk/roomkit/README.md)
- [sdk/roomkit/server/game_adapter.gd](../sdk/roomkit/server/game_adapter.gd)
- [sdk/roomkit/server/room_runtime.gd](../sdk/roomkit/server/room_runtime.gd)
- [sdk/roomkit/shared/local_rpc.gd](../sdk/roomkit/shared/local_rpc.gd)
- [sdk/roomkit/shared/secure_transport.gd](../sdk/roomkit/shared/secure_transport.gd)
- [StartManagedTurns.cmd](../StartManagedTurns.cmd)
- [StartManagement.cmd](../StartManagement.cmd)
- [StartShooterClient.cmd](../StartShooterClient.cmd)
- [STATUS.md](../STATUS.md)
- [StopManagement.cmd](../StopManagement.cmd)
- [tests/fixtures/account_database.ps1](../tests/fixtures/account_database.ps1)
- [tests/fixtures/account_recovery_database.ps1](../tests/fixtures/account_recovery_database.ps1)
- [tests/fixtures/result_reward_database.ps1](../tests/fixtures/result_reward_database.ps1)
- [tests/run_account_recovery.gd](../tests/run_account_recovery.gd)
- [tests/run_accounts.gd](../tests/run_accounts.gd)
- [tests/run_admin_http.gd](../tests/run_admin_http.gd)
- [tests/run_asset_callbacks.gd](../tests/run_asset_callbacks.gd)
- [tests/run_framework_clients.gd](../tests/run_framework_clients.gd)
- [tests/run_framework_feedback.gd](../tests/run_framework_feedback.gd)
- [tests/run_framework_ui_fixture.ps1](../tests/run_framework_ui_fixture.ps1)
- [tests/run_managed_contracts.gd](../tests/run_managed_contracts.gd)
- [tests/run_managed_shutdown.gd](../tests/run_managed_shutdown.gd)
- [tests/run_operator_auth_errors.gd](../tests/run_operator_auth_errors.gd)
- [tests/run_operator_logs.gd](../tests/run_operator_logs.gd)
- [tests/run_operator_projection.gd](../tests/run_operator_projection.gd)
- [tests/run_operator_schedules.gd](../tests/run_operator_schedules.gd)
- [tests/run_recovery.gd](../tests/run_recovery.gd)
- [tests/run_result_rewards.gd](../tests/run_result_rewards.gd)
- [tests/run_ui_opponent.ps1](../tests/run_ui_opponent.ps1)
- [tests/test_admin_auth_errors.cjs](../tests/test_admin_auth_errors.cjs)
- [tests/test_asset_audit.ps1](../tests/test_asset_audit.ps1)
- [tests/test_assets.gd](../tests/test_assets.gd)
- [tests/test_framework_capacity.ps1](../tests/test_framework_capacity.ps1)
- [tests/test_framework_clients.ps1](../tests/test_framework_clients.ps1)
- [tests/test_framework_release.ps1](../tests/test_framework_release.ps1)
- [tests/test_managed_shutdown.ps1](../tests/test_managed_shutdown.ps1)
- [tests/test_operator.ps1](../tests/test_operator.ps1)
- [tests/test_operator_logs.ps1](../tests/test_operator_logs.ps1)
- [tests/test_operator_maintenance.ps1](../tests/test_operator_maintenance.ps1)
- [tests/test_operator_schedules.ps1](../tests/test_operator_schedules.ps1)
- [tests/test_shooter.gd](../tests/test_shooter.gd)
- [tools/account_store.ps1](../tools/account_store.ps1)
- [tools/bounded_helper.ps1](../tools/bounded_helper.ps1)
- [tools/build_framework.ps1](../tools/build_framework.ps1)
- [tools/build_framework_release.ps1](../tools/build_framework_release.ps1)
- [tools/operator_maintenance.ps1](../tools/operator_maintenance.ps1)
- [tools/run.ps1](../tools/run.ps1)
- [tools/run_framework.ps1](../tools/run_framework.ps1)
- [tools/sqlite_store.ps1](../tools/sqlite_store.ps1)

## 最后增补的用途

以下说明本轮后续增补的文件与修改；完整清单已包含这些项目，不以暂存或提交状态划分：

- `docs/01_scope_architecture.md`、`02_contracts.md`、`03_sdk_integration.md`、`06_roadmap_acceptance.md`：补当前 S 分支、SDK 0.5、协议与运行入口指引，明确保留的 M/S 初期“未实现”描述属于历史时点。
- `tests/run_operator_auth_errors.gd`、`tests/test_admin_auth_errors.cjs`：执行实际管理请求/错误传播与页面 API 函数，区分暂时存储/工作队列失败和真正认证失败，并检查迟到的旧会话错误不能注销新会话。账号响应、HTTP/浏览器环境为测试替身，不是实际数据库故障注入或浏览器 UI 验收。
- `tests/run_framework_feedback.gd`：覆盖确认死亡、等待复活、确认复活后的提示转换；对应 `examples/framework/client.gd` 清除已完成复活的等待提示。该专项使用确认快照投影验证客户端反馈，不代替真实联机或原生窗口验收。
- `tests/run_operator_logs.gd`、`tests/test_operator_logs.ps1`：通过真实 Godot 日志及 Windows 文件独占锁，检查日志路径映射、有界尾部读取，以及空文件、缺失文件和读取失败的不同返回。
- `tests/run_operator_schedules.gd`、`tests/test_operator_schedules.ps1`：使用独立数据与端口，运行实际 Operator、SQLite 自动备份和宿主重启预算；只在测试实例中控制到期时间和历史重启时间，因此不代表已经等待完整 30 分钟备份周期或 10 分钟重启窗口。
- `examples/admin_observability.example.json`：补充备份大小、空日志、日志缺失和读取失败的请求／响应示例。
- 已有 `tools/run_framework.ps1` 与 `tools/build_framework_release.ps1` 中的导出启动器模板，向 Operator 明确传递实际引擎日志路径；发布构建同时使用每次构建的唯一标识区分游戏清单与服务端产物。已有 `host/admin.html` 清除登录前遗留提示，并在宿主未运行时显示“未运行”。

对应代码与测试文件列入清单，不等于本轮执行结果全部通过；实际命令、结果和最终导出包的交互证据以 STATUS 为准。

## 追加的容量验证

新增 [tests/test_framework_capacity.ps1](../tests/test_framework_capacity.ps1)，复用 [真实客户端驱动](../tests/run_framework_clients.gd)。驱动新增 `join_sdk`，保留 SDK 返回的房间预留拒绝码；原 `join` 读取的 `last_error` 只反映后续 ENet 连接错误。其余追加的 UI 夹具、管理停服与投影专项也已纳入上方清单；列入文件清单本身不表示相应验收已通过。

从仓库目录复跑：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/test_framework_capacity.ps1
```

本轮实际运行退出 **0**，**174 项通过、0 项失败**，环境是 Windows 本机 Godot `4.7.2.stable.steam.ed1daf0bf`。测试建立独立的当前源码副本、私有数据库和动态 TCP/UDP 端口，不使用默认 `data/framework`，也不覆盖其它管理服务的公开连接配置。生产对局仍为 300000ms、奖励参与门槛 60000ms、手动复活等待 3000ms，未为容量测试缩短规则。

- 17 个独立真实客户端完成邀请码注册与 WSS 登录；其中 16 人通过 DTLS/ENet 进入同一个容量为 16 的射击房间。
- 第 17 人明确收到 `ROOM_FULL`，保持在大厅；其余 16 人收到相同的服务端身份集合。
- 满员观察持续 **17.528 秒**，7 个完整样本均保持 16 个连接与 16 个占用名额。所有客户端的快照 tick 持续增加，并共同观察到真实服务端移动；样本间心跳增加 59 次。
- 16 人依次退房后逐个确认名额回收；此前被拒绝的第 17 人成功使用回收后的座位，再正常退出。
- 全部玩家注销，房间停止并确认退出，私有进程 journal 清空，UDP 可重新绑定。17 个客户端与 operator 均正常退出；另通过身份核验确认 host/room 退出。最终进程核查显示本专项三轮测试的 Godot 进程均为 0，三个 host 标记均已移除。

生产源码副本建立于 **2026-09-22 01:39:41（北京时间）**，即 `2026-09-21T17:39:41.8985934Z`；141 个生产源码、协议与工具文件的 SHA256 保存在 `source-snapshot.json`。容量专项结束时的核对显示，当时工作区相对该副本只有 `host/admin.html` 和 `tools/build_framework_release.ps1` 另有修改，容量相关生产代码保持一致。此后分支继续增补客户端反馈、日志及调度相关修改；该容量结果仅对应上述副本，不能替代随后源码或导出包变更的验收。

本机证据目录：`logs/capacity-0f1e2cdae67c42a79129524c40530eef/`，包含 `result.json`、`samples.json`、`source-snapshot.json`、`final-audit.json`，以及各客户端与 operator 的报告和日志。

前两轮失败证据保留：`capacity-abb185935cb640e1b7d34d36f5ba1e0e` 的驱动未保留预留错误码；`capacity-08ab0cb4e6bf4f17bcdc05d715c69cac` 的单次本地报告读取遇到文件替换，被误判为 tick 为 0。修正后完整重跑；仅对报告文件增加最多 200ms 的读取重试，未放松 `ROOM_FULL`、人数、快照进展或清理断言。各目录的 `diagnosis.json` 说明原因，原失败结果没有覆盖。

## 验收边界

本次新增证据是**单台 Windows、源工程副本、短时容量和准入**，不是长期压测、性能指标达标或跨设备联机验收。浏览器完整业务点击、最新独立导出客户端的完整交互与视觉检查、跨电脑实体设备、Linux 完整宿主等需要各自的执行证据；不能因本项通过就标为完成。整体状态继续以 STATUS 中分别记录的结果为准。
