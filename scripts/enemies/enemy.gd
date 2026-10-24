class_name Enemy
extends CharacterBody2D
## 敌人基类：状态机 + 视野三件套 + 听觉 + 一击必杀。
##
## 子类只需要重写三件事：
##   _should_attack()   什么时候从 CHASE 切进 ATTACK
##   _ai_chase(delta)   没看见玩家、走向最后已知位置时做什么
##   _ai_attack(delta)  ATTACK 状态做什么
## 感知、移动、巡逻、死亡、听声辨位这些共用逻辑全在这里。
## 攻击方式由子类决定；是否巡逻只看路点，持枪敌人也能沿路线巡逻。
##
## 数值不要写死在代码里 —— 全部在各自的 .tscn 里用 Inspector 调，这样改数值不用碰代码。

const LAYER_WORLD := 1 << 0
const LAYER_PLAYER := 1 << 1
## 门单独占一层：只挡子弹和视野，不挡角色（角色能直接穿过去）
const LAYER_DOOR := 1 << 7
enum State { IDLE, PATROL, ALERT, CHASE, ATTACK, DEAD }

@export_group("感知")
## 视距
@export var vision_range: float = 260.0
## 视锥总张角（度）
@export var vision_angle_deg: float = 100.0
## 听力倍数：实际能听到的范围 = 噪声半径 × 本值
@export var hearing_multiplier: float = 1.0
## 失去目标后还会保持警觉多久（秒）
@export var alert_time: float = 4.0
## 调试开关：打开后，这个敌人每次"第一次看见玩家"都会往控制台打印一行，
## 写明它和玩家在哪、隔多远、视线中间挡着的是**墙**还是**门**。
##
## 用途：排查"敌人隔着墙看到我"这种说不清的问题。
## 在 Inspector 里给可疑的那个敌人勾上就行（不用改代码）。
@export var debug_vision: bool = false

@export_group("尸体")
## 自己倒地时发出的噪声半径。
##
## 故意设得很小：只有贴着的人才听得见"咚"的一声。
## 远处的同伴应该是**看见**尸体才起疑心（见 _check_corpses），而不是全图都听见 ——
## 否则"杀一个人"等于免费给全场报点，潜行就没意义了。
@export var death_noise_radius: float = 56.0
## 每隔多久检查一次"视野里有没有同伴的尸体"（秒）。
## 不必每帧查：尸体又不会跑，而每帧遍历 corpses 组纯属浪费。
@export var corpse_check_interval: float = 0.25

## 尸体查看的计时器
var _corpse_timer: float = 0.0
## 已经查看过的尸体（instance_id → true）。看过就不再重复起疑心，
## 否则敌人会围着尸体反复进入警戒、永远回不到岗位。
var _seen_corpses: Dictionary = {}

@export_group("移动")
@export var move_speed: float = 120.0
@export var accel: float = 900.0

@export_group("巡逻")
## A* 的终点是格心，路点却可以在格角；容差低于 12px 会一直差一点、永久卡住。
@export var waypoint_tolerance: float = 18.0
## 到不了的点要跳过，避免一处摆错的路点让整条路线停摆。
@export var waypoint_timeout: float = 4.0

@export_group("战斗")
## 兼容旧场景序列化字段，已不参与伤害判定。
@export var contact_kill: bool = false
@export var contact_range: float = 18.0
@export var weapon: WeaponData
var combat: WeaponCombat
var weapon_instance: WeaponState:
	get: return combat.instance if combat != null else null
var ammo: int:
	get: return weapon_instance.ammo if weapon_instance != null else 0
var execution_armed := false

@onready var aim: Node2D = $Aim
@onready var shape: CollisionShape2D = $CollisionShape2D
@onready var visual: ActorVisual = $Visual
## 寻路代理。挂在各个敌人场景里（节点名 NavAgent）。
## 用 get_node_or_null 是为了万一漏挂时还能退回直线移动，而不是直接崩。
## 寻路用。关卡的网格 A*（见 level.gd 的 find_path）——
## 不用 NavigationAgent2D：导航图在窄门洞上会静默连不上。
var _level: Level = null
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _path_target: Vector2 = Vector2.ZERO
var _repath_left: float = 0.0

