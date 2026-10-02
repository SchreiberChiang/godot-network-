# D1 离线网络报告

## 三步查看

1. 双击项目根目录 `NETWORK_REPORT.html`；复制页面时保留它与 `docs/assets/network-report/` 的相对位置。
2. 点击“选择 JSONL 文件”，选择客户端 `client-data/reports/` 中的一至八个报告。页面不自动扫描目录，也不选择、修改或上传账号 / 设置 / 其它文件。
3. 看并排摘要，在“会话时间线”选文件与会话；点“下个卡顿标记”或标记下拉框，查看前后 15 秒。点“查看全程”返回，逐条记录默认折叠。重新选择会替换当前报告，“清空”中止读取并移除数据。

使用者不需要 Node、Godot、服务器、安装或联网；测试脚本才使用已有 Node / Playwright / Chromium。
主线已补完 Windows Edge 143 的真实 `file://` 自动验收并查看截图，含合成边界和两个隔离真实客户端的报告。云端首次浏览器失败仍保留在 [验收记录](VALIDATION.md)。真人操作、其它浏览器和朋友公网日志尚未验收。

## 实际 N1 字段依据

固定基准：`0e33fa615957f4a29174fe4800d7d05862741746`。

- `examples/framework/client_data.gd`：`_record` 的 UTC、monotonic_ms、32 位十六进制 session_id、build、kind、phase、error 与 `NUMERIC_FIELDS` 允许列表。日志未知负值被省略；卡顿是 `kind=mark`，没有自由文本标签或指标。
- `sdk/roomkit/client/room_client.gd`：当前真实路径；RTT 是 ENet 平滑往返观测，`rtt_sample_count>0` 才可用；滚动分位数至少 10 条；`loss_sample_count>0` 才有成熟可靠发送丢包估计。`loss_state` 没有写入 N1 日志，查看器不依赖它。`transport_sample_count>0` 才视为已知收发速率。
- `examples/framework/client.gd`：实际写入 `fps`、`frame_max_ms`、`snapshot_interval_ms`、`snapshot_age_ms`。此基准不向日志传入 snapshot_samples 或快照分位数，D1 不将其作为快照 age/interval 的可用前提。
- 本目录仅消费已有字段；没有改 SDK、客户端、日志生成或保留规则。

## 口径与限制

- 文件摘要独立，跨文件不合并会话，不对齐不同电脑 UTC；同文件多个会话也各用自己的单调时钟。会话跨度不是在线时长，各跨度相加也不是跨机器持续时间。
- “RTT 观测中位数”对该文件接受的已知秒级 RTT 观测计算，至少 10 条；不是包级 RTT 分位数，也不是日志中滚动 rtt_p50 的平均。
- 未知、未成熟和字段缺失都显示“未知”，有效零值保留。图表在缺测、阶段变化或间隔超过 2.5 秒处断线，不插值补零。纵轴各自缩放。
- “可靠发送丢包估计”不是所有 UDP 丢包率，不是下行快照丢失率；卡顿标记没有因果证明。不会判断 Wi-Fi、运营商、服务器或 GPU 是根因。
- 最慢帧是最近 1 秒最大帧间隔。快照 age / interval 是采样时观测，不能还原每次短卡顿。无逐包时序、导出、自动根因或多机时钟校准。
- 仅投影允许字段；陌生键、陌生错误文本、原始坏行永不回显。所有用户数据用 textContent / 文本节点输出，不作为 HTML、脚本或 URL。无 CDN、远程字体、fetch、eval、后端或存储。
- 上限：每批 8 个文件，每个 8 MiB；64 KiB 字节行缓冲，64 KiB 分块读取；每文件最多 10000 条记录、16 会话、100000 行、前 100 个问题位置。总问题数仍保留。拒绝超大文件；超长行拒绝整行并继续；记录/行数上限停止且标明不完整，不静默采样。
- 数值必须是有限非负数且不超过 10^12；计数必须整数，丢包百分比不超过 100。非法数值按未知并标记行号；同会话时钟倒退拒绝该行。读取失败也明确显示部分数据。未知格式不能冒充可用记录。
- 合成夹具不含真人数据；另外读取的真实报告来自 N2 隔离联机自动测试。本查看器未采集新的游戏或公网数据，不能据此评价朋友的 Wi-Fi、运营商或实际帧率。

## 定向验证

已有 Node 环境运行：

```
node --test tests/test_network_report.cjs
```

真正的浏览器验收脚本（需要开发机上已经存在 Playwright 和 Chromium，不自动安装）：

```
CHROMIUM_EXECUTABLE=/path/to/chromium node --test tests/test_network_report_browser.cjs
```

Windows 可先在 PowerShell 设置 `$env:CHROMIUM_EXECUTABLE` 为现有 Chromium/Chrome/Edge 可执行文件的完整路径，再执行同一 Node 测试。脚本在临时浏览器中真正打开 `file://`、通过文件选择器加载夹具，检查图表像素、两次标记导航、未知/恶意数据、超大输入、清空/重复选择、窄屏与控制台/远程请求。缺工具会明确跳过，不计为通过；浏览器启动失败会失败。

可选 `NETWORK_REPORT_EVIDENCE` 指定截图目录，写总览、标记与 760/390 宽度截图；否则不生成截图。可选 `NETWORK_REPORT_SAMPLE_DIR` 指向一份已确认脱敏的隔离客户端 `reports/`，额外验实际 JSONL 并生成 real-client.png；不扫描整个 client-data，不复制报告进入仓库。

## 人工浏览器检查清单（未代替实测）

- 在断网环境双击 HTML，选 normal/unknown/malformed 三个夹具，三个文件摘要同时可见
- normal 的 RTT 峰值 240 ms、快照未更新峰值 700 ms、FPS 最低 32、最慢帧 145 ms；两个标记可以来回导航
- unknown 的 RTT 与丢包估计为未知；第二会话独立归零
- malformed 显示拒绝行 2/3/5，数值警告行 4；不显示恶意文本或陌生 secret 字段
- 超大文件和超长行解释清楚，重新选择 / 清空正常；控制台无错误，没有远程请求
