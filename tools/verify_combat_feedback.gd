extends SceneTree
## 所有关卡几何都在内存创建；验证实际命中、位移、输入、暂停与视觉生命周期。
var room: Node2D
var player: Node2D
var failures := 0
var checks := 0

func _initialize() -> void: call_deferred("run")

func check(label: String, value: bool) -> void:
	checks += 1
	if not value: failures += 1
	print("%s %s" % ["PASS" if value else "FAIL", label])

func frames(count := 2) -> void:
	for i in range(count): await physics_frame

func arena() -> void:
	paused = false
	if is_instance_valid(room): room.free()
	root.get_node("Feel").reset_session()
	room = load("res://scenes/levels/Level_test.tscn").instantiate()
	for node in room.get_node("Enemies").get_children(): node.free()
	for node in room.get_node("Doors").get_children(): node.free()
	var floor_layer: TileMapLayer = room.get_node("Floor")
	var walls: TileMapLayer = room.get_node("Walls")
	floor_layer.clear()
	walls.clear()
	for y in range(20):
		for x in range(32): floor_layer.set_cell(Vector2i(x,y),0,Vector2i.ZERO)
	root.add_child(room)
	player = room.get_node("Player")
	player.set_physics_process(false)
	player.global_position = Vector2(120,120)
	player.equip_weapon(null)
	await frames()

func enemy(offset: Vector2) -> Node2D:
	var value: Node2D = load("res://scenes/enemies/EnemyMelee.tscn").instantiate()
	room.get_node("Enemies").add_child(value)
	value.global_position = player.global_position + offset
	value.set_physics_process(false)
	return value

func key_f() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F
	event.keycode = KEY_F
	event.pressed = true
	root.push_input(event,true)
	Input.action_press("execute")
	await frames()
	Input.action_release("execute")
	event.pressed = false
	root.push_input(event,true)

func wall(point: Vector2, size: Vector2, layer := 1) -> StaticBody2D:
	var value := StaticBody2D.new()
	value.collision_layer = layer
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = size
	shape.shape = box
	value.add_child(shape)
	room.add_child(value)
	value.global_position = point
	return value

