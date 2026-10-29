class_name WeaponView
extends Node2D
## 持有 / 地面 / 飞行显示共用这一层。不持有弹药，也不参与命中或物理形状计算。
##
## 这一层负责三件纯显示的事，都不影响玩法：
##   1. 投影切换：手里拿着看顶面（held_texture），躺着/飞着看侧面（texture）；
##   2. 手持姿态：斜一点、往手那一侧偏一点，别像焊在胸口上；
##   3. 落地可拾取的浮动 + 地面阴影，让人一眼看出"这东西能捡"。

## 落地浮动幅度：**素材像素**，角速度：弧度/秒。纯显示，拾取判定只看距离。
##
## ⚠️ 为什么浮动要改贴图 offset，而不改节点 position：
## 工程开了 `snap_2d_transforms_to_pixel`，节点位置会被吸附到**整世界像素**。
## 1 世界px = 2.7 屏幕px，2px 的浮动只剩 2~3 个档位 —— 看起来就是一顿一顿。
## `Sprite2D.offset` 走的是素材像素，1 档 = 0.675 屏幕px，档位多 4 倍。
##
## ⚠️ 但真正决定"顺不顺"的是**总行程有多少屏幕像素**（屏幕永远只能整像素跳）：
## 行程 8 屏幕px ≈ 半周期 8 个档位、每档 ~0.12 秒，刚好够读出连续运动。
## 所以幅度取 12 素材px（=3 世界px）。调小之前先想想档位会掉到几个。
const BOB_PX := 12.0
const BOB_SPEED := 3.6
## 轻微摇摆（度）。旋转**不受**像素吸附影响，是唯一能真正连续动的通道，
## 用来补垂直方向的台阶感。
const ROCK_DEG := 2.5

## ---- 挥砍视觉 ----
## 为什么要在显示层重画运动曲线：战斗模块输出的是**线性匀速**角度，
## 前摇直接把刀固定在弧线起点、后摇线性缩回去 —— 看起来像转盘，没有发力感。
## 这里只改"怎么动"，不改"什么时候算命中"：阶段与进度仍来自战斗模块。
##
## 两侧各多甩出几度，超出伤害弧一点，看起来才有余势。
const SWING_LEAD_DEG := 8.0
## 前摇时刀身从横握转向挥砍的顺刃方向的比例（0 = 完全横握，1 = 完全顺刃）。
const SWING_ALIGN_WINDUP := 0.35
## 刀光弧的透明度、内径比例、以及只覆盖最近扫过的多长一段弧。
## ⚠️ 刀光要画成**贴着刃口的一条窄带**，不能铺满整段扫过的扇形 ——
## 铺满会变成一块半透明的板子，看着像 UI 而不是打击感。
const TRAIL_ALPHA := 0.62
const TRAIL_INNER := 0.78
const TRAIL_SPAN := 0.45

var definition: WeaponData
var grounded := false
var using_fallback := true
var displayed_id := ""
var last_pose: Dictionary = {}
var profile: WeaponVisualData
var _mount_offset := Vector2.ZERO
## 视觉子节点的基准位置 / 基准贴图偏移。浮动是叠在它们上面的 ——
## 直接改子节点位置会把锚点算出来的位移（握持点 / 地面中心）覆盖掉。
var _base_pos := Vector2.ZERO
var _base_offset := Vector2.ZERO
var _bob_time := 0.0
## 本次挥砍的伤害弧半角（弧度）。由战斗模块输出的角度反推，跟随 `melee_arc_deg` 变化。
var _arc_half := deg_to_rad(45.0)
## 0 = 保持横握姿态，1 = 刀身顺着挥砍方向。手腕在挥砍里"转过来"的过程。
var _hold_blend := 0.0
@onready var fallback: Polygon2D = $Fallback
@onready var sprite: Sprite2D = $Sprite
@onready var shadow: Polygon2D = $Shadow
@onready var trail: Polygon2D = $Trail

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
	_apply_hold()

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
	_bob_time = 0.0
	_apply_anchor()
	_apply_hold()
	# 只有躺在地上才需要每帧算浮动；手持和飞行都交给静态变换。
	set_process(grounded)
	if not grounded:
		_visual().position = _base_pos

