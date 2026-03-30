extends Node2D

## 画布调试场景 
## 用于测试程序化生成的现代方块渲染效果

func _ready() -> void:
	# 设置清爽的暗色背景背景，凸显发光霓虹材质
	RenderingServer.set_default_clear_color(Color("0f0f13"))
	
	var start_pos = Vector2(100, 100)
	var offset = Vector2(150, 0)
	
	# 遍历 7 种形状，挨个生成出来测试它的 _draw 渲染效果
	var i = 0
	for type in [PieceData.Type.I, PieceData.Type.O, PieceData.Type.T, PieceData.Type.S, PieceData.Type.Z, PieceData.Type.J, PieceData.Type.L]:
		var piece = Piece.new()
		piece.initialize(type)
		
		piece.position = start_pos + offset * (i % 4) + Vector2(0, 150) * int(i / 4)
		add_child(piece)
		i += 1
		
	# 独家奉送一个幽灵方块预览
	var ghost = Piece.new()
	ghost.initialize(PieceData.Type.T)
	ghost.position = start_pos + offset * 3 + Vector2(0, 150)
	ghost.set_as_ghost()
	add_child(ghost)
