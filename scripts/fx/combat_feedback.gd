extends Node2D
## 每关一个反馈组件，正式游戏与F6共用；随关卡释放，不依赖Main，也不保存死者强引用。
const POOL := preload("res://scripts/fx/blood_pool.gd")
const BULLET_DOTS := 16
const EXECUTION_DOTS := 4
var level: Node2D
var deaths := {}
var burst_count := 0

func _ready() -> void:
	level = get_parent()
	Events.hit_resolved.connect(_on_hit)
	Events.actor_died.connect(_on_death)

func _on_hit(victim: Node2D, point: Vector2, direction: Vector2, cause: StringName, lethal: bool) -> void:
	if not level.is_ancestor_of(victim): return
	if cause == &"execution":
		Audio._at("impact", point, -9.0, 0.14)
		burst(point, direction, EXECUTION_DOTS, 6.0, 18.0)
	elif cause == &"bullet" and lethal:
		burst(point, direction, BULLET_DOTS, 18.0, 72.0)

func _on_death(victim: Node2D, point: Vector2, _direction: Vector2, _cause: StringName) -> void:
	if not level.is_ancestor_of(victim) or deaths.has(victim.get_instance_id()): return
	deaths[victim.get_instance_id()] = true
	level.add_blood(point)

func burst(point: Vector2, direction: Vector2, count: int, near: float, far: float) -> void:
	burst_count += 1
	for i in range(count):
		var half := randf_range(1.5,3.5)
		var dot := Polygon2D.new()
		dot.polygon = PackedVector2Array([Vector2(-half,-half),Vector2(half,-half),Vector2(half,half),Vector2(-half,half)])
		dot.color = Color(0.62,0.05,0.07).lightened(randf_range(0.0,0.25))
		dot.z_as_relative = false
		dot.z_index = level.corpse_z() + 1
		add_child(dot)
		dot.global_position = point
		dot.add_to_group("blood_drops")
		var dir := direction.normalized().rotated(randf_range(-0.9,0.9))
		if dir.is_zero_approx(): dir = Vector2.RIGHT.rotated(randf()*TAU)
		var end := point + dir * randf_range(near,far)
		var ray := PhysicsRayQueryParameters2D.create(point,end,193)
		ray.hit_from_inside = true
		var hit := get_world_2d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty(): end = hit.position
		var tween := dot.create_tween().set_parallel(true)
		var duration := randf_range(0.26,0.42)
		tween.tween_property(dot,"global_position",end,duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(dot,"modulate:a",0.0,duration)
		tween.chain().tween_callback(dot.queue_free)
