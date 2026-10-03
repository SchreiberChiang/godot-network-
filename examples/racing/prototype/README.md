# 离线驾驶原型候选

这是 `99e6df4` 研究之后的一个可驾驶小阶段。一个 `RigidBody3D`、四个射线接地点、弹簧/阻尼、前轮转向力、后轮驱动和可调后轮抓地。约 4 m 长的几何占位车，米制、Y 向上、-Z 朝前；四轮视觉节点独立。当前未接赛车规则、模型、网络、账号、host 或 SDK，也没有比赛流程。

## 一个入口

双击上一级 `OpenDrivingPrototype.cmd`。默认使用本机已有的 Godot `D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`；不安装引擎或导出模板。入口会把七份最小运行源码复制到工作树 `artifacts/racing-driving-play/project/`，把用户目录、缓存和临时目录全部指向同一 F 盘隔离区。窗口退出后入口结束。

1. 按 W/↑ 前进，A/D 或 ←/→ 转向；Shift 单独刹车。行驶中按 S/↓ 会先刹停，再倒车；倒车中按 W 同样先停再换向。
2. 按 2 到平地练习区，保持约 36 km/h，转弯时短按 Space 降低后轮抓地；松开后反打，再回中。**没有自动救车，长时间漂移仍可甩头。** 本轮通过的是可重复脚本反打，真人手感待反馈。
3. 按 3 到坡道正前方，按 W 驶上 10°坡并离地落地。按 1 回直线区。
4. R 回当前练习区出生点并清除按键状态；继续行驶需松开再按 W。F1 显示采样轮位与力，Esc 退出。

右上角滑块即时调整：`rear_grip` 为正常后轮侧向衰减率 6–14 s⁻¹（默认 10）；`drift_mu` 为漂移后轮摩擦系数 0.35–0.90（默认 0.85）；`recovery_half_life` 为松开后参数恢复半衰期 0.12–0.60 s（默认 0.25）。Restore grip defaults 恢复参数；R 不改变调参值。低抓地/慢恢复组合允许难以救回，参数范围不是全部组合的合格保证。

## 物理边界

- 质量 1200 kg、轮距 1.7 m、轴距 2.5 m；轮半径 0.30 m，悬挂静长 0.45 m、压缩行程 0.30 m。每轮弹簧 24525 N/m，阻尼 4339.9539 N·s/m。
- 接触查询来自当前物理变换；轮位速度包含角速度和质心偏移。每 tick 施加力，不乘第二次 dt，也不累积 constant force。重力由引擎积分。
- 法向支撑非负；后轮驱动、滚动阻力、制动和侧向力共享摩擦上限。空中没有轮胎力；只有小幅空气阻力。只支持静态地面，未计算移动地面的相对速度。
- Space 只改变抓地参数。前轮 k=10、mu=1.2；后轮漂移目标 k=4、mu=0.85，进入半衰期 0.12 s。离开漂移恢复参数；不覆盖横向速度、朝向，不叠加自动偏航辅助。
- 只有物理复位会直接清速度、改变变换并重置插值。相机取插值车身位置；F1 箭头来自同一物理采样，因此可能与插值画面存在小幅时间差。

场地包括平面、圆形参考线、10°坡道和小障碍。圆线是参考标记，不是赛道/规则；锥块和台阶只是几何，尚未完成通行验收。画面全部由简单几何创建，不覆盖另一个任务的车辆或赛道美术。

## 可复跑检查

在本工作树根执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File examples/racing/prototype/launch.ps1 -Mode Physics -Round dev
powershell.exe -NoProfile -ExecutionPolicy Bypass -File examples/racing/prototype/launch.ps1 -Mode Render -Round final
```

Physics 使用真实 Godot 刚体求解，但 `--headless --fixed-fps 60` 不按墙钟同步，不能据此测显卡 FPS。Render 打开实际窗口、按正常墙钟运行，保存两张 viewport PNG。它们均由脚本驾驶，输入事件检查仅注入 Godot 事件，不代表物理键盘验收。

最多复用 `dev`、`final` 两份测试工程/缓存；旧尝试保留轻量日志、源码哈希及报告。另有一个当前试玩目录。入口持有独占运行锁，拒绝链接路径及被手动改动的已暂存源码。不会自动删除产物、合并分支或启动服务。

真实结果、初期失败、未验项目见 [ACCEPTANCE.md](ACCEPTANCE.md)。
