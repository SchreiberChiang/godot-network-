# 设计包 v0.2 入门与检查记录

本文件合并保存最初设计包（2026-09-18，v0.2）的两份根目录文档：`START_HERE.md`（在 Codex 中新建项目并发送首个任务的入门说明）和 `VALIDATION.md`（设计包自身的结构检查记录）。两者描述的是“只有设计文档、尚无 project.godot”的起点，现已过时，于 2026-09-27 从根目录移入归档，正文逐字保留（标题降级）。

当前项目入口见 [README](../../README.md)，实际状态见 [STATUS](../../STATUS.md)。首次 M0/M1 任务原文仍在根目录 [CODEX_START.md](../../CODEX_START.md)，其首轮范围已由 AGENTS.md 标为历史。

---

## 原 START_HERE.md

### 从新目录开始，不接旧工程

### 1. 解压

把 ZIP 中的 RoomKit 文件夹放到一个新的独立位置，例如 F:\Projects\RoomKit。不放进旧游戏仓库，不覆盖已有文件。直接包含 AGENTS.md 的这一层就是项目根目录。

```text
RoomKit/
  AGENTS.md
  CODEX_START.md
  README.md
  START_HERE.md
  STATUS.md
  VALIDATION.md
  CHANGELOG.md
  .gitignore
  docs/
  schemas/
  examples/
```

不要把 AGENTS.md 留在下一层“资料包”目录，然后让 Codex 在外层写工程。

### 2. 在 Codex 添加新项目

选本地项目/打开文件夹的入口，将上面的 RoomKit 目录设为该项目的主要工作文件夹，只添加这个新目录，再在该项目中新开对话。界面用词可能随客户端版本变化；以实际选择的工作目录为准。[C1]

Codex 会发现项目 AGENTS.md；用户级指导仍可能存在，新建项目不等于清除全局指令。不需要删除 ~/.codex 或修改全局设置来“重新开始”。[C2]

### 3. 发送第一条任务

复制 CODEX_START.md 的任务正文，或者发送：

> 这是全新项目，不接旧工程。请先读取 AGENTS.md、README.md、CODEX_START.md、docs/00_greenfield_start.md 和 STATUS.md，按 CODEX_START.md 完成 M0 与 M1 的最小闭环；实际编写代码和测试，不只提交计划。

不用再发旧代码，也不用把整段聊天记录粘贴过去。边界、架构和第一阶段验收已在本目录中写明。

### 4. 首轮预期

应得到可检查的新工程文件、M1 生命周期实现、真实测试记录和本地运行说明。不应得到整套游戏已完成的宣称，也不应被带回旧项目重构。

本包尚无 project.godot，不用先在 Godot 手工建一个游戏；由 Codex 为 host 和测试工程建立各自的入口。M0/M1 完成后再开展双端 SDK 和两客户端入房。

### 参考

[C1] OpenAI 官方：Projects and chats，检索日期 2026-09-18。
`https://learn.chatgpt.com/docs/projects`

[C2] OpenAI 官方：Custom instructions with AGENTS.md，检索日期 2026-09-18。
`https://learn.chatgpt.com/docs/agent-configuration/agents-md`

---

## 原 VALIDATION.md

### 本包实际检查记录

日期：2026-09-18。对象：RoomKit 从零开发文档包 v0.2。

已执行：

- 两份 JSON Schema 的 Draft 2020-12 结构检查。
- 游戏清单与创建请求示例验证；额外检查 game_id、兼容标识、模式、地图与人数对应一致。
- 三份测试用成功响应、失败响应、事件外壳通过结构验证；六份非法外壳被拒绝。
- Markdown 代码围栏配对、主要入口文件存在性、AGENTS.md 大小检查。
- 检查导致旧项目改造的原有启动指令已被替换；示例改为 minimal_room。
- ZIP 内容与 CRC 完整性检查；根路径为 RoomKit/，该层直接包含 AGENTS.md。

未执行：

Godot 解析、插件加载、真实进程、网络、Windows/Linux 启动、数据库、安全传输、导出或压力测试。本包没有运行时代码，不能作为可运行框架使用。

Godot 版本仍为 PIN_EXACT_TESTED_VERSION 模板占位；server_artifact 为示例标签。结构验证允许设计模板存在，不证明存在相应服务端产物。开发和部署时必须锁定真实版本、注册产物并拒绝未填写占位符。

验证只覆盖外壳与当前清单；每种控制消息的 payload、安全语义、跨字段关系与运行时状态仍需实施和测试。STATUS.md 中 M0—M5 全部保持未开始。
