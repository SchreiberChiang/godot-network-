# 独立管理后台与 HTTP 接口

## 当前任务：后台改版收尾（2026-09-29，交 Claude）

收尾状态：用户已确认建房等管理操作、退出和重新登录正常；Codex 抽查房间截图和隐藏样式并重跑四项页面测试 44/0。下列任务保留作为交付范围记录，下一项为 docs/17 的基础音效任务；深色/窄屏截图与独立包仍未补验收。

预览和正式接入已完成实现；下面的预览任务保留为历史范围。当前先收尾，不继续扩展页面。工作目录 `F:\文档\GodotGame\Net\RoomKit`，分支 `main`，基准 `bf21fe0`，接手重新核实。工作区包含 Claude 的 UI/夹具/文档和 Codex 的登录显示修复；保留全部改动，同目录由 Claude 单方写入。

1. 先读 AGENTS、STATUS 和本节，复核 `host/admin.html` 的 `[hidden]{display:none!important}` 及 `tests/test_admin_auth_errors.cjs` 的新增检查。Codex 已在隔离真实后台复现旧页面登录成功却仍显示登录框，并验证修复后登录、退出正常；四项 Node 测试 44/0。不要把用户“继续安排”记为修复后真人验收通过。
2. 用 `tests/run_admin_ui_fixture.ps1` 的隔离目录与端口补齐真实浏览器验收：已有管理员登录、错误密码、退出再登录、刷新后会话恢复；七页切换时只显示当前页；在线不显示离线横幅，停隔离服务后禁用写操作。检查隐藏确认字段不会阻止普通登录。保存登录后总览、房间、玩家及离线状态截图；不能仅凭 DOM 双桩测试宣称视觉通过。
3. 不重复已经有有效证据的全量游戏测试。无新增功能改动时，重跑四项页面 Node 测试及必要的受影响检查；若修复了新问题，按影响补测。真实服务、`data/framework/`、客户端版本与发布候选保持不动；不打包、不发布、不提交推送。
4. 整理 README/STATUS/docs/17/docs/19 中当前入口及状态，清除“仅安排预览、尚未制作”等过时的当前指示；历史测试证据保留。报告实际差异、命令、结果、截图、失败与未运行项，交 Codex 复核后再进入音效阶段。

后续基础音效范围已定：开枪、命中、死亡、购买、按钮反馈，音量和静音可保存；只在游戏/客户端展示层实现，素材需可分发并记录来源。不在本次后台收尾中同时开工。

### 收尾结果（Claude，2026-09-29，未提交，待 Codex 复核）

- **登录修复复核**：`[hidden]{display:none!important}` 保留，没有改动。`tests/test_admin_auth_errors.cjs` 新增的是结构检查（13 项全过），实际显示效果由下面的浏览器验收确认。
- **真实浏览器验收 28/0**：
  - 环境：`tests/run_admin_ui_fixture.ps1` 启动隔离的源码版 Operator，用独立 Edge 无头实例（一次性配置目录，不碰用户浏览器配置）通过 CDP 操作，窗口 1366×900。
  - 覆盖：
    - 首次设置后退出，用已有管理员重新登录；
    - 错误密码提示“用户名、密码或登录凭据无效。”，仍停在登录页；
    - 已有管理员时确认密码框隐藏且不是必填，空着时表单校验照样通过，普通登录不受影响；
    - 刷新页面后不用重新登录，会话恢复；
    - 七个页面逐个切换，每次只有当前页可见；
    - 在线时不显示离线横幅；
    - 启动服务器到“运行中”，建房到“已就绪”，生成邀请码后用它注册测试玩家，顶部搜索回车打开该玩家；
    - 正常停服（60 秒倒计时）后停止 Operator，出现离线横幅，10 个写操作按钮全部禁用。
  - 证据：`logs/admin-ui-df17c850fa8540fab4f8c9155df216bc/browser/`，含 `results.json`、驱动脚本 `admin_browser_check.cjs` 和截图：登录错误、总览运行中、房间、玩家详情、离线。Operator 停止时 stderr 为 0 条 ERROR/WARNING。
- **截图发现并修正**：1366 宽下，房间表的操作列按钮文字被挤成竖排（“成/员”“关/闭”）。改为按钮文字不换行、按钮组可以折成两行，只改了 CSS 一处（`td .actions`）。修正后重跑，28 项全过，截图正常。上一轮的 `logs/admin-ui-c85a322bebef4b219d31e3d564a90eda/` 保留了修正前的截图。
  - 第一轮有 3 项失败，都是脚本问题，页面本身没有问题：一是邀请码选中了邀请码页卡片里的空输入框；二是正常停服有 60 秒倒计时，脚本没等够；第三项是前两项的连带结果。
- **检查**：
  - 四项 Node 测试 44/0（9 + 12 + 13 + 10）；
  - 内联脚本可以解析；101 个 id 引用没有缺失，也没有重复；
  - `git diff --check` 通过。
  - 只改了 CSS，`run_admin_http.gd` 没有重跑，上轮是 143/0。
- **未验收**：
  - 用户本人在 Chrome 或 Edge 里的操作，包括 Codex 登录修复之后的真人复测；
  - 深色模式和 760 宽的截图（上一轮 760 宽只做过 DOM 溢出检查）；
  - 独立包重新导出。
## 2026-09-29 UI 改版任务：先预览，再接入

用户已同意暂缓 GitHub Release 后继续安排开发。发布/下载验收与后台 UI 解耦；本小阶段由 Claude 做预览，Codex 复核，用户确认布局后再接入真实后台。目标是清爽现代、信息清楚、减少常用操作步骤，Windows 桌面浏览器优先；继续保持通用游戏管理，不把枪械或射击专属规则写进通用后台。

### Claude 可直接执行的预览任务