## 被门撞晕（见 door.gd 的 _stun）：这段时间不跑 AI，只带着被打退的速度滑行。
## 晕眩本身**不致命** —— 但玩家贴上来、或者开枪，都能补掉。
const STUN_TIME := 1.6
## 被打退的速度衰减（像素/秒²）。越大滑得越近 —— 击退距离约 30px，别把人打飞半个房间
const STUN_DRAG := 1200.0
var _stun_left := 0.0
var _stun_vel := Vector2.ZERO

var state: State = State.IDLE
## 面朝方向。视野锥、视觉朝向都由它驱动。
var facing: Vector2 = Vector2.RIGHT
## 最后一次确认到玩家的位置（或听到噪声的位置）
var last_known_pos: Vector2 = Vector2.ZERO
var player: Player = null

var _alert_left: float = 0.0
var _home: Vector2 = Vector2.ZERO
## 第 0 个点是出生岗位；只读直接挂在敌人下的 Marker2D，避免把枪口当成路点。
var _route: PackedVector2Array = PackedVector2Array()
var _route_index: int = 0
var _waypoint_left: float = 0.0
var _waypoints: Array[Marker2D] = []
## 到达"最后已知位置"后原地张望用的相位
var _scan_phase: float = 0.0
var _scan_center: Vector2 = Vector2.RIGHT
var _scanning: bool = false


func _ready() -> void:
	add_to_group("enemies")
	_home = global_position
	last_known_pos = global_position
	# 出生朝向 = **自己在编辑器里的旋转角**。
	#
	# 这样你在 2D 视图里把敌人转个方向（或者改 Inspector 里的 Rotation），
	# 它的视野锥和鼻子就朝那边 —— 摆哨位、堵门口都靠这个。
	#
	# ⚠️ 以前这里写死 Vector2.RIGHT，于是无论把敌人转多少度，
	# 朝向永远是"向右"，只有贴图跟着转了。
	# 出生朝向 = **自己在编辑器里被转到的方向**。
	#
	# 这样你在 2D 视图里把敌人转个方向（或者改 Inspector 里的 Rotation），
	# 它的视野锥和鼻子就朝那边 —— 摆哨位、堵门口都靠这个。
	#
	# ⚠️ 用 rotation（角度）而不是 transform.x：
	# 节点刚进树时 transform 可能还没结算（读到的是单位矩阵），
	# 但 rotation 一定是准的。这个坑实测过。
	#
	# ⚠️ 以前这里写死 Vector2.RIGHT，于是无论把敌人转多少度，
	# 朝向永远是"向右"，只有贴图跟着转了。
	facing = Vector2.RIGHT.rotated(rotation)
	_sync_aim()
	player = get_tree().get_first_node_in_group("player") as Player
	# 玩家可能比敌人晚进场景（同一个 add_child 里 _ready 的顺序受节点顺序影响），
	# 或者旧关卡的 Player 刚被释放 —— 两种都要延迟一帧再找。
	# ⚠️ 判据用 is_instance_valid，不是 == null（被释放的引用不等于 null）
	if not is_instance_valid(player):
		_find_player.call_deferred()
	Events.noise_emitted.connect(_on_noise)
	combat = WeaponCombat.new()
	aim.add_child(combat)
	var model := preload("res://scenes/visuals/WeaponView.tscn").instantiate() as WeaponView
	model.name = "Weapon"
	aim.add_child(model)
	for old_name in ["Nose", "Barrel"]:
		var old_model := aim.get_node_or_null(old_name) as CanvasItem
		if old_model != null:
			old_model.visible = false
	combat.setup(self, false, model)
	combat.pose_changed.connect(visual.receive_pose)
	visual.bind_weapon_view(model)
	equip_weapon(WeaponState.new(weapon) if weapon != null else null)
	_on_enemy_ready()
	rebuild_route()
	state = _default_state()
	# 敌人的 _ready 早于关卡，延迟检查才能读到已经建立的寻路网格。
	call_deferred("_validate_waypoints")


## 补查找玩家。_ready 没找到时延迟一帧再试（那时整棵场景树都已经就位）。
func _process(_delta: float) -> void:
	visual.update_state(velocity, aim.global_rotation, move_speed, is_stunned())


func _find_player() -> void:
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Player


