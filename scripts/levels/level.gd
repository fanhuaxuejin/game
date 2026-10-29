class_name Level
extends Node2D
## 一个关卡。职责：自己的房间边界（相机限制）、血迹层、**导航面**、以及这一关的地图与敌人。
##
## 关卡都是普通场景，可以在 Godot 编辑器里直接画图块、摆敌人和路点。
## 手画完直接按 F5：运行时按 Floor / Walls 自动重建寻路网格（见 _build_grid）。
##
## 节点结构（层级约定见 DESIGN.md）：
##   Floor(TileMapLayer, z=-10) / Blood(z=-5) / Walls(TileMapLayer, z=0)
##   Player(z=2) / Enemies(z=2) / Projectiles

## 导航面每格的尺寸来自 TileSet；这里只是敌人的寻路网格分辨率。
## 敌人碰撞体 10x10，格 16px → 用格中心走的话离墙 8px，余量 3px，够用。
const NAV_INSET := 6.0

@export var level_name: String = ""
## 房间在世界坐标里的矩形范围，用来把相机限制在关卡内
@export var room_rect: Rect2 = Rect2(0, 0, 768, 448)

@onready var blood: Node2D = $Blood
@onready var player: Player = $Player
@onready var floor_layer: TileMapLayer = $Floor
@onready var walls: TileMapLayer = $Walls

## 可通行格集合（运行时按 Floor / Walls 两层算出来）
var _walkable := {}
var _cell_size := 16.0
var _astar: AStarGrid2D = null
var navigation_revision := 0


func _enter_tree() -> void:
	# 在 _enter_tree 就注册进组：敌人是关卡的子节点，它们的 _ready 早于关卡的 _ready
	add_to_group("level")


func _ready() -> void:
	_build_grid()
	_normalize_character_layer()
	var feedback := Node2D.new()
	feedback.set_script(preload("res://scripts/fx/combat_feedback.gd"))
	feedback.name = "CombatFeedback"
	add_child(feedback)

	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.limit_left = int(room_rect.position.x)
		cam.limit_top = int(room_rect.position.y)
		cam.limit_right = int(room_rect.end.x)
		cam.limit_bottom = int(room_rect.end.y)


## 已经提醒过的关卡名。同一个关卡只警告一次 —— 重开关卡时会重新加载，
## 每次都刷一遍就变成噪音了。
static var _layer_warned: Dictionary = {}


## 保证"墙 < 人物"这个层级约定成立。
##
## 为什么要在代码里兜一道：尸体是压在**活人之下**的（见 enemy.gd 的 _corpse_z），
## 而那是按"活人的有效 z"现算的。如果关卡里 Player 漏设了 z_index
## （手工搭关卡时很容易漏），玩家的有效 z 就和墙一样是 0，
## 于是尸体**盖在玩家身上** —— 看起来像"尸体层级坏了"，其实是关卡少了一行。
##
## 这里发现不对就把玩家抬到敌人那一层（用绝对 z），并警告一次，让问题可见。
func _normalize_character_layer() -> void:
	if player == null:
		return
	var wall_z := _effective_z(walls)
	var was := _effective_z(player)
	if was > wall_z:
		return
	# 目标：和敌人容器同一层；没有敌人容器就退到"墙的上一层"
	var target := wall_z + 1
	var box := get_node_or_null("Enemies") as Node2D
	if box != null:
		target = _effective_z(box)
	player.z_as_relative = false
	player.z_index = target
	if not _layer_warned.has(name):
		_layer_warned[name] = true
		push_warning(("关卡 %s 的 Player 没有设 z_index（有效 z=%d，不高于墙的 %d）："
				+ "已自动抬到 %d。建议在编辑器里把 Player 的 Z Index 设成 %d —— "
				+ "否则玩家会被墙的图块盖住（玩家该和敌人同一层、且高于墙）。") % [
				name, was, wall_z, target, target])