func run() -> void:
	await arena()
	var target := enemy(Vector2(10,0))
	target.stun(Vector2.ZERO,0)
	await frames()
	player._process(0.0)
	check("手动处决提示按F且接触不会杀人", player.execution.prompt.visible and target.state != 5)
	var state: RefCounted = load("res://scripts/weapons/weapon_state.gd").new(load("res://resources/weapons/pistol.tres"))
	state.ammo = 5
	player.equip_weapon(state)
	player.set_physics_process(true)
	await key_f()
	player.set_physics_process(false)
	check("真实F输入启动处决并隐藏手中武器", player.execution.active and not player.get_node("Aim/Gun").visible)
	check("处决占用目标但仍未扣生命", target.execution_owner == player and target.state != 5)
	var stun_left: float = target._stun_left
	target._physics_process(0.5)
	check("处决占用期间冻结目标苏醒", is_equal_approx(stun_left,target._stun_left))
	player.execution.tick(0.20 - player.execution.elapsed)
	check("第一拳喷4血点而不致命", target.state != 5 and get_nodes_in_group("blood_drops").size() == 4 and room.blood.get_child_count() == 0)
	player._fire()
	check("处决中直接攻击也不发射或扣弹", state.ammo == 5 and get_nodes_in_group("player_bullets").is_empty())
	player._throw_weapon()
	player._pickup_weapon()
	check("处决期间投掷和拾取入口也被阻止", player.weapon_instance == state and state.ammo == 5)
	player.execution.tick(0.25)
	check("第二拳累计8血点仍不致命", target.state != 5 and get_nodes_in_group("blood_drops").size() == 8)
	player.execution.tick(0.25)
	check("第三拳才致命且只生成一滩血泊", target.state == 5 and get_nodes_in_group("blood_drops").size() == 12 and room.blood.get_child_count() == 1)
	check("第三拳后仍有收势且不丢弃原武器实例", player.execution.active and player.weapon_instance == state and state.ammo == 5)
	player.execution.tick(0.21)
	check("收势结束恢复原武器显示", not player.execution.active and player.get_node("Aim/Gun").visible and state.ammo == 5)
	check("缴械后处决不重复掉落", get_nodes_in_group("dropped_weapons").size() == 1)
	var pool: Node2D = room.blood.get_child(0)
	pool.set_process(false)
	pool._process(3.0)
	check("血泊逐步扩散且未超过上限", pool.radius > 3.0 and pool.radius < 18.0)
	pool._process(20.0)
	check("血泊到6秒上限停止增长", pool.radius == 18.0 and not pool.is_processing())
	check("旧死亡放大和闪白已移除", target.visual.scale == Vector2.ONE and target.visual.modulate == Color.WHITE)

	await arena()
	target = enemy(Vector2(10,0))
	target.stun(Vector2.ZERO,0)
	player.execution.start()
	player.execution.tick(0.2)
	stun_left = target._stun_left
	player.stun(Vector2.ZERO,0)
	check("玩家被击晕立即中断处决且目标仍活着", not player.execution.active and target.execution_owner == null and target.state != 5)
	target._physics_process(0.1)
	check("中断后继续原有剩余眩晕时间", is_equal_approx(target._stun_left,stun_left-0.1))
	player._physics_process(1.1)
	player.execution.start()
	check("重新处决不继承拳数", player.execution.strikes == 0)
	player.take_damage()
	check("玩家死亡中断处决且自己也有血泊", not player.execution.active and target.execution_owner == null and room.blood.get_child_count() == 1)

	await arena()
	target = enemy(Vector2(10,0))
	target.stun(Vector2.ZERO,0)
	var obstruction := wall(player.global_position+Vector2(5,0),Vector2(2,20))
	await frames()
	check("隔墙按F不能启动处决", not player.execution.start())
	obstruction.free()
	await frames()
	player.execution.start()
	obstruction = wall(player.global_position+Vector2(5,0),Vector2(2,20),128)
	await frames()
	player.execution.tick(0.1)
	check("途中门板遮挡会中断处决", not player.execution.active and target.state != 5)
	obstruction.free()
	await frames()
	player.execution.start()
	target.take_damage(1,Vector2.ZERO,&"bullet")
	player.execution.tick(0.1)
	check("目标被别的攻击击杀后安全中止", not player.execution.active and target.visual.death_play_count == 1)
	await arena()
	target = enemy(Vector2(20,0))
	target.stun(Vector2.ZERO,0)
	check("14px以外不能处决", not player.execution.start())
	target.global_position = player.global_position + Vector2(10,0)
	player._fire()
	check("已有攻击期间不能插入处决", not player.execution.start())
	player.combat.cancel()
	player.execution.start()
	target.free()
	player.execution.tick(0.1)
	check("目标释放时安全取消处决", not player.execution.active)

	await arena()
	target = enemy(Vector2(24,0))
	var blade: RefCounted = load("res://scripts/weapons/weapon_state.gd").new(load("res://resources/weapons/knife.tres"))
	player.equip_weapon(blade)
	player.get_node("Aim").global_rotation = 0
	await frames()
	player.get_node("Aim").global_rotation = 0
	player._fire()
	player.combat.tick(0.2)
	check("真实刀击致命但不喷血", target.state == 5 and get_nodes_in_group("blood_drops").is_empty())
	check("近战死亡仍有血泊", room.blood.get_child_count() == 1)
	await arena()
	target = enemy(Vector2(35,0))
	var bullet: Node2D = load("res://scenes/projectiles/EnemyBullet.tscn").instantiate()
	bullet.configure(true,1,900)
	room.add_child(bullet)
	bullet.global_position = player.global_position
	bullet.launch(Vector2.RIGHT)
	for i in range(10):
		if target.state == 5: break
		await frames(1)
	check("真实子弹致命时喷血且生成血泊", target.state == 5 and room.get_node("CombatFeedback").burst_count == 1 and room.blood.get_child_count() == 1)
	target.take_damage(1,Vector2.ZERO,&"bullet")
	check("重复致命命中不会重复喷血和血泊", room.get_node("CombatFeedback").burst_count == 1 and room.blood.get_child_count() == 1)
	await arena()
	obstruction = wall(Vector2(128,120),Vector2(2,100))
	await frames()
	target = enemy(Vector2.ZERO)
	target.take_damage()
	pool = room.blood.get_child(0)
	check("血泊朝墙方向的半径受裁剪", pool.limits[0] < 8.0)
	check("血泊仍在尸体下面", room.blood.z_index < target.z_index)

	await arena()
	var watcher := enemy(Vector2(-80,0))
	watcher.facing = Vector2.RIGHT
	watcher._update_perception()
	watcher.rotation = PI * 0.5
	watcher.update_alert_marker()
	check("发现玩家立即追击且旋转角色仍在头顶显示红叹号", watcher.state == 3 and watcher.alert_marker.visible and watcher.alert_marker.text == "!" and watcher.alert_marker.global_position.is_equal_approx(watcher.global_position + Vector2(-4,-24)))
	var seen: Vector2 = watcher.last_known_pos
	watcher._on_noise(Vector2(10,10),500,null)
	check("声音不能覆盖目视追踪的玩家位置", watcher.last_known_pos == seen)
	player.global_position = Vector2(450,300)
	watcher._update_perception()
	watcher.update_alert_marker()
	check("丢失玩家进入黄问号调查且不隔墙追踪新坐标", watcher.state == 2 and watcher.alert_marker.text == "?" and watcher.last_known_pos == seen)
	watcher._alert_left = 4.0
	watcher.last_known_pos = Vector2(360,120)
	watcher._ai_alert(0.5)
	check("走向调查点时不消耗搜索时间", watcher._alert_left == 4.0)
	watcher.global_position = Vector2(360,120)
	watcher._ai_alert(0.5)
	check("到达调查点后才开始搜索计时", watcher._alert_left == 3.5)
	watcher._ai_alert(4.0)
	watcher.update_alert_marker()
	check("搜索结束回岗并隐藏标记", watcher.state == 0 and not watcher.alert_marker.visible)
	watcher.stun(Vector2.ZERO,0)
	watcher.state = 2
	watcher.update_alert_marker()
	check("眩晕时隐藏警觉标记", not watcher.alert_marker.visible)

	await arena()
	watcher = enemy(Vector2(-80,0))
	player.global_position = Vector2(480,300)
	watcher.facing = Vector2.RIGHT
	target = enemy(Vector2(-20,0))
	target.global_position = watcher.global_position + Vector2(80,0)
	target.take_damage()
	watcher._check_corpses(1.0)
	watcher.update_alert_marker()
	check("看见尸体进入黄问号调查", watcher.state == 2 and watcher.alert_marker.text == "?" and watcher.last_known_pos == target.global_position)
	watcher._finish_investigation()
	watcher._check_corpses(1.0)
	check("同一尸体不会反复触发警觉", watcher.state == 0)

	await arena()
	player.global_position = Vector2(480,300)
	watcher = enemy(Vector2.ZERO)
	watcher.global_position = Vector2(120,72)
	watcher.vision_range = 1.0
	for y in range(2,10): room.walls.set_cell(Vector2i(10,y),0,Vector2i(2,0))
	room.rebuild_navigation()
	await frames()
	var destination := Vector2(216,72)
	watcher.last_known_pos = destination
	watcher.state = 2
	watcher._alert_left = 4.0
	watcher.set_physics_process(true)
	await frames(240)
	watcher.set_physics_process(false)
	check("实际绕墙到调查点，没有穿墙或永久卡住", watcher.global_position.distance_to(destination) < 25.0)
	check("长路程没有提前耗尽搜索状态", watcher.state == 2 and watcher._alert_left > 0)
	var collision_body := wall(Vector2(300,100),Vector2(8,30),256)
	await frames()
	check("身体扫掠会阻挡中心线未碰到的家具角", not room.navigation_segment_clear(Vector2(280,80),Vector2(320,80),watcher))
	collision_body.free()
	# 完全隔断网格，取消无路径时向墙硬走的旧兜底。
	for y in range(20): room.walls.set_cell(Vector2i(10,y),0,Vector2i(2,0))
	room.rebuild_navigation()
	watcher.global_position = Vector2(120,72)
	watcher.last_known_pos = destination
	watcher.state = 2
	watcher._alert_left = 4
	watcher.set_physics_process(true)
	await frames(50)
	watcher.set_physics_process(false)
	check("不可达调查点有限重试后放弃且不向墙硬走", watcher.state == 0 and watcher.global_position.x < 140)

	await arena()
	watcher = enemy(Vector2(-100,0))
	watcher.facing = Vector2.RIGHT
	for y in range(20): room.floor_layer.erase_cell(Vector2i(5,y))
	room.rebuild_navigation()
	watcher.set_physics_process(true)
	await frames(50)
	watcher.set_physics_process(false)
	watcher.update_alert_marker()
	check("看得见但不可达时保持红色警觉而不顶墙", watcher.state in [3,4] and watcher.alert_marker.text == "!" and watcher.global_position.x < 40)

	await arena()
	target = enemy(Vector2(10,0))
	target.stun(Vector2.ZERO,0)
	player.set_physics_process(true)
	Input.action_press("execute")
	player.resume_from_menu()
	await frames(4)
	check("菜单恢复时残留F不会误启动处决", not player.execution.active)
	Input.action_release("execute")
	await frames(4)
	await key_f()
	player.execution.tick(0.20-player.execution.elapsed)
	var other := enemy(Vector2(80,0))
	other.take_damage()
	pool = room.blood.get_child(0)
	var blood_time: float = pool.elapsed
	var drop: Node2D = get_nodes_in_group("blood_drops")[0]
	var drop_position := drop.global_position
	var elapsed: float = player.execution.elapsed
	var left: float = target._stun_left
	paused = true
	await create_timer(0.12,true,false,true).timeout
	check("暂停冻结处决与眩晕时钟", player.execution.elapsed == elapsed and target._stun_left == left)
	check("暂停同时冻结血泊扩散和飞溅", pool.elapsed == blood_time and drop.global_position == drop_position)
	paused = false
	player.resume_from_menu()
	await frames(3)
	check("继续后仍在原处决中", player.execution.active and player.execution.elapsed > elapsed)
	room.free()
	room = null
	root.get_node("Feel").reset_session()
	await frames()
	check("释放关卡后无血泊或处决目标残留", get_nodes_in_group("blood_pools").is_empty() and get_nodes_in_group("blood_drops").is_empty())
	print(">>> %s：战斗反馈 %d 项，失败 %d" % ["全部通过" if failures == 0 else "失败",checks,failures])
	quit(failures)
