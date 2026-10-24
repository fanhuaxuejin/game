class_name WeaponCombat
extends Node2D
## 双方共用弹药与挥击；武器动画和命中采样读同一进度，不能动画挥空却按距离杀人。
const BULLET := preload("res://scenes/projectiles/EnemyBullet.tscn")
signal pose_changed(pose: Dictionary)
@export var melee_reach: float = 28.0
@export var melee_arc_deg: float = 90.0
@export var push_reach: float = 24.0
@export var push_arc_deg: float = 60.0
@export var knockback: float = 160.0
@export var player_windup: float = 0.06
@export var player_active: float = 0.12
@export var player_recovery: float = 0.18
@export var enemy_windup: float = 0.15
@export var enemy_active: float = 0.12
@export var enemy_recovery: float = 0.30
@export var push_windup: float = 0.06
@export var push_active: float = 0.10
@export var push_recovery: float = 0.30
@export var enemy_push_recovery: float = 1.1
@export var enemy_push_windup: float = 0.30

var instance: WeaponState
var actor: CharacterBody2D
var player_owned := false
var model: WeaponView
var cooldown := 0.0
var swinging := false
var attack_elapsed := 0.0
var _windup := 0.0
var _active := 0.0
var _recovery := 0.0
var _push := false
var _direction := Vector2.RIGHT
var _hits: Dictionary = {}
var _previous_origin := Vector2.ZERO

func setup(body: CharacterBody2D, is_player: bool, weapon_model: WeaponView) -> void:
	actor = body
	player_owned = is_player
	model = weapon_model
	pose_changed.connect(model.receive_pose)

func equip(value: WeaponState) -> void:
	cancel()
	instance = value
	model.set_definition(instance.definition if instance != null else null)

func cancel() -> void:
	swinging = false
	_hits.clear()
	pose_changed.emit({"kind": &"idle", "phase": &"idle", "progress": 0.0, "angle": 0.0, "extension": 0.0})

func can_shoot() -> bool:
	return instance != null and instance.can_shoot()

func committed() -> bool:
	return swinging and attack_elapsed < _windup + _active

func reach() -> float:
	return push_reach if instance == null else melee_reach

func tick(delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)
	if not swinging:
		return
	var previous := attack_elapsed
	attack_elapsed += delta
	var origin := actor.global_position
	if attack_elapsed >= _windup and previous < _windup + _active:
		var a := clampf((previous - _windup) / _active, 0.0, 1.0)
		var b := clampf((attack_elapsed - _windup) / _active, 0.0, 1.0)
		if _push:
			_push_hit(origin)
		else:
			_sweep(a, b, _previous_origin, origin)
	_previous_origin = origin
	if not swinging:
		return
	_animate()
	if attack_elapsed >= _windup + _active + _recovery:
		cancel()

func attack(dir: Vector2) -> bool:
	if swinging or cooldown > 0.0:
		return false
	_direction = dir.normalized()
	if can_shoot():
		return _shoot()
	_push = instance == null
	_windup = (push_windup if player_owned else enemy_push_windup) if _push else (player_windup if player_owned else enemy_windup)
	_active = push_active if _push and player_owned else (player_active if player_owned else enemy_active)
	_recovery = (push_recovery if player_owned else enemy_push_recovery) if _push else (player_recovery if player_owned else enemy_recovery)
	attack_elapsed = 0.0
	swinging = true
	_hits.clear()
	_previous_origin = actor.global_position
	_animate()
	return true

func _shoot() -> bool:
	var data := instance.definition
	if not instance.consume_round():
		return false
	cooldown = data.fire_rate
	var from := actor.global_position
	var center_spread := randf_range(-data.spread_deg, data.spread_deg) if data.pellets == 1 else 0.0
	for i in range(data.pellets):
		# 多弹丸均匀覆盖扇面，避免随机扎堆让霰弹的实际攻击范围不可读。
		var spread := center_spread if data.pellets == 1 else lerpf(-data.spread_deg, data.spread_deg, float(i) / float(data.pellets - 1))
		var bullet := BULLET.instantiate()
		bullet.configure(player_owned, data.damage, data.max_range)
		_projectile_parent().add_child(bullet)
		bullet.global_position = from
		bullet.launch(_direction.rotated(deg_to_rad(spread)))
	# 一次扳机只发一次反馈和噪声，霰弹不能震六次镜头或扣六发弹药。
	if player_owned:
		Events.bullet_fired.emit(from, from + _direction * data.max_range)
	else:
		Events.enemy_fired.emit(from)
	Events.emit_noise(from, data.noise_radius, actor)
	actor.call("weapon_ammo_changed")
	return true

