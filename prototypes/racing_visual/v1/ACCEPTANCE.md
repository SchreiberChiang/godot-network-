# V1 街车独立本机验收（2026-10-02）

结论：建议收为 `prototypes/racing_visual/v1/` 独立视觉能力样本，并附带本验收记录。模型资产结构满足本次能力样本范围；车身有 16 个零面积或近零面积三角面，需记录，后续可驾驶资产阶段前应清理并重新导出。此记录不宣称 Godot 导入、实际渲染、物理或驾驶通过。本验收没有改动主线受控文件，也没有接入游戏。

## 收到的本机包

- ZIP：`F:\文档\GodotGame\Net\RoomKit\artifacts\dot-car-v1-20261002\car-v1.zip`
- 大小：3,322,617 字节。
- 本机回读 SHA256：`179b2612559b2fbf7f99a4f85b28185afd768e0d592a7bef98032ab4e792581b`，与上游提供值匹配。
- 已安全解压到 `F:\文档\GodotGame\Net\RoomKit\artifacts\dot-car-v1-20261002\extracted\prototypes\racing_visual\`。
- 检查 9 项 ZIP 成员，绝对路径、盘符、父路径越界、大小写路径碰撞、Unix 链接/特殊文件、Windows reparse 标志、加密成员均未发现；总解压尺寸约 3.29 MiB，未触及 32 MiB 限额。解压前核验路径处于指定目录并拒绝覆盖已有成员。

## 本机实测

- GLB v2，长度 119,260 字节，JSON/BIN 块长度和边界通过检查。
- 1 个空根节点 `Street_Car_V1`，下接 `Body` 与 4 个车轮节点。各车轮引用不同 mesh，因此可独立变换。
- 实际索引计数 1,792 三角面：Body 832，四轮各 240；索引均在对应 POSITION 数据范围内，POSITION 均为有限值。
- 实际场景包围盒按顶点和世界矩阵计算：X -2.01999998～2.02999997，Y 0～1.37029445，Z -0.92450001～0.92450001。长×宽×高约 4.050×1.849×1.370 米，与上游报告相符。
- GLB 为 Y-up：车头按说明为 +X，+Y 向上，车左为 -Z。四轮节点平移分别为 (±1.2,0.32,±0.8)，轮半径约 0.32 米；轮底 Y=0，轮轴对应局部 Z。独立节点的旋转均为单位四元数、缩放均为 (1,1,1)。轮中心与轮 mesh 局部包围盒中心相符。没有实跑轮转或转向。
- 4 个材质：`01_Petrol_Teal`、`02_Smoked_Glass`、`03_Graphite`、`04_Satin_Alloy`。均为纯色 PBR，玻璃不透明；所有材质均设置 doubleSided=true。
- 无外部 buffer/image URI，无 glTF 扩展依赖，无动画，无 skin。资源自包含；未检查完整 Khronos glTF Validator 规则。
- 根据几何叉积平方小于 1e-16 的判据，Body 有 16 个零面积或近零面积三角面，四轮为 0。这是独立检查发现，上游 PASS 报告没有覆盖该项；不会把上游 PASS 当成本机所有门禁通过。

## 已查看的预览

逐张使用本机 `view_image` 查看 `three_quarter.png` 和 `top.png`，均为 1200×900。青绿色低多边形双门街车轮廓完整，车窗、灯、轮拱、后视镜可辨；三分之四图可见右侧两轮，俯视图可见四轮和左右后视镜，未见品牌或文字。阴影能看出接地，画面有可见采样颗粒，玻璃为深色不透明。预览适合作为能力样本展示。

本机未重新渲染；两张图和 GLB 的视觉一致性仅作外观层面的观察，预览是否确由此哈希对应的 GLB/Blend 渲染尚未独立验证。原创性及 CC0 许可为交付者在 `说明.txt` 中的声明；已保留原声明，未做来源追踪。

## 建议接收的精确文件清单

以下文件当前均位于上述 `extracted\prototypes\racing_visual\`，建议保持相同文件名接收到 `prototypes/racing_visual/v1/`。生成/复验脚本仅作为源码随样本留存，本次只读未运行。

| 文件名 | 字节 | SHA256 |
|---|---:|---|
| street_car_v1.blend | 111265 | 6f429f994e9391c2ea3582a189ba14834e9d78ae7135a98b46304e5f24eda64b |
| street_car_v1.glb | 119260 | 8f08bb51813802b1103b74c5be379ee2d66180a66e00fd4cc58b2f478d4a6169 |
| three_quarter.png | 1584243 | 9ad5426e58b0eb1c84109367741239ca3daf7a7f1423ad03a0687040b7b3f0c0 |
| top.png | 1610598 | 04815a715e27d3aeaeb986a129a77060511b091675df8342be689763cc0f264c |
| source_stats.json | 380 | 58866ab25c7dc3b6950d0be4a31d0063ec4ee3588b99464de199abf62dd41abe |
| validation.json | 1457 | 999b70f468831ec4327ac78d67633e2f31fe770f1f13de6a74c20d2d23f52669 |
| 说明.txt | 2656 | af1392baee3e66e7220c072cde5308f88ea7b1ac3a04e4e1be1bbc185201a7fd |
| create_car.py | 8082 | f5fba3b16be1acacf7653a0107725149255f06605b12ed99c5ed4a329e2f9363 |
| validate_glb.py | 1920 | 10381271f96ab90b6974123e65dd401868d5666f4ba03beaf89dfe8f5bef25a8 |

## 实际命令与未运行门禁

独立检查脚本位于本目录 `inspect_car_v1.py`，仅使用 Python 标准库 zipfile/json/struct/hashlib/math，不执行 ZIP 内脚本。实际命令：

```powershell
& 'C:\Users\赵江\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' 'logs\car-v1-20261002\inspect_car_v1.py'
```

退出码 0，详细 JSON 与每个解压文件的大小/哈希在同目录 `structure.json`。脚本为首次解压设计，重复运行会在发现已有成员时拒绝覆盖；若需复核已收到文件，应直接回读哈希与 GLB，不删除原样本来制造新一次解压通过。

环境只读核对：Git 2.55.0.windows.3，仓库根目录正确；Godot `--version` 返回 `4.7.2.stable.steam.ed1daf0bf`、退出 0。Godot 仅查询版本，未运行项目或导入模型。没有使用 Blender、安装软件、启动服务或运行包内脚本。

未验证：Blend 重开/可编辑性、上游 Blender 重导入报告复现、Godot 首次导入及真实渲染、车轮动态转向/滚动、碰撞体/物理/驾驶、游戏运行时/联网、完整 glTF Validator、预览生成与 GLB 对应关系。主线文件/STATUS/ROADMAP 接收与提交由主负责人负责，本子任务仅交付指定忽略目录中的验收证据。
