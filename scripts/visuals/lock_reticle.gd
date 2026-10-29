extends Node2D
## 世界画布中的反馈，不能挂在CanvasLayer下直接使用世界坐标。
var target_ref: WeakRef
var elapsed := 0.0

func _ready() -> void:
	z_as_relative = false
	z_index = 100
	top_level = true
	visible = false
	get_node("/root/Events").lock_changed.connect(set_target)

func set_target(value: Node2D) -> void:
	target_ref = weakref(value) if value != null else null
	visible = value != null
	if value != null:
		global_position = value.global_position
	queue_redraw()

func _process(delta: float) -> void:
	var value: Node2D = target_ref.get_ref() as Node2D if target_ref != null else null
	visible = is_instance_valid(value) and value.is_inside_tree() and value.is_in_group("enemies")
	if not visible:
		return
	global_position = value.global_position
	elapsed += delta
	scale = Vector2.ONE * (1.0 + sin(elapsed * 5.0) * 0.06)

func _draw() -> void:
	for corner in [Vector2(-1,-1), Vector2(1,-1), Vector2(-1,1), Vector2(1,1)]:
		var p: Vector2 = corner * 10.0
		draw_polyline(PackedVector2Array([p - Vector2(corner.x * 4.0,0), p, p - Vector2(0,corner.y * 4.0)]), Color(1.0,0.75,0.2), 1.0)
