extends Level
## 独立验收房间：只在内存布置，绝不写回正式关卡或固定夹具。
const ITEM := preload("res://scenes/projectiles/ThrownWeapon.tscn")
const IDS := ["pistol", "knife", "dagger", "machete", "katana", "smg", "shotgun"]
var _status: Label
var _help: Label

func _ready() -> void:
	for y in range(20):
		for x in range(32):
			$Floor.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
			if x == 0 or x == 31 or y == 0 or y == 19:
				$Walls.set_cell(Vector2i(x, y), 0, Vector2i(2, 0))
	for y in range(7, 13):
		$Walls.set_cell(Vector2i(25, y), 0, Vector2i(2, 0))
	super._ready()
	for i in range(IDS.size()):
		var item := ITEM.instantiate()
		item.weapon_instance = WeaponState.new(load("res://resources/weapons/%s.tres" % IDS[i]))
		item.landed = true
		$Projectiles.add_child(item)
		item.position = Vector2(112 + i * 36, 232)
	_status = $HUD/Status
	_help = $HUD/Help
	Events.enemy_died.connect(_on_kill)

func _process(_delta: float) -> void:
	if _status == null:
		return
	var held := player.weapon_instance
	var text := "空手 · 推击"
	if held != null:
		text = held.definition.display_name
		if held.definition.kind == WeaponData.Kind.FIREARM:
			text += "  %d/%d%s" % [held.ammo, held.definition.magazine, " · 空枪近战" if held.ammo == 0 else ""]
	_status.text = "%s  |  %s" % [text, "已倒地 · R 重置" if player.is_dead else "WASD 移动 · 鼠标瞄准"]

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_R:
		get_tree().reload_current_scene()
	elif event.keycode == KEY_TAB:
		# 仅在预览暂停敌人物理（含眩晕计时），显示仍播放，便于安全观察动作。
		for enemy: Enemy in $Enemies.get_children():
			enemy.set_physics_process(not enemy.is_physics_processing())
		_help.text = "Tab 切换 AI · R 重置房间；1～7 换样板武器，0 空手"
	elif event.keycode == KEY_0:
		player.equip_weapon(null)
	elif event.keycode >= KEY_1 and event.keycode <= KEY_7:
		player.equip_weapon(WeaponState.new(load("res://resources/weapons/%s.tres" % IDS[event.keycode - KEY_1])))

func _on_kill(pos: Vector2) -> void:
	add_blood(pos)
