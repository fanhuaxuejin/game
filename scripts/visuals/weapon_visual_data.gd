class_name WeaponVisualData
extends Resource
## 锚点使用原始素材像素；只有显示层转换单位，不能反推命中范围。
@export var texture: Texture2D
## 手持时专用的"俯视角"贴图：从正上方看只能看到枪的顶面，
## 那和平躺在地上看到的侧面轮廓**不是同一张图**。
## 留空表示该武器不分状态（刀从上方和侧面几乎一样，只给 texture 就够）。
## 两张图共用同一套锚点：握持点、枪口、地面中心都是原始素材像素坐标。
@export var held_texture: Texture2D
## 手持姿态：武器不该"直直顶在身前"，而是像真握在手里 ——
## 相对瞄准方向斜一点（`held_tilt_deg`，负值 = 枪口向上偏），
## 再往持枪手那一侧偏一点（`held_shift`，**世界像素**）。
## 只作用于显示子节点，不动 WeaponView 自身的位置/旋转：
## 挥击伸出量和 28px 刀尖半径都读 WeaponView，改这里不影响命中。
@export var held_tilt_deg: float = 0.0
@export var held_shift := Vector2.ZERO
@export var sample_id: String = ""
@export var pixels_per_unit: float = 4.0
@export var grip_px := Vector2(8, 8)
@export var muzzle_px := Vector2(80, 8)
@export var tip_px := Vector2(80, 8)
@export var ground_center_px := Vector2(52, 14)

func get_texture() -> Texture2D:
	return texture if texture != null else VisualSamples.weapon_texture(sample_id)

## 躺着 / 飞行中用的侧面图；手里拿着时由 WeaponView 优先取 held_texture。
func get_held_texture() -> Texture2D:
	return held_texture if held_texture != null else get_texture()

func point_from_grip(point: Vector2) -> Vector2:
	return (point - grip_px) / maxf(pixels_per_unit, 0.001)
