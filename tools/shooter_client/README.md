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

双击 `StartGame.cmd`，然后用邀请码注册、登录，创建或加入房间。
