class_name ActorVisual
extends Node2D
## 只消费状态、速度与攻击进度；不回调伤害、弹药、死亡或掉落逻辑。
@export var appearance: ActorAppearance
@onready var legs: AnimatedSprite2D = $LegRig/Legs
@onready var upper: AnimatedSprite2D = $UpperRig/Upper
@onready var arms: AnimatedSprite2D = $UpperRig/Arms
@onready var corpse: AnimatedSprite2D = $Corpse
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var weapon_mount: Marker2D = $UpperRig/WeaponMount
var locomotion: StringName = &"idle"
var life_state: StringName = &"live"
var death_play_count := 0
var last_action: StringName = &"idle"
var action_phase: StringName = &"idle"
var phase_progress := 0.0
var _weapon: WeaponData
var _dead := false
var _stunned := false
var _life_elapsed := 0.0
var _feedback_left := 0.0
var _facing_angle := 0.0
var _weapon_view: WeaponView

func _ready() -> void:
	if appearance == null:
		appearance = ActorAppearance.new()
	set_appearance(appearance)

func set_appearance(value: ActorAppearance) -> void:
	appearance = value
	if not is_instance_valid(upper):
		return
	for part: String in ["legs", "upper", "arms", "corpse"]:
		var sprite: AnimatedSprite2D = get(part)
		sprite.sprite_frames = appearance.frames_for(part)
		sprite.scale = Vector2.ONE / maxf(appearance.pixels_per_unit, 0.001)
		sprite.centered = false
		sprite.offset = -(appearance.corpse_origin_px if part == "corpse" else appearance.body_origin_px)
	_sync_visibility()
	if _dead:
		_sample(corpse, "corpse", 1.0)
	else:
		_idle()
	_build_feedback()

func bind_weapon_view(view: WeaponView) -> void:
	_weapon_view = view

func set_weapon(data: WeaponData) -> void:
	_weapon = data
	if not _dead and not _stunned:
		_idle()

func update_state(velocity: Vector2, world_aim: float, max_speed: float, stunned: bool) -> void:
	if _dead:
		return
	_facing_angle = world_aim
	$UpperRig.rotation = world_aim - global_rotation
	$LegRig.rotation = world_aim - global_rotation
	corpse.rotation = world_aim - global_rotation
	set_stunned(stunned)
	var relative := velocity.rotated(-world_aim)
	if relative.length_squared() < 1.0:
		locomotion = &"idle"
	elif absf(relative.x) >= absf(relative.y):
		locomotion = &"forward" if relative.x >= 0.0 else &"backward"
	else:
		locomotion = &"strafe_right" if relative.y > 0.0 else &"strafe_left"
	legs.speed_scale = clampf(velocity.length() / maxf(max_speed, 0.001), 0.1, 2.0) if locomotion != &"idle" else 1.0
	if life_state == &"live":
		_play(legs, locomotion)

func set_stunned(value: bool) -> void:
	if _dead or value == _stunned:
		return
	_stunned = value
	_life_elapsed = 0.0
	life_state = &"stunned" if value else &"rising"
	last_action = &"idle"
	action_phase = &"idle"
	animation_player.stop()
	$UpperRig.position = Vector2.ZERO
	_sync_visibility()

func die() -> void:
	if _dead:
		return
	_dead = true
	death_play_count += 1
	life_state = &"dying"
	_life_elapsed = 0.0
	last_action = &"idle"
	action_phase = &"idle"
	animation_player.stop()
	$UpperRig.position = Vector2.ZERO
	legs.stop()
	upper.stop()
	arms.stop()
	_sync_visibility()
	_sample(corpse, "death", 0.0, "corpse")

func receive_pose(pose: Dictionary) -> void:
	if _dead or _stunned:
		return
	last_action = StringName(pose.get("kind", "idle"))
	action_phase = StringName(pose.get("phase", "idle"))
	phase_progress = float(pose.get("progress", 0.0))
	if last_action == &"idle":
		_idle()
	else:
		var clip := "%s_%s" % [last_action, action_phase]
		arms.rotation = float(pose.get("angle", 0.0)) if last_action == &"melee" else 0.0
		var extension: float = pose.get("extension", 0.0)
		if action_phase == &"windup":
			extension *= phase_progress * 0.3
		arms.position = Vector2(maxf(0.0, float(pose.get("reach", 24.0)) - 6.5) * extension, 0) if last_action == &"push" else Vector2.ZERO
		_sample(upper, clip, phase_progress, _idle_name())
		_sample(arms, clip, phase_progress, _idle_name())

