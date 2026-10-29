extends SceneTree
var room: Node2D
var player: Node2D
var camera: Camera2D
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, result: bool) -> void:
	checks += 1
	if not result: failures += 1
	print("%s %s" % ["PASS" if result else "FAIL", label])

func settle() -> void:
	await physics_frame
	await physics_frame

func update() -> void:
	player.call("_process", 0.0)

func toggle() -> void:
	player.get("aim_lock").set("toggle_requested", true)
	update()

func cycle() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_TAB
	event.physical_keycode = KEY_TAB
	event.pressed = true
	root.push_input(event, true)
	update()
	var released := event.duplicate() as InputEventKey
	released.pressed = false
	root.push_input(released, true)

func enemy(offset: Vector2) -> Node2D:
	var value: Node2D = load("res://scenes/enemies/EnemyMelee.tscn").instantiate()
	room.add_child(value)
	value.global_position = player.global_position + offset
	value.set_physics_process(false)
	return value

func equip(id: String, ammo := -1) -> RefCounted:
	var state: RefCounted = load("res://scripts/weapons/weapon_state.gd").new(load("res://resources/weapons/%s.tres" % id))
	if ammo >= 0: state.set("ammo", ammo)
	player.call("equip_weapon", state)
	return state

func wall(pos: Vector2, mask: int) -> Node2D:
	var body := StaticBody2D.new()
	body.collision_layer = mask
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(2, 8)
	collision.shape = shape
	body.add_child(collision)
	room.add_child(body)
	body.global_position = pos
	return body

