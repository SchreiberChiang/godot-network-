# RoomKit 横版射击 · 玩家客户端（Windows x64，GitHub 版）

这是一个完整的游戏目录，不需要安装 Godot，也不是压缩包。它和服务器主机用 `PreparePlayerClient.cmd` 生成的本地客户端是同一次导出，版本见 `client-version.json` 的 `build_id` 和 `release_tag`。目录里不含账号数据、服务器私钥或管理员凭据，也不含任何服务器的连接配置。

## 获取

GitHub 单个文件不能超过 100 MiB，而 `Client.exe` 有 104 MiB，所以它不在仓库里，只作为 GitHub Release 的附件提供。

- **克隆了仓库**：打开 `clients/shooter-windows`，双击 `FetchClient.cmd`。脚本会从 `release_tag` 对应的 Release 下载 `Client.exe` 原文件，并核对大小和 SHA256。
- **只用浏览器**：打开 `release_tag` 对应的 Release 页面，把全部附件下载到同一个新文件夹。不要下载 Source code 压缩包。

`CheckClient.cmd` 用来检查文件是否齐全、版本是否一致。

## 设置服务器

向服务器主机要 `connection.json` 和 `server.crt` 这两个公开文件（主机运行 `StartManagement.cmd` 后，它们在 `artifacts\client` 里）。拿到后，二选一：

- 把装着这两个文件的文件夹拖到 `SetServer.cmd` 上；
- 或者把两个文件放进本目录下的 `server-config` 文件夹，再双击 `SetServer.cmd`。

服务器必须运行同一版本；版本不一致时，登录后会提示“客户端与服务器版本不匹配”。

## 开始游戏

双击 `Client.exe`（它会读取同一文件夹里的 `connection.json`；`StartGame.cmd` 效果相同，保留作兼容入口），然后用邀请码注册、登录，创建或加入房间。

## 本机数据与更新

新版“网络详情 / 报告”可在本机整理邮件草稿、复制诊断摘要和服主配置的收件地址。不会上传到游戏服务器，也不保存邮箱密码；需自己在邮件软件或网页邮箱检查并发送。详细 JSONL 可从报告目录自行附加，不要发送整个 `client-data`。

运行后，设置、诊断和待确认的资产操作保存在 `Client.exe` 旁的 `client-data/`，与启动时的工作目录无关。账号密码和会话凭据只留在内存，不存到这个目录。目录不可写时会提示停止记录，不会悄悄改存到其它磁盘，也不阻止登录或游戏。

给别人发送诊断时，只发送客户端导出的脱敏报告；不要把 `client-data` 整个打包或放到 Git/Release。诊断日志使用有界存储，多开各自记录；磁盘预算用尽或写入失败时会停止记录并提示。不要在游戏运行时手动整理日志。

主机重新运行 `PreparePlayerClient.cmd` 前，先关闭该目录的所有客户端。工具只保留普通、无链接的 `client-data`，把它完整移入新版客户端；交换或迁移失败会恢复旧客户端和数据。其它新增或改动的文件仍会阻止替换，不会被自动删除。历史目录如果含 `client-data`，自动清理也会拒绝。

手工换目录时，先关闭客户端，保留自己的 `client-data`，再用匹配服务器的新程序；不要用朋友的本机数据覆盖它。给朋友发客户端请使用全新生成的干净目录或 Release 文件，不能复制已经玩过的整个目录。`CheckClient.cmd` 会提示本机数据存在以及发现的链接问题，不会把数据加入程序校验清单。

旧版 `data/client-operations` 只作为一次性迁移输入识别，不是新的运行目录豁免：只有完全符合旧回执格式、无链接且没有其它文件的目录才会整体改名保留到 `client-data/legacy-client-operations/client-operations/`。原始字节和 operation_id 不变，空目录也保留；原有隔离目录冲突或任何未知、损坏内容都会拒绝更新并保留原目录。交换或迁移失败会恢复完整旧目录。此步骤不推测服务器归属、不联网、不自动补发；登录后仍需在客户端显式确认旧操作对应的服务器。