## 玩家还在不在、活着吗。
##
## ⚠️ **绝对不要写 `player == null`**：GDScript 里"被释放过的节点引用"**不等于 null**，
## 但访问它的属性会直接报错。唯一正确的判据是 `is_instance_valid()`。
##
## 这个坑真的踩过：重开关卡时旧的 Player 被释放，敌人的 `player` 变成了
## 一个失效引用 —— `== null` 判不出来，于是既不去重找、又用不了，
## 敌人就**永远瞎着**，而且不报任何错。
func player_alive() -> bool:
	return is_instance_valid(player) and not player.is_dead


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	# 在任何角色处理顺序下记录分离，推倒同帧不会直接连成处决。
	if _stun_left > 0.0 and player_alive() and global_position.distance_to(player.global_position) > player.execution_radius:
		execution_armed = true
	# 被门撞晕中：不跑 AI，只带着被打退的速度滑行一小段
	if _stun_left > 0.0:
		_stun_left = maxf(_stun_left - delta, 0.0)
		velocity = _stun_vel
		_stun_vel = _stun_vel.move_toward(Vector2.ZERO, STUN_DRAG * delta)
		move_and_slide()
		if _stun_left <= 0.0:
			visual.modulate = Color.WHITE    # 清醒过来，恢复原色
		return

	if state == State.DEAD:
		return

	# 玩家可能比敌人晚进场景，也可能旧关卡的 Player 刚被释放导致引用失效 ——
	# 两种情况都要重新找（判据必须是 is_instance_valid，见 player_alive 的说明）
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Player

	combat.tick(delta)
	if state == State.DEAD or is_stunned():
		return
	if combat.committed():
		velocity = Vector2.ZERO
		return
	_alert_left = maxf(_alert_left - delta, 0.0)
	_update_perception()
	# 看见同伴的尸体 → 过去查看。放在玩家感知之后：正在追玩家时不该被尸体打断。
	_check_corpses(delta)

	match state:
		State.IDLE:
			_ai_idle(delta)
		State.PATROL:
			_ai_patrol(delta)
		State.ALERT:
			_ai_alert(delta)
		State.CHASE:
			if _should_attack():
				state = State.ATTACK
				_on_attack_enter()
			else:
				_ai_chase(delta)
		State.ATTACK:
			if not _should_attack():
				state = State.CHASE
				_on_attack_exit()
			else:
				_ai_attack(delta)


# ------------------------------------------------------------------ 感知

## 视野三件套：距离 + 夹角 + 中间无遮挡。缺任何一个都会做出不合理的 AI。
## 抽成"能不能看见某个点"，因为尸体查看（_check_corpses）也要用同一套判定。
func can_see_point(p: Vector2) -> bool:
	var to_p: Vector2 = p - global_position
	if to_p.length() > vision_range:
		return false
	if facing.length_squared() > 0.01 and absf(facing.angle_to(to_p)) > deg_to_rad(vision_angle_deg * 0.5):
		return false
	return not _world_blocks(global_position, p)


func can_see_player() -> bool:
	if not player_alive():
		return false
	return can_see_point(player.global_position)


