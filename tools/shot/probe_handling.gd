extends "res://tools/shot/shot_support.gd"
## 手感规则自测：godot --headless --path . -s res://tools/shot/probe_handling.gd

var _fail := 0

func _start() -> void:
	_run.call_deferred()


func _check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		_fail += 1


func _clear(board: Board) -> void:
	for r in range(board.total_rows):
		for c in range(board.columns):
			board.grid[r][c] = null


func _fill_row_except(board: Board, r: int, holes: Array) -> void:
	for c in range(board.columns):
		board.grid[r][c] = null if c in holes else Color.GRAY


func _place(g, type: int, rot: int, col: int, row: int) -> void:
	g.cur_type = type
	g.cur_rot = rot
	g.cur_col = col
	g.cur_row = row
	g.last_was_rotation = true
	g.last_kick_index = 0
	g.last_rotation_was_180 = false


func _run() -> void:
	var g = instantiate_scene("res://scenes/game.tscn")
	if g == null:
		return
	for i in 3:
		await process_frame
	g.set_process(false)
	var b: Board = g.board
	var bottom := b.total_rows - 1

	# 1) T-Spin Double：T 朝下，底行只缺中间，上一行缺三格，右上有屋檐
	_clear(b)
	_fill_row_except(b, bottom, [4])
	_fill_row_except(b, bottom - 1, [3, 4, 5])
	b.grid[bottom - 2][5] = Color.GRAY
	_place(g, PieceData.Type.T, PieceData.RotationState.TWO, 4, bottom - 1)
	_check("TSD 判定为完整 T-Spin", g._resolve_spin() and g._is_full_t_spin() and not g.last_spin_mini)

	# 2) T-Spin Mini：T 朝上贴地，底部两角（地板外）+ 左上一角
	_clear(b)
	b.grid[bottom - 1][3] = Color.GRAY
	_place(g, PieceData.Type.T, PieceData.RotationState.SPAWN, 4, bottom)
	_check("前角不足 → T-Spin Mini", g._resolve_spin() and g.last_spin_mini and not g._is_full_t_spin())

	# 3) 没有旋转 → 不算 Spin
	g.last_was_rotation = false
	_check("最后一步非旋转 → 无 Spin", not g._resolve_spin())

	# 4) 非 T 块：四向卡死才算 Mini Spin，只卡三面不算
	_clear(b)
	_fill_row_except(b, bottom, [3, 4])
	_fill_row_except(b, bottom - 1, [4, 5])
	_place(g, PieceData.Type.S, PieceData.RotationState.TWO, 4, bottom - 1) # S 朝下：(0,0)(1,0)(-1,1)(0,1)
	var immobile: bool = g._check_immobile()
	var s_spin: bool = g._resolve_spin()
	_check("S 卡死 → S-Spin Mini (immobile=%s)" % immobile, s_spin == immobile and (not s_spin or g.last_spin_mini))
	_clear(b)
	_place(g, PieceData.Type.S, PieceData.RotationState.SPAWN, 4, bottom)
	_check("S 平地（可上移）→ 无 Spin", not g._resolve_spin())

	# 5) 180° 踢墙表与 SRS+ I 对称
	var k180: Array = PieceData.get_wall_kicks(PieceData.Type.T, PieceData.RotationState.SPAWN, PieceData.RotationState.TWO)
	_check("0->2 使用 TETR.IO 180 表（6 项，第二项上移）", k180.size() == 6 and k180[1] == Vector2(0, -1))
	var i01: Array = PieceData.get_wall_kicks(PieceData.Type.I, PieceData.RotationState.SPAWN, PieceData.RotationState.R)
	var i03: Array = PieceData.get_wall_kicks(PieceData.Type.I, PieceData.RotationState.SPAWN, PieceData.RotationState.L)
	_check("SRS+ I 踢墙左右对称", i01[1].x == -i03[1].x and i01[2].x == -i03[2].x)

	# 6) 锁定延迟：着地 0.49s 不锁，>= 0.5s 锁
	_clear(b)
	g._spawn_next_piece()
	while g._try_move(0, 1):
		pass
	var lines_before: int = b.get_stack_height()
	g._update_lock_delay(0.49)
	_check("0.49s 未锁定", b.get_stack_height() == lines_before)
	g._update_lock_delay(0.02)
	_check("0.51s 已锁定", b.get_stack_height() > lines_before)

	# 7) 15 次重置用尽：着地立即锁定
	_clear(b)
	g._spawn_next_piece()
	while g._try_move(0, 1):
		pass
	for i in 15:
		g._on_piece_manipulated()
	var h0: int = b.get_stack_height()
	g._update_lock_delay(0.001)
	_check("15 次重置后着地立即锁定", b.get_stack_height() > h0)

	# 8) 连击音高递增
	g.scoring.combo = 0
	var p0: float = g._combo_pitch()
	g.scoring.combo = 4
	var p4: float = g._combo_pitch()
	g.scoring.combo = 30
	var p30: float = g._combo_pitch()
	_check("连击音高递增并封顶 (%.2f < %.2f <= %.2f)" % [p0, p4, p30], p0 < p4 and p4 < p30 and p30 <= pow(2.0, 19.0 / 12.0) + 0.001)

	print("RESULT fail=%d" % _fail)
	quit(1 if _fail > 0 else 0)