- 工作目录 `F:\文档\GodotGame\Net\RoomKit`，预期 `main`、基准 `bf21fe0`；接手重新核实。已有未提交的 STATUS/docs/17 发布准备记录，以及 Codex 本轮 docs/19 任务与导航更新需保留。同目录只由 Claude 写入，Codex 等交付后复核。
- 先读 AGENTS、README、STATUS、本页和 `host/admin.html`。只读核实现有 API 与页面：总览、房间、玩家与资产、邀请码、备份恢复、日志审计、配置。列出“启动并建房、生成邀请码、找到玩家并发测试金币”的当前步骤及建议步骤；不以取消必要确认减少步骤。
- 做一个方案，不堆多个风格供用户反复选择。新增根目录 `ADMIN_PREVIEW.html`，双击可离线使用；资源如有需要放 `docs/assets/admin-preview/`，不用 CDN、构建服务或新依赖。明确标注“界面预览，全部为演示数据”，不连接真实 API、不读取真实账号或配置、不存放 token。
- 重点完成三个页面：总览（服务器状态、主要启停动作、房间/玩家摘要、异常提示）；房间（列表、状态筛选、创建与详情）；玩家（搜索、详情、按游戏分开的资产和管理操作）。邀请码等其余页面可做轻量导航草图，明确哪些未实现；不能伪装成完整功能。
- 让常用操作容易发现，危险操作单独分组；区分管理服务与游戏宿主、启动中与就绪、请求已接受与已完成。演示加载、空数据、离线/旧快照、操作失败和成功状态；CPU 等缺数据时显示不可用，不造实时指标。对话框支持键盘关闭/焦点返回，桌面窄窗口不遮挡内容。
- 允许修改范围：预览 HTML/专用资源、本页、STATUS（简短进度）、必要的 README 导航。不能修改 `host/admin.html`、服务端、协议、启动器或游戏；不操作真实服务/数据，不发布 Release、不删除文件、不提交推送。需要额外素材时优先已有图标/CSS，不花费费用。
- 验收：真实浏览器检查页面切换、搜索筛选、主要对话框、上述状态切换、键盘与窄窗口；截图检查文字可读和布局。静态检查与浏览器实测分开记录；未完成的浏览器操作明确写未验收。无需跑 Godot 回归。
- 交付一个预览入口、最多三条用户查看步骤，以及当前/建议操作步骤对照。将结论更新本节及 STATUS，不新增长篇逐轮日志。不要因预览确认就自行进入功能接入。

### 预览交付（Claude，2026-09-29，未提交，待 Codex 复核）

入口：根目录 **`ADMIN_PREVIEW.html`**，双击打开。单文件，CSS 和 JS 全部内联，没有外部资源，不发网络请求，不用 localStorage 或 sessionStorage，所以没有新增 `docs/assets/admin-preview/`。顶部固定标注“界面预览 · 全部为演示数据”；按钮只在页面内模拟，演示数据都是虚构的。没有修改 `host/admin.html`、服务端、协议、启动器或游戏。

**布局方案（只做一套）**
- 左侧导航分“日常”（总览、房间、玩家与资产）和“其他（草图）”；邀请码、备份恢复、日志审计、配置四页都标“草图 · 本预览未实现”，只列出计划保留的内容。
- 顶部是全局玩家搜索（`/` 聚焦，方向键选择，回车打开）和管理服务的连接状态。
- 总览把“管理服务”和“游戏服务器”分成两块：前者常驻，停止游戏服务器也不会关闭它；后者显示“已停止 → 启动中 → 运行中”进度。常用操作集中在一行；停服、立即停止、维护模式收进可折叠的“危险操作”。异常提示示例：自动备份超时。
- 房间页：搜索，状态筛选（全部 / 已就绪 / 启动中 / 异常），列表加详情。启动中的房间有提示“绑定端口后才就绪”；关闭、重新创建放在“危险操作”里。房间规则的文字来自演示数据。
- 玩家页：列表加详情，资产按游戏分页签显示，并标出资产空间；金币调整有 +100 / +500 / +1000 快捷值，原因必填；踢下线、停用、永久删除放在“危险操作”里（删除沿用现有多步确认，预览不模拟）。
- 状态演示：加载中（骨架屏）、空数据（引导下一步）、离线（旧快照，写明多久之前，操作全部禁用，可“立即重试”）、下次操作失败（错误留在对话框里，数据不变）。提示分两段：“请求已接受”和“已完成”。CPU 和内存显示“不可用”，不编造实时指标。
- 支持深色和浅色（跟随系统，也可手动切换）；760 像素宽时改为顶部导航。

**常用操作步骤对照（按现有 `host/admin.html` 代码统计，建议值以预览为准）**

| 操作 | 现在 | 预览建议 | 保留的确认 |
|---|---|---|---|
| 启动并建房 | 总览点“启动服务器”→ 等宿主运行、按钮才可用 → 点“创建房间”→ 选游戏、模式、地图、人数 → 提交 → 切到房间页看是否就绪（约 5 次操作 + 1 次换页） | 点“启动游戏服务器”（进度就地显示）→ 点“创建房间”（按上次设置预填）→ 确认；就绪提示直接弹出，总览列表同步更新（3 次操作，不用换页） | 创建前仍然确认设置 |
| 生成邀请码 | 点“生成邀请码”→ 填次数、有效期、原因 → 提交 → 自动跳到邀请码页 → 复制（4 步 + 换页） | 点“生成邀请码”→ 填原因 → 生成，邀请码和“复制”按钮直接显示在同一个对话框里（3 步，不用换页） | 原因仍然必填 |
| 找到玩家并发测试金币 | 进“玩家与资产”→ 搜索 → 点玩家 → 选游戏 → 点“调整钱包”→ 填金币、经验、原因 → 提交（约 6 步） | 在顶部搜索框输入并回车 → 选游戏页签（默认第一个游戏）→ 点“调整金币”→ 点 +100 / +500 / +1000 并填原因 → 确认（4 步，在任何页面都能开始） | 原因必填，写入审计；金币和经验分开调整 |