func _world_blocks(from: Vector2, to: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(from, to)
	# 关着的门和墙一样挡视线（门在独立的 door 层上）
	q.collision_mask = LAYER_WORLD | LAYER_DOOR | 64
	q.exclude = [get_rid()]
	# ⚠️ 必须打开 hit_from_inside。
	# 默认是 false，意思是"射线起点在某个形状内部时，忽略那个形状"。
	# 敌人贴着墙角追人时身体会压进墙里，那一瞬间它就会**隔着墙看见玩家**
	# （而且是概率性的：蹭到墙才发生）。打开之后，"我已经在墙里"也算被挡住。
	q.hit_from_inside = true
	return not get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func _update_perception() -> void:
	if not player_alive():
		if state == State.CHASE or state == State.ATTACK:
			state = State.ALERT
			_on_attack_exit()
		return

	if can_see_player():
		last_known_pos = player.global_position
		_alert_left = alert_time
		if state != State.CHASE and state != State.ATTACK:
			if debug_vision:
				_debug_report_sight()
			state = State.CHASE
			_on_spotted()
	elif state == State.CHASE or state == State.ATTACK:
		# 丢失视野 → 去最后已知位置找，而不是立刻放弃
		state = State.ALERT
		_on_attack_exit()


## 视野里有同伴的尸体 → 过去查看（走到尸体位置，然后原地张望）。
##
## 为什么单独做这一套：尸体倒地的**声音**传得很近（death_noise_radius），
## 所以远处的敌人不是"听见"、而是"看见"才知道出了事。
## 这让"把尸体留在过道/门口"变成一种有意义的玩法 ——
## 敌人会被引过去查看，而你可以换个角度再来一轮。
##
## 看过一次就记住（_seen_corpses）：否则它会围着尸体反复进入警戒、永远回不了岗位。
func _check_corpses(delta: float) -> void:
	# 正在追玩家 / 已经死了：别被尸体打断
	if state == State.CHASE or state == State.ATTACK or state == State.DEAD:
		return
	_corpse_timer -= delta
	if _corpse_timer > 0.0:
		return
	_corpse_timer = corpse_check_interval

	for c in get_tree().get_nodes_in_group("corpses"):
		var corpse := c as Node2D
		if corpse == null or not is_instance_valid(corpse):
			continue
		var id := corpse.get_instance_id()
		if _seen_corpses.has(id):
			continue
		if not can_see_point(corpse.global_position):
			continue
		_seen_corpses[id] = true
		last_known_pos = corpse.global_position
		_alert_left = alert_time
		if state == State.IDLE or state == State.PATROL:
			state = State.ALERT
		return


## 调试用：报告"我在哪看到了玩家"，并说明视线中间挡着的是墙还是门。
func _debug_report_sight() -> void:
	print("[看见] %s 在 %s 看到玩家 %s（距离 %.0fpx）｜中间有墙=%s 有门=%s" % [
			name, str(global_position.round()), str(player.global_position.round()),
			global_position.distance_to(player.global_position),
			str(_ray_hits_layer(LAYER_WORLD)), str(_ray_hits_layer(LAYER_DOOR))])


## 这条视线中间有没有某个层的东西（用来区分"墙"和"门"）
func _ray_hits_layer(mask: int) -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position, player.global_position)
	q.collision_mask = mask
	q.exclude = [get_rid()]
	q.hit_from_inside = true
	return not get_world_2d().direct_space_state.intersect_ray(q).is_empty()


## 听到噪声。这是本作的核心机制：开枪的声音就是你的位置。
func _on_noise(pos: Vector2, radius: float, source: Node) -> void:
	if state == State.DEAD:
		return
	# 自己弄出的动静不重新定位自己。最典型的例子：敌人撞开门，
	# 门的响声不该让它把正在追的枪声位置忘掉、站在门口发呆。
	if source == self:
		return
	if global_position.distance_to(pos) > radius * hearing_multiplier:
		return
	last_known_pos = pos
	_alert_left = alert_time
	if state == State.IDLE or state == State.PATROL:
		state = State.ALERT
		_on_heard(pos)


# ------------------------------------------------------------ 默认行为

func _ai_idle(delta: float) -> void:
	# 警戒解除后走回自己的岗位，而不是就地发呆
	if global_position.distance_to(_home) > 20.0:
		_move_toward_point(_home, delta, 0.7)
	else:
		_slow_down(delta)


func _ai_patrol(delta: float) -> void:
	if not _has_patrol_route():
		state = State.IDLE
		_ai_idle(delta)
		return
	var target: Vector2 = _route[_route_index]
	_waypoint_left -= delta
	if global_position.distance_to(target) <= waypoint_tolerance or _waypoint_left <= 0.0:
		_route_index = (_route_index + 1) % _route.size()
		_waypoint_left = waypoint_timeout
		target = _route[_route_index]
	_move_toward_point(target, delta, 0.8)


## 出生岗位算第一个位置：无 point 站岗，一个 point 往返，多个 point 按顺序闭环。
## 运行时修改路点后调用它；不会打断追击、警戒、眩晕或把尸体重新激活。
func rebuild_route() -> void:
	_waypoints.clear()
	_route = PackedVector2Array([_home])
	for child in get_children():
		if child is Marker2D:
			var mark := child as Marker2D
			_waypoints.append(mark)
			_route.append(_waypoint_world_position(mark))
	_route_index = 1 if _route.size() > 1 else 0
	_waypoint_left = waypoint_timeout
	_path = PackedVector2Array()
	_repath_left = 0.0
	if state == State.IDLE or state == State.PATROL:
		state = _default_state()


func patrol_route() -> PackedVector2Array:
	return _route


