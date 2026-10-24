extends Enemy
## 追到武器可触及的位置才起手，碰到身体本身不造成伤害。
func _should_attack() -> bool:
	return can_see_player()

func _ai_chase(delta: float) -> void:
	_move_toward_point(last_known_pos, delta)

func _ai_attack(delta: float) -> void:
	_ai_melee(delta)
