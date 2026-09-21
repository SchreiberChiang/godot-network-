# 07 版本、配置与决策记录

## 1. 不把所有版本混在一起

`control_protocol`：宿主—SDK消息契约。

`sdk_version`：插件/API发布版本。

`game_protocol`：该游戏的战斗协议。

`build_id`：具体不可变构建。

`compatibility_id`：CI确认能互联的客户端/服务端构建组合标识；v0.1建议严格匹配，不做宽泛兼容猜测。

每个build记录Godot精确版本、导出模板、扩展插件/原生库版本和产物摘要。不同游戏可保留不同引擎构建，但同一房间的双端配对必须经过测试；不能承诺所有Godot 4.x版本天然互通。

## 2. 配置所有权

| 配置 | 谁能改 | 能否进入客户端 |
|---|---|---|
| game_id/兼容标识/大厅URL | 项目构建配置 | 可以 |
| 模式/地图ID/人数请求 | 用户在白名单中选择 | 可以，但服务端重新校验 |
| server_artifact与部署路径 | 管理员/发布流程 | 不需要 |
| 控制凭据、数据库密码、私钥 | 宿主/部署系统 | 绝不允许 |
| room_id/launch_id/分配端口 | 宿主生成 | 仅公开必要接入数据 |

清单示例含`PIN_EXACT_TESTED_VERSION`占位符，结构验证允许模板存在，但部署检查必须拒绝未填写的占位符；不能把它当成真实引擎版本。

## 3. 初始ADR

ADR-001：一房一进程。优先独立生命周期、故障隔离和可测试性；代价是重复内存开销。只有压测证明瓶颈再考虑一进程多房。

ADR-002：业务宿主从零使用Godot/GDScript。不为“通用”预先引入第二套后端语言。外部JSON协议稳定后，可用其他实现替换控制层，不承诺替换战斗高层协议。

ADR-003：标准WSS大厅，本机TCP控制，ENet战斗。接口边界先固定；大厅从首次实现就是标准JSON，不开发旧ENet大厅或迁移适配器。

ADR-004：游戏为独立构建，不动态加载所有项目进一个大主服。宿主不知道Player.tscn与枪械实现。

ADR-005：认证前不允许游戏实体/RPC。以稳定业务身份和单次票据接入；临时peer_id不是账号ID。

ADR-006：通用网络运行时≠通用玩法同步。射击预测/回滚/命中回溯为独立可选包，不进入最小核心。

ADR-007：v0.1不保证崩溃续局。明确中止和清理政策比未实现的“自动恢复”安全。以后增加快照恢复需新ADR和项目状态序列化协议。

## 4. 变更规则

2026-09-22 通用管理分支：新增受管理账号/资产 SDK **0.5.0**。源码射击构建 shooter-dev-001（shooter-v1），受管理取石子构建 turns-managed-dev-001（turns-managed-v1）；取石子旧演示的0.4清单保留，构建时生成独立0.5清单。管理大厅使用独立 managed_lobby/account/admin Schema；不能把旧无密码开发身份当成账号登录。控制协议仍为1，但增加资产许可、已确认资产状态和异步刷新消息，启用这些能力必须成对升级宿主与房间。已确认资产包含服务端版本、所有权和游戏配置，客户端不能指定空间或任意装备属性。完整兼容和错误码见 docs/21_managed_protocol.md。

ADR-011：管理服务独立于游戏宿主，只有管理服务持有账号与永久资产数据库。管理服务使用回环 HTTP 和认证的回环 TCP；游戏大厅使用 WSS，房间使用 DTLS/ENet。房间只通过注册的 GameAdapter 请求和接收资产；通用核心不识别枪械、死亡、复活或取石子主题。永久资产、比赛临时资产和具体玩法分层，后续战术模式不得复用永久钱包作为比赛经济。

ADR-012：恢复必须先证明旧宿主及其已登记房间全部退出、UDP端口可以重新绑定，才清理已确认的旧进程记录并启动新宿主。内部恢复操作只撤销玩家会话，保留管理员；删除与恢复审计同事务，且不暴露为玩家消息或远程管理动作。备份恢复则撤销全部会话，要求管理员重新登录。确认失败保持隔离，不按旧PID强杀或继续开服。

