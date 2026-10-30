extends "res://tools/shot/shot_support.gd"
## 对局特效探针：godot --path . -s res://tools/shot/probe_game_fx.gd -- <scene> <out_prefix>
## 构造高堆叠 + 垃圾队列，触发四消与攻击弹，并在多个时间点截图。

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		fail("Usage: <scene> <out_prefix>", 2)
		return
	_run.call_deferred(args[0], args[1])


func _shot(path: String) -> bool:
	return save_screenshot(path)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run(scene_path: String, prefix: String) -> void:
	var inst := instantiate_scene(scene_path)
	if inst == null:
		return
	if not (inst is TetrisCore):
		fail("Game FX probe requires a TetrisCore scene")
		return
	await _frames(10)
	var g = inst
	var board: Board = g.board

	# 高堆叠：底部 4 行只留第 0 列空（可被 I 竖放消四行），其上再堆 11 行杂乱块
	var colors := PieceData.COLORS.values()
	for r in range(board.total_rows - 4, board.total_rows):
		for c in range(1, board.columns):
			board.grid[r][c] = colors[(r + c) % colors.size()]
	for r in range(board.total_rows - 15, board.total_rows - 4):
		for c in range(board.columns):
			if (r * 7 + c * 3) % 5 != 0 and c != 0:
				board.grid[r][c] = colors[(r * 3 + c) % colors.size()]
	board.queue_redraw()

	# 垃圾队列：灰 / 黄 / 红 各阶段
	if "pending_attacks" in g:
		g.pending_attacks.append({"delay": 11.0, "amount": 2})
		g.pending_attacks.append({"delay": 5.0, "amount": 3})
		g.pending_attacks.append({"delay": 0.8, "amount": 2})
		g.ready_garbage = 2
	await create_timer(1.6).timeout
	if not _shot(prefix + "_danger.png"):
		return

	# 受击弹道
	if g.has_method("_receive_attack"):
		g._receive_attack(3)
	elif g.has_method("_on_attack_received"):
		g._on_attack_received(3)
	elif g.garbage_bar:
		g._fire_incoming(AttackFX.canvas_pos(g.garbage_bar) + Vector2(-90, -70), g.garbage_bar, 3)
	await create_timer(0.16).timeout
	if not _shot(prefix + "_incoming.png"):
		return
	await create_timer(0.8).timeout

	# I 竖放到第 0 列，硬降消四行
	g.cur_type = PieceData.Type.I
	g.cur_rot = PieceData.RotationState.L
	g.cur_col = 0
	g.cur_row = board.buffer_rows
	g.current_piece.initialize(g.cur_type)
	g.current_piece.apply_rotation(g.cur_rot)
	g.scoring.combo = 3
	g._hard_drop()
	await create_timer(0.04).timeout
	if not _shot(prefix + "_clear_a.png"):
		return
	await create_timer(0.12).timeout
	if not _shot(prefix + "_clear_b.png"):
		return
	await create_timer(0.2).timeout
	if not _shot(prefix + "_clear_c.png"):
		return
	await create_timer(1.0).timeout
	if not _shot(prefix + "_after.png"):
		return
	quit(0)
