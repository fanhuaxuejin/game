extends Node2D
## 固定轮廓只生成一次，逐帧改变半径，避免扩散时边缘乱跳。墙和地板只在生成时裁剪。
const GROW_TIME := 6.0
const START_RADIUS := 3.0
const MAX_RADIUS := 18.0
var elapsed := 0.0
var radius := START_RADIUS
var limits := PackedFloat32Array()
var directions := PackedVector2Array()
var level: Node2D

func _ready() -> void:
	add_to_group("blood_pools")
	for i in range(32):
		var dir := Vector2.RIGHT.rotated(TAU * i / 32.0)
		var reach := MAX_RADIUS * randf_range(0.82, 1.0)
		var q := PhysicsRayQueryParameters2D.create(global_position, global_position + dir * reach, 1)
		q.hit_from_inside = true
		var hit := get_world_2d().direct_space_state.intersect_ray(q)
		if not hit.is_empty(): reach = maxf(0, global_position.distance_to(hit.position) - 0.5)
		for step in range(1, int(ceil(reach)) + 1):
			var cell: Vector2i = level.world_to_cell(global_position + dir * step)
			if level.floor_layer.get_cell_source_id(cell) == -1:
				reach = float(step - 1)
				break
		directions.append(dir)
		limits.append(reach)
	queue_redraw()

func _process(delta: float) -> void:
	elapsed = minf(elapsed + delta, GROW_TIME)
	radius = lerpf(START_RADIUS, MAX_RADIUS, elapsed / GROW_TIME)
	queue_redraw()
	if elapsed >= GROW_TIME: set_process(false)

func _draw() -> void:
	var points := PackedVector2Array()
	for i in range(directions.size()): points.append(directions[i] * minf(radius, limits[i]))
	if points.size() > 2:
		# 三角扇允许墙边的部分半径为零，不让退化多边形触发三角化错误。
		for i in range(points.size()):
			var a := points[i]
			var b := points[(i+1)%points.size()]
			if absf(a.cross(b)) > 0.01:
				draw_colored_polygon(PackedVector2Array([Vector2.ZERO,a,b]), Color(0.36,0.025,0.045,0.85))
