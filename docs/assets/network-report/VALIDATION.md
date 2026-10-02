# D1 验收记录

## 主线独立验收（2026-10-03）

**通过 Windows Edge 的离线 file:// 验收，可接入主线。** 下方云端候选记录原样保留为历史，不把失败尝试删除或改成通过。

- 收件 ZIP 50924 字节，SHA256 `75e552cc099da35ca6c8c0d136847d3a1900595f6b4f37a6cc4e482d5d5996df`；14 项安全路径及清单全部核对一致。补丁在固定基准 `0e33fa6` 的 F 盘独立工作树通过 apply --check 后应用。
- 独立代码审查加定向解析 12/12，退出 0。补修一处计数字段边界：小数 `snapshot_samples` 现在按非法未知处理，不允许开启分位数；正整数仍可用。
- Node v24.18.0、现有 Playwright、Edge 143.0.3650.96，以全新临时配置真正打开 file://。没有安装依赖、启动游戏或操作现有浏览器。
- 最终命令：设置 `CHROMIUM_EXECUTABLE`、`NODE_PATH`、`NETWORK_REPORT_EVIDENCE`、`NETWORK_REPORT_SAMPLE_DIR` 后运行 `node --test tests/test_network_report.cjs tests/test_network_report_browser.cjs`。**10/10，退出 0、跳过 0**：8 个核心测试、1 个完整夹具浏览器流程、1 个实际客户端报告浏览器流程。临时目录在 F 盘本轮日志下。
- 选文件、真实 Canvas 像素、标记前后导航、未知/成熟零、恶意内容、坏行、大小边界、清空/重复选择通过；1360、760、390 宽度检查，宽屏和窄屏截图已查看；控制台错误和远程请求均为 0。
- 实际样本来自 N2 的两个 Windows Client.exe 连接 Linux 的隔离测试：2 文件、2 会话、42 条采样，拒绝/警告为 0。RTT 有效样本少于 10，摘要中位数正确显示未知；可靠丢包尚未成熟也显示未知。样本包含初始化阶段，不把摘要最低 FPS 当作房间内帧率结论。
- 证据位于主线 `logs/d1-review-20261002/`：parser、browser（原候选）、browser-final（最终结果及截图）；实际 JSONL 仍在 N2 隔离数据目录，不进 Git。

未验证：真人双击交互、屏幕阅读器、其它浏览器/系统，以及朋友公网日志。此项只增加离线查看器，未改游戏构建身份，也未为此重跑 Godot、联机或重新导出包。

## 云端候选原始记录（2026-10-02）

结论：可供主线复核的离线查看器候选；解析/边界定向测试 8/8 通过。真实 `file://` 浏览器验收未完成，不能称为 D1 全项验收通过。

## 交付范围

基准 `0e33fa615957f4a29174fe4800d7d05862741746`，独立分支 `codex/network-report-viewer`，以补丁交付，没有候选提交、推送或主线合并。

只增加 `NETWORK_REPORT.html`、`docs/assets/network-report/`、`tests/test_network_report*.cjs` 和 `tests/fixtures/network-report/`。未改 README、STATUS、ROADMAP、docs/17、SDK、客户端、服务器和生成器；未启动游戏/服务，未修改全局 Git 身份/配置。

功能：多个文件并排摘要、各会话独立时间轴、RTT 与快照 age/interval 图、FPS / 最慢帧 / 可靠发送丢包估计、卡顿标记前后 15 秒、折叠的逐条观测与坏行位置。无上传或外部运行依赖。详细口径、使用步骤与浏览器待验项目见本目录 README.md。

负责人亲自实现；一次只读审查确认 N1 成熟度和边界，并发现清空后隐藏文字/图表无障碍标签仍保留旧数据，已修复。N1 标记的 IDLE/NONE 是默认值而非实际阶段，已改为显示“未采集（卡顿标记）”；夹具同步真实默认值。窄屏上传区改为纵向，但真实布局尚待浏览器验收。

## 实际环境

- dot 云端 Linux 独立目录；不是用户 Windows 或正在运行的服务器目录
- Node v24.19.0，Git 2.52.0，已有 Chromium 154.0.8037.57（Debian GNU/Linux 13）
- 没有安装依赖或引擎，没有进行 Godot 回归
- .agents/skills 在此固定基准不存在；已按仓库 AGENTS 读取项目边界与实际源码

## 实际命令、退出码与结果

1. `git clone --no-checkout https://github.com/SchreiberChiang/godot-network-.git roomkit-d1/repo && git -C roomkit-d1/repo checkout -b codex/network-report-viewer 0e33fa615957f4a29174fe4800d7d05862741746`
   - 退出 0；固定基准检出成功。
2. `node --check docs/assets/network-report/core.js` 与 `node --check docs/assets/network-report/app.js`
   - 各退出 0；仅语法检查，不是浏览器通过。
3. `NETWORK_REPORT_EVIDENCE=/workspace/scratch/78591d623fe3/roomkit-d1/evidence node --test tests/test_network_report.cjs tests/test_network_report_browser.cjs`
   - 退出 1；核心 8 通过，浏览器 1 失败（启动阶段），0 跳过。
   - 覆盖真实 N1 字段合成夹具、未知/成熟零值、标记、非法数值、恶意未知文本、坏行位置、超大文件、超长行、UTF-8/BOM/CRLF/分块、记录/会话/问题/行数上限、取消与读取失败、禁止远程加载/危险 DOM。
4. 同命令仅运行 `tests/test_network_report_browser.cjs`，在允许的提升权限下重试一次。
   - 退出 1；浏览器仍在启动阶段失败，未进入页面测试；没有声称该重试修复环境。
5. 审查修正后 `node --test tests/test_network_report.cjs`
   - 退出 0；8/8 通过，0 失败，0 跳过。核心复跑由夹具默认值修正驱动。
6. 最终 `node --check docs/assets/network-report/core.js && node --check docs/assets/network-report/app.js && node --check tests/test_network_report_browser.cjs && git diff --check`
   - 退出 0。

## 失败摘要及未运行项

- 两次 Chromium 启动：`socket() failed: Operation not permitted (1)`，浏览器进程 SIGABRT。首次另有 crashpad database 错误；提升后仍有相同 IPC socket 权限阻断。
- 现有云端浏览器工具明确拒绝 `file://`：URL policy only allows http/https。没有切换路径绕过限制。
- 因此真实 HTML 打开、文件选择、Canvas 绘图/中文显示、标记操作、窄屏、页面控制台无错误和零远程请求均未验收；没有产生截图。已经交付真实浏览器验收脚本，不以静态解析替代。
- 没有真实朋友/生产日志样本；合成夹具严格使用固定基准的 N1 字段，恶意内容为无真实凭据的测试文本。
- Windows / Firefox / Edge / Safari 未验收；游戏联机、Godot 回归、生成器和升级回归按任务范围未运行。

## 主线取用

先在固定基准用 `git apply --check network-report-viewer.patch` 只读检查，再按主线自己的复核流程决定是否应用。本候选不替主线合并。
解压 ZIP 后可直接双击根目录 `NETWORK_REPORT.html`，但仍需完成上面的真实浏览器门槛。Windows 指定目录交付由上级任务单独核实，云端 ZIP 不等于已保存到 F 盘。
