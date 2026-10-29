extends Level
## 地图直接保存在新场景中，F6和编辑器看到同一份布局，不触碰用户的关卡。
const IDS := ["pistol", "knife", "dagger", "machete", "katana", "smg", "shotgun"]
var ai_enabled := false


func _ready() -> void:
	super._ready()
	_set_ai(false)


func _set_ai(enabled: bool) -> void:
	ai_enabled = enabled
	for enemy: Enemy in $Enemies.get_children():
		enemy.set_physics_process(enabled)
	$HUD/Status.text = "AI：%s  |  家具只挡移动，子弹与视线可越过" % ("运行" if enabled else "暂停")


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_R:
			get_tree().reload_current_scene()
		KEY_F8:
			_set_ai(not ai_enabled)
		KEY_C:
			get_tree().debug_collisions_hint = not get_tree().debug_collisions_hint
			# 内置开关对已创建碰撞体不总会刷新，独立绘制一份实际形状轮廓。
			$CollisionOverlay.visible = get_tree().debug_collisions_hint
			$CollisionOverlay.queue_redraw()
		KEY_0:
			player.equip_weapon(null)
		_:
			if event.keycode >= KEY_1 and event.keycode <= KEY_7:
				player.equip_weapon(WeaponState.new(load("res://resources/weapons/%s.tres" % IDS[event.keycode - KEY_1])))
