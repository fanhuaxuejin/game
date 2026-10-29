extends RefCounted
## 武器被投掷命中后碎裂的像素碎片。纯视觉：不参与命中、不发噪声、不影响掉落。
##
## 为什么不干脆 queue_free 了事：投掷是一次要付出代价的控制，
## "啪一下就没了"会让玩家以为自己投空了。碎片是"这一下确实打实了"的证据。
##
## 做法和 main.gd 的击杀血点一致（现场生成 Polygon2D + 补间），不用粒子系统：
## 数量少、活得短，生成式更好调，也不牵进新的资源文件。
##
## ⚠️ 故意不写 `class_name`：新增全局类要刷新 `.godot` 里的类缓存，
## 而命令行 `--import` 在受限环境里写不进去。调用方用 `preload()` 就够了。

const COUNT := 14
const MIN_SPEED := 45.0
const MAX_SPEED := 120.0
const MIN_LIFE := 0.22
const MAX_LIFE := 0.42

## 金属碎片：亮钢 / 中灰 / 暗钢 / 黄铜，按序取用，保证一次爆开四色都有。
const COLORS := [
	Color(0.91, 0.93, 0.97),
	Color(0.63, 0.68, 0.75),
	Color(0.36, 0.40, 0.46),
	Color(0.76, 0.62, 0.29),
]


## 在 `at` 处炸开一把武器的碎片。`parent` 必须比武器本身活得久
## （传子弹容器即可）—— 碎片不能挂在马上要被 free 的节点下面。
static func burst(parent: Node, at: Vector2) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	for i in COUNT:
		var half := randf_range(0.8, 1.8)
		var shard := Polygon2D.new()
		shard.polygon = PackedVector2Array([
			Vector2(-half, -half), Vector2(half, -half),
			Vector2(half, half), Vector2(-half, half),
		])
		shard.color = COLORS[i % COLORS.size()]
		shard.position = at + Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
		# 和武器同一层：在墙下、地板之上，不会盖住人物。
		shard.z_index = -1
		shard.add_to_group("weapon_debris")
		parent.add_child(shard)

		var dir := Vector2.RIGHT.rotated(randf_range(0.0, TAU))
		var life := randf_range(MIN_LIFE, MAX_LIFE)
		var target := shard.position + dir * randf_range(MIN_SPEED, MAX_SPEED) * life
		var tween := shard.create_tween().set_parallel(true)
		tween.tween_property(shard, "position", target, life).set_ease(Tween.EASE_OUT)
		tween.tween_property(shard, "rotation", randf_range(-5.0, 5.0), life)
		tween.tween_property(shard, "modulate:a", 0.0, life).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(shard.queue_free)
