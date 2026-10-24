class_name WeaponView
extends Node2D
## 持有/地面/飞行显示共用这一层，不持有弹药，也不参与命中或物理形状计算。
var definition: WeaponData
var grounded := false
var using_fallback := true
var displayed_id := ""
var last_pose: Dictionary = {}
var profile: WeaponVisualData
var _mount_offset := Vector2.ZERO
@onready var fallback: Polygon2D = $Fallback
@onready var sprite: Sprite2D = $Sprite

func set_definition(data: WeaponData) -> void:
	definition = data
	displayed_id = data.visual_id if data != null else ""
	profile = data.visual_profile if data != null else null
	visible = data != null
	position = Vector2.ZERO
	rotation = 0.0
	if data == null:
		return
	var texture: Texture2D = _active_texture()
	using_fallback = texture == null
	sprite.visible = not using_fallback
	fallback.visible = using_fallback
	if using_fallback:
		WeaponArt.apply(fallback, data)
	else:
		sprite.texture = texture
		sprite.centered = false
		sprite.scale = Vector2.ONE / maxf(profile.pixels_per_unit, 0.001)
	_apply_anchor()

## 当前该用哪张图。这是"投影"问题，不是换肤：
##   手里拿着 → 从正上方看，只看得见枪的顶面（held_texture）
##   掉落/飞行 → 平躺在地上，看的是侧面轮廓（texture）
## 刀的两种投影几乎一样，所以只配 texture，走了 else 分支。
## 两张图锚点相同，所以切换不影响握持点、枪口和 28px 刀尖半径。
func _active_texture() -> Texture2D:
	if profile == null:
		return null
	return profile.get_held_texture() if not grounded else profile.get_texture()

func set_grounded(value: bool) -> void:
	grounded = value
	_apply_anchor()

func _apply_anchor() -> void:
	if definition == null:
		return
	if using_fallback:
		var bounds := Rect2(fallback.polygon[0], Vector2.ZERO)
		for point: Vector2 in fallback.polygon:
			bounds = bounds.expand(point)
		fallback.position = -bounds.get_center() if grounded else Vector2.ZERO
	else:
		sprite.texture = _active_texture()
		sprite.offset = -(profile.ground_center_px if grounded else profile.grip_px)

func muzzle_offset() -> Vector2:
	return profile.point_from_grip(profile.muzzle_px) if profile != null else Vector2(WeaponArt.tip(definition), 0)

func visual_tip() -> float:
	return profile.point_from_grip(profile.tip_px).x if profile != null else WeaponArt.tip(definition)

func receive_pose(pose: Dictionary) -> void:
	last_pose = pose.duplicate()
	_apply_pose()

func set_mount_offset(value: Vector2) -> void:
	_mount_offset = value
	_apply_pose()

func _apply_pose() -> void:
	if definition == null or grounded:
		return
	rotation = float(last_pose.get("angle", 0.0))
	var extension: float = last_pose.get("extension", 0.0)
	position = _mount_offset + Vector2(maxf(0.0, float(last_pose.get("reach", visual_tip())) - visual_tip()) * extension, 0).rotated(rotation)
