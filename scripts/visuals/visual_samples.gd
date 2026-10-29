class_name VisualSamples
extends RefCounted
## 仅用于接入验收的临时素材源。正式像素画由外部 SpriteFrames/PNG 资源替换。
static var _cache: Dictionary = {}

static func _rect(img: Image, box: Rect2i, color: Color) -> void:
	var clipped := box.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if clipped.has_area():
		img.fill_rect(clipped, color)

static func _outlined(img: Image, box: Rect2i, color: Color) -> void:
	_rect(img, box.grow(1), Color(0.06, 0.07, 0.10))
	_rect(img, box, color)

static func actor_frames(id: String, part: String, outfit: Color, accent: Color) -> SpriteFrames:
	var key := "%s/%s/%s/%s" % [id, part, outfit.to_html(), accent.to_html()]
	if _cache.has(key):
		return _cache[key]
	var result := SpriteFrames.new()
	result.remove_animation("default")
	var names: Array[String] = ["idle_empty", "idle_firearm", "idle_melee", "push_windup", "push_active", "push_recovery", "melee_windup", "melee_active", "melee_recovery", "shoot", "throw", "pickup", "execute", "stun", "rise"]
	if part == "legs":
		names = ["idle", "forward", "backward", "strafe_left", "strafe_right", "stun", "rise"]
	elif part == "corpse":
		names = ["death", "corpse", "stun", "rise"]
	for name: String in names:
		result.add_animation(name)
		var loop := name.begins_with("idle") or name in ["forward", "backward", "strafe_left", "strafe_right"]
		var count := 8 if name in ["forward", "backward", "strafe_left", "strafe_right"] else (1 if name == "corpse" else 4)
		result.set_animation_loop(name, loop)
		result.set_animation_speed(name, 12.0)
		for index in range(count):
			var img := _actor_image(part, name, index, count, outfit, accent)
			result.add_frame(name, ImageTexture.create_from_image(img))
	_cache[key] = result
	return result

static func _actor_image(part: String, action: String, index: int, count: int, outfit: Color, accent: Color) -> Image:
	var size := 128 if part == "corpse" else 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var phase := float(index) / float(maxi(count - 1, 1))
	var stride := int(round(sin(float(index) / float(maxi(count, 1)) * TAU) * 5.0))
	var dark := outfit.darkened(0.45)
	var skin := Color(0.78, 0.60, 0.47)
	if part == "corpse":
		var fall := phase if action == "death" else (1.0 - phase if action == "rise" else 1.0)
		var shift := int(round(fall * 7.0))
		_outlined(img, Rect2i(30, 47 - shift, 32, 13), dark)
		_outlined(img, Rect2i(25, 69 + shift, 35, 13), dark)
		_outlined(img, Rect2i(49, 43, 34, 40), outfit.darkened(0.25))
		_outlined(img, Rect2i(81, 54, 19, 20), skin.darkened(0.2))
		_rect(img, Rect2i(58, 46, 5, 34), accent.darkened(0.25))
		_outlined(img, Rect2i(55, 28, 12, 22), outfit)
		_outlined(img, Rect2i(67, 80, 12, 18), outfit)
		_rect(img, Rect2i(74, 61, 8, 6), Color(0.4, 0.06, 0.08))
	elif part == "legs":
		if action in ["idle", "stun", "rise"]:
			stride = 0
		if action == "backward":
			stride = -stride
		if action == "strafe_left":
			stride = -stride
		var sideways := action.begins_with("strafe")
		var left := Vector2i(stride if not sideways else 0, stride if sideways else 0)
		var right := -left
		_outlined(img, Rect2i(Vector2i(13, 19) + left, Vector2i(23, 9)), dark)
		_outlined(img, Rect2i(Vector2i(13, 36) + right, Vector2i(23, 9)), dark)
		_outlined(img, Rect2i(Vector2i(8, 18) + left, Vector2i(11, 11)), Color(0.09, 0.10, 0.13))
		_outlined(img, Rect2i(Vector2i(8, 35) + right, Vector2i(11, 11)), Color(0.09, 0.10, 0.13))
		_rect(img, Rect2i(Vector2i(11, 20) + left, Vector2i(3, 6)), accent.darkened(0.4))
	elif part == "upper":
		_outlined(img, Rect2i(24, 14, 22, 36), outfit)
		_rect(img, Rect2i(26, 17, 5, 29), accent)
		_rect(img, Rect2i(34, 16, 7, 31), outfit.darkened(0.2))
		_outlined(img, Rect2i(39, 23, 18, 18), skin)
		_rect(img, Rect2i(39, 23, 10, 18), dark)
		_rect(img, Rect2i(52, 26, 3, 12), accent)
		_rect(img, Rect2i(42, 28, 3, 8), Color(0.05, 0.07, 0.09))
		if action == "stun":
			_rect(img, Rect2i(55, 19, 3, 4), Color(1.0, 0.9, 0.2))
	else:
		var extension := 4 if action.ends_with("active") else (int(phase * 3.0) if action in ["throw", "pickup"] else 0)
		if action == "execute": extension = int(phase * 7.0)
		_outlined(img, Rect2i(30, 10, 12, 9), outfit)
		_outlined(img, Rect2i(30, 45, 12, 9), outfit)
		_outlined(img, Rect2i(40 + extension, 15, 13, 8), outfit)
		_outlined(img, Rect2i(40 + extension, 41, 13, 8), outfit)
		_rect(img, Rect2i(51 + extension, 17, 7, 6), skin)
		_rect(img, Rect2i(51 + extension, 41, 7, 6), skin)
	return img

static func weapon_texture(id: String) -> Texture2D:
	if id not in ["pistol", "knife", "dagger", "machete", "katana"]:
		return null
	var key := "weapon/" + id
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(128, 32, false, Image.FORMAT_RGBA8)
	var knife := id != "pistol"
	var points := PackedVector2Array([Vector2(5,-2),Vector2(11,-2),Vector2(11,-3),Vector2(25,-2),Vector2(28,0),Vector2(25,2),Vector2(11,3),Vector2(11,2),Vector2(5,2)]) if knife else PackedVector2Array([Vector2(4,-2),Vector2(18,-2),Vector2(18,2),Vector2(9,2),Vector2(8,5),Vector2(5,5)])
	var grip := Vector2(8, 16) if knife else Vector2(8, 8)
	if id == "machete":
		points = PackedVector2Array([Vector2(5,-2),Vector2(11,-2),Vector2(23,-3.5),Vector2(28,-2),Vector2(27,2.5),Vector2(12,3.5),Vector2(11,2),Vector2(5,2)])
	elif id == "katana":
		points = PackedVector2Array([Vector2(5,-1),Vector2(12,-1),Vector2(12,-3),Vector2(13,-3),Vector2(13,-1),Vector2(28,-2),Vector2(27,0),Vector2(13,1),Vector2(13,3),Vector2(12,3),Vector2(12,1),Vector2(5,1)])
	for y in range(32):
		for x in range(128):
			var local := (Vector2(x, y) - grip) / 4.0
			if Geometry2D.is_point_in_polygon(local, points):
				var color := Color(0.78, 0.88, 0.95) if knife else Color(0.35, 0.41, 0.46)
				if knife and local.x < 11:
					color = Color(0.25, 0.20, 0.16)
					if id == "katana" and x % 8 < 3:
						color = Color(0.75, 0.2, 0.3)
				elif y % 4 == 0:
					color = color.lightened(0.2)
				img.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(img)
	_cache[key] = texture
	return texture
