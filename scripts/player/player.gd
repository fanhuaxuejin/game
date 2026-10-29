class_name Player
extends CharacterBody2D
## 空手、枪械和近战共用一条输入通路；只有敌人真的倒地后才允许走近处决。
const STUN_TIME := 1.0
const THROWN_SCENE := preload("res://scenes/projectiles/ThrownWeapon.tscn")
@export var speed: float = 260.0
@export var accel: float = 2200.0
@export var friction: float = 2600.0
## 默认空手；固定测试夹具可继续显式装备手枪，不必改写场景。
@export var weapon: WeaponData
@export var pickup_radius: float = 24.0
@export var execution_radius: float = 14.0
@onready var aim: Node2D = $Aim
@onready var muzzle: Marker2D = $Aim/Muzzle
@onready var muzzle_flash: CanvasItem = $Aim/Muzzle/Flash
@onready var actor_visual: ActorVisual = $Body
const AIM_LOCK := preload("res://scripts/player/aim_lock.gd")
const LOCK_RETICLE := preload("res://scripts/visuals/lock_reticle.gd")
var aim_lock: RefCounted
var lock_target: Node2D:
	get: return aim_lock.target() if aim_lock != null else null
const EXECUTION := preload("res://scripts/player/execution.gd")
var execution: RefCounted
var combat: WeaponCombat
var weapon_instance: WeaponState:
	get: return combat.instance if combat != null else null
var ammo: int:
	get: return weapon_instance.ammo if weapon_instance != null else 0
	set(value):
		if weapon_instance != null:
			weapon_instance.ammo = clampi(value, 0, weapon.magazine)
			weapon_ammo_changed()
var is_dead := false
var _stun_left := 0.0
var _flash_left := 0.0
var _fire_armed := false
var _menu_input_blocked := false
var _menu_resume_frame := -10

func _ready() -> void:
	combat = WeaponCombat.new()
	aim.add_child(combat)
	combat.setup(self, true, $Aim/Gun)
	combat.pose_changed.connect(actor_visual.receive_pose)
	actor_visual.bind_weapon_view($Aim/Gun)
	muzzle_flash.visible = false
	add_to_group("player")
	# 左键同时是死亡重开键，出生/拾取时必须等松手，不能凭空发出攻击。
	_fire_armed = not Input.is_action_pressed("fire")
	equip_weapon(WeaponState.new(weapon) if weapon != null else null)
	var reticle := Node2D.new()
	reticle.set_script(LOCK_RETICLE)
	reticle.name = "LockReticle"
	add_child(reticle)
	aim_lock = AIM_LOCK.new()
	aim_lock.actor = self
	aim_lock.reticle = reticle
	aim_lock.clear()
	execution = EXECUTION.new()
	execution.actor = self
	Events.player_spawned.emit(self)

func _unhandled_input(event: InputEvent) -> void:
	if is_dead or execution.active or _menu_input_blocked or event.is_echo():
		return
	if event.is_action_pressed("lock"):
		aim_lock.toggle_requested = true
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cycle_target") and aim_lock.enabled:
		aim_lock.cycle_requested = true
		get_viewport().set_input_as_handled()

func resume_from_menu() -> void:
	_menu_input_blocked = true
	_menu_resume_frame = Engine.get_physics_frames()
	_fire_armed = false
	aim_lock.toggle_requested = false
	aim_lock.cycle_requested = false

func _menu_input_ready() -> bool:
	if not _menu_input_blocked: return true
	if Engine.get_physics_frames() <= _menu_resume_frame + 1: return false
	for action in ["fire","throw_weapon","pickup","lock","cycle_target","execute"]:
		if Input.is_action_pressed(action): return false
	_menu_input_blocked = false
	return true

func _exit_tree() -> void:
	if execution != null: execution.cancel()
	if aim_lock != null:
		aim_lock.clear()

func equip_weapon(value: WeaponState) -> void:
	combat.equip(value)
	weapon = value.definition if value != null else null
	actor_visual.set_weapon(weapon)
	if weapon != null:
		muzzle.position = combat.model.muzzle_offset()
	_flash_left = 0.0
	muzzle_flash.visible = false
	_fire_armed = not Input.is_action_pressed("fire")
	Events.weapon_changed.emit(weapon)
	weapon_ammo_changed()

func capacity() -> int:
	return weapon.magazine if weapon != null else -1