func _has_patrol_route() -> bool:
	for point in _route:
		if not point.is_equal_approx(_home):
			return true
	return false


func _waypoint_world_position(mark: Marker2D) -> Vector2:
	# 路点跟着出生岗位缓存，不能在敌人走动后按它的当前位置重新算。
	# 必须计入敌人的旋转；漏掉它会让转过 180° 的敌人沿着镜像路线巡逻。
	return _home + mark.position.rotated(rotation)


func _validate_waypoints() -> void:
	if _waypoints.is_empty():
		return
	_ensure_level()
	if _level == null:
		return
	for i in _waypoints.size():
		# 校验与行走共用坐标换算，避免行走正确、警告却把旋转路点误报成墙内。
		var point := _waypoint_world_position(_waypoints[i])
		if not _level.is_walkable_cell(_level.world_to_cell(point)):
			printerr("⚠️ %s 的巡逻路点 %d 落在墙里（%s）：请把路点移到地板上，运行时会超时跳过。" % [
					name, i + 1, str(point.round())])
			continue
		if _level.find_path(_home, point).is_empty():
			printerr("⚠️ %s 的巡逻路点 %d（%s）从岗位走不到：运行时会超时跳过。" % [
					name, i + 1, str(point.round())])


## 走到"最后已知位置"查看。这是"看不见你之后还会追过来"的关键状态。
func _ai_alert(delta: float) -> void:
	if _alert_left <= 0.0:
		state = _default_state()
		# 搜索花掉的时间不计入路点超时，免得一结束警戒就无故跳过当前路点。
		_waypoint_left = waypoint_timeout
		_scanning = false
		_on_return_home()
		return

	if global_position.distance_to(last_known_pos) > 24.0:
		# 还没到：走过去（走导航路径，所以绕得开墙）。
		# 阈值给到 24px：路径终点是格中心，而"最后已知位置"可能偏移到格边，
		# 阈值太小会"永远差一点、走不到"，然后原地不停抖动。
		_scanning = false
		_move_toward_point(last_known_pos, delta, 0.9)
		return

	# 到了最后已知位置：原地左右张望，而不是站着不动
	_slow_down(delta)
	if not _scanning:
		_scanning = true
		_scan_phase = 0.0
		_scan_center = facing
	_scan_phase += delta * 2.4
	facing = _scan_center.rotated(sin(_scan_phase) * 1.1)   # 左右各扫约 63 度
	_sync_aim()


func _ai_chase(delta: float) -> void:
	_move_toward_point(last_known_pos, delta)


func _ai_attack(delta: float) -> void:
	_ai_melee(delta)


## 警觉结束后回到哪个状态
func _default_state() -> State:
	return State.PATROL if _has_patrol_route() else State.IDLE


## 是否应该从 CHASE 切进 ATTACK
func _should_attack() -> bool:
	return false


# -------------------------------------------------------------- 移动

## 朝一个世界坐标移动。**走格子 A* 的路径，不是直线** —— 直线会被墙卡死。
func _move_toward_point(point: Vector2, delta: float, speed_scale: float = 1.0) -> void:
	_ensure_level()
	var to_point: Vector2 = point - global_position
	if to_point.length_squared() > 4.0:
		facing = to_point.normalized()      # 始终朝着"要看的地方"，而不是当前路径点

	var move_dir := Vector2.ZERO
	if _level != null:
		# 目标动了、或者过了一段时间就重算路径 —— 不用每帧算
		_repath_left -= delta
		if _repath_left <= 0.0 or _path.is_empty() \
				or _path_target.distance_squared_to(point) > 576.0:
			_path = _level.find_path(global_position, point)
			_path_index = 0
			_path_target = point
			_repath_left = 0.25

		# 走到当前路径点附近就推进到下一个
		while _path_index < _path.size() \
				and global_position.distance_to(_path[_path_index]) < 8.0:
			_path_index += 1
		if _path_index < _path.size():
			var to_next: Vector2 = _path[_path_index] - global_position
			if to_next.length_squared() > 1.0:
				move_dir = to_next.normalized()

	# 兜底：完全算不出路径时才直线走，至少不站着不动。
	# 阈值给到 24px²：走到目标格之后路径本来就为空（起点终点同一格），
	# 若目标点又偏移到格边，直线兜底会朝着那个点来回抖 —— 所以只在真远时用。
	if move_dir == Vector2.ZERO and _path.is_empty() and to_point.length_squared() > 576.0:
		move_dir = to_point.normalized()

	velocity = velocity.move_toward(move_dir * move_speed * speed_scale, accel * delta)
	move_and_slide()
	_sync_aim()


