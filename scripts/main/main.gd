extends Node2D
## 游戏根节点。职责：关卡加载与推进、HUD、全局特效、瞬间重开。
##
## 地图和敌人已经不在这个场景里了 —— 它们由关卡场景提供（见 scripts/levels/level.gd）。
## 这个场景只保留"跨关卡"的东西：HUD、曳光弹、关卡容器。

## 关卡顺序。新增关卡时在这里加一行即可。
const LEVELS: Array[String] = [
	"res://scenes/levels/Level_01.tscn",
	"res://scenes/levels/Level_02.tscn",
	"res://scenes/levels/Level_03.tscn",
]

## 实际存在的关卡（_ready 时算一次，顺序同 LEVELS）。
##
## ⚠️ 为什么要过滤：关卡是随时在增删的内容。如果清单里留着一个已经删掉的文件，
## 推进到那一关时 load() 返回 null，结果是**游戏卡在原地、只有一行报错** ——
## 玩家那边看起来就是"打完这关就不动了"。删掉关卡不该让整个流程崩掉。
var _live_levels: Array[String] = []

## 清场后等多久自动进下一关
const ADVANCE_DELAY := 1.6

## 击杀时溅出的血点数量
const KILL_BLOOD_DOTS := 16

@onready var level_host: Node2D = $LevelHost
@onready var fx: Node2D = $FX
@onready var hint_label: Label = $HUD/HintLabel
@onready var status_label: Label = $HUD/StatusLabel
@onready var ammo_label: Label = $HUD/AmmoLabel
@onready var clear_label: Label = $HUD/ClearLabel
@onready var death_panel: Control = $HUD/DeathPanel

var level: Level = null
var level_index: int = 0
var kills: int = 0
var _hud_weapon: Resource = null

var _dead: bool = false
var _cleared: bool = false
var _advance_left: float = -1.0
## 本关开始的时间戳（秒）。用来在清场时报告用时。
var _started_at: float = 0.0


func _enter_tree() -> void:
	# 必须在 _enter_tree 连接：子节点的 _ready 早于父节点，
	# 若在 _ready 里连接，就会漏掉玩家出生时发出的那条信号。
	Events.player_died.connect(_on_player_died)
	Events.enemy_died.connect(_on_enemy_died)
	Events.ammo_changed.connect(_on_ammo_changed)
	Events.weapon_changed.connect(_on_weapon_changed)


func _ready() -> void:
	death_panel.visible = false
	clear_label.visible = false
	hint_label.text = "WASD 移动 · 左键射击 · 右键投掷 · E 拾取 · R 重开"
	# 只保留真的存在的关卡文件（清单里删掉的会被跳过并警告）
	for p in LEVELS:
		if ResourceLoader.exists(p):
			_live_levels.append(p)
		else:
			push_warning("关卡文件不存在，已跳过：%s" % p)
	_load_level(0)


## 加载第 index 关（同一关可以被重复调用 = 重开）。
## 返回是否真的加载了：没有可用关卡时返回 false。
func _load_level(index: int) -> bool:
	if _live_levels.is_empty():
		printerr("没有任何可用的关卡文件，检查 main.gd 里 LEVELS 的路径")
		return false
	level_index = clampi(index, 0, _live_levels.size() - 1)
	_load_path(_live_levels[level_index])
	return true


## 按路径加载一关。**给冒烟测试用的钩子。**
##
## 为什么要它：冒烟测试里几十条断言都建立在"关卡长什么样"上（敌人在哪、
## 门在哪、墙在哪）。如果测试跑在玩家会手工编辑的正式关卡上，
## 玩家一改关卡，测试就整片飘红 —— 分不清是"功能坏了"还是"关卡改了"。
## 所以测试跑在专门的 Level_test.tscn 上，正式关卡随便改。
##
## 保留 level_index = 0：这样测试关卡清场后，推进逻辑仍然走向 Level_02，
## "清场自动进下一关"那条断言才有意义。
func load_level_file(path: String) -> void:
	level_index = 0
	_load_path(path)


func _load_path(path: String) -> void:
	if level != null:
		# ⚠️ 先 remove_child 再 queue_free，不要只 queue_free。
		# queue_free 是**帧末**才真正删除，那之前旧关卡仍然在树里 ——
		# 它的 Player 也还留在 "player" 组里。新关卡的敌人 _ready 时
		# get_first_node_in_group("player") 就会抓到那个**马上要消失的**玩家，
		# 之后引用失效、敌人永远瞎着（而且不报错）。
		# 先摘出树，旧关卡立刻从各个组里消失，新关卡就只会看到自己的玩家。
		level_host.remove_child(level)
		level.queue_free()
		level = null

	var ps := load(path) as PackedScene
	if ps == null:
		printerr("无法加载关卡：", path)
		return

	kills = 0
	_dead = false
	_cleared = false
	_advance_left = -1.0
	_started_at = Time.get_ticks_msec() / 1000.0
	death_panel.visible = false
	clear_label.visible = false

	level = ps.instantiate() as Level
	level_host.add_child(level)
	_update_status()


