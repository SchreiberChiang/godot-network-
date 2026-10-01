# 本轮分支修改文件

2026-10-02 Codex 试玩反馈与后续规划（基准 `main / f132e4a`）：仅修改 CONTEXT、README、STATUS、docs/17、本清单和路线图；记录用户本机整体试玩正常、尚未分发他人，补充交付术语并规划部署/更新闭环。没有改功能、接触运行环境或实施更新，后续门槛见 [当前安排](17_framework_shooter_plan.md#next-delivery-stage)。

2026-10-02 Codex 独立包真人入口（基准 `main / 4bbafc8`）：新增 `PlayLinuxPackage.cmd`、`StopLinuxPackage.cmd`、`tools/open_linux_package.ps1`、`tests/test_linux_package_entry.ps1`；管理转发脚本的管理员提示改为实例中性说明；更新 README、STATUS、docs/17、22、本清单及路线图。客户端、私有说明和目标清单只在忽略目录，服务器/客户端不重建，旧 LAN 与 Windows 真实数据保留。说明见 [独立包试玩](17_framework_shooter_plan.md#linux-package-playtest)。

2026-10-02 Codex Linux 独立服务器目录（基准 `main / ae5225d`）：新增 `tools/build_linux_server.ps1`、`tools/linux_package_check.sh`、`tests/test_linux_server_package.ps1`；修改 `host/operator.gd` 的导出版宿主平台文件名、`tools/roomkit_linux.sh` 的包运行/端口保存/路径检查、`tests/run_operator_projection.gd` 与 `tests/support/client_harness.ps1` 的报告读取边界；更新 README、STATUS、CHANGELOG、docs/10、17、22、本清单和路线图。干净分发目录、Linux 隔离部署、假库、玩家客户端和失败证据仅在忽略目录，不把二进制或私有数据加入 Git。执行范围见 [独立目录](17_framework_shooter_plan.md#linux-server-directory)。

2026-10-01 Codex Linux 后台入口（基准 `main / 7d5594e`）：新增 `OpenLinuxManagement.cmd`、`tools/open_linux_management.ps1`；更新 README、STATUS、docs/10、17 和本清单。仅建立自持有的回环 SSH 转发，保留原服务与真实数据；补记 Linux 分发目录的资源调查与下一阶段任务，尚未修改导出或服务器代码。

2026-10-01 Codex 局域网跨机验收（基准 `main / 572c356`）：新增 `tests/test_linux_lan.ps1`、`OpenLinuxPlayerClient.cmd`、`tools/open_linux_player_client.ps1`；更新 README、STATUS、docs/10、17、22、本清单及路线图数据。生产服务器、SDK、协议和构建规则未改；源码快照、假数据库、私有测试说明、公开连接配置和新导出的客户端仅在忽略目录。说明见 [Windows → Linux](17_framework_shooter_plan.md#linux-lan)。

2026-10-01 Codex 备份等待收尾（基准 `main / b177e3f`）：新增 `tests/run_operator_backup_wait.gd`、`tests/run_local_rpc_cancel.gd`、`tests/test_operator_backup_login.ps1`、`tests/run_managed_reference_lifetime.gd`；修改 Operator、大厅及内部 LocalRPC、客户端/后台维护提示、协议例子及对应检查、`host/core/remote_results.gd` 的弱回引用；补严 Linux C/D/E 驱动和客户端退出码核对；同步 README、STATUS、CHANGELOG、docs/10、17、21、22、本清单与路线图数据。说明与证据见 [docs/17](17_framework_shooter_plan.md#l3-backup-wait)，稳定语义见 [docs/21](21_managed_protocol.md#玩家账号)。本地运行目录、设备快照及失败启动输出不纳入 Git；玩家副本和旧发行产物未重建。

2026-09-30 Linux 安装验证及 L1 存储切片（main，Claude 实现、Codex 复核）：新增 `tests/content_digest_portable.ps1`、`tests/storage_slice_portable.ps1`、`tests/linux_test_lib_selftest.sh`、`tools/linux_isolated_setup.sh`、`tools/linux_storage_slice.sh`、`tools/linux_test_lib.sh`；修改 `tools/sqlite_store.ps1`、`tools/account_store.ps1`、STATUS、docs/10、17 和本清单。Linux 仅存储脚本与纯逻辑有证据，完整服务器未实现。测试输出及假数据库位于忽略目录，不纳入提交；原生 SQLite 评估尚未实施。

2026-09-26，分支 `codex/shooter-framework`，相对起点提交 `711a657`。包含此前已提交与当前工作区源码；不包含 logs/data/artifacts 的运行产物。

已完成托管模板、客户端启动修复，以及射击平滑显示、短弹迹和房间规则。本次单独修改清单和证据见 [docs/25](25_shooter_room_rules.md)，全程进度见 [STATUS](../STATUS.md)。

2026-09-27 补记：AGENTS.md 由协作规则轮次修改（仅文档）；Claude 文档整理新增 `docs/archive/` 四个文件，修改 README、STATUS、CHANGELOG、docs/01、08、15、16、22、23，并把根目录 START_HERE.md、VALIDATION.md 的原文移入归档后删除原文件。随后按用户要求保存 Claude 角色立绘为 `docs/assets/claude-character.png`，其路径记入 AGENTS.md、STATUS.md 和本清单；未改游戏代码。

2026-09-27 账号请求 stdin 改造（Claude 实现、Codex 复核，本地提交）：新增 `tests/run_storage_timing.gd`、`tests/fixtures/storage_cost_breakdown.ps1`，修改 `host/core/account_service.gd`、`host/platform/bounded_helper.gd`、`tools/account_store.ps1`、`tools/bounded_helper.ps1`、`tools/test_helpers.ps1`、docs/21、22、23 和 STATUS。

2026-09-27 grant 签名密钥 stdin 改造（Claude 实现、Codex 复核，基于 `07aa0d2`，本地提交）：新增 `tests/run_grant_storage.gd`、`tests/fixtures/grant_database.ps1`，修改 `host/storage/sqlite_repository.gd`、`tools/sqlite_store.ps1`、`tests/run_secure.gd`、`tests/fixtures/secure_client.gd`、docs/21、22、23 和 STATUS。secure 测试改为通过 WSS 后单独验证 DTLS 错误主机名。

2026-09-27 常驻存储方案 B 第一阶段（Claude，已本地提交）：新增 `host/storage/resident_store.gd`、`tools/storage_worker.ps1`、`tests/run_resident_store.gd`；修改 `host/storage/sqlite_repository.gd`、`host/core/account_service.gd`、`host/operator.gd`、`tools/sqlite_store.ps1`、`tools/account_store.ps1`、`tools/build_framework_release.ps1`、`tests/run_asset_snapshot.gd`、`tests/run_storage_timing.gd`、`tests/test_framework_clients.ps1`（复活前等待倒计时）、`tests/test_framework_release.ps1`（房间状态轮询）、docs/17、21、22、23 和 STATUS。

2026-09-27 常驻存储评估（Claude，已本地提交，仅测量工具和文档）：新增 `tests/perf/` 下 6 个测量脚本，更新 docs/17 第六节、docs/22、23 和 STATUS；未改生产代码。

2026-09-27 资产 `asset.snapshot`（Codex 实现、Claude 复核，已本地提交）：修改 `host/core/asset_service.gd`、`tools/sqlite_store.ps1`、`tests/run_storage_timing.gd`、docs/17、STATUS；复核新增 `tests/run_asset_snapshot.gd`，并更新 docs/22、23。

2026-09-27 Codex 复核：修正 Windows PowerShell 5.1 内层标准输入的 UTF-8 BOM、测试夹具的中文输出编码，以及 `tests/run_admin_http.gd` 的旧分层断言；更新 STATUS。没有增加文件。

2026-09-27 后续方向梳理（仅文档）：新增根目录 `CONTEXT.md` 术语表，更新 docs/17 的多游戏定位、赛车与合作种田边界、授权回收和性能路线；同步 README、STATUS 与本清单。未修改运行代码。

2026-09-27 密码长度小阶段（Codex，已本地提交）：账号最低长度从 10 调到 8；修改 `schemas/account_request.schema.json`、`schemas/managed_lobby_request.schema.json`、`tools/account_store.ps1`、`host/admin.html`、`examples/framework/view.gd`、`tests/run_accounts.gd`、`tests/run_managed_contracts.gd`、`tests/test_framework_release.ps1`，同步 README、STATUS、docs/17、21、23。沿用现有密码哈希、会话和数据库格式；独立包已重建，全新解压副本使用 8 字符管理员和玩家密码完成自动包测试 44/0。

2026-09-27 第二台设备登记（Codex）：`docs/10_environment.md` 记录用户提供的 Linux 笔记本局域网 SSH 目标，STATUS 标记未连接、未验收；没有执行远程命令。

2026-09-27 账号停用安排（Codex，`domain-modeling`）：用户确认“删除用户”指可恢复的账号停用，所有游戏资产永久保留；更新 `CONTEXT.md`、docs/17 第七节、STATUS 与后台提示。沿用 `account.ban/unban`，没有新增删除接口或运行新测试。

2026-09-27 账号删除纠正（Codex，文档）：用户撤回“只停用”的理解，改为测试阶段清除指定玩家在当前账号库与资产库的数据，旧备份单独标明并处理。更新 `CONTEXT.md`、docs/17 第七节和 STATUS；删除功能尚未实现，前一轮停用入口仍为独立功能。

2026-09-27 测试阶段账号删除（Claude 实现，基于 `d79b1fc`，未提交，待 Codex 复核）：新增 `host/core/account_deletion.gd`、`tests/run_account_deletion.gd`、`tests/run_deletion_client.gd`、`tests/test_account_deletion.ps1`、`tests/test_admin_account_deletion.cjs`、`tests/fixtures/deletion_database.ps1`、`tests/fixtures/deletion_offline.gd`；修改 `tools/account_store.ps1`、`tools/sqlite_store.ps1`、`host/core/account_service.gd`、`host/operator.gd`、`host/admin.html`、`schemas/admin_request.schema.json`、`schemas/account_request.schema.json`、`schemas/account_response.schema.json`、`examples/managed_messages.example.json`、`tests/run_admin_http.gd`、`tests/run_managed_contracts.gd`，以及 README、CONTEXT、STATUS、docs/17、21、22 和本清单。

2026-09-27 账号删除复核修正（Claude，未提交，待 Codex 复核）：Operator 收尾可恢复、删除原因去名。修改 `tools/account_store.ps1`、`tools/sqlite_store.ps1`、`host/core/account_deletion.gd`、`host/core/account_service.gd`、`host/operator.gd`、`host/admin.html`、`schemas/account_response.schema.json`、`tests/run_account_deletion.gd`、`tests/test_account_deletion.ps1`、`tests/fixtures/deletion_offline.gd`，以及 STATUS、docs/17、21、22 和本清单；没有新增文件。

## 完整文件清单
共 185 个现存文件，另有 2 个已移除文件列在末尾。

- [AGENTS.md](../AGENTS.md)
- [CHANGELOG.md](../CHANGELOG.md)
- [CONTEXT.md](../CONTEXT.md)
- [docs/01_scope_architecture.md](../docs/01_scope_architecture.md)
- [docs/02_contracts.md](../docs/02_contracts.md)
- [docs/03_sdk_integration.md](../docs/03_sdk_integration.md)
- [docs/06_roadmap_acceptance.md](../docs/06_roadmap_acceptance.md)
- [docs/07_versions_decisions.md](../docs/07_versions_decisions.md)
- [docs/08_sources.md](../docs/08_sources.md)
- [docs/15_release_operations.md](../docs/15_release_operations.md)
- [docs/16_dashboard.md](../docs/16_dashboard.md)
- [docs/17_framework_shooter_plan.md](../docs/17_framework_shooter_plan.md)
- [docs/18_asset_foundation.md](../docs/18_asset_foundation.md)
- [docs/19_admin_ui.md](../docs/19_admin_ui.md)
- [docs/20_shooter.md](../docs/20_shooter.md)
- [docs/21_managed_protocol.md](../docs/21_managed_protocol.md)
- [docs/22_framework_operations.md](../docs/22_framework_operations.md)
- [docs/23_branch_files.md](../docs/23_branch_files.md)
- [docs/24_managed_game_template.md](../docs/24_managed_game_template.md)
- [docs/25_shooter_room_rules.md](../docs/25_shooter_room_rules.md)
- [docs/archive/README.md](../docs/archive/README.md)
- [docs/archive/design_package_v0.2.md](../docs/archive/design_package_v0.2.md)
- [docs/archive/early_entrypoints.md](../docs/archive/early_entrypoints.md)
- [docs/archive/status_history.md](../docs/archive/status_history.md)
- [docs/assets/claude-character.png](../docs/assets/claude-character.png)
- [examples/account_login.example.json](../examples/account_login.example.json)
- [examples/account_register.example.json](../examples/account_register.example.json)
- [examples/account_response.example.json](../examples/account_response.example.json)
- [examples/admin_observability.example.json](../examples/admin_observability.example.json)
- [examples/asset_catalog.example.json](../examples/asset_catalog.example.json)
- [examples/framework/client.gd](../examples/framework/client.gd)
- [examples/framework/preview.gd](../examples/framework/preview.gd)
- [examples/framework/services.json](../examples/framework/services.json)
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
- [host/core/account_deletion.gd](../host/core/account_deletion.gd)
- [host/core/account_service.gd](../host/core/account_service.gd)
- [host/core/admission_store.gd](../host/core/admission_store.gd)
- [host/core/asset_catalog.gd](../host/core/asset_catalog.gd)
- [host/core/asset_rules.gd](../host/core/asset_rules.gd)
- [host/core/asset_service.gd](../host/core/asset_service.gd)
- [host/core/game_registry.gd](../host/core/game_registry.gd)
- [host/core/managed_game_registry.gd](../host/core/managed_game_registry.gd)
- [host/core/remote_results.gd](../host/core/remote_results.gd)
- [host/core/result_service.gd](../host/core/result_service.gd)
- [host/core/room_manager.gd](../host/core/room_manager.gd)
- [host/lobby_server.gd](../host/lobby_server.gd)
- [host/managed_host.gd](../host/managed_host.gd)
- [host/managed_lobby.gd](../host/managed_lobby.gd)
- [host/operator.gd](../host/operator.gd)
- [host/platform/bounded_helper.gd](../host/platform/bounded_helper.gd)
- [host/platform/process_launcher.gd](../host/platform/process_launcher.gd)
- [host/storage/resident_store.gd](../host/storage/resident_store.gd)
- [host/storage/sqlite_repository.gd](../host/storage/sqlite_repository.gd)
- [README.md](../README.md)
- [schemas/account_request.schema.json](../schemas/account_request.schema.json)
- [schemas/account_response.schema.json](../schemas/account_response.schema.json)
- [schemas/admin_request.schema.json](../schemas/admin_request.schema.json)
- [schemas/asset_catalog.schema.json](../schemas/asset_catalog.schema.json)
- [schemas/asset_command.schema.json](../schemas/asset_command.schema.json)
- [schemas/control.schema.json](../schemas/control.schema.json)
- [schemas/game_manifest.schema.json](../schemas/game_manifest.schema.json)
- [schemas/local_rpc.schema.json](../schemas/local_rpc.schema.json)
- [schemas/managed_game_registry.schema.json](../schemas/managed_game_registry.schema.json)
- [schemas/managed_lobby_request.schema.json](../schemas/managed_lobby_request.schema.json)
- [schemas/managed_lobby_response.schema.json](../schemas/managed_lobby_response.schema.json)
- [schemas/result_rewards.schema.json](../schemas/result_rewards.schema.json)
- [schemas/room_rules.schema.json](../schemas/room_rules.schema.json)
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
- [templates/managed_game/asset_catalog.json](../templates/managed_game/asset_catalog.json)
- [templates/managed_game/client.gd](../templates/managed_game/client.gd)
- [templates/managed_game/game/adapter.gd](../templates/managed_game/game/adapter.gd)
- [templates/managed_game/game/asset_policy.gd](../templates/managed_game/game/asset_policy.gd)
- [templates/managed_game/game/room.gd](../templates/managed_game/game/room.gd)
- [templates/managed_game/game/world.gd](../templates/managed_game/game/world.gd)
- [templates/managed_game/README.md](../templates/managed_game/README.md)
- [templates/managed_game/schemas/managed_template_state.schema.json](../templates/managed_game/schemas/managed_template_state.schema.json)
- [templates/managed_game/schemas/template_result.schema.json](../templates/managed_game/schemas/template_result.schema.json)
- [tests/fault_lost_response_host.gd](../tests/fault_lost_response_host.gd)
- [tests/fault_lost_response_lobby.gd](../tests/fault_lost_response_lobby.gd)
- [tests/fixtures/account_database.ps1](../tests/fixtures/account_database.ps1)
- [tests/fixtures/account_recovery_database.ps1](../tests/fixtures/account_recovery_database.ps1)
- [tests/fixtures/deletion_database.ps1](../tests/fixtures/deletion_database.ps1)
- [tests/fixtures/deletion_offline.gd](../tests/fixtures/deletion_offline.gd)
- [tests/fixtures/grant_database.ps1](../tests/fixtures/grant_database.ps1)
- [tests/fixtures/result_reward_database.ps1](../tests/fixtures/result_reward_database.ps1)
- [tests/fixtures/secure_client.gd](../tests/fixtures/secure_client.gd)
- [tests/fixtures/storage_cost_breakdown.ps1](../tests/fixtures/storage_cost_breakdown.ps1)
- [tests/run_account_deletion.gd](../tests/run_account_deletion.gd)
- [tests/run_account_recovery.gd](../tests/run_account_recovery.gd)
- [tests/run_accounts.gd](../tests/run_accounts.gd)
- [tests/run_admin_http.gd](../tests/run_admin_http.gd)
- [tests/run_asset_callbacks.gd](../tests/run_asset_callbacks.gd)
- [tests/run_asset_response_loss.gd](../tests/run_asset_response_loss.gd)
- [tests/perf/measure_asset_e2e.ps1](../tests/perf/measure_asset_e2e.ps1)
- [tests/perf/resident_store_probe.ps1](../tests/perf/resident_store_probe.ps1)
- [tests/perf/run_asset_e2e.gd](../tests/perf/run_asset_e2e.gd)
- [tests/perf/run_gd_pbkdf2_probe.gd](../tests/perf/run_gd_pbkdf2_probe.gd)
- [tests/perf/run_resident_probe.gd](../tests/perf/run_resident_probe.gd)
- [tests/perf/storage_oneshot_variants.ps1](../tests/perf/storage_oneshot_variants.ps1)
- [tests/run_asset_snapshot.gd](../tests/run_asset_snapshot.gd)
- [tests/run_deletion_client.gd](../tests/run_deletion_client.gd)
- [tests/run_framework_clients.gd](../tests/run_framework_clients.gd)
- [tests/run_framework_feedback.gd](../tests/run_framework_feedback.gd)
- [tests/run_framework_ui_fixture.ps1](../tests/run_framework_ui_fixture.ps1)
- [tests/run_grant_storage.gd](../tests/run_grant_storage.gd)
- [tests/run_managed_contracts.gd](../tests/run_managed_contracts.gd)
- [tests/run_managed_registry.gd](../tests/run_managed_registry.gd)
- [tests/run_managed_shutdown.gd](../tests/run_managed_shutdown.gd)
- [tests/run_operator_auth_errors.gd](../tests/run_operator_auth_errors.gd)
- [tests/run_operator_logs.gd](../tests/run_operator_logs.gd)
- [tests/run_operator_projection.gd](../tests/run_operator_projection.gd)
- [tests/run_operator_schedules.gd](../tests/run_operator_schedules.gd)
- [tests/run_recovery.gd](../tests/run_recovery.gd)
- [tests/run_resident_store.gd](../tests/run_resident_store.gd)
- [tests/run_result_rewards.gd](../tests/run_result_rewards.gd)
- [tests/run_secure.gd](../tests/run_secure.gd)
- [tests/run_shooter.gd](../tests/run_shooter.gd)
- [tests/run_shooter_visual.gd](../tests/run_shooter_visual.gd)
- [tests/run_storage_timing.gd](../tests/run_storage_timing.gd)
- [tests/run_ui_opponent.ps1](../tests/run_ui_opponent.ps1)
- [tests/test_account_deletion.ps1](../tests/test_account_deletion.ps1)
- [tests/test_admin_account_deletion.cjs](../tests/test_admin_account_deletion.cjs)
- [tests/test_admin_asset_spaces.cjs](../tests/test_admin_asset_spaces.cjs)
- [tests/test_admin_auth_errors.cjs](../tests/test_admin_auth_errors.cjs)
- [tests/test_admin_room_rules.cjs](../tests/test_admin_room_rules.cjs)
- [tests/test_asset_audit.ps1](../tests/test_asset_audit.ps1)
- [tests/test_asset_response_loss.ps1](../tests/test_asset_response_loss.ps1)
- [tests/test_assets.gd](../tests/test_assets.gd)
- [tests/test_client_launcher.ps1](../tests/test_client_launcher.ps1)
- [tests/test_framework_capacity.ps1](../tests/test_framework_capacity.ps1)
- [tests/test_framework_clients.ps1](../tests/test_framework_clients.ps1)
- [tests/test_framework_release.ps1](../tests/test_framework_release.ps1)
- [tests/test_managed_shutdown.ps1](../tests/test_managed_shutdown.ps1)
- [tests/test_managed_template.ps1](../tests/test_managed_template.ps1)
- [tests/test_manager.gd](../tests/test_manager.gd)
- [tests/test_operator.ps1](../tests/test_operator.ps1)
- [tests/test_operator_logs.ps1](../tests/test_operator_logs.ps1)
- [tests/test_operator_maintenance.ps1](../tests/test_operator_maintenance.ps1)
- [tests/test_operator_schedules.ps1](../tests/test_operator_schedules.ps1)
- [tests/test_registry_ports.gd](../tests/test_registry_ports.gd)
- [tests/test_room_rules.ps1](../tests/test_room_rules.ps1)
- [tests/test_shooter.gd](../tests/test_shooter.gd)
- [tools/account_store.ps1](../tools/account_store.ps1)
- [tools/bounded_helper.ps1](../tools/bounded_helper.ps1)
- [tools/build_framework.ps1](../tools/build_framework.ps1)
- [tools/build_framework_release.ps1](../tools/build_framework_release.ps1)
- [tools/new_game.ps1](../tools/new_game.ps1)
- [tools/operator_maintenance.ps1](../tools/operator_maintenance.ps1)
- [tools/run.ps1](../tools/run.ps1)
- [tools/run_framework.ps1](../tools/run_framework.ps1)
- [tools/test_helpers.ps1](../tools/test_helpers.ps1)
- [tools/sqlite_store.ps1](../tools/sqlite_store.ps1)
- [tools/storage_worker.ps1](../tools/storage_worker.ps1)

已移除（原文已移入 [docs/archive/design_package_v0.2.md](archive/design_package_v0.2.md)）：`START_HERE.md`、`VALIDATION.md`。
