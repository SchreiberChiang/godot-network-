# 从新目录开始，不接旧工程

## 1. 解压

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

## 2. 在 Codex 添加新项目

选本地项目/打开文件夹的入口，将上面的 RoomKit 目录设为该项目的主要工作文件夹，只添加这个新目录，再在该项目中新开对话。界面用词可能随客户端版本变化；以实际选择的工作目录为准。[C1]

Codex 会发现项目 AGENTS.md；用户级指导仍可能存在，新建项目不等于清除全局指令。不需要删除 ~/.codex 或修改全局设置来“重新开始”。[C2]

## 3. 发送第一条任务

复制 CODEX_START.md 的任务正文，或者发送：

> 这是全新项目，不接旧工程。请先读取 AGENTS.md、README.md、CODEX_START.md、docs/00_greenfield_start.md 和 STATUS.md，按 CODEX_START.md 完成 M0 与 M1 的最小闭环；实际编写代码和测试，不只提交计划。

不用再发旧代码，也不用把整段聊天记录粘贴过去。边界、架构和第一阶段验收已在本目录中写明。

## 4. 首轮预期

应得到可检查的新工程文件、M1 生命周期实现、真实测试记录和本地运行说明。不应得到整套游戏已完成的宣称，也不应被带回旧项目重构。

本包尚无 project.godot，不用先在 Godot 手工建一个游戏；由 Codex 为 host 和测试工程建立各自的入口。M0/M1 完成后再开展双端 SDK 和两客户端入房。

## 参考

[C1] OpenAI 官方：Projects and chats，检索日期 2026-09-18。
`https://learn.chatgpt.com/docs/projects`

[C2] OpenAI 官方：Custom instructions with AGENTS.md，检索日期 2026-09-18。
`https://learn.chatgpt.com/docs/agent-configuration/agents-md`