**检查结果**

- 静态检查：内联脚本 `node --check` 通过；页面中没有 `http(s)://`、`fetch`、`XMLHttpRequest`、`WebSocket`、`localStorage` 或 `sessionStorage`。
- 真实浏览器（Claude 内置浏览器，按 `file://` 打开）：
  - 交互脚本在全新页面上最终 31 项全部通过，覆盖七个页面切换、草图标注、房间筛选和搜索（输入时焦点保持）、创建房间（请求已接受 → 启动中 → 已就绪 → 已完成）、全局搜索回车打开玩家、原因必填、快捷金额、按游戏分开的资产、失败演示、离线、加载、空数据、CPU 不可用、立即停止与重新启动两段提示、邀请码在同一对话框复制，以及运行期间没有加载任何资源。
  - 真实键盘：回车打开对话框后焦点落在第一个输入框，Esc 关闭后焦点回到原按钮。
  - 760 像素宽：三个主页面没有横向溢出，对话框完整显示在视口内。
  - 截图检查了浅色总览、窄窗口玩家页、调整金币对话框和深色房间页，文字清楚。
  - 另外扫描了所有页面和演示状态下的每个房间、每个玩家的每个游戏页签，没有残留的 null 或 undefined。
- 测试中发现并修正的问题：
  - 原生表单校验挡住了中文提示，改为 `novalidate`，由页面给出中文提示；
  - 后台状态刷新重绘页面时焦点丢失，改为按 id 或“标签 + 文字”恢复焦点；
  - 对话框关闭时焦点没有回到原按钮（`close` 事件在面板隐藏时被延迟），改为关闭时同步恢复；
  - 房间详情出现字面的“null”；
  - 快捷金额按钮间距过窄。
- 中途有几项测试失败，原因都是测试脚本本身：选择器匹配到别的卡片、测试状态延续、浏览器面板没有真正重新加载。都在新页面上重跑后通过。
- 未验收：用户电脑上 Chrome 或 Edge 的真实双击打开（内置浏览器用的是 `file://` 快照，页面全部内联，预期效果相同）；屏幕阅读器；1366 像素宽的笔记本屏幕（只测了 760 像素和约 1080 像素）。

### 预览确认后的接入门槛

保留既有 HTTP/Schema、权限、幂等、资产空间隔离、删除/恢复确认与超时处理，在 `host/admin.html` 接入布局。修正断线提示中的旧启动入口；运行受影响页面测试和 admin_http 回归，在隔离后台实测关键操作，用户只验收启动/建房、查玩家/资产、失败提示三条路径。实际实施范围待预览确认后由 Codex 固定。

### 真实后台接入（Claude，2026-09-29，未提交，待 Codex 复核）

用户确认预览布局后，已接入 `host/admin.html`，调用的都是现有接口。演示数据和模拟状态控件都没有带进来，服务端、协议和 Schema 没有改动。`ADMIN_PREVIEW.html` 保留为布局参考，不代表正式后台的当前状态。

**实施方式**：重写页面的标记和样式，保留原有的全部元素 id（101 个引用，0 个缺失）；脚本只做定向修改，原有函数和写法不变（Node 测试按行首前缀抽取这些函数），`api()`、权限处理、资产操作编号（`operation_id`，同一个对话框重试时复用）、必填原因和各项危险确认都原样保留。对话框继续使用浏览器原生校验，保证必填、数值范围和恢复备份时必须输入“恢复”。

**改动**：
- 布局：左侧导航分为“日常”和“管理”两组；顶部是全局玩家搜索和连接状态；总览把“管理服务”和“游戏服务器”分开显示，游戏服务器带“已停止 → 正在启动 → 运行中”进度；常用操作集中在一行；停服、重启、维护、立即停止收进可折叠的“危险操作”。
- 状态提示：提交时先显示“请求已接受”，之后根据真实状态变化提示“已完成”（宿主运行、宿主停止、房间就绪），出错时给出错误提示（宿主 FAILED、房间 FAILED）。
- 离线：显示最后一次收到状态的时间（旧快照），所有操作按钮禁用（新增邀请码、备份四个按钮），可“立即重试”；页面隐藏期间不判定离线。断线和登录页提示改为当前入口 `StartManagement.cmd`（独立包为 `StartPanel.cmd`），修正了旧入口。
- 房间：用筛选按钮代替下拉框，新增“启动中”（ALLOCATING / STARTING）；建房沿用上次的游戏、模式、地图和人数，提交后不再强制跳到房间页。
- 玩家：顶部搜索调用 `account.list`（最多 6 条），支持方向键和回车；结果未返回时按回车，结果一到就打开第一条。资产改为按游戏分页签，并注明资产空间；调整金币有 +100 / +500 / +1000 快捷值；踢下线、停用、删除测试账号收进“危险操作”（删除流程和确认完全不变）；“恢复账号”只在账号停用时显示。
- 邀请码：生成后直接在同一个对话框里显示并可复制，不再跳页；邀请码页仍保留最近生成的码和完整记录。
- 焦点：状态轮询重绘和对话框提交后，按 id 或“所在页面 + 标签 + 文字”恢复焦点。
- 新增错误说明：`ASSET_LIMIT_EXCEEDED` 显示为中文说明，不再显示错误码。

**隔离实测**：新增 `tests/run_admin_ui_fixture.ps1`（`start` / `player` / `stop`），用源码启动一个真实 Operator，使用独立的数据目录、端口、游戏索引和公开配置目录，不预建管理员；`player` 通过导出客户端用邀请码注册测试玩家，不改客户端代码（客户端代码参与 `build_id` 摘要，改动会破坏已准备的分发副本）。

