# Tetris Guide 教学系统

## 目标

`Tetris Guide` 是放在游戏大厅中的教学入口，定位是“可互动的学习百科”，不是未来要单独制作的 Practice Lab。

它要解决的核心问题是：新手不知道哪些消除有价值，也不知道为什么高手会主动准备 Tetris、T-Spin 和 Combo。

## 学习顺序

第一版采用以下路径：

1. 基本规则
2. 消除与攻击力
3. Tetris 四消
4. Combo 连击
5. T-Spin
6. 各种 Spin
7. AI 评价怎么看

## 页面结构

### 总览页

总览页用于快速说明学习路径和攻击价值。

应包含：

- 章节列表
- 推荐学习顺序
- 攻击力速查
- 每个章节的查看与模拟入口

### 章节页

每个章节保持统一结构：

- 它是什么
- 为什么重要
- 攻击价值
- 分步骤引导
- 常见错误
- 进入固定场景模拟

文案需要像教学材料，不要像产品宣传或 AI 总结。标题下方不需要解释“本系统如何工作”，只保留必要信息。

### 演示区

演示区应模仿玩家的正常操作，而不是瞬间切换状态。

每轮演示流程：

1. 显示预设地形
2. 方块从上方出现
3. 显示当前动作，例如“右移到井上方”
4. 平滑移动或下落
5. 需要旋转时显示“顺时针旋转 90°”
6. 锁定
7. 高亮消除行
8. 消除
9. 停顿
10. 自动重播

## 初始模拟内容

### Tetris 四消

目标：用 I 方块竖直进入右侧井，完成 4 行同时消除。

需要展示：

- 井的位置
- I 方块横向移动
- 顺时针旋转 90°
- 硬降入井
- 四行消除

### Combo 3

目标：连续完成 3 次消行。

需要展示：

- 每一步都补线
- Combo 不断线
- 每次消除后进入下一段固定地形

### T-Spin Single

目标：通过旋转让 T 方块进入槽位，并完成 T-Spin Single。

需要展示：

- T 槽
- 方块移动到槽口
- 顺时针旋转 90°
- 再次旋转进入目标朝向
- 锁定并消除

### 其它 Spin

L/J/S/Z 等非 T 方块 Spin 可以作为进阶地形理解和补救技巧展示，但当前规则下不提供 Spin 攻击奖励。
如果它们完成消行，只按普通 Single / Double / Triple / Tetris 和 Combo 规则计算攻击。

## 视觉方向

- 明亮、平面化、干净
- 避免深色对战页的压迫感
- 左侧章节导航要有足够内边距
- 按钮状态必须清楚：普通、悬停、焦点、按下
- 演示棋盘不能过窄或过高，比例应服务于阅读

## 实现文件

- `scenes/ui/guide_system.tscn`
- `scenes/ui/guide/overview_page.tscn`
- `scenes/ui/guide/chapter_page.tscn`
- `scenes/ui/guide/simulation_page.tscn`
- `scripts/ui/guide_system.gd`
- `scripts/ui/guide_board_view.gd`
- `scripts/ui/guide_scenario_runner.gd`
- `scripts/ui/main_lobby.gd`
- `scripts/ui/ui_manager.gd`

当前实现仍是 Guide，不引入 Lab 命名。

## 场景模块化准则

Guide 页面不能只由脚本临时拼 UI。需要保持“静态场景外壳 + 模块场景实例 + 数据绑定”的结构。

当前拆分：

- `guide_system.tscn`：总入口，包含背景、顶部栏、章节导航、内容承载区。
- `overview_page.tscn`：总览页结构，承载学习路径、章节卡片和攻击价值速查。
- `chapter_page.tscn`：单章教学页结构，承载标题、概念、步骤、常见错误和右侧演示棋盘。
- `simulation_page.tscn`：固定场景模拟页结构，承载操作说明、按钮和可交互棋盘。
- `guide_scenario_runner.gd`：教学场景执行器，只负责棋盘状态、移动、旋转、锁定和消行。

脚本可以填充章节数据、绑定按钮和播放动作，但页面层级、主要容器和可视模块应当在 `.tscn` 中可见，方便后续像正常 UI 场景一样维护。
