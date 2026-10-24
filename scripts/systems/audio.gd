extends Node
## 音频总管。在 Project Settings > Autoload 里注册为 `Audio`（排在 `Events` 之后）。
##
## 设计：别的系统只管发 `Events` 信号，这里统一决定放哪个声音。
## 好处是"加一个音效"不用去改开枪 / 开门的代码。
##
## ⚠️ 必须是 Autoload，不能挂在关卡里：
## 重开时关卡会被 queue_free，挂在它下面的播放器跟着一起消失 ——
## 清场音效会被当场掐断，死亡音效也放不完。
##
## resources/audio 中的音频已经预处理好，包含真实采样与合成反馈音，运行时直接加载。
## 旧素材加工工具已移出游戏工程；更换音频后仍需完成 Godot 资源导入。
##
## ⚠️ 加新音效时的一个陷阱（踩过一次）：
## `.wav` 必须先被 Godot 导入，`preload` 才能成功。而命令行跑 `--import` 时，
## 它会先编译 Autoload 脚本 —— 如果这个脚本 preload 了一个还没导入的 wav，
## 编译就失败、导入扫描随之中止，wav 永远导不进来（死循环）。
## 解法：新加音频时先在编辑器里打开一次（编辑器会自动导入），
## 或者临时把本 Autoload 从 project.godot 摘掉、跑一次 `--import`、再加回来。

# ------------------------------------------------------------------ 素材

const SHOT_PLAYER := preload("res://resources/audio/shot_player.wav")
const SHOT_ENEMY := preload("res://resources/audio/shot_enemy.wav")
const IMPACT := preload("res://resources/audio/impact.wav")
const KILL := preload("res://resources/audio/kill.wav")
const PLAYER_DIE := preload("res://resources/audio/player_die.wav")
const DOOR := preload("res://resources/audio/door.wav")
const STUN := preload("res://resources/audio/stun.wav")
const RELOAD := preload("res://resources/audio/reload.wav")

## 全部音效的清单。冒烟测试用它检查素材有没有漏、能不能加载。
const ALL := {
	"shot_player": SHOT_PLAYER,
	"shot_enemy": SHOT_ENEMY,
	"impact": IMPACT,
	"kill": KILL,
	"player_die": PLAYER_DIE,
	"door": DOOR,
	"stun": STUN,
	"reload": RELOAD,
}

## 2D 音效的听距（像素）。超过就听不见 —— 远处房间的枪声不该吵到你。
## 参考：一个房间约 240px 宽，所以 820 大约覆盖"隔壁房间"的范围。
const HEAR_DISTANCE := 820.0

## 同时存在的播放器上限。连发武器一秒能打 7 发，不上限的话节点会越堆越多。
const MAX_VOICES := 48

## 已经放过的音效次数。给冒烟测试用。
var played: int = 0
## 最近放的音效名。给冒烟测试用。
var last_key: String = ""
## 最近放过的音效名（最多 32 条）。冒烟测试用它判断"某个声音有没有响过"，
## 这样不用去猜信号连接顺序（同一帧里放好几个音时 last_key 只有一个）。
var history: Array[String] = []

## 跨关卡存活的一路，专门放"不定位"的声音（自己死亡、装填）
var _global_player: AudioStreamPlayer


func _enter_tree() -> void:
	_global_player = AudioStreamPlayer.new()
	add_child(_global_player)

	# 连接写在 _enter_tree：Autoload 早于主场景，能接住玩家出生时的第一发枪声
	Events.bullet_fired.connect(_on_bullet_fired)
	Events.bullet_impact.connect(_on_bullet_impact)
	Events.enemy_fired.connect(_on_enemy_fired)
	Events.enemy_died.connect(_on_enemy_died)
	Events.enemy_stunned.connect(_on_enemy_stunned)
	Events.player_died.connect(_on_player_died)
	Events.door_moved.connect(_on_door_moved)
	# ⚠️ 清场**故意不接音效**：改由 Feel.slow_mo() 把画面和音频一起慢下来。
	# 一声胜利琶音会把"最后一击"的余韵打断，慢放反而更有仪式感。


# ------------------------------------------------- 信号 → 声音（改这里就能调）

func _on_bullet_fired(from: Vector2, _to: Vector2) -> void:
	# 换成真实霰弹录音后 RMS 比合成版高约 2.5dB，所以往下压一点
	_at("shot_player", from, -6.0, 0.05)


func _on_bullet_impact(pos: Vector2, _normal: Vector2) -> void:
	_at("impact", pos, -9.0, 0.14)


func _on_enemy_fired(pos: Vector2) -> void:
	# 比玩家的枪闷一点、轻一点：听声就能分辨是谁在开枪
	_at("shot_enemy", pos, -7.0, 0.06)


func _on_enemy_died(pos: Vector2) -> void:
	_at("kill", pos, -3.0, 0.07)


func _on_enemy_stunned(pos: Vector2) -> void:
	_at("stun", pos, -6.0, 0.05)


func _on_door_moved(pos: Vector2, power: float) -> void:
	# ⚠️ 方向别写反：power 越大 = 撞得越狠 = 应该**越响**（db 越大越接近 0）
	# 和**音调越低**。真实门声的 RMS 只有枪声的约 1/3，所以基础音量给得比别的音效高。
	var db: float = -7.0 + clampf(power, 0.0, 1.0) * 4.0
	var pitch: float = 1.05 - clampf(power, 0.0, 1.0) * 0.18
	_at("door", pos, db, 0.06, pitch)


func _on_player_died() -> void:
	_global("player_die", -2.0)


# ------------------------------------------------------------------ 播放

## 在某个世界坐标放一个音效。会自动跟着相机做左右声像和距离衰减。
## `base_pitch` 是整体音调（门撞得越狠越低），`pitch_jitter` 是在它之上的随机抖动。
func _at(key: String, pos: Vector2, volume_db: float, pitch_jitter: float,
		base_pitch: float = 1.0) -> void:
	var stream: AudioStream = ALL.get(key)
	if stream == null:
		return
	if get_child_count() >= MAX_VOICES:
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = stream
	p.volume_db = volume_db
	# 每次音调略有随机，连发时不会听起来像复读机
	p.pitch_scale = base_pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	p.max_distance = HEAR_DISTANCE
	p.attenuation = 1.0
	add_child(p)                  # 挂在 Autoload 下：重开关卡也不会被掐断
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
	_note(key)


## 不定位的声音（自己死亡、清场、装填）
func _global(key: String, volume_db: float) -> void:
	var stream: AudioStream = ALL.get(key)
	if stream == null:
		return
	_global_player.stream = stream
	_global_player.volume_db = volume_db
	_global_player.play()
	_note(key)


func _note(key: String) -> void:
	played += 1
	last_key = key
	history.append(key)
	if history.size() > 32:
		history.pop_front()


## 清空记录。冒烟测试用来隔离每一段观察。
func clear_history() -> void:
	history.clear()
	played = 0
	last_key = ""


## 素材齐不齐。冒烟测试用。
func all_loaded() -> bool:
	for key in ALL:
		if ALL[key] == null:
			return false
	return ALL.size() == 8
