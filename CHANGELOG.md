# 版本变化

本文件只记录版本号与兼容标识的变化；设计决策与完整兼容说明见 [docs/07](docs/07_versions_decisions.md)，实际验证结果见 [STATUS](STATUS.md)。版本轴彼此独立：源码 SDK、框架包、游戏构建（`build_id` / `compatibility_id` / `game_protocol`）与控制协议 `control_protocol` 分开编号。以下均为本机开发或候选版本，不是正式发布。

## 2026-10-01 Linux 源码与备份等待

- 源码 SDK 仍为 **0.5.0**；账号、控制和结果 Schema 版本不变。内部 RPC 新增可选取消事件，宿主和 Operator 应使用同一份源码部署。
- 本轮构建为 `shooter-dev-002-src-70b8f5366f78`、`turns-managed-dev-001-src-6c031a3e2b26`，Windows 与 Linux 的摘要一致。当前客户端需随源码更新重新生成；旧玩家副本及旧发行附件没有同步重建。

## 2026-09-26 源码更新（2026-09-27 本地提交）

- 射击示例升级为 `shooter-dev-002` / `shooter-v2` / `game_protocol=2`：可信清单新增通用整数 `room_rules`，射击状态新增获胜击杀目标。旧射击客户端必须重新构建。
- 新增受信本地注册表契约 `managed_game_registry.schema.json`。SDK 仍为 **0.5.0**，账号/WSS/控制/ENet 线上消息版本不变。2026-09-22 的独立包不含这两项变化。

## 2026-09-22

- 源码 SDK **0.5.0**：新增托管账号/资产接口；源码构建为 `shooter-dev-001`（`shooter-v1`）与 `turns-managed-dev-001`（`turns-managed-v1`）。`control_protocol` 仍为 1，但新增资产许可与异步刷新消息，宿主与房间必须同时升级。
- 框架候选包 `0.5.0-framework-candidate`：正式构建标识改为 `<game>-framework-win-<构建唯一ID>`。
- 资产目录 v1 新增可选的 `level_thresholds`。

## 2026-09-21

- 源码 SDK **0.4.0**。开发构建为 `minimal_room/dev-004`、`blocks-dev-003`（`blocks-v3`）、`turns-dev-003`（`turns-v3`）；Windows 正式构建为 `blocks-win-001` / `turns-win-001`（`blocks-win-v1` / `turns-win-v1`）。
- 早期 Windows 候选包 **0.1.0-candidate**。
- 源码 SDK **0.3.0**（M4 第一部分）：新增可选的 `result.submit` / `result.ack`，`result_version=1`；构建依次升为 dev-003、`blocks-v2`、`turns-v2`。

## 2026-09-20

- 源码 SDK **0.2.0**（M2）：新增 WebSocket 大厅与双端 SDK，最小示例为 `dev-002`（`roomkit-minimal-dev-002`）。
- M3 新增 `blocks` / `turns`：`blocks-dev-001` / `turns-dev-001`（`blocks-v1` / `turns-v1`），`game_protocol=1`。

## 2026-09-19

- M0/M1：锁定引擎 `4.7.2.stable.steam.ed1daf0bf`，最小房间为 `dev-001`，`control_protocol=1`。

## v0.2 设计包 — 2026-09-18

改为独立新项目，从零开发，不接旧工程。

重写 AGENTS、README 和 M0/M1 路线；删除对保留旧流程、旧房间逻辑、旧大厅迁移和旧账号库的要求。大厅从第一次实现就使用标准 JSON 通道。

新增 START_HERE、CODEX_START、docs/00 首轮实施任务、STATUS 与 .gitignore。示例游戏改为 minimal_room，不使用旧射击项目标识。统一 schemas/ 作为契约文件来源。

保留架构边界、后续安全门禁与 25 项总体验收。引入 G00—G09 作为首轮明确验收。此版本号仅属于设计包，不表示框架已经实现或发布。

（START_HERE 与设计包检查记录 VALIDATION 已于 2026-09-27 移入 [docs/archive/design_package_v0.2.md](docs/archive/design_package_v0.2.md)。）
