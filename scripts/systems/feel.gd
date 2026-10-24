extends Node
## 打击感总管：顿帧 / 相机震动 / 慢动作。在 Autoload 里注册为 `Feel`。
##
## 这三样是"速杀"手感的地基：
##   顿帧   —— 命中瞬间画面停住。大脑会把这个停顿读成"打实了"。
##             它是这里最值钱的一样，成本极低、效果最明显。
##   震动   —— 让"发生了什么"有重量感，而不是屏幕上悄悄变了个数字。
##   慢动作 —— 清场收尾的仪式感（迈阿密热线的招牌）。
##
## 设计原则：**别的系统不直接碰 time_scale / 相机**，
## 只发 Events 信号，由这里统一决定"该有什么感觉"。
## 好处是调手感不用去翻开枪、开门的代码。

## 击杀时的顿帧。太长会让连杀变得拖沓；0.08 秒是"一顿"和"卡住"之间的分界。
const HIT_STOP_KILL := 0.08
## 玩家死亡时的顿帧。要更长更重 —— 这是一个"事件"，不是一次操作。
const HIT_STOP_DEATH := 0.15
## 顿帧时的时间缩放。**不要设成 0**：完全静止会让人以为游戏卡死了。
const HIT_STOP_SCALE := 0.04

## 开火时额外叠的随机抖动。连发时会积成一个持续的低频轰鸣，
## 真正表达"威力"的是定向后坐（见 game_camera.gd 的 kick）。
const FIRE_TRAUMA := 0.18
## 击杀 / 死亡时的抖动与镜头推进
const KILL_TRAUMA := 0.48
const DEATH_TRAUMA := 0.80
const KILL_ZOOM_PUNCH := 0.07
const DEATH_ZOOM_PUNCH := 0.10

## 清场慢动作
const SLOWMO_SCALE := 0.35
const SLOWMO_TIME := 0.9

## 正在顿帧 / 正在慢动作。两个都要记：顿帧结束时不能无脑恢复到 1.0，
## 否则会把正在进行的慢动作一起取消掉。
var _stopping: bool = false
var _slowing: bool = false


func _enter_tree() -> void:
	Events.bullet_fired.connect(_on_bullet_fired)
	Events.enemy_fired.connect(_on_enemy_fired)
	Events.enemy_died.connect(_on_enemy_died)
	Events.player_died.connect(_on_player_died)
	Events.door_moved.connect(_on_door_moved)
	Events.level_cleared.connect(_on_level_cleared)


# ------------------------------------------------------ 信号 → 手感（调这里）

func _on_bullet_fired(from: Vector2, to: Vector2) -> void:
	# 开火 = **定向后坐**（表达威力）+ 一点随机抖动（表达"炸"）。
	# 后坐朝子弹的反方向顶，所以每一发都看得清"往哪顶了一下"；
	# 光靠加大随机抖动的话，全自动连发只会糊成一片晃。
	_recoil((to - from).normalized())
	_shake(FIRE_TRAUMA)


func _on_enemy_fired(_pos: Vector2) -> void:
	_shake(0.09)


func _on_enemy_died(_pos: Vector2) -> void:
	hit_stop(HIT_STOP_KILL)
	_shake(KILL_TRAUMA)
	_punch_zoom(KILL_ZOOM_PUNCH)


func _on_player_died() -> void:
	hit_stop(HIT_STOP_DEATH)
	_shake(DEATH_TRAUMA)
	_punch_zoom(DEATH_ZOOM_PUNCH)


func _on_door_moved(_pos: Vector2, power: float) -> void:
	_shake(0.12 + power * 0.30)


func _on_level_cleared(_time_sec: float, _kills: int) -> void:
	slow_mo()


# ------------------------------------------------------------------ 顿帧

## 把时间缩到很小、再弹回来。
## `duration` 用**真实时间**计时（timer 忽略 time_scale），
## 否则时间被自己缩到 0.04 之后，这个等待会变成永远等不完。
func hit_stop(duration: float, scale: float = HIT_STOP_SCALE) -> void:
	if _stopping:
		return          # 已经在顿帧里就不叠加，否则连杀会把画面卡成一坨
	_stopping = true
	Engine.time_scale = scale
	await get_tree().create_timer(duration, true, false, true).timeout
	_stopping = false
	Engine.time_scale = SLOWMO_SCALE if _slowing else 1.0


# ---------------------------------------------------------------- 慢动作

func slow_mo() -> void:
	if _slowing:
		return
	_slowing = true
	if not _stopping:
		Engine.time_scale = SLOWMO_SCALE
	# 音频也一起慢：AudioServer.playback_speed_scale 会**同时**降音调和拉长时长。
	# 不设这一句的话，画面慢下来、枪声照常，听起来会像"声音飘在画面外面"。
	AudioServer.playback_speed_scale = SLOWMO_SCALE
	await get_tree().create_timer(SLOWMO_TIME, true, false, true).timeout
	_slowing = false
	AudioServer.playback_speed_scale = 1.0
	if not _stopping:
		Engine.time_scale = 1.0


# ------------------------------------------------------------------ 相机

## 关卡重载后相机是新的，所以每次都按组去找，不能缓存引用
func _camera() -> Node:
	return get_tree().get_first_node_in_group("game_camera")


func _shake(amount: float) -> void:
	var cam := _camera()
	if cam != null and cam.has_method("add_trauma"):
		cam.call("add_trauma", amount)


func _recoil(dir: Vector2) -> void:
	var cam := _camera()
	if cam != null and cam.has_method("kick"):
		cam.call("kick", dir)


func _punch_zoom(amount: float) -> void:
	var cam := _camera()
	if cam != null and cam.has_method("punch_zoom"):
		cam.call("punch_zoom", amount)