func _run() -> void:
	room = load("res://scenes/levels/Level_test.tscn").instantiate()
	root.add_child(room)
	player = room.get_node("Player")
	player.set_physics_process(false)
	player.set_process(false)
	for value in get_nodes_in_group("enemies"): value.queue_free()
	await settle()
	player.global_position = Vector2(1400,1400)
	camera = player.get_node("Camera2D")
	camera.set_process(false)
	camera.limit_left = -100000
	camera.limit_top = -100000
	camera.limit_right = 100000
	camera.limit_bottom = 100000
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2(1.35,1.35)
	camera.force_update_scroll()
	await settle()
	cycle()
	check("关闭时空场Tab不启用自动锁定", not player.get("aim_lock").get("enabled") and player.get("lock_target") == null)
	toggle()
	check("空场也能开启，保持等待目标而非自动关闭", player.get("aim_lock").get("enabled") and player.get("lock_target") == null)
	var rear := enemy(Vector2(-60,0))
	rear.set("vision_range",1.0)
	rear.set("vision_angle_deg",1.0)
	player.get_node("Aim").rotation = 0.0
	await settle()
	update()
	check("背后敌人入画自动锁定，不受双方朝向/视锥限制", player.get("lock_target") == rear and absf(absf(player.get_node("Aim").global_rotation)-PI) < 0.001)
	rear.global_position = player.global_position+Vector2(-1000,0)
	update()
	check("最后一个目标离开解除边界后等待，不关闭功能", player.get("aim_lock").get("enabled") and player.get("lock_target") == null)
	toggle()
	rear.global_position = player.global_position+Vector2(-60,0)
	await settle()
	update()
	check("等待时中键能关闭，随后入画也不自动选人", not player.get("aim_lock").get("enabled") and player.get("lock_target") == null)
	toggle()
	for mask in [1,128,64]:
		var blocker := wall(player.global_position+Vector2(-30,0),mask)
		await settle()
		update()
		check("单目标被层%d遮挡时保留开启并等待" % mask, player.get("aim_lock").get("enabled") and player.get("lock_target") == null)
		blocker.queue_free()
		await settle()
		update()
		check("层%d遮挡消失后无需再按中键自动重获" % mask, player.get("lock_target") == rear)
	rear.global_position = player.global_position+Vector2(350,0)
	player.get("aim_lock").call("set_target",null)
	update()
	check("人物正前方但在相机外的敌人不会新锁定", player.get("lock_target") == null)
	camera.position = Vector2(200,0)
	camera.force_update_scroll()
	update()
	check("只平移相机使敌人入画也自动锁定", player.get("lock_target") == rear)
	# 清掉当前目标以检查候选选取，避免离屏保持规则掩盖zoom导致的边界变化。
	camera.position = Vector2.ZERO
	camera.force_update_scroll()
	player.get("aim_lock").call("set_target",null)
	update()
	camera.zoom = Vector2(0.75,0.75)
	camera.force_update_scroll()
	update()
	check("只缩小相机zoom使敌人入画也自动锁定", player.get("lock_target") == rear)
	toggle()
	rear.queue_free()
	camera.zoom = Vector2(1.35,1.35)
	camera.force_update_scroll()
	await settle()
	var a := enemy(Vector2(40,0))
	var b := enemy(Vector2(80,30))
	var c := enemy(Vector2(120,0))
	await settle()
	cycle()
	check("未锁定Tab不主动锁人", player.get("lock_target") == null)
	# 中键走真实输入分发；目标选择仍只在_process发生。
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.pressed = true
	middle.position = Vector2(320,180)
	root.push_input(middle, true)
	await process_frame
	update()
	var released := middle.duplicate() as InputEventMouseButton
	released.pressed = false
	root.push_input(released, true)
	await process_frame
	check("中键默认锁最近且瞄向目标", player.get("lock_target") == a and absf(player.get_node("Aim").global_rotation) < 0.001)
	check("锁定框在世界坐标跟随，绝对z100", player.get_node("LockReticle").visible and player.get_node("LockReticle").global_position == a.global_position and player.get_node("LockReticle").z_index == 100 and not player.get_node("LockReticle").z_as_relative)
	cycle()
	check("Tab选次近且立即同步瞄准", player.get("lock_target") == b and absf(player.get_node("Aim").global_rotation - (b.global_position-player.global_position).angle()) < 0.001)
	cycle()
	cycle()
	check("Tab按距离循环返回最近", player.get("lock_target") == a)
	toggle()
	update()
	check("关闭恢复鼠标方向", player.get("lock_target") == null and absf(wrapf(player.get_node("Aim").global_rotation - (player.get_global_mouse_position()-player.global_position).angle(),-PI,PI)) < 0.001)
	for mask in [1,128,64]:
		var obstacle := wall(player.global_position+Vector2(20,0), mask)
		await settle()
		toggle()
		check("墙/门/门缝层%d遮挡最近目标" % mask, player.get("lock_target") == b)
		toggle()
		obstacle.queue_free()
		await settle()
	var furniture := wall(player.global_position+Vector2(20,0),256)
	await settle()
	toggle()
	check("低矮家具不阻挡锁定", player.get("lock_target") == a)
	furniture.queue_free()
	await settle()
	var rect: Rect2 = player.get("aim_lock").call("camera_rect")
	a.global_position = rect.get_center()+Vector2(rect.size.x*0.5+30,0)
	await settle()
	update()
	check("目标离开选取范围仍保持锁定", player.get("lock_target") == a and not player.get("aim_lock").call("candidates").has(a))
	cycle()
	check("Tab不选相机范围外的目标", player.get("lock_target") == b)
	toggle()
	a.global_position = player.global_position+Vector2(40,0)
	await settle()
	toggle()
	a.global_position = rect.get_center()+Vector2(rect.size.x*0.75+2,0)
	await settle()
	update()
	check("超出1.5倍相机范围释放原目标并自动选最近", player.get("lock_target") == b and player.get("aim_lock").get("enabled"))
	a.global_position = player.global_position+Vector2(40,0)
	c.global_position = player.global_position+Vector2(220,0)
	camera.zoom = Vector2(2,2)
	camera.force_update_scroll()
	check("动态zoom即时改变候选范围", not player.get("aim_lock").call("candidates").has(c))
	camera.zoom = Vector2(1.35,1.35)
	camera.force_update_scroll()
	check("相机恢复后目标可再选", player.get("aim_lock").call("candidates").has(c))
	toggle()
	toggle()
	a.queue_free()
	await settle()
	update()
	check("目标释放后安全切到最近存活敌人", player.get("lock_target") == b)
	var state := equip("pistol",5)
	player.call("_fire")
	var shots := get_nodes_in_group("player_bullets")
	var toward := (b.global_position-player.global_position).normalized()
	check("锁定射击生成朝向目标的子弹并只扣一发", shots.size() == 1 and absf(Vector2.RIGHT.rotated(shots[0].rotation).angle_to(toward)) <= deg_to_rad(1.51) and state.get("ammo") == 4)
	for shot in shots: shot.queue_free()
	player.get("combat").set("cooldown",0.0)
	player.call("_throw_weapon")
	var thrown := get_nodes_in_group("thrown_weapons")
	check("锁定投掷复用目标方向及原弹药", thrown.size() == 1 and thrown[0].get("direction").is_equal_approx(toward) and thrown[0].get("weapon_instance") == state and state.get("ammo") == 4)
	for item in thrown: item.queue_free()
	equip("knife")
	b.global_position = player.global_position+Vector2(24,0)
	c.global_position = player.global_position+Vector2(40,0)
	await settle()
	update()
	player.call("_fire")
	var direction: float = player.get_node("Aim").global_rotation
	b.global_position += Vector2(0,30)
	update()
	check("挥击中目标移动不会改变出手方向", is_equal_approx(direction,player.get_node("Aim").global_rotation))
	b.global_position = player.global_position+Vector2(24,0)
	await settle()
	player.get("combat").call("tick",0.2)
	check("锁定刀击实际命中近处且不延长28px", b.get("state") == 5 and c.get("state") != 5 and player.get("combat").get("melee_reach") == 28.0)
	update()
	check("死亡目标自动换到当前最近", player.get("lock_target") == c)
	c.queue_free()
	await settle()
	update()
	check("最后一个目标释放后隐藏框但保持等待", player.get("lock_target") == null and not player.get_node("LockReticle").visible and player.get("aim_lock").get("enabled"))
	var last := enemy(Vector2(50,0))
	await settle()
	player.get("combat").call("tick",1.0)
	update()
	check("新敌人进场无需中键自动重新锁定", player.get("lock_target") == last)
	var notified := [false]
	var cb := func(value: Node2D) -> void:
		if value == null: notified[0] = true
	get_root().get_node("Events").lock_changed.connect(cb)
	player.call("take_damage",1,Vector2.ZERO)
	check("玩家死亡立即关闭功能、清锁并发null事件", player.get("lock_target") == null and not player.get("aim_lock").get("enabled") and notified[0])
	get_root().get_node("Events").lock_changed.disconnect(cb)
	room.free()
	await process_frame
	var next: Node2D = load("res://scenes/levels/Level_test.tscn").instantiate()
	root.add_child(next)
	for value in get_nodes_in_group("enemies"): value.set_physics_process(false)
	next.get_node("Player").set_physics_process(false)
	check("重开新角色功能关闭、无锁定且框隐藏", next.get_node("Player").get("lock_target") == null and not next.get_node("Player").get("aim_lock").get("enabled") and not next.get_node("Player/LockReticle").visible)
	next.free()
	print(">>> %s：锁定 %d 项，失败 %d" % ["全部通过" if failures == 0 else "失败",checks,failures])
	quit(failures)