在 Claude 内置浏览器里走了首次设置和真实操作（证据在 `logs/admin-ui-823118891a854d9593cda7e2888b460f/` 等目录；四轮夹具停止时 stderr 均为 0 条 ERROR/WARNING）：
- 七个页面切换后都只显示当前页，各页数据正常加载；
- 宿主停止时不能建房；启动服务器后进度走到“运行中”并提示“已完成”；
- 在房间页建房，就绪后提示“已完成”；筛选和搜索正常；第二次打开时按上次设置预填；
- 邀请码在同一个对话框里显示，焦点落在“复制”，关闭后回到原按钮；原因为空时原生校验拦截；
- 顶部搜索在结果返回前按回车也能打开玩家；资产页签、资产空间、收起的危险操作都正确；
- 加 500 金币生效，提示“已完成”，焦点回到“调整金币”；扣除 100000 被拒绝，对话框里显示中文说明，余额不变；
- 第二个游戏的资产与第一个分开（0 金币，空间 turns）；每次打开对话框生成新的操作编号；
- 立即停止使用红色确认按钮、原因必填，先提示“请求已接受”，再提示“已完成：游戏服务器已停止”，管理服务仍在线；
- 页面打开时停止 Operator：出现离线横幅和旧快照时间，11 个操作按钮全部禁用，对话框和搜索都说明离线；
- 1280 和 760 像素宽下各页面没有横向溢出，也没有残留的 null 或 undefined；760 像素时对话框在视口内。

**回归**：4 个 Node 测试 43/0（账号删除 9、资产空间 12、认证错误 12、房间规则 10），`tests/run_admin_http.gd` 143/0、退出 0，内联脚本 `node --check` 通过。

**测试中发现并修正**：
- 页面切换的选择器 `main>section` 在新结构下一个都匹配不上，导致所有页面同时显示（只在总览页操作时发现不了），已改为 `.content>section`；
- 结果未返回时按回车，搜索没有反应；
- 离线时邀请码和备份按钮没有禁用；
- 资产超限时显示原始错误码。
- 另外撤回了为测试临时加进 `client.gd` 的分支，原因见上面“隔离实测”。

**测试环境造成、不属于缺陷的情况**：
- 浏览器面板隐藏时 `document.hidden` 为真，页面按设计暂停轮询，测试脚本把它模拟为可见；
- 脚本在登录表单还隐藏时提前提交，走成了“登录”而不是“首次设置”，真人无法这样操作；
- 隔离环境里还没有 operator 日志文件，日志页按设计提示“尚未生成”；
- 审计页的每个操作显示两条，分别来自管理服务和存储层（后者带前后值），这是原有的合并展示。

**未验收**：
- 后台各页的截图检查（本轮浏览器面板截图不稳定，只拿到深色登录页；已在上面的“收尾结果”中补齐）；
- 用户在 Chrome 或 Edge 里的真人操作；
- 房间“启动中”筛选只验证到了空结果（实测时房间就绪太快）；
- 独立 Windows 包：包里的 `admin.html` 需重新导出才会更新。

此页记录 `codex/shooter-framework` 的中文管理前端及它与管理服务的接口。实际宿主、账号、资产和导出验收以 `STATUS.md` 为准。网页控制来自独立管理进程，游戏服务器停止不应关闭本页面的 HTTP 服务。

## 使用流程

源码工程启动 `StartManagement.cmd`；独立 Windows 发布包启动 `StartPanel.cmd`，在浏览器打开本机管理页。首次进入设置独立管理员用户名和密码；以后使用该管理员账号登录。玩家账号不能登录此后台。会话仅保存在当前标签页的 `sessionStorage`，不出现在 URL 中；使用“退出登录”撤销会话。

1. 在服务器总览点“启动游戏服务器”，等进度走到“运行中”，再点“＋ 创建房间”（总览和房间页都有）。页面区分宿主启动、房间进程启动、房间就绪和回收，提交后先提示“请求已接受”，完成后再提示“已完成”。
2. 生成有注册次数与有效期的邀请码，邀请码会直接显示在对话框里供复制。注册发生在游戏客户端，后台显示实际创建的账号。
3. 在顶部搜索框（按 `/` 聚焦）或“玩家与资产”中查找账号，按游戏页签查看金币、经验、物品所有权和默认配置；修改必须填写原因。操作只有收到管理服务确认才显示完成。
4. 正常停服提前 60 秒通知玩家并拒绝新入房；立即停止与恢复备份另有明确确认。停服期间仍能访问后台。
5. 修改监听、连接地址、容量和资产空间时必须先停服。当前配置接受 IP 字面量，房间上限 1–16；资产空间可选该游戏的独立空间或 `shared`。不要用 `0.0.0.0` 作为玩家连接地址；玩家使用管理服务发布的固定证书。页面不自动设置防火墙或生成可信公网证书。

状态每 2 秒读取；8 秒未取得新状态就标为离线，保留数据明确作为旧快照。不可采集的指标显示不可用。写请求不自动重发；响应超时时应先刷新状态和审计确认结果。资产对话框在同次重试中保留原 `operation_id`。

## 传输接口与约束

`host/admin_http.gd` 是 `RefCounted`，接口为：

```gdscript
start(port: int = 28291) -> int
poll() -> void
close() -> void
signal request_received(request_id: String, request: Dictionary)
respond(request_id: String, result: Dictionary, http_status: int = 200) -> void
```

只绑定 `127.0.0.1`。`GET /` 或 `/index.html` 返回不依赖外部资源的网页；`POST /api` 接收 `application/json`，请求信封的唯一 Schema 是 `schemas/admin_request.schema.json`：

```json
{"action":"room.create","payload":{"game_id":"shooter","mode":"ffa","map":"depot","capacity":4}}
```

认证凭据由 `Authorization: Bearer <token>` 头提供。传输层发给服务的请求额外包含 `token`、实际连接的 `remote_ip`；客户端 JSON 不能覆盖它们。生成的 `request_id` 只用于关联此条 HTTP 响应，不等于资产事务的幂等编号。管理服务在副作用前验证管理员身份和每个操作的载荷，匿名只允许检查初始化、首次设置与登录。

