class_name WeaponState
extends RefCounted
## 定义可以共享，弹药必须属于实物；拾取和投掷只转移实例，绝不重新装满。
var definition: WeaponData
var ammo: int

func _init(data: WeaponData) -> void:
	definition = data
	ammo = data.magazine if data != null and data.kind == WeaponData.Kind.FIREARM else 0

func can_shoot() -> bool:
	return definition.kind == WeaponData.Kind.FIREARM and ammo > 0

func consume_round() -> bool:
	if not can_shoot():
		return false
	ammo -= 1
	return true