## 尸体（敌人和玩家都一样）该用哪个绝对 z。
##
## 规则：**在地板之上、所有"立着的物体"之下**。
##
## 为什么这样分：地板和血迹贴花是"躺在地上"的，墙 / 门 / 人物是"立着"的。
## 尸体属于前者 —— 横在地上的东西不该挡住立着的门和墙，
## 更不该盖住还活着的人和敌人。
##
## 用"墙下两层"算，而不是写死数字：关卡层级可以整体平移，
## 写死就会像以前那样，换个关卡配置就莫名其妙盖住别人（这个坑踩过两次）。
func corpse_z() -> int:
	return _effective_z(walls) - 2


## 一个 Node2D 的**有效** z：沿父链累加 z_index，直到遇到 z_as_relative = false。
func _effective_z(n: Node2D) -> int:
	if n == null:
		return 0
	var total := 0
	var cur: Node = n
	while cur is Node2D:
		var n2 := cur as Node2D
		total += n2.z_index
		if not n2.z_as_relative:
			break
		cur = n2.get_parent()
	return total


## 按 Floor / Walls 两层算出"哪些格能走"，并建好一张网格 A*。
##
## 为什么不用 NavigationServer2D / NavigationAgent2D：
## 导航图的多边形合并规则很挑 —— 同一个 NavigationPolygon 内的多边形**必须边完全重合**
## 才会被合并成一片（edge_connection_margin 只作用于不同 region 之间）。
## 而"两格宽的门洞"这种窄连接，只要相邻格形状差一点就会**静默连不上**，
## 表现是"敌人走到门口就停住、怎么都不进门"，而且不报任何错。
## 网格 A* 完全确定、可测试，关卡才几千格，性能毫无压力。
## 静态家具运行时增删/移动后显式刷新；清空旧集合，否则移走家具仍留隐形障碍。
func rebuild_navigation() -> void:
	_build_grid()


func _build_grid() -> void:
	navigation_revision += 1
	_walkable.clear()
	_astar = null
	if floor_layer == null or walls == null:
		return

	if floor_layer.tile_set != null:
		_cell_size = (floor_layer.global_transform.x * floor_layer.tile_set.tile_size.x).length()

	var solid := {}
	for cell in walls.get_used_cells():
		solid[world_to_cell(walls.to_global(walls.map_to_local(cell)))] = true
	# 家具只扣除走路网格，不加入视线和子弹掩码；否则低矮家具会变成墙。
	for prop in get_tree().get_nodes_in_group("navigation_furniture"):
		if is_ancestor_of(prop):
			for cell: Vector2i in prop.occupied_cells(floor_layer):
				solid[cell] = true
	for cell in floor_layer.get_used_cells():
		if not solid.has(cell):
			_walkable[cell] = true

	if _walkable.is_empty():
		printerr("关卡里没有任何可通行的地板格，敌人不会移动：", name)
		return

	var min_c := Vector2i(1 << 29, 1 << 29)
	var max_c := Vector2i(-(1 << 29), -(1 << 29))
	for cell: Vector2i in _walkable:
		min_c = Vector2i(mini(min_c.x, cell.x), mini(min_c.y, cell.y))
		max_c = Vector2i(maxi(max_c.x, cell.x), maxi(max_c.y, cell.y))

	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(min_c, max_c - min_c + Vector2i.ONE)
	_astar.cell_size = Vector2(_cell_size, _cell_size)
	# 允许走对角（但**不许切墙角**）：只用直角的话，斜向目标会变成"楼梯形"路径，
	# 敌人一格一格地追格子中心，看起来就是左右扭着走。
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for y in range(min_c.y, max_c.y + 1):
		for x in range(min_c.x, max_c.x + 1):
			_astar.set_point_solid(Vector2i(x, y), not _walkable.has(Vector2i(x, y)))


func world_to_cell(p: Vector2) -> Vector2i:
	return floor_layer.local_to_map(floor_layer.to_local(p))


func cell_center(c: Vector2i) -> Vector2:
	return floor_layer.to_global(floor_layer.map_to_local(c))


func is_walkable_cell(c: Vector2i) -> bool:
	return _walkable.has(c)


func walkable_cell_count() -> int:
	return _walkable.size()


