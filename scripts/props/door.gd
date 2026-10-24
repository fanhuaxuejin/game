class_name Door
extends Node2D
## 门。参考《迈阿密热线》，但门本身是**真的按角动力学在摆**，不是播一段动画：
##
##   - 谁推门，门就朝他**前进的方向**甩开（门局部 +Y 就是他推的方向）
##   - 门有角速度。**合页摩擦**让它慢慢减速，**回位弹簧**让它最终自己关上
##   - 甩到 ±open_angle 的极限角度时如果还有速度，就按 restitution **反弹**回来
##   - 门板是实心碰撞体（关着挡人 / 挡视线 / 挡子弹）
##   - 甩得够快时扫到谁就把谁**拍飞**；慢慢关上的门只是被挡住，不会穿过去
##
## 为什么不用"匀速转到目标角度"：那样没有惯性 —— 撞上去不觉得重，不会反弹，
## 也不会自己回位，本质就是一段补间动画。

const LAYER_PLAYER := 1 << 1
const LAYER_ENEMY := 1 << 2
const LAYER_CHARS := LAYER_PLAYER | LAYER_ENEMY

## 门洞宽度（像素）。生成器保证门洞是 2 格 = 32px。
const SPAN := 32.0
## 门板厚度。角色不与门板碰撞，铰链对齐门洞边缘避免关闭时漏视。
const THICK := 6.0
## 贴门判定的接触余量（每边外扩多少像素）。见 _touching_panel。
## 门板 6px 厚 → 探针 12px 厚："贴住门板"(0~3px 间隙) 算接触，
## "贴着墙从门洞旁走过"(约 5px 间隙) 不算。
const TOUCH_MARGIN := 3.0
## |angle| 超过这个值就算"推开了"（给外部查询用）
const OPEN_ENOUGH := 0.35

## 关门状态的门板方向：true = 横板（挡南北通行），false = 竖板（挡东西通行）
@export var horizontal: bool = true
## 极限角度。门最多开到这么大就会撞到门框
@export var open_angle: float = PI * 0.5
## 合页摩擦（1/秒）。角速度按这个比例衰减 —— 这就是"有阻力、速度慢慢降低"
@export var hinge_friction: float = 3.0
## 撞到死角（极限角度）后，根据**剩下的速度**按这个比例反弹
@export var restitution: float = 0.40
## 推力 → 角加速度（每次撞击给门的角速度/方向）
@export var push_gain: float = 0.60
## 就算贴住门、速度被碰撞打成 0 了也仍然推得动的最小推力
@export var min_push: float = 220.0
## 角速度超过这个，撞到人才会把人**撞晕**（太慢的门只是从人身上扫过去）
@export var stun_speed: float = 2.2
## 撞晕时的击退力量 = stun_power × 角速度 × 力臂
@export var stun_power: float = 1.2
## 开门噪声半径。**默认 0 = 开门不出声**。
##
## 为什么默认关掉：噪声走的是"听觉"，**不受视锥限制**。
## 只要开门有声，敌人哪怕背对着门、完全看不见你，也会立刻警觉并走到门口
## （实测：敌人 state=ALERT 而 can_see_player=false）。玩家体验就是
## "一进门就被光速发现，哪怕我在它盲区"。
## 想让门重新变吵（比如做"声东击西"），把这个值调大即可。
@export var noise_radius: float = 0.0

## 门板当前角度（0 = 关着）
var angle: float = 0.0
## 角速度（弧度/秒）
var omega: float = 0.0
## 是否被推开过（|angle| 曾超过 OPEN_ENOUGH）
var is_open: bool = false

var _pushers := {}
var _noise_done := false
var _noise_source: Node = null
## 最近一个推门的人。用来判断"这扇门算谁的" —— 自己人不会被自己人的门拍死。
var _last_pusher: Node = null
## 这一帧净推力方向（-1 / 0 / +1）。用来判断"撞到死角时是不是还在往里推"。
var _push_dir: float = 0.0

@onready var hinge: Node2D = $Hinge
@onready var panel: StaticBody2D = $Hinge/Panel
@onready var panel_shape: CollisionShape2D = $Hinge/Panel/CollisionShape2D
@onready var trigger: Area2D = $Trigger


