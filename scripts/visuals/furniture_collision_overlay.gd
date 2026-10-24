extends Node2D
## 预览专用，轮廓读取当前碰撞体，不能用另写的装饰尺寸冒充真实碰撞。
func _draw() -> void:
	for prop in get_tree().get_nodes_in_group("navigation_furniture"):
		if not get_parent().is_ancestor_of(prop):
			continue
		var collision := prop.get_node("CollisionShape2D") as CollisionShape2D
		var half: Vector2 = collision.shape.size * 0.5
		var points := PackedVector2Array()
		for p in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y), Vector2(-half.x, -half.y)]:
			points.append(to_local(collision.to_global(p)))
		draw_polyline(points, Color(0.1, 0.7, 0.45), 0.8)