## 返回一条从 from 到 to 的**拐点列**（含终点）。找不到路就返回空数组。
##
## ⚠️ 一定要做"拉直"（string-pulling）：A* 给的是一格一格的中心点，
## 直接照走的话，斜向目标会走成楼梯形、沿墙走会一格格贴边 ——
## 表现出来就是敌人左右扭着走，非常难看。
## 这里从头开始，每次尽量连到"最远的、中间没有墙的那一格"，
## 中间那些点全部丢掉，于是路径变成几条长直线。
func find_path(from: Vector2, to: Vector2, body: CharacterBody2D = null) -> PackedVector2Array:
	var out := PackedVector2Array()
	if _astar == null:
		return out
	var a := _nearest_walkable(world_to_cell(from))
	var b := _nearest_walkable(world_to_cell(to))
	if not _walkable.has(a) or not _walkable.has(b):
		return out
	var cells: Array = _astar.get_id_path(a, b)
	if cells.is_empty():
		return out

	# 拉直：i 是当前站定的格子，每次跳到"直线走得通"的最远格子
	var i := 0
	while i < cells.size() - 1:
		var j: int = cells.size() - 1
		while j > i + 1 and (not _line_clear(cells[i], cells[j]) or (body != null and not navigation_segment_clear(cell_center(cells[i]), cell_center(cells[j]), body))):
			j -= 1
		out.append(cell_center(cells[j]))
		i = j
	if out.is_empty():
		out.append(cell_center(cells[cells.size() - 1]))
	return out


## 两格之间能不能直线走过去。
## 用 Bresenham 逐格检查；走对角步时要求**不切墙角**（两侧都能走），
## 这样拉直出来的直线不会从墙角上蹭过去。
func _line_clear(a: Vector2i, b: Vector2i) -> bool:
	var x := a.x
	var y := a.y
	var dx := absi(b.x - a.x)
	var dy := absi(b.y - a.y)
	var sx := signi(b.x - a.x)
	var sy := signi(b.y - a.y)
	var err := dx - dy
	while true:
		if not _walkable.has(Vector2i(x, y)):
			return false
		if x == b.x and y == b.y:
			return true
		var e2 := err * 2
		var step_x := false
		var step_y := false
		if e2 > -dy:
			err -= dy
			x += sx
			step_x = true
		if e2 < dx:
			err += dx
			y += sy
			step_y = true
		if step_x and step_y:
			# 对角步：任一侧被挡就是切角；否则路径拉直后会卡在家具角上
			if not _walkable.has(Vector2i(x - sx, y)) \
					or not _walkable.has(Vector2i(x, y - sy)):
				return false
	return true


## 起点/终点可能落在墙上（比如噪声点贴着墙），就近找一个可通行格
func _nearest_walkable(c: Vector2i) -> Vector2i:
	if _walkable.has(c):
		return c
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := c + Vector2i(dx, dy)
				if _walkable.has(n):
					return n
	return c


## 血迹是**永久贴花**，画在专属背景层 Blood 上。
## 层级：地板(-10) < 血迹(-5) < 尸体(墙-2) < 掉落武器(-1) < 墙(0) < 人物(2)。
func add_blood(pos: Vector2) -> void:
	var pool := Node2D.new()
	pool.set_script(preload("res://scripts/fx/blood_pool.gd"))
	pool.level = self
	pool.position = blood.to_local(pos)
	blood.add_child(pool)

## 身体扫掠而非中心射线；门不挡移动，家具只在这项移动查询里参与。
func navigation_segment_clear(from: Vector2, to: Vector2, body: CharacterBody2D) -> bool:
	var collision := body.get_node("CollisionShape2D") as CollisionShape2D
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = collision.shape
	q.transform = collision.global_transform
	q.transform.origin += from - body.global_position
	q.motion = to - from
	q.collision_mask = 257
	q.exclude = [body.get_rid()]
	q.margin = 0.1
	return get_world_2d().direct_space_state.cast_motion(q)[0] >= 0.999


func _blob_poly(radius: float, segments: int, jitter: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var phase: float = randf() * TAU
	for i in segments:
		var a: float = TAU * float(i) / float(segments) + phase
		var r: float = radius * randf_range(1.0 - jitter, 1.0 + jitter)
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts
