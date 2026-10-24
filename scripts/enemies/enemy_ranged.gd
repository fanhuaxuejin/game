extends Enemy
## 同一持枪兵根据武器实例决定射击节奏，打空或缴械后改用近战。
@export var engage_range: float = 300.0
@export var preferred_range: float = 200.0
## 保留旧 Inspector 字段；实际射击节奏来自武器定义，避免换枪仍按旧射速射击。
@export var fire_cooldown: float = 1.2
@export var flash_time: float = 0.08
@export var aim_error_deg: float = 5.0
@export var min_fire_range: float = 48.0
@export var reaction_time: float = 0.4
@onready var muzzle: Marker2D = $Aim/Muzzle
@onready var flash: CanvasItem = $Aim/Flash
var _cooldown_left := 0.0
var _flash_left := 0.0
var _reaction_left := 0.0
var _burst_fired := 0

func _physics_process(delta: float) -> void:
	_flash_left = maxf(_flash_left - delta, 0.0)
	super(delta)
	flash.visible = _flash_left > 0.0 and not is_stunned() and state != State.DEAD

func _should_attack() -> bool:
	return player_alive() and can_see_player() and (not combat.can_shoot() or global_position.distance_to(player.global_position) <= engage_range)

func _ai_chase(delta: float) -> void:
	_move_toward_point(last_known_pos, delta)

func _ai_attack(delta: float) -> void:
	if not combat.can_shoot():
		_ai_melee(delta)
		return
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_keep_distance(delta)
	if _reaction_left > 0.0:
		_reaction_left -= delta
		return
	if _cooldown_left > 0.0:
		return
	var distance := global_position.distance_to(player.global_position)
	if distance < min_fire_range or distance > weapon.max_range:
		return
	_fire()

func _keep_distance(delta: float) -> void:
	if not player_alive():
		_slow_down(delta)
		return
	var dist := global_position.distance_to(player.global_position)
	if dist < preferred_range * 0.75:
		var away := (global_position - player.global_position).normalized()
		_move_toward_point(global_position + away * maxf(dist, 24.0), delta, 0.8)
	elif dist > preferred_range * 1.15:
		_move_toward_point(player.global_position, delta, 0.8)
	else:
		_slow_down(delta)
	facing = (player.global_position - global_position).normalized()
	_sync_aim()

func _fire() -> void:
	if not player_alive() or is_stunned() or state == State.DEAD or not combat.can_shoot() or _cooldown_left > 0.0:
		return
	var direction := (player.global_position - global_position).normalized()
	if global_position.distance_to(player.global_position) > weapon.max_range:
		return
	direction = direction.rotated(deg_to_rad(randf_range(-aim_error_deg, aim_error_deg)))
	var data := weapon
	if not combat.attack(direction):
		return
	visual.show_effect(&"shoot")
	_flash_left = flash_time
	flash.visible = true
	_burst_fired += 1
	if _burst_fired >= data.enemy_burst_size:
		_burst_fired = 0
		_cooldown_left = data.enemy_burst_pause if data.enemy_burst_size > 1 else data.enemy_shot_interval
	else:
		_cooldown_left = data.enemy_shot_interval

func _on_attack_enter() -> void:
	_reaction_left = reaction_time
	_burst_fired = 0

func _on_attack_exit() -> void:
	# 缴械和失去视线都中止这一轮连射；不能苏醒后补射旧枪的剩余连发。
	_burst_fired = 0
	_stop_flash()

func _on_death_fx() -> void:
	_stop_flash()

func _stop_flash() -> void:
	_flash_left = 0.0
	if flash != null:
		flash.visible = false
