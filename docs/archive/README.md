# 文档归档

这里存放已经不代表当前状态的过程记录和旧入门说明。当前入口见 [README](../../README.md)，当前状态见 [STATUS](../../STATUS.md)。归档正文都是原文搬运，失败、未运行和限制记录没有删减。

| 文件 | 内容 |
|---|---|
| [status_history.md](status_history.md) | 2026-09-19 至 2026-09-27 的逐轮 STATUS 记录（M0/M1 到托管模板与房间规则），以及原 docs/22 的 09-22 停服/调度专项结果；包含全部命令、计数、失败修复和证据路径 |
| [early_entrypoints.md](early_entrypoints.md) | 早期无账号演示入口一览，以及 2026-09-27 整理前的 README 原文 |
| [design_package_v0.2.md](design_package_v0.2.md) | 最初设计包的 START_HERE（Codex 新建项目入门）与 VALIDATION（设计包检查记录） |

## 证据位置

- 正文中的 `logs/…`、`data/…`、`artifacts/…` 都相对仓库根目录，是 Git 忽略的本机目录，只存在于产生这些结果的电脑上。
- 2026-09-23 清理时删除了旧导出包和旧解压副本。删除前，其中的非可再生文件已逐项校验，打包进 `data/cleanup-history-a4c423b0bdb6498bbb2b685ca8ac1452/artifact-evidence.zip`；`manifest.json` 记录原路径、大小和 SHA256。旧的 `artifacts/release.json`、`artifacts/delivery.json` 也在其中。该归档可能含测试账号数据，不要公开分发。

## 仍在原位置的历史性专题

以下编号文档仍在 `docs/` 中，因为其它文档和构建脚本引用了它们的路径；内容以各自写入时的阶段为准：[09 M1 控制](../09_m1_control.md)、[11 M2](../11_m2_implementation.md)、[12 M3 双玩法](../12_m3_games.md)、[13 M4 结果](../13_m4_results.md)、[14 M4/M5 工作表](../14_completion_work.md)、[15 早期发布](../15_release_operations.md)、[16 早期状态面板](../16_dashboard.md)、[23 分支文件清单](../23_branch_files.md)。首轮任务原文 [CODEX_START](../../CODEX_START.md) 被 AGENTS.md 引用，所以也留在根目录。