func _process(delta: float) -> void:
	# 清场后延迟一小会儿再进下一关，让玩家看清最后的击杀
	if _advance_left > 0.0:
		_advance_left -= delta
		if _advance_left <= 0.0:
			_advance_left = -1.0
			if level_index + 1 < _live_levels.size():
				_load_level(level_index + 1)
			else:
				clear_label.text = "全部通关！按 R 重开"
		return

	var wants_restart: bool = Input.is_action_just_pressed("restart")
	# 迈阿密热线式：死后按左键也能重开，手不用离开鼠标
	if _dead and Input.is_action_just_pressed("fire"):
		wants_restart = true
	if wants_restart:
		_load_level(level_index)


## 组 "enemies" 里只有活着的敌人 —— 死亡的敌人会自己退组（见 enemy.gd 的 _die）
func _update_status() -> void:
	status_label.text = "击杀 %d · 剩余 %d" % [kills, get_tree().get_nodes_in_group("enemies").size()]


func _on_enemy_died(pos: Vector2) -> void:
	kills += 1
	if level != null:
		level.add_blood(pos)
	_spawn_blood_burst(pos)
	_spawn_kill_flash(pos)
	_update_status()
	if not _cleared and get_tree().get_nodes_in_group("enemies").is_empty():
		_cleared = true
		clear_label.text = "清场！"
		clear_label.visible = true
		_advance_left = ADVANCE_DELAY
		# 通知音频总管放清场音（顺带把用时和击杀数带出去，以后做结算面板要用）
		Events.level_cleared.emit(Time.get_ticks_msec() / 1000.0 - _started_at, kills)


func _on_player_died() -> void:
	_dead = true
	death_panel.visible = true


## 击杀时溅出一小把血点。纯视觉，不参与任何玩法判定。
##
## 用代码现场生成 Polygon2D，而不是提前做一个粒子系统：
## 数量少、活得短，生成式反而更好调、也不用管资源。
func _spawn_blood_burst(pos: Vector2) -> void:
	for i in KILL_BLOOD_DOTS:
		var half := randf_range(1.5, 3.5)
		var dot := Polygon2D.new()
		dot.polygon = PackedVector2Array([
			Vector2(-half, -half), Vector2(half, -half),
			Vector2(half, half), Vector2(-half, half),
		])
		dot.color = Color(0.62, 0.05, 0.07).lightened(randf_range(0.0, 0.25))
		dot.position = pos
		fx.add_child(dot)

		var target := pos + Vector2.RIGHT.rotated(randf_range(0.0, TAU)) * randf_range(18.0, 72.0)
		var life := randf_range(0.26, 0.42)
		var t := create_tween().set_parallel(true)
		t.tween_property(dot, "position", target, life).set_ease(Tween.EASE_OUT)
		t.tween_property(dot, "modulate:a", 0.0, life)
		t.chain().tween_callback(dot.queue_free)


## 击杀处的一记白闪。
##
## 比溅血更"响"，而且位置精准 —— 玩家一眼就知道"是这里、这一下"。
## 用菱形而不是圆形：平涂色块的美术风格下，菱形更搭，也不用做圆的多边形。
func _spawn_kill_flash(pos: Vector2) -> void:
	var flash := Polygon2D.new()
	flash.polygon = PackedVector2Array([
		Vector2(0.0, -6.0), Vector2(6.0, 0.0), Vector2(0.0, 6.0), Vector2(-6.0, 0.0),
	])
	flash.color = Color(1.0, 0.97, 0.85, 0.95)
	flash.position = pos
	flash.scale = Vector2(0.4, 0.4)
	flash.rotation = randf_range(0.0, TAU)
	fx.add_child(flash)

	var t := create_tween().set_parallel(true)
	t.tween_property(flash, "scale", Vector2(3.6, 3.6), 0.15).set_ease(Tween.EASE_OUT)
	t.tween_property(flash, "modulate:a", 0.0, 0.15)
	t.chain().tween_callback(flash.queue_free)


func _on_weapon_changed(definition: Resource) -> void:
	_hud_weapon = definition


func _on_ammo_changed(current: int, capacity: int) -> void:
	if ammo_label == null:
		return
	if _hud_weapon == null:
		ammo_label.text = "空手 · 左键推击"
	elif capacity == 0:
		ammo_label.text = _hud_weapon.display_name
	elif current <= 0:
		ammo_label.text = "%s · 空枪近战" % _hud_weapon.display_name
	else:
		ammo_label.text = "%s %d / %d" % [_hud_weapon.display_name, current, capacity]
