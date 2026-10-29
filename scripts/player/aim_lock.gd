extends RefCounted
## 选取与追踪都在玩家_process调用，不让物理帧和显示帧各持一个目标。
var actor: Node2D
var target_ref: WeakRef
var enabled := false
var toggle_requested := false
var cycle_requested := false
var reticle: Node2D
var margin := 24.0
var release_scale := 1.5

func target() -> Node2D:
	return target_ref.get_ref() as Node2D if target_ref != null else null

func set_target(value: Node2D, force_notify := false) -> void:
	var previous := target()
	target_ref = weakref(value) if value != null else null
	if previous != value or force_notify:
		var events := actor.get_node_or_null("/root/Events")
		if events != null:
			events.lock_changed.emit(value)

func clear() -> void:
	enabled = false
	toggle_requested = false
	cycle_requested = false
	set_target(null, true)

func camera_rect(scale_factor := 1.0) -> Rect2:
	var camera := actor.get_viewport().get_camera_2d()
	if camera == null:
		return Rect2()
	var size := actor.get_viewport_rect().size / camera.zoom * scale_factor
	return Rect2(camera.get_screen_center_position() - size * 0.5, size)

func valid(value: Node2D) -> bool:
	return is_instance_valid(value) and value.is_inside_tree() and not value.is_queued_for_deletion() and value.is_in_group("enemies") and value.global_position.distance_squared_to(actor.global_position) > 1.0

func visible_target(value: Node2D) -> bool:
	# 近闭门的64层封口也必须挡锁定，避免从肉眼不可见的门缝选人。
	var ray := PhysicsRayQueryParameters2D.create(actor.global_position, value.global_position, 193)
	ray.hit_from_inside = true
	return actor.get_world_2d().direct_space_state.intersect_ray(ray).is_empty()

func candidates() -> Array[Node2D]:
	var result: Array[Node2D] = []
	# 俯视相机矩形决定候选范围，不用人物朝向、敌人视锥或武器射程过滤。
	var bounds := camera_rect().grow(margin)
	for enemy: Node2D in actor.get_tree().get_nodes_in_group("enemies"):
		if valid(enemy) and bounds.has_point(enemy.global_position) and visible_target(enemy):
			result.append(enemy)
	result.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		var da := actor.global_position.distance_squared_to(a.global_position)
		var db := actor.global_position.distance_squared_to(b.global_position)
		return a.get_instance_id() < b.get_instance_id() if is_equal_approx(da, db) else da < db)
	return result

func update() -> Node2D:
	if toggle_requested:
		enabled = not enabled
		if not enabled:
			set_target(null, true)
	if enabled:
		var current := target()
		if not valid(current) or not visible_target(current) or not camera_rect(release_scale).has_point(current.global_position):
			# 没有目标只清空框，不能关闭功能，否则空场开启后敌人入画也不会自动锁定。
			var choices := candidates()
			set_target(choices[0] if not choices.is_empty() else null, target_ref != null)
		elif cycle_requested:
			var choices := candidates()
			if not choices.is_empty():
				set_target(choices[(choices.find(current) + 1) % choices.size()])
	toggle_requested = false
	cycle_requested = false
	return target()