func show_effect(action: StringName) -> void:
	if _dead or _stunned:
		return
	last_action = action
	action_phase = &"feedback"
	_feedback_left = appearance.feedback_duration
	if animation_player.has_animation(action):
		# 后坐沿开火方向退，不能让朝左开枪的人仍向屏幕左侧后坐。
		var anim := animation_player.get_animation(action)
		var kick := Vector2(-1, 0) if action == &"shoot" else Vector2(1, 0)
		anim.track_set_key_value(0, 1, kick.rotated(_facing_angle - global_rotation))
		animation_player.play(action)
		animation_player.advance(0.0)
	_sample(upper, action, 0.0, _idle_name())
	_sample(arms, action, 0.0, _idle_name())

func _process(delta: float) -> void:
	# 挂点只传递显示位移；攻击采样始终以角色身体为原点，不跟随美术后坐力。
	if is_instance_valid(_weapon_view):
		_weapon_view.set_mount_offset((_weapon_view.get_parent() as Node2D).to_local(weapon_mount.global_position))
	_life_elapsed += delta
	if _dead:
		if life_state == &"dying":
			var progress := clampf(_life_elapsed / maxf(appearance.death_duration, 0.001), 0.0, 1.0)
			_sample(corpse, "death", progress, "corpse")
			if progress >= 1.0:
				life_state = &"corpse"
				_sample(corpse, "corpse", 1.0)
		return
	if life_state == &"stunned":
		_sample(corpse, "stun", fmod(_life_elapsed, 1.0), "corpse")
		return
	if life_state == &"rising":
		var progress := clampf(_life_elapsed / maxf(appearance.rise_duration, 0.001), 0.0, 1.0)
		_sample(corpse, "rise", progress, "corpse")
		if progress >= 1.0:
			life_state = &"live"
			_sync_visibility()
			_idle()
		return
	if action_phase == &"feedback":
		_feedback_left = maxf(_feedback_left - delta, 0.0)
		var progress := 1.0 - _feedback_left / maxf(appearance.feedback_duration, 0.001)
		_sample(upper, last_action, progress, _idle_name())
		_sample(arms, last_action, progress, _idle_name())
		if _feedback_left <= 0.0:
			_idle()

func _sync_visibility() -> void:
	var fallen := life_state != &"live"
	$LegRig.visible = not fallen
	$UpperRig.visible = not fallen
	corpse.visible = fallen

func _idle_name() -> StringName:
	if _weapon == null:
		return &"idle_empty"
	return &"idle_melee" if _weapon.kind == WeaponData.Kind.MELEE else &"idle_firearm"

func _idle() -> void:
	if _dead or life_state != &"live":
		return
	last_action = &"idle"
	action_phase = &"idle"
	arms.rotation = 0.0
	arms.position = Vector2.ZERO
	_play(upper, _idle_name())
	_play(arms, _idle_name())
	_play(legs, locomotion)

func _play(sprite: AnimatedSprite2D, clip: StringName) -> void:
	if sprite.sprite_frames.has_animation(clip) and (sprite.animation != clip or not sprite.is_playing()):
		sprite.play(clip)

func _sample(sprite: AnimatedSprite2D, clip: StringName, progress: float, fallback: StringName = &"corpse") -> void:
	if not sprite.sprite_frames.has_animation(clip):
		clip = fallback
	if not sprite.sprite_frames.has_animation(clip):
		return
	sprite.stop()
	sprite.animation = clip
	var count := sprite.sprite_frames.get_frame_count(clip)
	if count > 0:
		sprite.frame = mini(count - 1, int(clampf(progress, 0.0, 1.0) * count))

func _build_feedback() -> void:
	# 这些轨道只改显示属性，绝不写方法轨道去调用开枪/扣弹/掉落。
	var library := AnimationLibrary.new()
	if animation_player.has_animation_library(""):
		animation_player.stop()
		animation_player.remove_animation_library("")
	for action: String in ["shoot", "throw", "pickup", "execute"]:
		var anim := Animation.new()
		anim.length = appearance.feedback_duration
		var track := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(track, NodePath("UpperRig:position"))
		anim.track_insert_key(track, 0.0, Vector2.ZERO)
		var kick := Vector2(-1, 0) if action == "shoot" else Vector2(1, 0)
		anim.track_insert_key(track, anim.length * 0.4, kick)
		anim.track_insert_key(track, anim.length, Vector2.ZERO)
		library.add_animation(action, anim)
	animation_player.add_animation_library("", library)