成功响应统一为 `{"ok":true,"payload":{...}}`，失败为 `{"ok":false,"code":"ERROR_CODE"}`。异步接受启动/关闭请求不代表进程已就绪或退出；最终以 `status` 实际状态为准。传输层和管理服务均通过同一份 Schema 对 36 个 action 的载荷做严格校验：必填字段、类型、整数界限、未知字段、日志类别和备份编号。账号和资产标量约束通过 `$ref` 引用其原始 Schema，不重复定义另一套验证规则。

边界：16 条连接，头部 8 KiB，正文 16 KiB，响应 2 MiB；读请求 5 秒、等待业务结果 60 秒、写响应 10 秒。每轮写入最多 64 KiB，并保留部分写入偏移。严格检查 `Host` 和可选 `Origin`，不启用 CORS，拒绝重复头、分块请求、管线请求、重复 JSON 键（含等价转义）、非有限数和任意路径读取。身份校验、限速及业务排队属于管理服务。

## 前端调用与服务返回

下列载荷字段均位于请求 `payload` 内；返回字段位于成功响应的 `payload`。`reason` 为管理员填写的非空单行原因，最长 256 字符；单次金币或经验调整限定 ±1,000,000。时间戳使用 Unix 秒；资源大小以字节计。

| 操作 | 请求字段 | 返回字段 / 行为 |
|---|---|---|
| `setup.status` | 无 | `initialized: bool` |
| `setup.create`、`admin.login` | `username, password` | `token, username` |
| `admin.logout` | 无 | 撤销会话 |
| `status` | 无 | `host, rooms, players, metrics, games`，见下文 |
| `server.start` | 无 | 接受启动，随后轮询状态 |
| `server.stop`、`server.restart` | `immediate: bool, restart: bool, reason` | 正常倒计时或立即停止；重启等待资源回收 |
| `maintenance.set` | `enabled: bool, message` | 设置维护公告和禁止新接入 |
| `room.create` | `game_id, mode, map, capacity` | 新 `room_id`；模式/地图来自注册清单 |
| `room.stop`、`room.recreate` | `room_id, reason` | 关闭或按原选项创建新房间 |
| `room.joinable` | `room_id, joinable: bool, reason` | 不驱逐现有玩家 |
| `player.kick` | `user_id, reason` | 断开当前连接 |
| `account.list` | `query, offset, limit: 50` | `accounts: [], total` |
| `account.get` | `user_id` | `account` |
| `account.rename` | `user_id, display_name, reason` | 保存昵称 |
| `account.reset_password` | `user_id, password, reason` | 重置并撤销旧会话 |
| `account.ban` | `user_id, hours, reason` | `hours: 0` 表示永久；撤销会话 |
| `account.unban` | `user_id, reason` | 解除封禁 |
| `invite.create` | `uses, expires_hours, reason` | `invite_code`，仅创建时展示原码；`code` 是业务状态码，不能当邀请码 |
| `invite.list` | 无 | `invites: [{invite_id, used, max_uses, expires, revoked}]` |
| `invite.revoke` | `invite_id, reason` | 禁止继续用该码注册 |
| `asset.read` | `user_id, game_id` | 下述资产投影 |
| `asset.adjust` | `user_id, game_id, coins_delta, xp_delta, reason, operation_id` | 原子增减永久钱包 |
| `asset.grant`、`asset.revoke` | `user_id, game_id, item_id, reason, operation_id` | 修改非堆叠所有权 |
| `asset.select` | `user_id, game_id, slot, item_id, reason, operation_id` | 保存此游戏默认配置 |
| `backup.list` | 无 | `backups: [{backup_id, kind, automatic, created_at, size_bytes}]`；`size_bytes` 为已验证清单内文件的字节数总和，不含清单本身 |
| `backup.create` | `reason` | 完成备份 |
| `backup.restore` | `backup_id, reason` | 停服恢复并撤销旧会话 |
| `logs.list` | 无 | `logs: [{label}]`，仅允许标签 |
| `logs.read` | `label` | `text`，最多最后 60000 字节；空文件成功返回空字符串，未生成返回 `LOG_NOT_FOUND`，不可读返回 `LOG_READ_FAILED` |
| `audit.list` | `limit: 100` | `entries`，兼容账号行 `created_at, actor_id, action, target_id, reason, result` 及管理行 `time, code`；资产/账号行可提供 `before, after` 供折叠查看 |
| `config.get` | 无 | `config`，见下文 |
| `config.set` | `config, reason` | 仅在服务器停止后保存 |

`status.host`：`state` 使用 `STOPPED / STARTING / RUNNING / DRAINING / STOPPING / FAILED`；另有 `pid, uptime`（秒）、`maintenance, maintenance_message, countdown`（秒）、`error`。游戏停止时管理服务仍返回 `STOPPED`；不能将整个 HTTP 连接消失作为正常停服。

`status.rooms` 为房间列表，包含 `room_id, game_id, state, capacity, connected, occupied, pid, port, heartbeats, heartbeat_age_ms, joinable, cleaned, code, metrics.working_set_bytes`。`status.players` 包含 `user_id, display_name, game_id, room_id, state`。列表不包含票据、控制凭据、密码派生值或私有路径。

`status.metrics` 由本机采集助手返回 `system_cpu_percent, system_memory_used_bytes, system_memory_total_bytes, data_disk_free_bytes, data_disk_total_bytes`。网页对应标注“整机 CPU”和“整机已用内存”，不把这些值冒充宿主进程占用；每间房的进程内存另在房间列表展示。缺项使用 `null`、负值或省略，不能伪造为 0。`status.games` 为 `[{game_id, name, modes:{模式名:{maps:[地图名],min_players,max_players}}}]`。前端据此建立创建表单，不内置枪械、地图或游戏模式。