2026-09-21 后续实施（历史）：SDK **0.4.0**，覆盖下方0.3.0历史记录。开发构建 minimal_room/dev-004（roomkit-minimal-dev-004）、blocks/blocks-dev-003（blocks-v3）、turns/turns-dev-003（turns-v3）。Windows正式模板独立构建为 blocks-win-001 / turns-win-001，兼容标识 blocks-win-v1 / turns-win-v1，清单引擎为4.7.2.stable.official.ed1daf0bf。源码开发引擎为4.7.2.stable.steam.ed1daf0bf。双端必须同构建/兼容标识，不接受旧产物混入。

框架包名0.1.0-candidate与SDK 0.4.0是不同版本轴。当前可复验组合是Windows10.0.26200、上述Steam编辑器/official模板、系统SQLite3.51.1；两种引擎都已实际跑十轮精确身份和句柄回收。模板全hash为ed1daf0bf001b61586d9930840f2f1394092c079；其它hash拒绝执行专用缓存句柄释放路径，不能只凭4.x标签宣称兼容。Linux official模板仅跑可移植检查。

ADR-009：正式模板使用固定MainLoop+空主场景，宿主/房间/客户端各自PCK；不能把开发期--script或路径覆盖当成正式入口。外部可写路径明确基于EXE目录，PCK只读契约仍从res://读取。

ADR-010：托管重启保守隔离旧端口，不认领或终止前一宿主的进程。持有有效身份且确认退出后才可回收；缺失身份永久隔离直到人工核验。当前资源限制为有界队列、采样工作集和超时，不承诺OS硬配额。

2026-09-21 M4第一部分：源码SDK标识0.3.0，control_protocol=1增加可选result.submit/result.ack，正文result_version=1。结果服务要求宿主与房间同步升级，当前仅接受SDK 0.3.0；旧宿主不支持新事件。M1夹具使用原消息子集，未启用结果服务的M2流程不发送结果事件。当前示例构建更新为minimal_room/dev-003、blocks/blocks-dev-002、turns/turns-dev-002；兼容标识分别roomkit-minimal-dev-003、blocks-v2、turns-v2，避免将旧产物误当新构建。game_protocol仍为1；未承诺与旧客户端交叉互通。以上是开发源码版本，不是发行包。

ADR-008：Windows SQLite适配通过系统winsqlite3.dll及宿主PowerShell助手实现。数据库Schema user_version=1，从空库初始化或打开已有v1库，未知版本拒绝。result_id及(game_id,match_id,result_kind)双重唯一约束，提交完成才ACK。密钥、数据库与持久outbox在项目data/下，排除Git；结果恢复不等于恢复房间进程或对局。同步助手延迟、资源限额和断电限制见docs/13。

2026-09-19 M0/M1 实施记录：实际锁定 `4.7.2.stable.steam.ed1daf0bf`。开发组合入口位于 `host/development.gd`，核心不引用示例路径。Windows 终止过程固定进程句柄并校验创建时间、父 PID、可执行路径与 launch_id；仅对精确已验证引擎实现缓存句柄回收，其它版本不执行该专用路径。SDK 分发、GameAdapter 玩家回调和导出产物仍属后续阶段；本轮完整结果见 STATUS。

修改公开消息或SDK先改契约/示例/测试，再改实现。破坏性变更升级协议或兼容标识。发布SDK时记录支持矩阵与迁移步骤。不得把固定分支永远设为latest，让旧项目自动获得未验证的新行为。

2026-09-20 M2 本地实施记录：新增标准 WebSocket JSON 大厅、源码双端 SDK、GameAdapter 和两人无玩法示例。新示例 build_id=dev-002、sdk_version=0.2.0、compatibility_id=roomkit-minimal-dev-002，与 M1 dev-001 分开登记。control_protocol=1 是本地尚未发布的契约增量；宿主和新 SDK 同步升级，不保证旧宿主支持 M2 事件。M1 夹具继续使用原消息子集。SDK 插件分发与导出产物尚未验证，不能将 0.2.0 源码标识视为正式发行声明。

2026-09-20 M3：新增 blocks / turns 两个 game_id，分别使用 blocks-dev-001 / turns-dev-001 构建以及 blocks-v1 / turns-v1 兼容标识。每个开发工程携带同一份未修改的 SDK 0.2.0，独立目录启动。玩法输入/状态 Schema 独立放在 schemas/，无 CharacterBody/武器依赖。没有改动宿主核心或 SDK 协议；Godot ENet RPC 仅属于对应游戏。独立开发工程验证与专用可执行文件导出验证明确分开。
