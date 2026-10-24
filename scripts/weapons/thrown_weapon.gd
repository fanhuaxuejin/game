extends CharacterBody2D
## 飞行和落地用同一个实物节点；弹药状态在交接时转移而不复制。
@export var speed: float = 600.0
@export var max_distance: float = 240.0
@export var knockback: float = 160.0
var weapon_instance: WeaponState
var direction := Vector2.RIGHT
var landed := false
var _travelled := 0.0

func _ready() -> void:
	$Gun.set_definition(weapon_instance.definition)
	$Gun.set_grounded(true)
	if landed:
		_land()
	else:
		add_to_group("thrown_weapons")

func launch(dir: Vector2) -> void:
	direction = dir.normalized()
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	if landed:
		return
	var distance := minf(speed * delta, max_distance - _travelled)
	var hit := move_and_collide(direction * distance)
	_travelled += distance
	if hit != null:
		var body := hit.get_collider()
		if is_instance_valid(body) and body.has_method("stun"):
			body.call("stun", direction, knockback)
			Events.enemy_stunned.emit(body.global_position)
		_land()
	elif _travelled >= max_distance:
		_land()

func _land() -> void:
	landed = true
	collision_mask = 0
	remove_from_group("thrown_weapons")
	add_to_group("dropped_weapons")
	set_physics_process(false)
