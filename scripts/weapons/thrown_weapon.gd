extends CharacterBody2D
## 飞行和落地用同一个实物节点；弹药状态在交接时转移而不复制。
##
## 三种归宿，规则不同，别合并：
##   1. 撞墙 / 门 → 落在原地，还能捡回来（`_land`）
##   2. 飞满射程 → 落地，还能捡回来（`_land`）
##   3. 打在敌人身上 → 当场碎裂，武器没了（`_shatter`），只留像素碎片
@export var speed: float = 600.0
@export var max_distance: float = 240.0
@export var knockback: float = 160.0
## 飞行自转角速度（度/秒）。甩出去的东西会翻 —— 不翻就像贴着轨道滑过去。
@export var spin_speed: float = 900.0
## 用 preload 而不是 class_name：新增全局类要刷新 .godot 类缓存，
## 命令行 `--import` 在受限环境里写不进去（见 weapon_debris.gd 顶部说明）。
const DEBRIS := preload("res://scripts/fx/weapon_debris.gd")
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
	# 自转纯显示：命中判定只用 `direction`，与当前角度无关。
	rotation += deg_to_rad(spin_speed) * delta
	var distance := minf(speed * delta, max_distance - _travelled)
	var hit := move_and_collide(direction * distance)
	_travelled += distance
	if hit != null:
		var body := hit.get_collider()
		if is_instance_valid(body) and body.has_method("stun"):
			body.call("stun", direction, knockback)
			Events.enemy_stunned.emit(body.global_position)
			_shatter()
			return
		_land()
	elif _travelled >= max_distance:
		_land()

## 打在敌人身上：武器损坏。不加入 dropped_weapons，也不保留 WeaponState ——
## 这把武器连同它的剩余弹药一起没了，这正是"投掷是一次真决策"的代价。
func _shatter() -> void:
	landed = true
	collision_mask = 0
	set_physics_process(false)
	remove_from_group("thrown_weapons")
	# 碎片挂到子弹容器下：武器自己马上就 free 了，不能挂在它下面。
	DEBRIS.burst(get_parent(), global_position)
	queue_free()

func _land() -> void:
	landed = true
	collision_mask = 0
	remove_from_group("thrown_weapons")
	add_to_group("dropped_weapons")
	set_physics_process(false)
