# 俯视 ARPG 肉鸽项目学习与实践手册（Godot 4.5）

本仓库用于系统学习与实现一个俯视视角的暗黑类（ARPG 风格）肉鸽游戏。目标是以模块化、数据驱动的方式搭建核心循环（移动-战斗-掉落-成长-关卡推进），并兼顾易扩展与可维护性。

下面内容既是整体设计文档，也是后续开发的执行手册。

**目录**
- 项目结构（目标与演进）
- 开发环境与运行
- 输入映射约定
- 架构与模块划分
- 移动与相机（俯视 ARPG）
- 物品与词缀（数据驱动）
- 战斗与碰撞（层与掩码）
- 程序化关卡（房间模板）
- UI/HUD 规范
- 存档与配置
- 代码风格与命名
- 性能与调试
- 导出与版本
- 学习路线与里程碑


## 项目结构（目标与演进）

目标结构：
```
/project_root
|-- addons/                  # Godot 插件
|-- assets/                  # 非代码资源（与引擎无关）
|   |-- environments/          # 3D 环境与材质
|   |-- vfx/                   # 视觉特效素材
|   `-- audio/                 # 音频（music/sfx）
|-- core/                    # 全局/引导层
|   |-- main.tscn              # 主入口（可包含加载流程/菜单切换）
|   |-- main.gd
|   |-- globals.gd             # Autoload 单例（配置/工具/RNG）
|   `-- scene_manager.gd       # 场景切换（Autoload）
|-- data/                    # 数据资源（Resource/Tres/Tscn）
|   |-- items/
|   |   |-- bases/
|   |   |-- affixes/
|   |   `-- uniques/
|   `-- skills/
|-- features/                # 领域模块（解耦互不依赖 UI）
|   |-- player/
|   |-- enemies/
|   |-- combat/
|   |-- inventory/
|   |-- procedural_generation/
|   `-- ui/
|-- docs/                    # 设计/规范/研究记录
|-- tests/                   # 测试（如 GUT/WAT）
|-- tools/                   # 导入器、批处理、脚本
|-- project.godot            # Godot 项目文件
`-- export_presets.cfg       # 导出配置（创建导出后生成）
```

## 开发环境与运行
- 安装 Godot 4.5，对应渲染：Forward+
- 打开工程，直接运行（F5）
- 推荐在编辑器内新建导出配置，生成 `export_presets.cfg`


## 输入映射约定
在「项目设置 -> 输入映射」中新增以下动作（脚本会回退到 `ui_*`，但建议显式配置）：
- 移动：`move_left` / `move_right` / `move_forward` / `move_back`
- 冲刺/疾跑：`dash` / `sprint`

参考绑定（键盘/手柄）：
- WASD / 方向键 / 左摇杆；Shift=疾跑；B/Circle=冲刺


## 架构与模块划分
- Core（引导与单例）
  - `globals.gd`：配置常量、RNG、全局事件总线
  - `scene_manager.gd`：加载过场、淡入淡出、存档切换
- Features（领域模块）
  - Player：移动、动画、状态、输入适配
  - Enemies：感知（Ray/Area）、状态机/行为树、掉落钩子
  - Combat：伤害结算、抗性、命中/暴击、敌我识别、硬直与无敌帧
  - Inventory：背包、装备槽、属性汇总、掉落拾取
  - Skills：技能数据（Resource）+ 播放器（施法/冷却/成本）
  - Procedural Generation：房间模板拼接、门/钥匙、事件/精英/商店
  - UI：HUD、背包面板、工具提示、数值飘字


## 移动与相机（俯视 ARPG）
目标：XZ 平面自由移动，不使用横版锁轴与跳跃（默认禁用跳跃）。

- 配置：默认启用 `move_relative_to_camera=true`
- 相机：`SpringArm3D/Camera3D`（正交模式 size≈10）随主角移动，提供稳定俯视视角
- 朝向：默认朝向移动方向，后续可扩展“面向鼠标/右摇杆”


