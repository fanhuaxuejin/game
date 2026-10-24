class_name WeaponArt
extends RefCounted
## 持有、飞行、落地共用轮廓，避免刀投出去却变成一把手枪。
static func apply(model: Polygon2D, data: WeaponData) -> void:
	model.position = Vector2.ZERO
	model.rotation = 0.0
	model.visible = data != null
	if data == null:
		return
	match data.visual_id:
		"knife", "dagger":
			model.polygon = PackedVector2Array([Vector2(5,-2),Vector2(11,-2),Vector2(11,-3),Vector2(25,-2),Vector2(28,0),Vector2(25,2),Vector2(11,3),Vector2(11,2),Vector2(5,2)])
			model.color = Color(0.85, 0.96, 1.0)
		"machete":
			model.polygon = PackedVector2Array([Vector2(5,-2),Vector2(11,-2),Vector2(23,-3.5),Vector2(28,-2),Vector2(27,2.5),Vector2(12,3.5),Vector2(11,2),Vector2(5,2)])
			model.color = Color(0.75, 0.85, 0.79)
		"katana":
			model.polygon = PackedVector2Array([Vector2(5,-1),Vector2(12,-1),Vector2(12,-3),Vector2(13,-3),Vector2(13,-1),Vector2(28,-2),Vector2(27,0),Vector2(13,1),Vector2(13,3),Vector2(12,3),Vector2(12,1),Vector2(5,1)])
			model.color = Color(0.91, 0.87, 0.98)
		"smg":
			model.polygon = PackedVector2Array([Vector2(3,-3),Vector2(17,-3),Vector2(22,-1),Vector2(22,1),Vector2(13,2),Vector2(12,7),Vector2(9,7),Vector2(9,2),Vector2(3,2)])
			model.color = Color(0.65, 0.85, 0.65)
		"shotgun":
			model.polygon = PackedVector2Array([Vector2(2,-2),Vector2(26,-2),Vector2(26,2),Vector2(9,2),Vector2(5,5),Vector2(2,4)])
			model.color = Color(0.85, 0.65, 0.43)
		_:
			model.polygon = PackedVector2Array([Vector2(4,-2),Vector2(18,-2),Vector2(18,2),Vector2(9,2),Vector2(8,5),Vector2(5,5)])
			model.color = Color(0.8, 0.85, 0.94)

static func tip(data: WeaponData) -> float:
	match data.visual_id:
		"knife", "dagger", "machete", "katana": return 28.0
		"smg": return 22.0
		"shotgun": return 26.0
	return 18.0