func _ready() -> void:
	# 触发区只关心玩家和敌人。
	# 掩码里不含 world，所以门板自己不会挡住自己的触发区。
	trigger.collision_mask = LAYER_CHARS

	# Hinge 只是"铰链在哪"的位置标记，**它自己不旋转**。
	# 竖门：整个门旋转 90°，于是局部 +X 的门板变成朝着世界 +Y 的竖板。
	rotation = 0.0 if horizontal else PI * 0.5
	# 额外退半个厚度会在关门远端留下 3px 缝，导致隔门发现玩家。
	hinge.position = Vector2(-SPAN * 0.5, 0.0)
	_apply_angle()
	# 门一直跑物理：就算停着也要留意有没有人来推
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_gather_pushes(delta)

	# 阻力：角速度按比例衰减。**没有回位弹簧** —— 门不会自己弹回关门，
	# 撞开后停在哪就是哪（这是有意为之：弹簧会把正在过门的人夹住/拍回来）。
	omega -= omega * hinge_friction * delta

	var pushed := not _pushers.is_empty()
	# 慢到看不出来就停住；如果正好停在关门附近，顺手吸附到 0（消除残留的几度）
	if absf(omega) < 0.03 and not pushed:
		omega = 0.0
		_last_pusher = null
		if absf(angle) < 0.02:
			angle = 0.0
			_apply_angle()
		return

	var from := angle
	angle += omega * delta
	# 扫过这一段弧：撞到别人就把他**撞晕**（不杀，也不会把门挡住）
	_sweep(from, angle, omega)

	# 撞到死角：按剩下的速度反弹。但**还在往里推就顶住别弹**，
	# 否则有人一直推，门就会在死角高频抖个不停。
	var hit_limit := false
	if angle <= -open_angle:
		angle = -open_angle
		if _push_dir < 0.0:
			omega = 0.0
		else:
			hit_limit = absf(omega) > 0.8
			omega = _bounce(omega)
	elif angle >= open_angle:
		angle = open_angle
		if _push_dir > 0.0:
			omega = 0.0
		else:
			hit_limit = absf(omega) > 0.8
			omega = _bounce(omega)
	if hit_limit:
		# 撞到极限 = 一声闷响（给玩家听的，不惊动敌人）
		Events.door_moved.emit(global_position, 1.0)

	_apply_angle()
	if absf(angle) > OPEN_ENOUGH:
		is_open = true


## 把门板摆到当前角度。
##
## ⚠️ 关键：这里改的是**门板自己**的变换，绝对不要去转它的父节点 Hinge。
## Godot 的物理体只在**自己**的 transform 变化时才更新碰撞，
## 转父节点不会通知到子节点 —— 表现就是"门看着转开了、人却还是被挡在门口"，
## 而且不报任何错。这个坑踩过一次，改之前先想清楚。
func _apply_angle() -> void:
	panel.rotation = angle
	# 接近关闭时封住细缝，只挡视线；开门后仍按真实门板遮挡。
	$VisionSeal/CollisionShape2D.set_deferred("disabled", absf(angle) > OPEN_ENOUGH)
	# ⚠️ 门板的碰撞**永远启用**，绝对不要按角度去关它。
	#
	# 这里曾经有过一段"开到 OPEN_CLEAR(≈63°) 就关掉碰撞"的逻辑。那是门还占
	# world 层、会挡住角色走路时留下的 —— 当时是为了让打开的门不阻挡寻路。
	#
	# 现在门已经挪到独立的 door 层（角色根本不和它碰撞，见 Door.tscn），
	# 那条逻辑就只剩下副作用：
	#   门已经开到 63°~90°、门板明明横在眼前，子弹却从它身上穿过去。
	# 玩家看到的是"看得见的东西打不中"，这比"打开的门挡子弹"更糟。
	# 原则很简单：**门板在哪儿就挡哪儿**。


# ------------------------------------------------------------ 推门