## 物品与词缀（数据驱动）
- 使用资源：`data/items/{bases,affixes,uniques}/*.tres`
- Item 结构建议：
  - 基础：部位/类型、基础数值（攻击、速度、范围）、可滚词缀槽位
  - 词缀：前/后缀、权重、数值区间、分段（T1-T5）
  - 生成：根据关卡进度/幸运值加权抽取，最终合成 `ItemInstance`（保存实际数值）
- 技能资源：`data/skills/*.tres`，字段包含冷却、施法时间、消耗、投射体/范围参数、受属性加成标签


## 战斗与碰撞（层与掩码）
在「项目设置 -> 3D 物理 -> 层名称」配置：
- 1 Player
- 2 Enemy
- 3 PlayerHitbox（玩家伤害盒/投射物）
- 4 EnemyHitbox
- 5 Environment
- 6 Loot
- 7 Interactable
- 8 Sensor（感知/触发区）

实现要点：
- 命中框/受击框分离（`Area3D` + `CollisionShape3D`），用信号回调结算
- 投射体：对象池复用；命中后回收；可穿透/可弹射参数化
- 受击反馈：硬直/击退/无敌帧，统一在 Combat 中央处理


## 程序化关卡（房间模板）
- `features/procedural_generation/room_templates/` 保存可拼接房间（入口/出口锚点）
- 生成器：
  - 根据进度生成走廊-战斗-事件-奖励的序列
  - 控制稀有度/精英/商店/秘境的权重
  - 出口校验避免不连通/自交


## UI/HUD 规范
- HUD：血蓝/能量、经验、技能条、Buff 图标、战斗浮字
- 交互：物品拾取提示（对准/自动/按键）、装备比较（绿升红降）
- 工具提示：从资源数据动态拼装（范围、冷却、伤害标签）
- UI 组件统一放在 `features/ui/components/` 可复用


## 存档与配置
- 存档：使用 `FileAccess` + JSON 或 `ResourceSaver` 存 `*.tres`
- 内容：玩家 Build（装备/技能/天赋）、进度（层数/种子）、选项（音量/按键）
- 建议通过 `globals.gd` 集中提供 `save/load` 接口与当前 run 的随机种子


## 代码风格与命名
- GDScript：
  - 文件名：`snake_case.gd`；场景名：`PascalCase.tscn`；类名：`PascalCase`
  - 每个场景同名脚本一对一；信号统一在文件头声明
  - 避免在 `_process` 里做可延迟的逻辑；用信号/状态机拆分
- 资源与数据：
  - `*.tres` 只存数据，不耦合节点树；逻辑脚本读取并实例化
- 物理：
  - 清晰的碰撞层/掩码约定；不要让 Player 直接检测 EnemyHitbox


## 性能与调试
- 对象池：投射体/掉落物/临时特效实例池化
- 导航：只在需要的房间构建 NavMesh；切换时及时释放
- 材质与贴图：体积限制与压缩；优先 1K~2K 级别；法线与粗糙度分离
- 调试：`VisibleCollisionShapes`、`DebugDraw`、`NavigationServer` 可视化、`RenderingDebugger`


## 导出与版本
- 打开「项目 -> 导出」，添加平台预设，保存生成 `export_presets.cfg`
- 建议版本语义化：`major.minor.patch`，并在 `docs/changelog.md` 记录变更


## 学习路线与里程碑（俯视 ARPG）
建议按以下顺序迭代，每步产出可运行内容：
1) 基础功能：角色移动与俯视相机
2) 基础战斗：近战轻/重击，受击反馈与伤害数字
3) 投射体技能：火球/箭矢，冷却与消耗显示
4) 掉落与背包：基础物品 + 简单词缀，HUD 提示与装备比较
5) 敌人 AI：巡逻/追击/攻击，精英与特殊能力（冰环/冲锋）
6) 房间模板与关卡推进：生成小地图/事件/商店
7) 存档系统：本局/元进度；难度与种子
8) 打磨：VFX/SFX、数值曲线、手柄震动与可达性（色弱模式）