## 关卡把自己注册进组 "level"，敌人用它拿到寻路网格。
## 用惰性查找是因为敌人的 _ready 早于关卡的 _ready。
func _ensure_level() -> void:
	if _level == null:
		_level = get_tree().get_first_node_in_group("level") as Level


func _slow_down(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, accel * delta)
	move_and_slide()


func _sync_aim() -> void:
	if aim != null:
		# ⚠️ 用「局部角 = 目标全局角 − 自己的旋转」，不要写 aim.rotation = facing.angle()，
		# 也不要写 aim.global_rotation = facing.angle()：
		#   - 前者：Aim 是子节点，敌人转多少度它就再转多少度，总共转两倍；
		#   - 后者：节点刚进树时父级变换可能还没结算，算出来的局部角是错的。
		# 减法这两种问题都没有。再 wrap 一下：180° 时算出来是 2π，
		# 视觉上等价但数值难看，收敛到 [-π, π] 更干净。
		aim.rotation = wrapf(facing.angle() - rotation, -PI, PI)


func equip_weapon(value: WeaponState) -> void:
	combat.equip(value)
	weapon = value.definition if value != null else null
	visual.set_weapon(weapon)
	var muzzle := aim.get_node_or_null("Muzzle") as Marker2D
	if muzzle != null and weapon != null:
		muzzle.position = combat.model.muzzle_offset()
		# 旧火光是 Aim 的兄弟节点，独立跟随枪口，不能挪动身体弹道。
		var flash := aim.get_node_or_null("Flash") as Node2D
		if flash != null:
			flash.position = muzzle.position


func weapon_ammo_changed() -> void:
	pass


func _drop_weapon() -> void:
	if weapon_instance == null:
		return
	var item := preload("res://scenes/projectiles/ThrownWeapon.tscn").instantiate()
	item.weapon_instance = weapon_instance
	item.landed = true
	var holder := get_tree().get_first_node_in_group("projectile_parent")
	(holder if holder != null else get_parent()).add_child(item)
	item.global_position = global_position
	equip_weapon(null)


func _ai_melee(delta: float) -> void:
	if not player_alive():
		return
	var offset := player.global_position - global_position
	if offset.length() > combat.reach():
		_move_toward_point(player.global_position, delta)
	else:
		_slow_down(delta)
		facing = offset.normalized()
		_sync_aim()
		combat.attack(facing)


# -------------------------------------------------------------- 死亡

func take_damage(_amount: int = 1, _from: Vector2 = Vector2.ZERO) -> void:
	if state == State.DEAD:
		return
	_die()


func _die(silent: bool = false) -> void:
	combat.cancel()
	_drop_weapon()
	state = State.DEAD
	# 退组：组 "enemies" 只统计活着的敌人，方便 Main 判定清场
	remove_from_group("enemies")
	# 进组：让同伴能"看见"这具尸体（见 _check_corpses）
	add_to_group("corpses")
	Events.enemy_died.emit(global_position)
	# 倒地声。半径很小 —— 远处的同伴是靠**看见**尸体才知道出事了，
	# 而不是靠听见（见 death_noise_radius 的说明）。
	# 暗杀走 silent = true，**完全不发声**。
	if not silent:
		Events.emit_noise(global_position, death_noise_radius, self)
	_settle_corpse()
	_on_death_fx()
	_play_death_punch()


## 能不能被玩家**贴上去暗杀**。
##
## 条件：还没发现玩家（IDLE / PATROL），或者正被门撞晕。
## 一旦进入 ALERT / CHASE / ATTACK，说明它已经警觉、正在找你或追你 —— 只能硬来。
func can_be_assassinated() -> bool:
	# 保留旧调用入口供门及调试使用，站立目标不再允许自动触碰暗杀。
	return state != State.DEAD and is_stunned()