指标响应附带 `available` 与 `sampled_at`（Unix秒）。采集失败立即清空旧测量值；采样超过15秒的数值在网页显示为不可用，避免把旧数据当成当前状态。“在线玩家”计入所有已认证连接，包括仍在大厅的玩家。`audit.list` 的账号或资产任一查询失败时返回 `STORAGE_UNAVAILABLE`，不把缺少一部分流水的列表包装成完整成功。

`account` 行包含 `user_id, username, display_name, created_at` 和封禁投影 `banned`/`banned_until`。不得把完整数据库行（含密码盐、密码摘要、会话令牌）透传给浏览器。

审计的“查看变更”展开服务返回的 `before / after`，用于核对永久资产购买、对局奖励和管理操作。详情仅通过 `textContent` 渲染 JSON；没有变更字段时显示横线。服务必须先脱敏，网页另遮盖名称含 password/token/secret/salt/credential 的字段，避免在审计界面展示秘密。

`asset.read` 支持现有通用资产格式 `state:{revision,credits,experience,owned,profiles}`，另给 `space_id, level, catalog:{items:{物品ID:{name,price}}}, slots:{槽名:{allowed:[物品ID],default}}`。前端只显示当前游戏配置，按服务实际返回的目录渲染枪械或非射击物品。等级由服务给出，页面不自创等级公式。

`config` 可编辑部分为 `lobby_bind, advertised_host, lobby_port, max_rooms, asset_spaces:{game_id:space_id}`；当前地址为 IP 字面量，房间上限 16，射击空间选 `shooter/shared`，取石子空间选 `turns/shared`。服务额外保存游戏监听、控制与 UDP 端口等字段，页面不覆盖这些字段。输入只修改这些明确字段，不提供任意文件、脚本路径、SQL 或命令执行。

运行日志的文件映射在 Operator 启动时固定。由于 Godot 4.7.2 会从 `OS.get_cmdline_args()` 中移除 `--log-file`，受信启动器将同一绝对路径同时传给引擎 `--log-file` 和应用 `--operator-log-path`；旧启动方式未给后者时仍使用私有数据目录的 `logs/operator.log`。宿主始终使用私有数据目录的 `logs/managed-host.log`。浏览器只能选择 `operator / host` 两个标签；不能覆盖启动参数或提供文件路径。日志错误会明确显示，且不妨碍独立审计列表加载。当前工程关闭普通引擎文件日志，合法空日志不能冒充“没有进行管理操作”；业务操作另有独立审计。

请求 Schema 的白名单和字段没有变化；管理 HTTP 返回目前使用开放的 `ok / payload / code` 信封，没有单独的封闭响应 Schema 或错误码枚举。本次补齐原约定的 `size_bytes` 并区分两个日志错误码，兼容示例见 `examples/admin_observability.example.json`，未增加另一套请求契约。

这两项 UI 问题的专项验证：`tests/test_operator_logs.ps1` 实际启动 Godot，14/14、退出 0；包括活动引擎日志读取、60000 字节尾部、合法空文件、缺失文件及真实 Windows 独占句柄拒绝，证据 `logs/operator-logs-67ce5e3edfe94278b9c1c0263cd700ca/`。`tests/test_operator_maintenance.ps1` 为 35/35、退出 0；新增公开大小等于实际备份内容字节数、响应不泄露路径或私密内容两项，测试数据与结果记录在 `data/test-maintenance-9194b4030f0e4a0e806a5b0ea348a89f/`。最初直接从引擎参数读取日志路径的实测为 12/1，证明 Godot 已移除该参数；失败证据保留在 `logs/operator-logs-76211028540d4f779e70fcae390c5e9c/`，随后采用上述明确启动参数并通过测试。

## 独立 HTTP 验证

当前运输层测试使用真实 Godot 与实际本机 TCP，业务处理器是测试夹具，**不证明真实管理员密码、进程控制、SQLite 或游戏已通过**。完整操作还须运行主服务集成测试和浏览器验收。

执行入口：

```powershell
# Godot 是 Windows GUI 子系统程序，必须等待进程并检查输出标记。
$process = Start-Process -WindowStyle Hidden -PassThru `
  -FilePath 'D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' `
  -ArgumentList '--headless --path "F:\文档\GodotGame\Net\RoomKit" --script res://tests/run_admin_http.gd' `
  -RedirectStandardOutput 'logs/admin-http-console.log' `
  -RedirectStandardError 'logs/admin-http-stderr.log'
$handle = $process.Handle
if (-not $process.WaitForExit(45000)) {
  $process.Kill() # 仅终止本次创建且持有句柄的测试进程。
  $process.WaitForExit()
  throw 'HTTP 测试超时，请检查日志。'
}
$process.ExitCode
Get-Content -Encoding UTF8 'logs/admin-http-console.log'
Get-Content -Encoding UTF8 'logs/admin-http-stderr.log'
```

2026-09-22 最终专项结果为 `ADMIN_HTTP_RESULT passed=50 failed=0`，退出 0，证据 `logs/admin-http-final-console.log` 与 `logs/admin-http-final-stderr.log`。超大指数测试保留 Godot 的预期警告，但拒绝断言通过。覆盖实际拆包、UTF-8 字节长度与非法字节、头与 JSON 拒绝、非本机来源、异步响应、连接总数、响应分次发送及大小上限、停止监听和释放连接。读超时和业务等待超时只推进测试连接的计时起点，明确不是等待真实 5 秒或 60 秒的测量；分次发送不能证明本次系统调用必然发生部分写入。