func _projectile_parent() -> Node:
	var holder := get_tree().get_first_node_in_group("projectile_parent")
	return holder if holder != null else actor.get_parent()

func _sweep(a: float, b: float, previous_origin: Vector2, origin: Vector2) -> void:
	var arc := deg_to_rad(melee_arc_deg)
	# 弧线和角色位移都细分到不超过现有弹体半径，低帧率也不能跳过人或薄门。
	var steps := maxi(1, int(ceil((absf(b - a) * arc * melee_reach + previous_origin.distance_to(origin)) / 3.0)))
	for i in range(steps + 1):
		if not swinging:
			return
		var t := float(i) / float(steps)
		var angle := lerpf(-arc * 0.5, arc * 0.5, lerpf(a, b, t))
		var base := previous_origin.lerp(origin, t)
		var ray_dir := _direction.rotated(angle)
		var tip := base + ray_dir * melee_reach
		# 先从身体检查遮挡，再检查真实武器段；否则枪托伸过薄门就能隔门挥杀。
		var block_q := PhysicsRayQueryParameters2D.create(base, tip, 129)
		block_q.hit_from_inside = true
		var block := actor.get_world_2d().direct_space_state.intersect_ray(block_q)
		var available := base.distance_to(block.position) if not block.is_empty() else melee_reach
		var inner := instance.definition.melee_inner
		if available <= inner:
			continue
		var q := PhysicsRayQueryParameters2D.create(base + ray_dir * inner, base + ray_dir * available, 4 if player_owned else 2)
		q.exclude = [actor.get_rid()]
		q.hit_from_inside = true
		var hit := actor.get_world_2d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			continue
		var target: Object = hit.collider
		if target.has_method("take_damage") and not _hits.has(target.get_instance_id()):
			_hits[target.get_instance_id()] = true
			target.call("take_damage", instance.definition.damage, base)

func _push_hit(origin: Vector2) -> void:
	if not _hits.is_empty():
		return
	var targets := get_tree().get_nodes_in_group("enemies" if player_owned else "player")
	var nearest: Node2D = null
	var best := push_reach
	for target: Node2D in targets:
		var offset := target.global_position - origin
		if offset.length() > best or absf(_direction.angle_to(offset)) > deg_to_rad(push_arc_deg * 0.5):
			continue
		if target.has_method("is_stunned") and target.call("is_stunned"):
			continue
		if not clear_path(origin, target.global_position):
			continue
		nearest = target
		best = offset.length()
	if nearest != null:
		_hits[nearest.get_instance_id()] = true
		nearest.call("stun", _direction, knockback)
		Events.enemy_stunned.emit(nearest.global_position)

func clear_path(from: Vector2, to: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(from, to, 129)
	q.hit_from_inside = true
	return actor.get_world_2d().direct_space_state.intersect_ray(q).is_empty()

func _animate() -> void:
	# 输出玩法时钟的阶段和轨迹；显示层可以换任意帧数，不拥有攻击时间。
	var progress := clampf((attack_elapsed - _windup) / _active, 0.0, 1.0)
	var phase: StringName = &"windup"
	var phase_progress := clampf(attack_elapsed / maxf(_windup, 0.001), 0.0, 1.0)
	var extension := 1.0
	var angle := lerpf(-deg_to_rad(melee_arc_deg) * 0.5, deg_to_rad(melee_arc_deg) * 0.5, progress)
	if attack_elapsed >= _windup + _active:
		phase = &"recovery"
		phase_progress = clampf((attack_elapsed - _windup - _active) / maxf(_recovery, 0.001), 0.0, 1.0)
		extension = 1.0 - phase_progress
		angle *= extension
	elif attack_elapsed >= _windup:
		phase = &"active"
		phase_progress = progress
	pose_changed.emit({"kind": &"push" if _push else &"melee", "phase": phase, "progress": phase_progress, "angle": angle, "extension": extension, "reach": push_reach if _push else melee_reach})
