class_name ActorAppearance
extends Resource
## 美术交付 SpriteFrames 即可；无正式素材时用可辨认的临时样板，不影响角色状态。
@export var appearance_id: String = "player_sample"
@export var upper_frames: SpriteFrames
@export var legs_frames: SpriteFrames
@export var arms_frames: SpriteFrames
@export var corpse_frames: SpriteFrames
@export var pixels_per_unit: float = 4.0
@export var body_origin_px := Vector2(32, 32)
@export var corpse_origin_px := Vector2(64, 64)
@export var outfit := Color(0.12, 0.52, 0.65)
@export var accent := Color(0.65, 0.95, 1.0)
@export var death_duration: float = 0.20
@export var rise_duration: float = 0.18
@export var feedback_duration: float = 0.14

func frames_for(part: String) -> SpriteFrames:
	var supplied: SpriteFrames
	match part:
		"upper": supplied = upper_frames
		"legs": supplied = legs_frames
		"arms": supplied = arms_frames
		"corpse": supplied = corpse_frames
	var fallback := VisualSamples.actor_frames(appearance_id, part, outfit, accent)
	if supplied == null:
		return fallback
	# 正式素材可分批交付；缺一个片段不能让整个上身消失，也不能改共享导入资源。
	var result := supplied.duplicate() as SpriteFrames
	for clip: StringName in fallback.get_animation_names():
		if result.has_animation(clip) and result.get_frame_count(clip) > 0:
			continue
		if result.has_animation(clip):
			result.remove_animation(clip)
		result.add_animation(clip)
		result.set_animation_loop(clip, fallback.get_animation_loop(clip))
		result.set_animation_speed(clip, fallback.get_animation_speed(clip))
		for index in range(fallback.get_frame_count(clip)):
			result.add_frame(clip, fallback.get_frame_texture(clip, index), fallback.get_frame_duration(clip, index))
	return result