失败记录保留：首次测试误用不存在的 `TCPServer.get_local_address`，Godot 脚本报错，即使引擎退出 0 也未判通过；修复测试夹具。第二次 44/1 发现重复 JSON 键未被共享语法检查器拒绝，已在 HTTP 入口加入等价键检查，未删掉失败测试。之后 47/0，增加响应大小、待处理超时和非法 UTF-8 后 50/0；HTML 脚本经 Node `--check` 语法检查通过，语法检查不替代浏览器视觉验收。

补充严格载荷契约后，实际专项为 `ADMIN_HTTP_RESULT passed=138 failed=0`、退出 0，证据 `logs/admin-http-strict-final-console.log` 与 `logs/admin-http-strict-final-stderr.log`。包含 36 个合法操作、36 个额外字段拒绝、15 个字段缺失/类型/范围/路径约束以及完整动作覆盖断言。首次严格规则使用 PCRE2 不支持的 `\\u` 字符范围，导致分包请求和运行中的邀请码创建被拒绝；已改为兼容的 `\\x` 范围并重跑通过，保留 `logs/admin-http-strict-*` 失败证据。合法操作在专项中的处理器依然是夹具，完整业务结论仍须主服务集成测试。

## 独立 Windows 构建与实测

`tools/build_framework.ps1` 复制本仓库的通用 SDK 和两个示例运行时，排除 `preview.gd / test_runner.gd`。复制后的托管取石子清单升级为 SDK 0.5；旧取石子源码清单保留原基线。可传 `-IndexPath` 将临时构建索引写到本仓库内的其他文件，避免覆盖正在运行的源码实例索引。

运行 `powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_framework_release.ps1` 导出新发布包；`-PrepareOnly` 仅准备构建，不等于导出通过。需要本机记录的 Godot 4.7.2 编辑器及匹配 Windows x86_64 release 模板。脚本生成全新目录和 ZIP，通过 `artifacts/framework-release.json` 查找位置，保留旧发布脚本和旧发布索引。包内是 6 对固定 MainLoop 的 EXE/PCK：Operator、ManagedHost、两个游戏 Server 和两个 Client。运行包不需要 Godot 编辑器、Node 或外部数据库服务器，需 Windows PowerShell 和系统 `winsqlite3.dll`。

解压到可写目录，先执行 `CheckFramework.cmd`，再用 `StartPanel.cmd` 启动管理程序。`StopFramework.cmd` 请求管理程序关闭它拥有的宿主与房间；玩家分别使用 `StartShooter.cmd / StartTurns.cmd`。启动后台或更改连接地址后执行 `PublishClients.cmd`，可将 `clients/shooter` 或 `clients/turns` 整目录发给玩家；目录中的 `StartGame.cmd` 可独立启动。只分发公开连接配置和证书，不能夹带 `data / run`、私钥或备份。

启动器检查 `data/framework/operator.json`。若对应 PID 已经不存在且 HTTP 不可访问，只清理本包该描述文件与同目录 `operator-stop.request` 后重启；PID 仍存在、查询失败或地址由其他服务响应时拒绝重复启动，不凭 PID 终止或接管进程。该边界已实际验证 3 项：不存在 PID 的两个残留标记回收、仍存活 PID 拒绝启动、畸形描述文件拒绝启动。测试使用真实本机进程查询和不可访问的本机 HTTP 端口，未把这 3 项当作完整原生服务启动通过。

可重复的发布验收入口为 `tests/test_framework_release.ps1`：

```powershell
$bundle = (Get-Content -Encoding UTF8 -Raw artifacts/framework-release.json | ConvertFrom-Json).bundle
powershell -NoProfile -ExecutionPolicy Bypass -File tests/test_framework_release.ps1 -Bundle $bundle
```

`-Bundle` 必须是当前仓库内已解压发布目录的绝对路径；也可以显式传入另一份本仓库内的解压目录。`-Godot` 可覆盖编辑器路径，供现有源码测试 driver 使用。脚本直接读取该包的游戏索引和清单，不依赖当前源码构建索引，也不向发行客户端注入 `--script`。同包有原生进程运行时拒绝测试。每次使用全新 `data/release-test-随机号`、动态 TCP/UDP 端口，并在结束后恢复原有公开连接配置和证书。证据留在仓库 `logs/framework-release-随机号/result.json` 与相邻日志，私有测试数据库保留在测试数据目录。

验收先运行两个真实导出 `Client.exe` 的无窗口 UI 初始化，再以源码 driver 连接真实原生宿主与房间完成注册、登录和 ENet 入房。结果文件明确区分这两个范围，未包含浏览器或发行客户端的人工交互、画面验收。脚本保存自建进程句柄，对宿主/房间另核对私有记录中的父进程、可执行路径、启动标记和创建时间并持有句柄；优雅停止超时只对这些已确认的进程句柄清理，不能操作其他实例。

2026-09-22 候选包 `355ab837639f4942b13447b6f1bfcce0` 的 6 次真实导出通过；不可变文件 SHA-256 校验 35 项通过。实际 Operator.exe 首次初始化和从磁盘配置重启各一次，匿名 HTTP 初始化状态、两个 SQLite 文件和优雅退出 0 均通过。两个实际 Client.exe 的 `--ui-smoke` 退出 0、`login_ready=true`；这只证明导出后登录界面与配置初始化，不证明发行客户端已联机或已视觉验收。

该候选还在独立数据目录和动态 TCP/UDP 端口完成 `NATIVE_ACCEPTANCE_PASS passed=30`：真实管理员建立、ManagedHost.exe 启动、两种 Server.exe 的 READY 与实际 UDP 绑定、邀请码、两名测试玩家 WSS 注册登录、ENet 入房和状态复制、心跳、停止后宿主与房间进程退出、UDP 重新绑定，以及停止期间后台继续响应。联机端使用源码测试 driver，服务端使用实际导出的 EXE；这不等于发行版 Client.exe 的交互联机验收。证据为 `artifacts/framework-release-work-355ab837639f4942b13447b6f1bfcce0/native-acceptance/result.json` 和同目录日志，界面初始化证据在 `native-smoke/`。所有测试进程已退出。上述结果不代表公网、Linux、局域网或战术回合模式通过。