## 谁在推门、往哪个方向推。
##
## 推力取"人的速度在**门局部 +Y** 方向上的分量"，也就是他**前进的方向** ——
## 往东走就把门往东推开。门局部 +Y 正是门板甩出去的方向，所以两者天然一致。
func _gather_pushes(delta: float) -> void:
	# 上一帧记住的方向要留着：贴住门之后 move_and_slide 会把速度打成 0，
	# 只看当前速度的话门会在人面前停住，把人关在门外。
	var previous := _pushers
	var current := {}
	_push_dir = 0.0

	for body in trigger.get_overlapping_bodies():
		if body == null:
			continue
		var local_y := 0.0
		var speed_sq := 0.0
		var v: Variant = body.get("velocity")
		if v is Vector2:
			# 用**门板**的朝向（而不是"门"的朝向）算推力方向。
			# 门板转开后，"过门"的移动方向与门板平行、垂直分量 ≈ 0，
			# 就不会再把门带动 —— 这是"从门洞中央穿过也会推门"的真正原因。
			local_y = (panel.global_transform.basis_xform_inv(v as Vector2)).y
			speed_sq = (v as Vector2).length_squared()
		# 只有整个人**真的停住**了（被门板挡住、速度被 move_and_slide 打成 0）
		# 才用记住的方向继续推。如果只是垂直分量≈0、但人还在走（正平行于门板
		# 穿过门洞），绝不能用记住的方向 —— 否则过门时门会被带着乱动。
		if speed_sq < 100.0 and previous.has(body):
			local_y = float(previous[body])
		if absf(local_y) <= 8.0:
			# 没在动的人推不开门。这里**不要**按"他站在哪一侧"硬猜方向 ——
			# 那样站在门边发呆的敌人也会把门推开，还会因此免疫门的拍击。
			continue

		# 先把前进方向记进 current（供下一帧"贴住门、速度被碰撞归零"时继续推）……
		current[body] = local_y
		# ……但只有**真正贴着门板**的人才算推门：门开了之后，人从门洞中央
		# 经过时仍在触发区里，不能因此把门带动、朝人走的方向甩。
		if not _touching_panel(body):
			continue

		var push: float = maxf(absf(local_y), min_push)
		omega += signf(local_y) * push * push_gain * delta
		_push_dir += signf(local_y)
		_last_pusher = body
		if _noise_source == null:
			_noise_source = body

	_pushers = current
	_push_dir = clampf(_push_dir, -1.0, 1.0)

	# 门被推开：**先给玩家一声响**（door_moved），再按 noise_radius 决定要不要惊动敌人。
	# ⚠️ 这两件事必须分开，别合并：
	#   声音是必要的反馈（不然推门毫无手感）；
	#   但"惊动敌人"默认关掉 —— 噪声走听觉、不受视锥限制，一旦有声，
	#   背对着门的敌人也会转身过来，玩家体验到就是"一进门就被发现"。
	if not _noise_done and absf(angle) > 0.12 and _noise_source != null:
		_noise_done = true
		Events.door_moved.emit(global_position, clampf(absf(omega) / 6.0, 0.0, 1.0))
		Events.emit_noise(global_position, noise_radius, _noise_source)


## 这个角色是不是真的**贴着门板**（而不是从门洞旁边/贴墙走过）。
##
## 用一块比门板略厚一点的矩形做**形状重叠查询**，直接回答"身体和门板有没有接触"。
## 为什么不用"到门板中心线的距离"：门板只有 6px 厚、又嵌在 16px 厚的墙里，
## "贴住门板"(0px 间隙) 和 "贴墙走过"(约 5px 间隙) 的中心距只差 5px，
## 用距离阈值很难稳定区分 —— 阈值大了会误伤贴墙的人，小了又推不动门。
## 重叠查询看的是真实的形状接触，一步到位。
func _touching_panel(body: Node) -> bool:
	if not (body is Node2D):
		return false
	var rect := panel_shape.shape as RectangleShape2D
	if rect == null:
		return false
	var probe := RectangleShape2D.new()
	probe.size = Vector2(rect.size.x, rect.size.y + TOUCH_MARGIN * 2.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = probe
	query.transform = panel_shape.global_transform
	query.collision_mask = LAYER_CHARS
	query.collide_with_bodies = true
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 8):
		if hit.get("collider") == body:
			return true
	return false


## 撞门（脚本/测试用）。按 opener 的前进方向给门一记冲量；
## 他站着不动时就按他站在哪一侧、往反方向开。
func open(opener: Node = null) -> void:
	var local_y := 0.0
	if opener != null:
		var v: Variant = opener.get("velocity")
		if v is Vector2:
			local_y = (global_transform.basis_xform_inv(v as Vector2)).y
		if absf(local_y) <= 8.0 and opener is Node2D:
			local_y = -signf(to_local((opener as Node2D).global_position).y) * 100.0
		_noise_source = opener
	if is_zero_approx(local_y):
		local_y = 100.0
	push(signf(local_y) * 9.0)


## 直接给门一记角速度冲量
func push(impulse: float) -> void:
	omega += impulse


