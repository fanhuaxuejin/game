class_name WeaponData
extends Resource
enum Kind { FIREARM, MELEE }
@export var kind: Kind = Kind.FIREARM
@export var visual_id: String = "pistol"
@export var visual_profile: WeaponVisualData
## 从旧多边形迁移出的身体到有效武器段起点，单位为世界px；不再读取图片或模型顶点。
@export var melee_inner: float = 14.0
@export var pellets: int = 1
@export var enemy_burst_size: int = 1
@export var enemy_shot_interval: float = 1.2
@export var enemy_burst_pause: float = 1.0
## 一把武器的全部参数。
##
## 用法：右键 FileSystem 面板 > New Resource > WeaponData，存到 `resources/weapons/`。
## 好处：调数值不用碰代码，复制一份 .tres 改几个数字就是一把新枪。

@export_group("伤害与射速")
@export var display_name: String = "消音手枪"
@export var damage: int = 1
## 两发之间的最小间隔（秒）
@export var fire_rate: float = 0.14
## false = 半自动，需要反复点击
@export var automatic: bool = true

@export_group("弹道")
## 散布半角（度）
@export var spread_deg: float = 1.5
@export var max_range: float = 900.0

@export_group("弹药")
## 每把枪一生的弹药上限；近战武器为 0，不表示无限射击。
@export var magazine: int = 12
## 兼容旧资源的字段；目前所有枪都不装弹，改它没有效果。
@export var reload_time: float = 0.9

@export_group("声音与反馈")
## 噪声传播半径。0 = 无声。
## ⚠️ 这是本作的核心机制：吵的枪会把敌人引过来，所以"刀"才有存在意义。
##
## 参考尺寸（1 格 = 16px，一个房间约 15 格宽 = 240px）：
##   320 → 盖住"本房间 + 隔壁房间"，开枪就被两个房间包夹，惩罚过重
##   200 → 大约"本房间 + 门口"（当前霰弹枪）
##   120 → 只有贴脸的人听得到
##
## 注意：实际听距 = 本值 × 敌人的 hearing_multiplier
## 巡逻不改变听力；消音手枪 0、冲锋枪 180、霰弹枪 200。
@export var noise_radius: float = 0.0
## 预留给 M2 的击退
@export var knockback: float = 220.0