## 被暗杀。和普通死亡只差一点：**不发声**（连倒地声都免了）。
##
## 暗杀的意义就是"无声解决" —— 否则它和开枪没有区别（开枪还会把周围人引过来）。
## 代价是**尸体照样会被同伴看见**（见 _check_corpses），
## 所以"把人杀在过道上"依然有后果，只是不会立刻招来一圈人。
func assassinate() -> void:
	if state == State.DEAD:
		return
	_die(true)


## 死亡的一下"冲击"：闪白 + 短暂放大，再收回到尸体状态。
##
## 为什么值得做：`_settle_corpse` 只是把颜色调暗，等于"悄悄换成尸体"，
## 大脑收不到"打中了"的信号。加这一下之后，即使顿帧和震动都被关掉，
## 也能单靠画面看出"这一枪打实了"。
func _play_death_punch() -> void:
	var corpse := Color.WHITE
	visual.modulate = Color(4.5, 4.5, 4.5)      # >1 的 modulate 会提亮 → 闪白
	visual.scale = Vector2(1.7, 1.7)            # 撑大一下，像被打爆
	visual.rotation = randf_range(-0.5, 0.5)    # 顺手被打歪一个角度
	var t := create_tween().set_parallel(true)
	t.tween_property(visual, "modulate", corpse, 0.14)
	t.tween_property(visual, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	t.tween_property(visual, "rotation", 0.0, 0.20).set_trans(Tween.TRANS_BACK)


## 变成躺在地上的尸体。绝对 z（墙下两层），关掉碰撞。
func _settle_corpse() -> void:
	velocity = Vector2.ZERO
	_stun_vel = Vector2.ZERO
	_stun_left = 0.0
	shape.set_deferred("disabled", true)
	collision_layer = 0
	# ⚠️ 用绝对 z（z_as_relative = false），这样不管敌人挂在哪个容器下都成立。
	# 但值**不能写死** —— 见 _corpse_z() 的说明。
	z_as_relative = false
	z_index = _corpse_z()
	visual.modulate = Color.WHITE
	visual.die()


## 尸体该用哪个绝对 z：**在地板之上、所有"立着的物体"之下**。
##
## 具体值交给关卡算（level.gd 的 corpse_z）—— 只有它知道墙在哪一层。
## ⚠️ 这里踩过两次坑：以前写死 z_index = 1，那等于假设"活人的有效 z 一定 ≥ 2"，
## 而那是**关卡数据**决定的（手工搭关卡很容易漏设 Player 的 z_index），
## 于是一具尸体就盖在玩家身上，看起来完全像是"尸体层级坏了"。
func _corpse_z() -> int:
	_ensure_level()
	if _level != null:
		return _level.corpse_z()
	return 1                    # 万不得已的退路（正常不会走到）


## 一个 Node2D 的**有效** z：沿父链把 z_index 累加，直到遇到 z_as_relative = false。
func effective_z(n: Node2D) -> int:
	var total := 0
	var cur: Node = n
	while cur is Node2D:
		var n2 := cur as Node2D
		total += n2.z_index
		if not n2.z_as_relative:
			break
		cur = n2.get_parent()
	return total


## 被门撞晕（door.gd 调用）。`dir` 是门板扫过来的切线方向。
## 晕眩期间不跑 AI、会被打退一点；玩家贴上来或开枪都能补刀。
## 注意：晕眩**不致命** —— 门的定位是控场，不是击杀。
func stun(dir: Vector2, power: float) -> void:
	if state == State.DEAD:
		return
	combat.cancel()
	_drop_weapon()
	_on_attack_exit()
	execution_armed = player_alive() and global_position.distance_to(player.global_position) > player.execution_radius
	_stun_left = STUN_TIME
	_stun_vel = dir.normalized() * power if dir.length_squared() > 0.0001 else Vector2.ZERO
	velocity = _stun_vel
	visual.set_stunned(true)
	_alert_left = 0.0
	_scanning = false
	set_physics_process(true)


## 是否正处于晕眩。玩家靠这个判断"能不能贴上去补刀"。
func is_stunned() -> bool:
	return _stun_left > 0.0


# -------------------------------------------------------- 子类钩子（默认空）

func _on_enemy_ready() -> void:
	pass


func _on_spotted() -> void:
	pass


func _on_heard(_pos: Vector2) -> void:
	pass


func _on_return_home() -> void:
	pass


func _on_attack_enter() -> void:
	pass


func _on_attack_exit() -> void:
	pass


func _on_death_fx() -> void:
	pass