func weapon_ammo_changed() -> void:
	Events.ammo_changed.emit(ammo, capacity())

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if is_stunned():
		_stun_left = maxf(_stun_left - delta, 0.0)
		# 沿用玩家受门击晕时的原地停顿，敌人推击也不能把玩家弹到墙另一侧。
		velocity = Vector2.ZERO
		move_and_slide()
		if not is_stunned():
			modulate = Color.WHITE
		return
	if execution.active:
		execution.tick(delta)
		return
	if _menu_input_ready() and Input.is_action_just_pressed("execute") and execution.start():
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = velocity.move_toward(dir * speed, (accel if dir != Vector2.ZERO else friction) * delta)
	move_and_slide()
	combat.tick(delta)
	if is_dead or is_stunned():
		return
	if not _menu_input_ready(): return
	if Input.is_action_just_pressed("throw_weapon"):
		_throw_weapon()
		return
	if Input.is_action_just_pressed("pickup"):
		_pickup_weapon()
	if not _fire_armed:
		if Input.is_action_pressed("fire"):
			return
		_fire_armed = true
	var hold := weapon != null and combat.can_shoot() and weapon.automatic
	if Input.is_action_pressed("fire") if hold else Input.is_action_just_pressed("fire"):
		_fire()

func _process(delta: float) -> void:
	_flash_left = maxf(_flash_left - delta, 0.0)
	muzzle_flash.visible = weapon != null and _flash_left > 0.0
	execution.update_prompt()
	if execution.active:
		return
	var locked: Node2D = aim_lock.update() if not is_dead else null
	if not is_dead and not combat.swinging:
		var target := locked.global_position if locked != null else get_global_mouse_position()
		if global_position.distance_squared_to(target) > 4.0:
			aim.look_at(target)
	actor_visual.update_state(velocity, aim.global_rotation, speed, is_stunned())

func _fire() -> void:
	if is_dead or is_stunned() or execution.active:
		return
	var shot := combat.can_shoot()
	if combat.attack(Vector2.RIGHT.rotated(aim.global_rotation)) and shot:
		_flash_left = 0.045
		actor_visual.show_effect(&"shoot")

func _projectile_parent() -> Node:
	var holder := get_tree().get_first_node_in_group("projectile_parent")
	return holder if holder != null else get_parent()

func _drop(value: WeaponState, flying: bool) -> Node2D:
	var item := THROWN_SCENE.instantiate()
	item.weapon_instance = value
	item.landed = not flying
	_projectile_parent().add_child(item)
	item.global_position = global_position
	if flying:
		item.launch(Vector2.RIGHT.rotated(aim.global_rotation))
	return item

func _throw_weapon() -> void:
	if weapon_instance == null or is_dead or is_stunned() or combat.committed() or execution.active:
		return
	var value := weapon_instance
	equip_weapon(null)
	_drop(value, true)
	actor_visual.show_effect(&"throw")

func _pickup_weapon() -> void:
	if is_dead or is_stunned() or combat.committed() or execution.active:
		return
	var nearest: Node2D = null
	var best := pickup_radius
	for item: Node2D in get_tree().get_nodes_in_group("dropped_weapons"):
		if item.is_queued_for_deletion() or item.weapon_instance == null:
			continue
		var distance := global_position.distance_to(item.global_position)
		if distance <= best and combat.clear_path(global_position, item.global_position):
			best = distance
			nearest = item
	if nearest == null:
		return
	# 先摘走地上实例，再把旧枪放下，避免同帧第二次 E 又捡到同一节点。
	var value: WeaponState = nearest.weapon_instance
	nearest.weapon_instance = null
	nearest.remove_from_group("dropped_weapons")
	nearest.queue_free()
	var previous := weapon_instance
	equip_weapon(value)
	actor_visual.show_effect(&"pickup")
	if previous != null:
		_drop(previous, false)

func _try_contact_kill() -> void:
	execution.update_prompt()


func stun(_dir: Vector2, _power: float) -> void:
	if is_dead:
		return
	execution.cancel()
	combat.cancel()
	_flash_left = 0.0
	_stun_left = STUN_TIME
	velocity = Vector2.ZERO
	actor_visual.set_stunned(true)

func is_stunned() -> bool:
	return _stun_left > 0.0

func take_damage(_amount: int = 1, _from: Vector2 = Vector2.ZERO, cause: StringName = &"generic") -> void:
	if is_dead:
		return
	execution.cancel()
	is_dead = true
	var direction := (global_position - _from).normalized()
	actor_visual.receive_impact(direction)
	Events.hit_resolved.emit(self, global_position, direction, cause, true)
	Events.actor_died.emit(self, global_position, direction, cause)
	aim_lock.clear()
	combat.cancel()
	var held := weapon_instance
	if held != null:
		equip_weapon(null)
		_drop(held, false)
	velocity = Vector2.ZERO
	_flash_left = 0.0
	muzzle_flash.visible = false
	actor_visual.die()
	var lv := get_tree().get_first_node_in_group("level")
	if lv != null and lv.has_method("corpse_z"):
		z_as_relative = false
		z_index = int(lv.call("corpse_z"))
	Events.player_died.emit()