func _apply_anchor() -> void:
	if definition == null:
		return
	if using_fallback:
		var bounds := Rect2(fallback.polygon[0], Vector2.ZERO)
		for point: Vector2 in fallback.polygon:
			bounds = bounds.expand(point)
		_base_pos = -bounds.get_center() if grounded else Vector2.ZERO
		fallback.position = _base_pos
	else:
		sprite.texture = _active_texture()
		_base_offset = -(profile.ground_center_px if grounded else profile.grip_px)
		sprite.offset = _base_offset
		_base_pos = Vector2.ZERO

## 手持姿态：斜一点 + 往手那侧偏一点。
## ⚠️ 只改**显示子节点**的 rotation / position，绝不改 WeaponView 自己的 ——
## 挥击的 `position.length() + visual_tip() == 28` 和刀尖轨迹都读这一层。
func _apply_hold() -> void:
	shadow.visible = grounded
	if trail != null:
		trail.visible = false
	if grounded:
		shadow.rotation = 0.0
		shadow.scale = Vector2.ONE
		# 侧视枪身会把正下方的阴影整块挡住，往下挪一点才露得出来。
		shadow.position = Vector2(0.0, 2.2)
	_hold_blend = 0.0
	_apply_child_hold()

## 把"横握姿态"和"挥砍顺刃"混起来：站着时按 `held_tilt_deg` 横握；
## 挥砍过程中 `_hold_blend` 升到 1，手腕把刀身转成顺着挥砍方向 ——
## 这就是"转动接力"：起身/转身的余势直接接进挥砍，而不是从横握瞬间跳到斜砍。
func _apply_child_hold() -> void:
	var tilt := 0.0
	var shift := Vector2.ZERO
	if not grounded and definition != null and profile != null:
		var keep: float = 1.0 - _hold_blend
		tilt = deg_to_rad(profile.held_tilt_deg) * keep
		shift = profile.held_shift * keep
	sprite.rotation = tilt
	fallback.rotation = tilt
	if not grounded:
		_base_pos = shift
		_visual().position = _base_pos

func _visual() -> Node2D:
	return fallback if using_fallback else sprite

## 落地可拾取的上下浮动 + 阴影随高度收缩。只在 grounded 时跑。
func _process(delta: float) -> void:
	if not grounded or definition == null:
		return
	_bob_time += delta
	var hover: float = 0.5 + 0.5 * sin(_bob_time * BOB_SPEED)      # 0 贴地，1 最高
	var rock := deg_to_rad(ROCK_DEG) * sin(_bob_time * BOB_SPEED * 0.5)
	if using_fallback:
		# 回退多边形只能走世界坐标，会被像素吸附；它本来就是临时件，认了。
		fallback.position = _base_pos + Vector2(0.0, -BOB_PX * 0.25 * hover)
		fallback.rotation = rock
	else:
		sprite.offset = _base_offset + Vector2(0.0, -BOB_PX * hover)
		sprite.rotation = rock
	if shadow != null:
		# 阴影的缩放和透明度是浮点，不受像素吸附影响 —— 正好用来补平滑。
		var shrink: float = 1.0 - hover * 0.18
		shadow.scale = Vector2(shrink, shrink)
		shadow.modulate.a = 0.5 - hover * 0.12
		# 投掷时整把武器在自转，阴影要留在地面上，不能跟着转。
		shadow.global_rotation = 0.0

