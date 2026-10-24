@tool
class_name FurnitureProp
extends StaticBody2D
## 只描述静态占地；显示阴影不纳入导航，不能拿贴图边缘当碰撞轮廓。

func _enter_tree() -> void:
	add_to_group("navigation_furniture")


func occupied_cells(floor_map: TileMapLayer) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var shape_node := get_node("CollisionShape2D") as CollisionShape2D
	if shape_node.disabled:
		return result
	var shape := shape_node.shape as RectangleShape2D
	var half := shape.size * 0.5
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]:
		var p := floor_map.to_local(shape_node.to_global(corner))
		low = low.min(p)
		high = high.max(p)
	# 只接受直角旋转；缩一丝边界，避免恰在格线上时多占旁边一整格。
	var first := floor_map.local_to_map(low + Vector2(0.01, 0.01))
	var last := floor_map.local_to_map(high - Vector2(0.01, 0.01))
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			result.append(Vector2i(x, y))
	return result


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not is_equal_approx(scale.x, 1.0) or not is_equal_approx(scale.y, 1.0):
		warnings.append("家具根节点保持scale=1，只缩放Sprite；否则实际占地会改变。")
	if absf(wrapf(rotation + PI * 0.25, 0.0, PI * 0.5) - PI * 0.25) > 0.001:
		warnings.append("家具仅支持0/90/180/270度旋转，斜放会让导航包围盒多占格子。")
	return warnings
