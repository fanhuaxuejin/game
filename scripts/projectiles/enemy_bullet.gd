extends CharacterBody2D
## 双方共用扫掠实体，避免高速穿过薄墙；出生点也必须检测碰撞。
##
## 视觉是一张 22x7 的像素贴图（assets/sprites/bullet_*.png）：
##   弹体 10x5 px 在原点附近，拖尾 12px 向 -X 甩在身后。
##   Skin 节点用 centered=false + offset=(-16, -3.5) 摆放，让**节点原点**
##   （= 旋转中心 = 碰撞圆心）正好落在弹体中心，而不是贴图中心 ——
##   否则子弹会绕着尾巴转，看起来像在打转。
##   （Godot 会把绘制矩形对齐到整像素：写 -3.5，实际画在 -3.0，偏差 < 1px，不用管。）
##   玩家子弹与敌人子弹同形不同色：敌人橙红、玩家冷白青。
##   为什么要分色：敌人子弹是玩家唯一要读的威胁，必须比自己的子弹更扎眼。
@export var speed: float = 1500.0
@export var lifetime: float = 1.5
@export var fade_out_time: float = 0.3
var direction := Vector2.RIGHT
var damage: int = 1
var max_distance: float = INF
var player_owned := false
var _life_left := 0.0
var _travelled := 0.0
var _spent := false

const SKIN_ENEMY := preload("res://assets/sprites/bullet_enemy.png")
const SKIN_PLAYER := preload("res://assets/sprites/bullet_player.png")

@onready var skin: Sprite2D = $Skin

func configure_for_player(amount: int, reach: float) -> void:
	configure(true, amount, reach)

func configure(friendly: bool, amount: int, reach: float) -> void:
	player_owned = friendly
	damage = amount
	max_distance = reach
	collision_layer = 8 if friendly else 16
	collision_mask = 133 if friendly else 131
	# configure() 通常在 add_child 之前调用（那时还没有 @onready），
	# 所以两边都试一次：进树前靠 _ready，进树后立刻换贴图。
	if is_node_ready():
		_apply_skin()
	# 分组也得补一次：正常发射路径是"先 configure 再 add_child"，
	# 但如果以后有人在进树之后才 configure，光靠 _ready 就会把它留在敌人的组里 ——
	# 那种错误不报错，只会让"玩家子弹"统计漏掉几发。
	if is_inside_tree():
		add_to_group("player_bullets" if player_owned else "enemy_bullets")
		remove_from_group("enemy_bullets" if player_owned else "player_bullets")

func _ready() -> void:
	add_to_group("player_bullets" if player_owned else "enemy_bullets")
	_life_left = lifetime
	z_as_relative = false
	# 墙遮住贴墙弹体，人物和枪模型始终在弹体上方。
	z_index = -1
	_apply_skin()

## 按阵营换贴图。两套图共用同一份像素布局，只换调色板，所以不会对不上。
func _apply_skin() -> void:
	if skin != null:
		skin.texture = SKIN_PLAYER if player_owned else SKIN_ENEMY

func launch(dir: Vector2) -> void:
	direction = dir.normalized()
	rotation = direction.angle()
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = $CollisionShape2D.shape
	q.transform = global_transform
	q.collision_mask = collision_mask
	q.exclude = [get_rid()]
	var hits := get_world_2d().direct_space_state.intersect_shape(q)
	if not hits.is_empty():
		_hit(hits[0].collider, global_position, -direction)

func _physics_process(delta: float) -> void:
	if _spent:
		return
	_life_left -= delta
	if _life_left <= 0.0 or _travelled >= max_distance:
		queue_free()
		return
	if _life_left < fade_out_time:
		modulate.a = _life_left / fade_out_time
	var distance := minf(speed * delta, max_distance - _travelled)
	var collision := move_and_collide(direction * distance)
	_travelled += distance
	if collision != null:
		_hit(collision.get_collider(), collision.get_position(), collision.get_normal())

func _hit(body: Object, pos: Vector2, normal: Vector2) -> void:
	if _spent:
		return
	_spent = true
	Events.bullet_impact.emit(pos, normal)
	if is_instance_valid(body) and body.has_method("take_damage"):
		body.call("take_damage", damage, global_position)
	queue_free()