func _bounce(w: float) -> float:
	# 太慢就不弹了，免得贴着极限角度一直微微抖
	if absf(w) < 0.6:
		return 0.0
	return -w * restitution


# ------------------------------------------------------------ 扫门撞晕

## 扫过 [from_angle, to_angle] 这段弧，把撞到的人**撞晕**。
##
## 用形状查询逐段扫，而不是读 Area2D 的缓存重叠 —— 门是"这一刻扫过去"的，
## 必须即时。分段数按扫过的角度算，保证取样间距不超过约 7°。
##
## 注意：门**不会**被人挡住（它已经不是实体障碍了），扫到谁就晕谁。
func _sweep(from_angle: float, to_angle: float, w: float) -> void:
	var rect := panel_shape.shape as RectangleShape2D
	if rect == null:
		return
	if absf(w) < stun_speed:
		return      # 甩得太慢，从人身上扫过去就行，不产生任何效果
	var steps: int = maxi(3, int(ceil(absf(to_angle - from_angle) / 0.12)))

	for i in range(1, steps + 1):
		var a: float = lerpf(from_angle, to_angle, float(i) / float(steps))
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = rect
		query.transform = _panel_transform(a)
		query.collision_mask = LAYER_CHARS
		query.collide_with_bodies = true
		for hit in get_world_2d().direct_space_state.intersect_shape(query, 16):
			var body: Variant = hit.get("collider")
			if body == null or _pushers.has(body):
				continue        # 正在推门的人不会被自己的门撞晕
			if not _can_affect(body):
				# 自己人推开的门不会撞晕自己人 —— 否则敌人一开门就把同伴撞晕。
				continue
			# 已经晕了的就别再撞一次：门板扫过去会在连续几帧里反复碰到同一个人。
			# （用对方自己的状态判断，不需要门再记一份名单 —— 那份名单很容易忘记清，
			#   结果就是一扇门一辈子只能撞晕同一个人一次。）
			if body.has_method("is_stunned") and body.call("is_stunned"):
				continue
			_stun(body, w)


## 这扇门能不能影响到 body：只有**和推门的人敌对**的才会被撞晕。
## 用 "enemies" 组当队伍标记（玩家不在这个组里）：
##   玩家推门 → 撞晕敌人          敌人推门 → 只能撞晕玩家，不会误伤同伴
## 没人推门（门在自己慢慢关）→ 谁都不影响。
func _can_affect(body: Variant) -> bool:
	if _last_pusher == null or not is_instance_valid(_last_pusher):
		return false
	var target := body as Node
	var pusher := _last_pusher as Node
	if target == null or pusher == null:
		return false
	return target.is_in_group("enemies") != pusher.is_in_group("enemies")


## 门板转到 angle 时，门板碰撞形状的世界变换。
## 要和 Door.tscn 的节点结构对上：Hinge 在 (-19, 0)，形状在 Hinge/Panel 下再偏 (16, 0)。
func _panel_transform(a: float) -> Transform2D:
	var hinge_xf := global_transform * Transform2D(a, Vector2(-SPAN * 0.5, 0.0))
	return hinge_xf * Transform2D(0.0, Vector2(SPAN * 0.5, 0.0))


## 把撞到的人**撞晕**（不杀）。方向取门板在该点的**切线速度**方向 ——
## 也就是门推人的真实方向；力量跟角速度和力臂成正比。
##
## 晕眩期间玩家贴上去、或者开枪，都能把它补掉 ——
## 门的定位是"控场"，不是"击杀"。
func _stun(body: Variant, w: float) -> void:
	if not (body is Node2D):
		return
	var node := body as Node2D
	if not node.has_method("stun"):
		return
	var rel: Vector2 = node.global_position - hinge.global_position
	if rel.length_squared() < 1.0:
		return
	var tangent := Vector2(-rel.y, rel.x).normalized() * signf(w)
	# 击退**距离** = power² / (2 × 敌人的 STUN_DRAG)，而 STUN_DRAG 是 1200。
	# 所以 160 → 11px（0.7 格）、250 → 26px（1.6 格）：正好落在"撞出去 1~2 格"里。
	# ⚠️ 距离和 power 是**平方**关系，想调距离不要按比例线性估。
	var power: float = clampf(stun_power * absf(w) * rel.length(), 160.0, 250.0)
	node.call("stun", tangent, power)
	# 击晕音效。放在"真的晕了"之后发，避免对已经晕的人重复响
	Events.enemy_stunned.emit(node.global_position)
