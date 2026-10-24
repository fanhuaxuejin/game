extends Camera2D
## 相机效果：随机抖动（trauma）+ 定向后坐 + 镜头推进。挂在 Player/Camera2D 上。
##
## 三种效果是**分开的**，因为它们表达的东西不一样：
##
##   随机抖动（trauma）—— 表达"撞击"。用创伤值模型：连续受击会自然叠加变强，
##                        平方映射让层次分明，衰减到 0 就彻底静止。
##   定向后坐（recoil）—— 表达"威力"。**朝开枪的反方向顶一下**再收回。
##                        为什么不复用随机抖动：手枪是全自动（0.14 秒一发），
##                        随机抖动连发时会糊成一片持续晃动，只剩"糊"没有"威力"；
##                        定向后坐每一发都能看清"往哪顶了一下"。
##   镜头推进（zoom）—— 表达"这一下很重"。击杀瞬间拉近一点再弹回。
##
## 谁想触发就调对应的方法，见 scripts/systems/feel.gd。

# ---------------------------------------------------------------- 随机抖动

## 最大位移（像素）。配合 snap_2d_transforms_to_pixel，抖动会落在整数像素上。
const MAX_OFFSET := 7.0
## 最大旋转（弧度）。约 2.3 度 —— 再多就会让人晕。
const MAX_ROLL := 0.04
## 每秒衰减多少创伤值。越大收得越快。
const DECAY := 2.8

# ---------------------------------------------------------------- 定向后坐

## 单发后坐顶多少像素
const RECOIL_KICK := 6.0
## 每秒收回多少像素。90 的话 6px 大约 0.07 秒回完 —— 干脆，不拖泥带水
const RECOIL_RETURN := 90.0
## 后坐位移上限。连发时叠加到这里为止，避免把视野顶飞
const MAX_RECOIL := 10.0

# ---------------------------------------------------------------- 镜头推进

## 推进幅度（比例）。0.07 = 拉近 7%
const ZOOM_PUNCH := 0.07
## 每秒收回多少推进量
const ZOOM_RETURN := 5.0

# ------------------------------------------------------------------ 视野

## 视野缩放。**数值越大，看得越少**（按窗口 640x360、格子 16px 算）。
##
## 关卡里的房间是 **15 格宽 x 13 格高 = 240 x 208 px**。要"正好看见一个完整房间"，
## 起决定作用的是**高度**（16:9 的横向天然看得更宽）：
##
##     zoom 2.0  → 可见 320x180 px = 20.0 x 11.3 格   纵向装不下房间 ✗
##     zoom 1.7  → 可见 376x212 px = 23.5 x 13.2 格   刚刚好装下一个房间
##     zoom 1.6  → 可见 400x225 px = 25.0 x 14.1 格   一个房间 + 一点余量
##     zoom 1.35 → 可见 474x267 px = 29.6 x 16.7 格   一个房间 + 明显余量 ← 默认
##     zoom 1.2  → 可见 533x300 px = 33.3 x 18.8 格   开始能瞄到隔壁房间
##     zoom 1.0  → 可见 640x360 px = 40.0 x 22.5 格   看得见隔壁房间，没有紧张感
##
## 粗略记法：**每放大 5 格宽 ≈ zoom 减少 0.25**。
##
## 为什么用这个参数，而不是 Camera2D 自带的 zoom：
## 本脚本每帧都要拿"基准缩放"重算 zoom（击杀时要做镜头推进），
## 所以在 Inspector 里直接改 zoom 会被每帧覆盖掉 —— 要改就改这里。
##
## ⚠️ 缩小视野会连带削弱远程兵的公平性：它在 300px 外就能开火，
## 而子弹速度 1500px/s（300px 只要 0.2 秒）。视野越小，它越可能在画面外开枪、
## 你等于没有预警 —— 配套要调小 EnemyRanged.tscn 的
## vision_range / engage_range / preferred_range（见该文件里的说明）。
@export var view_zoom: float = 1.35

var trauma: float = 0.0
var _recoil: Vector2 = Vector2.ZERO
var _zoom_punch: float = 0.0
var _base_zoom: Vector2 = Vector2.ONE


func _ready() -> void:
	# Feel 靠这个组找相机（关卡重载后玩家和相机都是新的，不能用硬引用）
	add_to_group("game_camera")
	set_view_zoom(view_zoom)


## 运行时改视野。过场和冒烟测试都用得上。
func set_view_zoom(v: float) -> void:
	view_zoom = maxf(v, 0.1)
	_base_zoom = Vector2(view_zoom, view_zoom)
	zoom = _base_zoom


## 累加创伤。amount 取 0~1：0.1 是一记轻晃，0.7 是玩家死了。
func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## 开火后坐。`dir` 是**子弹飞出去的方向**，相机朝反方向顶 —— 就是你被推了一下。
func kick(dir: Vector2, amount: float = RECOIL_KICK) -> void:
	if dir.length_squared() < 0.0001:
		return
	_recoil = (_recoil - dir.normalized() * amount).limit_length(MAX_RECOIL)


## 镜头猛推一下（击杀时用）
func punch_zoom(amount: float = ZOOM_PUNCH) -> void:
	_zoom_punch = maxf(_zoom_punch, amount)


func _process(delta: float) -> void:
	# --- 随机抖动 ---
	var shake := Vector2.ZERO
	if trauma > 0.0:
		trauma = maxf(trauma - DECAY * delta, 0.0)
		var amp: float = trauma * trauma          # 平方映射：层次感的关键
		shake = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * MAX_OFFSET * amp
		rotation = randf_range(-1.0, 1.0) * MAX_ROLL * amp
	else:
		rotation = 0.0                            # 归零，别残留最后一帧的角度

	# --- 定向后坐收回 ---
	_recoil = _recoil.move_toward(Vector2.ZERO, RECOIL_RETURN * delta)

	# --- 镜头推进收回 ---
	_zoom_punch = move_toward(_zoom_punch, 0.0, ZOOM_RETURN * delta)
	zoom = _base_zoom * (1.0 + _zoom_punch)

	offset = shake + _recoil