func muzzle_offset() -> Vector2:
	if profile == null:
		return Vector2(WeaponArt.tip(definition), 0)
	var point := profile.point_from_grip(profile.muzzle_px)
	if not grounded:
		# 手持会斜过来，火光锚点要跟着走，否则枪口贴在枪管外面。
		point = point.rotated(deg_to_rad(profile.held_tilt_deg)) + profile.held_shift
	return point

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
	var kind := StringName(last_pose.get("kind", &"idle"))
	if kind == &"idle":
		rotation = 0.0
		_hold_blend = 0.0
		if trail != null:
			trail.visible = false
	else:
		var phase := StringName(last_pose.get("phase", &"windup"))
		var progress := clampf(float(last_pose.get("progress", 0.0)), 0.0, 1.0)
		rotation = _swing_angle(phase, progress, float(last_pose.get("angle", 0.0)))
		_hold_blend = _swing_blend(phase, progress)
		_update_trail(phase, progress)
	_apply_child_hold()
	var extension: float = last_pose.get("extension", 0.0)
	position = _mount_offset + Vector2(maxf(0.0, float(last_pose.get("reach", visual_tip())) - visual_tip()) * extension, 0).rotated(rotation)

## 挥砍角度曲线。三段首尾相接，段内都做缓动，不用线性匀速：
##   前摇 0 → -(弧+余势)：快起慢收，像把刀甩到身后蓄力
##   有效 -(弧+余势) → +(弧+余势)：快起慢收（指数 2.4），起手快、收尾拖
##   后摇 +(弧+余势) → 0：快速收回并带一点回弹
## 弧半角从战斗模块输出的角度反推，`melee_arc_deg` 改了这里自动跟随。
func _swing_angle(phase: StringName, progress: float, pose_angle: float) -> float:
	if phase == &"windup":
		_arc_half = maxf(absf(pose_angle), deg_to_rad(5.0))
	var lead := deg_to_rad(SWING_LEAD_DEG)
	var end := _arc_half + lead
	match phase:
		&"windup":
			return lerpf(0.0, -end, 1.0 - pow(1.0 - progress, 2.0))
		&"active":
			return lerpf(-end, end, 1.0 - pow(1.0 - progress, 2.4))
		&"recovery":
			var back := 1.0 - pow(1.0 - progress, 3.0)
			var wobble := sin(progress * PI) * deg_to_rad(5.0) * (1.0 - progress)
			return lerpf(end, 0.0, back) + wobble
	return pose_angle

## 手腕转动：前摇转进来一点，有效段完全顺刃，后摇再转回横握。
func _swing_blend(phase: StringName, progress: float) -> float:
	match phase:
		&"windup":
			return lerpf(0.0, SWING_ALIGN_WINDUP, progress)
		&"active":
			return lerpf(SWING_ALIGN_WINDUP, 1.0, minf(1.0, progress * 3.0))
		&"recovery":
			return lerpf(1.0, 0.0, progress)
	return 0.0

## 刀光弧：从挥砍起点扫到当前刃角的一条弧形残影，越接近收尾越淡。
## 只给真刀做 —— 枪托砸人挥出一片光就变成魔法了。
func _update_trail(phase: StringName, progress: float) -> void:
	if trail == null:
		return
	var bladed: bool = definition != null and definition.kind == WeaponData.Kind.MELEE
	if not bladed or phase == &"windup":
		trail.visible = false
		return
	var radius: float = maxf(visual_tip(), 10.0)
	var inner: float = radius * TRAIL_INNER
	var swing_from: float = -(_arc_half + deg_to_rad(SWING_LEAD_DEG))
	var to: float = rotation
	# 只画最近扫过的那一段，后面拖长会变成一块板子。
	var from: float = lerpf(swing_from, to, TRAIL_SPAN)
	if absf(to - from) < 0.03:
		trail.visible = false           # 还没扫出角度，别画退化多边形
		return
	trail.visible = true
	# 抵消武器自身的旋转，回到挂点坐标系里画弧，弧心才落在身体原点。
	trail.rotation = -rotation
	var steps := 10
	var points := PackedVector2Array()
	for i in steps + 1:
		var a := lerpf(from, to, float(i) / float(steps))
		points.append(Vector2(cos(a), sin(a)) * radius)
	for i in range(steps, -1, -1):
		var a2 := lerpf(from, to, float(i) / float(steps))
		points.append(Vector2(cos(a2), sin(a2)) * inner)
	trail.polygon = points
	var fade: float = 1.0 - progress
	trail.modulate.a = TRAIL_ALPHA * fade if phase == &"active" else TRAIL_ALPHA * 0.6 * fade