接入最新会话回收、经验表、指标过期、在线人数、备份大小、日志路径、复活反馈、停止态运行时长和登录提示修复后，源码再次构建为 `RoomKit-0.5.0-framework-windows-9d16d01539bb4f5bb235b1b0aadf9c6f.zip`，构建命令退出 0；随后可重复脚本 `tests/test_framework_release.ps1 -Bundle <该包解压绝对路径>` 实际取得 `FRAMEWORK_RELEASE_RESULT passed=44 failed=0`、退出 0、`cleanup_failed=false`。包含原有 42 项：两个导出客户端的无窗口登录 UI 初始化、原生服务管理员建立与登录、两个原生游戏房间、源码 driver 的真实 WSS/ENet、进程/端口回收和日志检查；另增加真实 HTTP 读取本次 Operator 启动日志、原生 SQLite 备份列表返回正数字节数两项。证据为 `logs/framework-release-b9e8270d105640598b4a8b543f371c61/result.json` 及同目录日志；6 项导出日志为 `logs/framework-export-9d16d01539bb4f5bb235b1b0aadf9c6f-*`。完成后再查同包进程为 0，测试前不存在的公开配置文件也已恢复为不存在。每次原生构建的 `build_id / server_artifact` 包含本次随机构建编号，`compatibility_id` 仍为 v1，避免用相同构建身份覆盖不同内容。

该 `9d16` 候选的干净 ZIP 共 36 项文件、228950675 字节，不可变文件校验 35 项通过，私有数据/私钥/测试入口为 0；SHA-256 为 `d767b8d988e8a4cd18bd27f55326529d2b7eed341c51aaf3bd1dd772be414354`。该 ZIP 在真实运行测试之前生成；测试数据不在 ZIP 内。包检查另记录于 `artifacts/framework-release-work-9d16d01539bb4f5bb235b1b0aadf9c6f/package-validation.json`。此轮没有调用浏览器或桌面自动化，44 项结果仍不包含发行客户端的交互联机或视觉验收。

失败已保留：早期候选重载 JSON 后把端口发布为 `28300.0`，导致客户端配置初始化失败；管理程序改为整数端口并在新候选两次启动验证。第一次原生 HTTP 探测被 PowerShell 默认的 `Expect: 100-continue` 头拒绝；测试显式关闭该头后重跑，严格 HTTP 策略未放宽。测试过的解压目录会产生私有运行数据，发行应使用构建时生成的干净 ZIP，不能直接重新压缩测试后的目录。

最后两处界面状态修复：宿主 PID 为 0 时运行时间显示“未运行”，保留正在运行或倒计时宿主的实际时长；成功进入后台先清空旧全局提示，再刷新当前状态，避免恢复备份后重新登录仍显示旧凭据错误。提取实际渲染表达式和入口函数的定向检查为 6/0，证据 `logs/admin-final-feedback-check.json`；该检查使用简化 DOM，明确不代替真实浏览器验收。上述修复已包含在该最终包并通过同一轮 44 项原生验收。

2026-09-22 对 `9d16` 原生界面验收中一次意外退回登录进行了只读审查：实际账号审计在首次管理员登录与人工重新登录之间没有管理员注销、密码修改或第二次管理员登录；管理员会话有效期仍为 12 小时，现存运行日志为空。代码中确认存在独立缺陷：身份检查把线程容量不足和存储暂不可用也映射成 `AUTH_FAILED`，页面因而清除会话；错误提示位于已经隐藏的管理页面。该缺陷可以解释现象，但没有当时的 HTTP 响应证据，不能宣称已经确定此次退出的根因。

后续源码已保留身份检查的临时错误码，真正凭据失效则在登录页显示原因；晚到的旧 token 认证失败也不能撤销新登录。`tests/run_operator_auth_errors.gd` 继承真实 Operator，执行实际管理请求、HTTP 状态映射和工作线程入口，用账号响应及 HTTP 输出替身隔离运行实例：修复前 3/3，修复后 6/0、退出 0。`node tests/test_admin_auth_errors.cjs` 执行实际 HTML 内的 `api()`，覆盖临时失败后的重试、真正失效、明确登录失败和旧响应竞态：修复前 7/5，修复后 12/0、退出 0。证据为 `logs/operator-auth-errors-before/after-console.log`、对应 stderr 和 `logs/admin-auth-errors-before/after.log`；这些定向测试不代表真实存储故障或浏览器视觉验收。此项修复不在此前已验收的 `9d16` 包中，不能用其 44 项结果证明后续代码；后续候选须独立导出和验收，最新结果以本页后续记录与 STATUS 为准。

上述身份检查错误映射修复已独立重导出为最新 `RoomKit-0.5.0-framework-windows-f4f40384083d45e28ffa38bcb5dea472.zip`。`tools/build_framework_release.ps1` 实际 6 次导出完成、退出 0；`tests/test_framework_release.ps1 -Bundle <该包绝对路径>` 实际 44/44、退出 0、`cleanup_failed=false`，证据 `logs/framework-release-0316ee0928e647b8b324ddd6a43e37b9/result.json`。收尾另以 OS 查询确认该包进程为 0，测试生成公开文件已恢复。干净 ZIP 为 228951845 字节、36 个条目、35 项不可变文件校验通过、私有文件 0；SHA-256 为 `49b8f13f92917b1305b9d2529bed9c371dce4c8397015501152e81ca542e173e`。包校验与清理记录在 `artifacts/framework-release-work-f4f40384083d45e28ffa38bcb5dea472/package-validation.json` 和 `cleanup-recheck.json`。本次测试仍区分导出客户端无窗口初始化、源码 driver 对原生服务的真实 WSS/ENet；最终真实浏览器追加验收另由 STATUS 记录。
