# WIDE TETRIS 核心文档

更新时间：2026-04-05

## 1. 项目目标与当前范围

本项目基于 Godot 4.6，目标是实现现代规则俄罗斯方块，并逐步扩展到在线多人对战。

当前主线包含：
- 单人马拉松模式（已可运行）
- 双人对战模式（开发中，已具备服务端和客户端基础链路）

## 2. 代码结构（核心）

- `scenes/`：游戏与 UI 场景
- `scripts/core/`：棋盘、方块、核心状态与网络管理
- `scripts/game/`：单人与多人玩法逻辑
- `scripts/ui/`：登录、大厅、多人设置与房间 UI
- `server/`：Node.js + ws 的 WebSocket 服务端
- `docs/`：文档

关键入口：
- Godot 主入口：`res://scenes/ui/main.tscn`
- 多人设置：`res://scenes/ui/multiplayer_setup.tscn`
- 多人大厅：`res://scenes/ui/multiplayer_lobby.tscn`
- 对战场景：`res://scenes/multiplayer_game.tscn`
- 服务端入口：`server/index.js`

## 3. 双人模式现状（检查结论）

### 3.1 已完成

- 已建立 WebSocket 服务端（`server/index.js`），支持基础房间与转发逻辑。
- 客户端已实现网络管理单例（`scripts/core/network_manager.gd`），可完成：
  - 连接服务器
  - 登录
  - 拉取房间
  - 创建/加入房间
  - 接收开局信号
- 多人大厅 UI 与流程已打通：
  - `multiplayer_setup -> multiplayer_lobby -> multiplayer_game`
- 对战消息已接入：
  - 棋盘同步（`board_update`）
  - 攻击发送/接收（`attack`）
  - 结束同步（`game_over`）

### 3.2 当前阻塞与风险

1. `scenes/multiplayer_game.tscn` 引用了不存在的资源：
- `res://scenes/core/board.tscn`
- `res://scenes/core/piece.tscn`

这会导致多人场景加载失败，是当前第一优先级阻塞。

2. 文本与注释存在编码混杂现象（部分文件显示乱码），协作和维护成本高。

3. 服务端缺少健壮性能力：
- 无鉴权/防重名
- 无心跳与超时清理
- 无重连恢复
- 无版本号/协议版本校验

4. 仓库未忽略 `server/node_modules`，建议补充忽略策略并避免提交依赖目录。

## 4. 双人模式通信协议（当前实现）

消息统一结构：
```json
{
  "type": "message_type",
  "payload": {}
}
```

### 4.1 C -> S

- `login`：`{ name }`
- `list_rooms`：`{}`
- `create_room`：`{ name }`
- `join_room`：`{ room_id }`
- `board_update`：`{ grid }`
- `attack`：`{ amount }`
- `game_over`：`{}`

### 4.2 S -> C

- `login_success`：`{ id }`
- `room_list`：`{ rooms: [{ id, name, playerCount }] }`
- `room_created`：`{ room_id }`
- `room_joined`：`{ room_id }`
- `game_start`：`{ opponent_name }`
- `board_update`：`{ grid }`
- `attack`：`{ amount }`
- `game_over`：`{}`
- `opponent_left`：`{}`
- `error`：`{ message }`

## 5. 联调与运行

### 5.1 服务端

在 `server/` 目录：
- 安装依赖：`npm install`
- 运行服务：`node index.js`

默认端口：`8080`

### 5.2 客户端

- 在 Godot 打开项目后运行主场景
- 主菜单进入多人模式
- 在多人设置页输入 `IP + 端口 + 昵称`
- 连接后创建房间或加入房间

## 6. 下一阶段任务（建议按顺序）

1. 修复多人场景资源引用（最高优先级）
- 创建并接入 `scenes/core/board.tscn`、`scenes/core/piece.tscn`
- 或改为直接复用现有 `game.tscn` 内节点结构

2. 整理编码为 UTF-8（无 BOM）
- 统一 GDScript、TSGN、Markdown 文本编码
- 修复 UI 文案乱码

3. 强化服务端稳定性
- 增加心跳与超时断线
- 增加房间状态机与异常兜底
- 增加错误码（避免纯字符串消息）

4. 增加联机调试工具
- 客户端网络日志开关
- 服务端房间/连接统计输出

## 7. 双人模式里程碑定义（建议）

- M1：可完整打一局（创建房间、开始、胜负结算）
- M2：断线/重连行为可预期（至少对手断线通知稳定）
- M3：攻击结算与观感优化（延迟与动画一致性）
- M4：基础反作弊与协议版本控制

## 8. 近期更新记录（2026-04-05）

1. 多人模式垃圾块同步修复  
- 修复了对手棋盘中灰色垃圾块不显示的问题。  
- 棋盘网络序列化新增垃圾块专用编码，避免被当作空格丢失。

2. 多人受攻击条逻辑恢复（对齐单人）  
- 收到攻击后改为“每段独立 12 秒 CD”入队，而非立即灌入棋盘。  
- 受攻击条按灰/黄/红阶段显示（>6s 灰，<=6s 黄，到时红）。  
- 本地打出伤害时优先抵消待受击队列（先红段，再灰黄段），仅将剩余伤害发送给对手。

3. 红段落地结算修复  
- 修复“红段长时间不转垃圾行”的问题。  
- 结算条件改为基于“本次锁定前后消行数差值”判断是否消行，避免 combo 状态值误判。

4. 失焦运行公平性修复  
- 关闭项目低处理器模式，避免窗口失焦时逻辑降频。  
- 多人主循环改用 `_physics_process`，降低不同帧率带来的速度偏差。

5. 对局结束音频行为修复  
- 多人对局在以下结束场景都会停止 BGM：本地失败、对手失败、对手离开。

## 9. 场景文件编辑红线（2026-04-07）

这是一条高优先级协作约束，必须严格遵守：

1. `.tscn` 文件必须使用 `UTF-8（无 BOM）`。  
2. `.tscn` 文件必须使用 `LF` 行尾，禁止 `CRLF`。  
3. 任何会把 `.tscn` 写成 `UTF-8 BOM` 或 `CRLF` 的操作都禁止使用。  
4. 若出现“场景无法解析/Parser Error”，优先检查：  
- 是否引入了 BOM（`EF BB BF`）  
- 是否被改成 CRLF  
- 是否存在未闭合的 `text = "..."` 字符串

说明：已确认 Godot 4.6 对是否含 `load_steps` 不是关键问题；当前项目里 `.tscn` 解析失败的高风险点是编码与行尾被破坏。

---

如需，我可以在下一步直接帮你把第 1 项（多人场景资源引用）连同编码清理一起修掉，并把文档中的任务状态改成“已完成/进行中”。
