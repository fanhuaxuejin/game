extends SceneTree
var app: Node
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, result: bool) -> void:
	checks += 1
	if not result: failures += 1
	print("%s %s" % ["PASS" if result else "FAIL",label])

func frames(count: int = 3) -> void:
	for i in range(count): await physics_frame

func wait_real(duration: float) -> void:
	await create_timer(duration,true,false,true).timeout

func button(page: Control, name: String) -> Button:
	return page.get_node("Margin/Column/Body/Buttons/" + name) as Button

func escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event,true)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	root.push_input(release,true)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event,true)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	root.push_input(release,true)

func _run() -> void:
	app = load("res://scenes/main/App.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	await frames()
	check("启动仅有主菜单，没有加载游戏或敌人", app.get("state") == &"title" and app.get_node("GameHost").get_child_count() == 0 and get_nodes_in_group("enemies").is_empty())
	check("主菜单四个选项及初始焦点", app.get("title_page").buttons.get_child_count() == 4 and root.gui_get_focus_owner() == button(app.get("title_page"),"Start"))
	check("F5启动入口已切换App", ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main/App.tscn")
	key(KEY_DOWN)
	check("方向键可选择教程", root.gui_get_focus_owner() == button(app.get("title_page"),"Tutorial"))
	key(KEY_ENTER)
	check("Enter实际打开教程页", app.get("state") == &"placeholder" and app.get("placeholder_page").heading.text == "教程")
	escape()
	await frames()
	escape()
	check("主菜单Esc不退出", app.get("state") == &"title")
	button(app.get("title_page"),"Tutorial").pressed.emit()
	check("教程进入空白可返回页", app.get("state") == &"placeholder" and app.get("placeholder_page").heading.text == "教程" and app.get_node("GameHost").get_child_count() == 0)
	escape()
	check("教程Esc返回主菜单", app.get("state") == &"title")
	button(app.get("title_page"),"Settings").pressed.emit()
	button(app.get("placeholder_page"),"Back").pressed.emit()
	check("主菜单设置返回原页", app.get("state") == &"title" and not paused)
	# 观察退出意图，避免检查第一个退出按钮就把整套测试终止；最后再走实际退出。
	var quit_call := Callable(app,"_quit_application")
	check("退出意图默认连接实际退出函数", app.quit_requested.is_connected(quit_call))
	app.quit_requested.disconnect(quit_call)
	var quits := [0]
	app.quit_requested.connect(func() -> void: quits[0] += 1)
	button(app.get("title_page"),"Quit").pressed.emit()
	check("主菜单退出按钮发出退出意图", quits[0] == 1)
	button(app.get("title_page"),"Start").pressed.emit()
	var game: Node = app.get("game")
	var player: Node2D = game.get("level").player
	check("开始创建第一关并空手出生", app.get("state") == &"playing" and game.get("level_index") == 0 and player.get("weapon_instance") == null)
	check("旧操作HUD已隐藏，弹药和状态HUD仍在", not game.get_node("HUD/HintLabel").visible and game.get_node("HUD/AmmoLabel").visible and game.get_node("HUD/StatusLabel").visible)
	for enemy: Node2D in get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	player.global_position = Vector2(1400,1400)
	var camera := player.get_node("Camera2D") as Camera2D
	camera.limit_left = -100000
	camera.limit_top = -100000
	camera.limit_right = 100000
	camera.limit_bottom = 100000
	camera.force_update_scroll()
	await frames(4)
	Input.action_press("move_right")
	var before := player.global_position
	await frames(12)
	Input.action_release("move_right")
	check("开始后玩家实际移动", player.global_position.x > before.x+5)
	var state: RefCounted = load("res://scripts/weapons/weapon_state.gd").new(load("res://resources/weapons/pistol.tres"))
	state.set("ammo",5)
	player.call("equip_weapon",state)
	var bullet: Node2D = load("res://scenes/projectiles/EnemyBullet.tscn").instantiate()
	bullet.call("configure",true,1,900.0)
	game.get("level").add_child(bullet)
	bullet.global_position = player.global_position+Vector2(0,100)
	bullet.call("launch",Vector2.RIGHT)
	var blade: RefCounted = load("res://scripts/weapons/weapon_state.gd").new(load("res://resources/weapons/knife.tres"))
	var swing: Node2D = get_nodes_in_group("enemies")[0]
	swing.global_position = player.global_position+Vector2(180,0)
	swing.call("equip_weapon",blade)
	swing.get("combat").call("attack",Vector2.LEFT)
	swing.set_physics_process(true)
	player.get("aim_lock").set("toggle_requested",true)
	player.call("_process",0.0)
	# 镜头有边界，此处单独指定已验证的活目标，检查暂停期间实例和锁定不丢失。
	player.get("aim_lock").call("set_target",swing)
	game.set("_advance_left",0.8)
	var started: float = game.get("_started_at")
	escape()
	check("Esc打开暂停页且冻结游戏容器", paused and app.get("state") == &"paused" and not game.can_process())
	check("暂停四按钮与操作表完整", app.get("pause_page").buttons.get_child_count() == 4 and "鼠标中键" in app.get("pause_page").get_node("Margin/Column/Body/Help/HelpText").text and "弹药用完自动挥枪" in app.get("pause_page").get_node("Margin/Column/Body/Help/HelpText").text)
	var pos := player.global_position
	var shot_pos := bullet.global_position
	var swing_time: float = swing.get("combat").get("attack_elapsed")
	var countdown: float = game.get("_advance_left")
	var paused_wall := Time.get_ticks_msec()
	await wait_real(0.16)
	check("暂停时角色/实体子弹/攻击动画时钟不推进", player.global_position == pos and bullet.global_position == shot_pos and is_equal_approx(swing.get("combat").get("attack_elapsed"),swing_time))
	check("暂停时清场倒计时不推进", is_equal_approx(game.get("_advance_left"),countdown))
	button(app.get("pause_page"),"Settings").pressed.emit()
	check("暂停设置页保持冻结", paused and app.get("state") == &"placeholder")
	escape()
	check("设置Esc返回暂停而不继续游戏", paused and app.get("state") == &"paused")
	game.set("_advance_left",-1.0)
	Input.action_press("fire")
	Input.action_press("throw_weapon")
	Input.action_press("pickup")
	Input.action_press("restart")
	button(app.get("pause_page"),"Resume").pressed.emit()
	check("继续保留原角色/武器/弹药/锁定", not paused and game.get("level").player == player and player.get("weapon_instance") == state and state.get("ammo") == 5 and player.get("lock_target") == swing)
	var wall_elapsed := (Time.get_ticks_msec() - paused_wall) / 1000.0
	check("关卡用时准确扣除实际暂停时长", absf(float(game.get("_started_at")) - started - wall_elapsed) < 0.02)
	swing.set_physics_process(false)
	await frames(6)
	check("恢复时残留左右键/E/R不会误攻击、丢枪或重开", state.get("ammo") == 5 and player.get("weapon_instance") == state and game.get("level").player == player)
	Input.action_release("fire")
	Input.action_release("throw_weapon")
	Input.action_release("pickup")
	Input.action_release("restart")
	await frames(4)
	Input.action_press("fire")
	await frames(3)
	Input.action_release("fire")
	check("松手重新按攻击可正常射击", state.get("ammo") == 4)
	var resumed_pos := bullet.global_position
	check("继续后实体子弹恢复飞行", resumed_pos != shot_pos)
	escape()
	button(app.get("pause_page"),"Quit").pressed.emit()
	check("暂停页退出按钮也发出退出意图", quits[0] == 2)
	button(app.get("pause_page"),"MainMenu").pressed.emit()
	await frames()
	check("回主菜单释放整局角色/敌人/锁定框且解除暂停", not paused and app.get("game") == null and get_nodes_in_group("player").is_empty() and get_nodes_in_group("enemies").is_empty())
	var feel: Node = root.get_node("Feel")
	feel.call("hit_stop",0.08)
	feel.call("slow_mo")
	app.call("return_to_title")
	app.call("start_game")
	var next: Node = app.get("game")
	for enemy: Node2D in get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	check("再次开始回到第一关空手并重置时间音频倍率", next.get("level_index") == 0 and next.get("level").player.get("weapon_instance") == null and Engine.time_scale == 1.0 and AudioServer.playback_speed_scale == 1.0)
	await wait_real(0.12)
	feel.call("slow_mo")
	await wait_real(0.8)
	check("旧会话真实timer不会覆盖新会话慢动作", feel.get("_slowing") and is_equal_approx(Engine.time_scale,0.35))
	feel.call("reset_session")
	next.get("level").player.call("take_damage",1,Vector2.ZERO)
	escape()
	check("死亡后也能暂停", paused and app.get("state") == &"paused")
	escape()
	check("死亡后继续保留死亡界面而不复活", not paused and next.get("level").player.get("is_dead") and next.get_node("HUD/DeathPanel").visible)
	for i in range(3):
		app.call("return_to_title")
		app.call("start_game")
		check("第%d次开始没有重复角色或游戏实例" % i, app.get_node("GameHost").get_child_count() == 1 and get_nodes_in_group("player").size() == 1)
	app.call("return_to_title")
	print(">>> %s：菜单 %d 项，失败 %d" % ["全部通过" if failures == 0 else "失败",checks,failures])
	if failures == 0: app.call("_quit_application")
	else: quit(failures)
