extends SceneTree
## M1 + M2 + M3 功能冒烟测试：不是"能跑不报错"，而是真的验证玩法链路。
##
## 运行：
##   & "D:\Godot\Godot_v4.7.2-stable_win64_console.exe" --headless `
##       --path "D:\deepseek-harness\game\project" --script res://tools/smoke.gd
##
## ⚠️ 本脚本刻意不使用 `Events` / `Enemy.State.ALERT` / `Player` / `Level` 这类项目内全局标识符：
##    在 --script 模式下，本脚本的编译发生在 Autoload 与全局类注册**之前**，
##    直接引用会以 "Identifier not found" 编译失败。所以改用节点路径 + 整数常量。
##
## Level_01 的关键几何（像素）：
##   尺寸 768x448；墙块 (112-176, 128-160) 等
##   Enemy_01 巡逻(168,104)  Enemy_02 远程(584,296)  Enemy_03 近战(168,376)  Enemy_04 近战(520,376)
##   Player (392,200)

const MAIN_SCENE := "res://scenes/main/Main.tscn"
const BULLET_SCENE := "res://scenes/projectiles/EnemyBullet.tscn"
## ★ 冒烟测试跑在这张**专门的测试关卡**上，而不是 Level_01。
##
## 为什么：下面几十条断言都建立在"关卡长什么样"上（敌人在哪、门在哪、墙在哪）。
## 如果跑在正式关卡上，玩家一在编辑器里改关卡，测试就整片飘红 ——
## 分不清是"功能坏了"还是"关卡改了"。
##
## Level_test.tscn 是从完好版本复制出来的**固定夹具**，不要手工编辑它。
## 正式关卡由 第十一幕 用动态断言（数量、连通性）单独覆盖。
const TEST_LEVEL := "res://scenes/levels/Level_test.tscn"
const LV := "LevelHost/Level_test"

## 对应 enemy.gd 里的 enum State（顺序必须一致）
const S_IDLE := 0
const S_PATROL := 1
const S_ALERT := 2
const S_CHASE := 3
const S_ATTACK := 4
const S_DEAD := 5

## Level_01 的几何（3x2 房间 + 7 扇门）：
##   竖墙带 x=16 / x=31 → 像素 256..272 / 496..512
##   横墙带 y=14       → 像素 224..240
##   房间 x 分三间：16..256 / 272..496 / 512..752；上排 y 16..224，下排 y 240..464
const WALL_RAY_FROM := Vector2(240, 32)      # 左→右穿过 x=16 的竖墙带
const WALL_RAY_TO := Vector2(300, 32)
const OPEN_RAY_FROM := Vector2(32, 32)       # 左上房间内部的空地
const OPEN_RAY_TO := Vector2(200, 32)
const ROOM_TM_WEST := Vector2(300, 88)       # 中上房间西侧（远程兵出生点在 376,88）
const ROOM_TM_EAST := Vector2(470, 88)       # 中上房间东侧
const ROOM_TL_EAST := Vector2(240, 32)       # 左上房间靠东、靠北 —— 隔着一道墙就是远程兵

var _fail := 0
var _main: Node = null
var player: Node2D = null
var blood: Node2D = null
var walls: Node2D = null


func _initialize() -> void:
	print("=== M1 + M2 + M3 功能冒烟测试 ===")

	print("\n--- 第一幕：结构 / 图层顺序 / TileSet 碰撞 ---")
	await _reload()
	var lv := _level()

	_check("主场景脚本已挂载", _main.get_script() != null)
	_check("关卡已加载进 LevelHost", lv != null and lv.get_script() != null)
	_check("玩家脚本已挂载", player.get_script() != null)
	_check("武器引用 pistol.tres", String(player.get("weapon").resource_path) == "res://resources/weapons/pistol.tres")
	_check("初始弹药 12", player.get("ammo") == 12)
	# 不写死数量：测试关卡换了布局也不该失败（写死就等于把"关卡长什么样"当成了规格）
	var initial_enemies: int = _enemies().size()
	_check("关卡里有敌人可打（%d 个）" % initial_enemies, initial_enemies > 0)

	var floor_layer := lv.get_node("Floor") as Node2D
	_check("图层：地板 < 血迹", blood.z_index > floor_layer.z_index)
	_check("图层：血迹 < 墙", blood.z_index < walls.z_index)
	_check("图层：墙 < 人物", walls.z_index < player.z_index)
	_check("开局血迹层是空的", blood.get_child_count() == 0)

	# TileSet 的碰撞真的生效吗？穿墙射线应该命中，空处射线不该命中。
	# 两个探测点都是**从图块数据里现找的**，不写死坐标 —— 关卡改了几何也不会失效。
	await _settle()
	var wall_probe: Array = _find_wall_probe()
	_check("能从 Walls 图层里找到一个「地板 → 紧邻墙格」探测对", wall_probe.size() == 2)
	if wall_probe.size() == 2:
		_check("射线穿墙会命中（TileSet 碰撞生效）", _ray_hits(wall_probe[0], wall_probe[1]))
	var open_probe: Array = _find_open_probe()
	_check("能找到一段连续 5 格、且不在门附近的空地", open_probe.size() == 2)
	if open_probe.size() == 2:
		_check("空处射线不命中", not _ray_hits(open_probe[0], open_probe[1]))

	print("\n--- 第二幕：视野三件套 ---")
	await _reload()
	var seer := _enemy_of_kind("ranged")
	_check("找得到远程兵", seer != null)
	seer.global_position = ROOM_TM_WEST          # 中上房间西侧
	await _settle()

	# ① 同一房间、正前方、无遮挡
	seer.set("facing", Vector2.RIGHT)
	player.global_position = ROOM_TM_EAST
	_check("无遮挡时能看见", _can_see(seer))

	# ② 同样无遮挡，但在背后 —— 视锥外
	seer.set("facing", Vector2.LEFT)
	_check("在视锥外看不见（背后且无墙）", not _can_see(seer))

	# ③ 隔着 x=16 的竖墙带，挪到左上房间
	player.global_position = ROOM_TL_EAST
	seer.set("facing", (player.global_position - seer.global_position).normalized())
	_check("隔墙看不见（墙带挡住）", not _can_see(seer))

	# ④ 出生朝向：在编辑器里把敌人转个方向，视野锥和鼻子就该朝那边。
	#    以前 facing 写死 Vector2.RIGHT，而且 _sync_aim 会把瞄准器的旋转
	#    覆盖成 0 —— 转多少度，敌人都是"朝右"。
	#
	# ⚠️ 必须**入树当帧立刻读**，不能 await：巡逻兵下一帧就开始走路，
	#    于是 facing 会被正常地改写成"要走的方向"（那是正确行为）。
	#    这条要验的是"出生那一刻的朝向 = 编辑器里转的角度"。
	for facing_deg: float in [0.0, 90.0, 180.0, -90.0]:
		var probe := (load("res://scenes/enemies/EnemyMelee.tscn") as PackedScene).instantiate() as Node2D
		probe.set_physics_process(false)
		probe.rotation = deg_to_rad(facing_deg)
		get_root().add_child(probe)
		var want := Vector2.RIGHT.rotated(deg_to_rad(facing_deg))
		var got: Vector2 = probe.get("facing")
		var probe_aim := probe.get_node("Aim") as Node2D
		_check("敌人转 %.0f° → 出生朝向 %s、瞄准器局部角 %.1f°（应为 0）" % [
				facing_deg, str(got.round()), rad_to_deg(probe_aim.rotation)],
				got.distance_to(want) < 0.01
						and absf(angle_difference(probe_aim.rotation, 0.0)) < 0.01)
		probe.queue_free()
		await process_frame

	# ⑤ 敌人自己压进墙里时，不许透过那面墙看见玩家。
	#    以前 _world_blocks 没开 hit_from_inside —— 射线**起点在某个形状内部**时
	#    Godot 默认会忽略那个形状，于是贴着墙角的近战兵会"隔墙看见你"，
	#    而且是概率性的（蹭进墙里才发生）。
	var wall_pair: Array = _find_wall_probe()
	if wall_pair.size() == 2:
		seer.global_position = wall_pair[1]                    # 站进墙格里
		player.global_position = wall_pair[0]                  # 玩家在紧邻的地板格
		seer.set("facing", (player.global_position - seer.global_position).normalized())
		_check("敌人自己压进墙里时也看不见玩家（距离 %.0fpx）" % seer.global_position.distance_to(player.global_position),
				not _can_see(seer))

	# ⑥ 独立标尺：物理射线（敌人用的那套）和图块数据（A* 用的那套）
	#    在"什么挡视线"上必须一致。不一致 = 敌人会隔墙看到玩家。
	#    两条路完全独立，所以这是个真交叉验证，不是自己验自己。
	var los: Array = _count_los_leaks()
	_check("物理射线与图块数据一致（抽样 %d 条，漏墙 %d 条）" % [los[0], los[1]],
			int(los[0]) > 50 and int(los[1]) == 0)

	print("\n--- 第三幕：听觉（开枪的噪声就是你的位置）---")
	await _fresh_main()
	var patrol := _enemy_of_kind("listener")
	var melee_far := _enemy_of_kind("melee")
	_check("找得到巡逻兵 / 近战兵", patrol != null and melee_far != null)
	_check("听觉测试对象没有路点时站岗 = IDLE", _state(patrol) == S_IDLE)
	_check("近战兵出生待命 = IDLE", _state(melee_far) == S_IDLE)

	await _freeze_enemies(true)
	patrol.global_position = Vector2(600, 400)      # 右下房间
	melee_far.global_position = Vector2(400, 56)    # 中上房间，离噪声正好 344px
	await _settle()

	# 噪声在 (400,400)：巡逻兵距离 200，近战兵距离 344。
	# ⚠️ 半径**不写死**：noise_radius 是会调的数值（刚被调小过一次）。
	# 从武器数据里读出来，并先断言"前提成立"—— 否则以后调半径，
	# 下面两条会变成"碰巧还对"或者"莫名其妙挂了"。
	# ⚠️ 这里必须用 _player() 现场取，不能用 player 变量：
	# 本幕用的是 _fresh_main()（不是 _reload），player 变量还指着上一幕那个**已释放**的实例。
	var noise_r: float = float(load("res://resources/weapons/shotgun.tres").get("noise_radius"))
	var hear_patrol: float = noise_r * float(patrol.get("hearing_multiplier"))
	var hear_melee: float = noise_r * float(melee_far.get("hearing_multiplier"))
	var noise_pos := Vector2(400, 400)
	var d_patrol: float = patrol.global_position.distance_to(noise_pos)
	var d_melee: float = melee_far.global_position.distance_to(noise_pos)
	_check("前提：巡逻兵 %.0fpx 落在听力 %.0fpx 内" % [d_patrol, hear_patrol],
			d_patrol <= hear_patrol)
	_check("前提：近战兵 %.0fpx 落在听力 %.0fpx 外" % [d_melee, hear_melee],
			d_melee > hear_melee)

	_events().emit_signal("noise_emitted", noise_pos, noise_r, null)
	_check("巡逻兵听到噪声 → ALERT", _state(patrol) == S_ALERT)
	_check("巡逻兵记住了噪声位置",
			(patrol.get("last_known_pos") as Vector2).distance_to(noise_pos) < 1.0)
	_check("近战兵听不到 → 仍 IDLE", _state(melee_far) == S_IDLE)

	print("\n--- 第四幕：射击击杀 / 血迹 / 尸体层级 ---")
	await _reload()
	var victim := _enemy_of_kind("ranged")
	victim.global_position = ROOM_TM_WEST
	# 其它敌人全挪到右下房间，免得挡在弹道上
	for other in _enemies():
		if other != victim:
			other.global_position = Vector2(632, 352)
	player.global_position = ROOM_TL_EAST          # 左上房间
	await _settle()

	# 先隔墙打：子弹必须被 x=16 的竖墙带挡住
	player.get_node("Aim").look_at(victim.global_position)
	player.call("_fire")
	for flight_frame in range(20):
		await physics_frame
	await _settle()
	_check("子弹被墙挡住，墙后敌人存活", _state(victim) != S_DEAD)

	# 再挪到同一房间、无遮挡处一枪击杀
	player.global_position = ROOM_TM_EAST
	await _settle()
	player.get_node("Aim").look_at(victim.global_position)
	player.call("_fire")
	for flight_frame in range(20):
		await physics_frame
	await _settle()
	_check("无遮挡时一枪击杀", _state(victim) == S_DEAD)
	_check("击杀计数 = 1", int(_main.get("kills")) == 1)
	_check("剩余敌人 = %d" % (initial_enemies - 1), _enemies().size() == initial_enemies - 1)
	_check("击杀在背景层留下了血迹贴花", blood.get_child_count() >= 3)
	_check("尸体改用绝对 z", victim.z_as_relative == false)
	# 层级要用**有效 z**（沿父链累加）比，不能只比各自的 z_index。
	# ⚠️ 这个坑踩过两次：尸体以前写死绝对 z=1，而关卡里 Player 的有效 z 可能只有 0
	# （手工搭关卡漏设 z_index），于是尸体盖在玩家身上。
	# 只比 player.z_index 是看不出来的 —— 容器上还有一层 z。
	var corpse_z := _effective_z(victim)
	var player_z := _effective_z(player)
	var wall_z := _effective_z(walls)
	var living_z := 2147483647
	for e in _enemies():
		if e != victim:
			living_z = mini(living_z, _effective_z(e))
	_check("尸体在玩家之下（尸体 %d < 玩家 %d）" % [corpse_z, player_z], corpse_z < player_z)
	_check("尸体在活着的敌人之下（尸体 %d < 敌人 %d）" % [corpse_z, living_z], corpse_z < living_z)
	# 尸体的定位是"横躺在地板上的东西"：在墙、门这些"立着的物体"之下，但在地板之上。
	# 以前它压在墙上面（z=1），看起来像纸片浮在墙前。
	var floor_z := _effective_z(_level().get_node("Floor") as Node2D)
	_check("尸体在墙之下（尸体 %d < 墙 %d）" % [corpse_z, wall_z], corpse_z < wall_z)
	_check("尸体在地板之上（尸体 %d > 地板 %d）" % [corpse_z, floor_z], corpse_z > floor_z)

	print("\n--- 第五幕：清场 → 推进关卡 ---")
	for e in _enemies():
		e.call("take_damage", 1, Vector2.ZERO)
	await _settle()
	_check("全部清场后剩余 = 0", _enemies().is_empty())
	_check("清场提示已显示", (_label("HUD/ClearLabel")).visible)
	for i in 200:      # ADVANCE_DELAY = 1.6s（约 96 帧），加上清场慢动作的 0.9 秒
		await physics_frame
	_check("清场后自动进入下一关（Level_02）",
			_level() != null and String(_level().name) == "Level_02")
	_check("新关卡有它自己的敌人（%d 个）" % _enemies().size(), _enemies().size() > 0)

	# 直接跳到最后一关，验证"全部通关"分支。
	# ⚠️ 用**实际存在**的最后一关：关卡文件是随时在增删的
	# （Level_03~05 就被删过一次，写死索引会让整条测试挂掉）。
	var live_levels := _live_levels()
	_main.call("_load_level", live_levels.size() - 1)
	await _settle()
	_check("能跳到最后一关（%s）" % (String(_level().name) if _level() != null else "无"),
			_level() != null
					and String(_level().name) == live_levels[live_levels.size() - 1].get_file().get_basename())
	for e in _enemies():
		e.call("take_damage", 1, Vector2.ZERO)
	await _settle()
	for i in 200:
		await physics_frame
	_check("最后一关清场后提示全部通关",
			(_label("HUD/ClearLabel")).text == "全部通关！按 R 重开")

	print("\n--- 第六幕：远程兵发射实体子弹 ---")
	await _reload()
	var shooter := _enemy_of_kind("ranged")
	shooter.set("aim_error_deg", 0.0)
	shooter.global_position = ROOM_TM_WEST          # 中上房间西侧 (300,88)
	player.global_position = ROOM_TM_EAST           # 同一房间，正前方 170px，无遮挡
	await _settle()
	_check("玩家在正前方，无遮挡", _can_see(shooter))
	_check("预警线节点已被移除", shooter.get_node_or_null("Telegraph") == null)
	_check("开局没有任何子弹", _bullets().is_empty())

	var flash := shooter.get_node("Aim/Flash") as Polygon2D
	_check("开枪前火光不可见", not flash.visible)

	shooter.set_physics_process(true)
	await physics_frame
	await physics_frame
	_check("进入 ATTACK 状态", _state(shooter) == S_ATTACK)

	var bullet: Node2D = null
	var flash_before_bullet := false
	var frames_to_shot := -1
	for i in 60:
		await physics_frame
		if not _bullets().is_empty():
			bullet = _bullets()[0] as Node2D
			frames_to_shot = i + 1
			break
		if flash.visible:
			flash_before_bullet = true
	var flash_at_spawn := false
	for i in 3:
		if flash.visible:
			flash_at_spawn = true
			break
		await physics_frame
	_check("有反应时间：发现玩家后 %d 帧（%.2f 秒）才开第一枪" % [frames_to_shot, frames_to_shot / 60.0],
			frames_to_shot >= 15)
	_check("反应期间没有任何可见预警（不是预警线、也不是闪烁倒计时）", not flash_before_bullet)
	_check("子弹生成的同时炮口火光可见", bullet != null and flash_at_spawn)

	if bullet != null and is_instance_valid(bullet):
		var x0: float = bullet.global_position.x
		await physics_frame
		await physics_frame
		# 射手在中上房间西侧、玩家在东侧，所以子弹朝 +X 飞
		_check("子弹在持续飞行（不是瞬时命中）",
				is_instance_valid(bullet) and bullet.global_position.x > x0 + 5.0)
		if is_instance_valid(bullet):
			bullet.queue_free()

	for i in 200:
		await physics_frame
		if bool(player.get("is_dead")):
			break
	_check("子弹命中 → 玩家死亡", bool(player.get("is_dead")))
	_check("死亡面板已显示", (_control("HUD/DeathPanel")).visible)

	print("\n--- 第七幕：持枪敌人贴身不开枪、接触不致死 ---")
	await _reload()
	var hugger := _enemy_of_kind("ranged")
	hugger.set("aim_error_deg", 0.0)
	# 放在房间**东侧**，它往西退才有足够空间拉开距离（西墙只留 14px 的话它退两步就贴墙了）
	hugger.global_position = Vector2(400, 88)
	player.global_position = Vector2(414, 88)       # 贴脸 14px
	await _settle()
	_check("持枪敌人 contact_kill = false", bool(hugger.get("contact_kill")) == false)
	_check("贴身下限 min_fire_range 已配置", float(hugger.get("min_fire_range")) > 0.0)

	hugger.set_physics_process(true)
	for i in 12:
		await physics_frame
	_check("贴身 12 帧后玩家仍然活着", not bool(player.get("is_dead")))
	_check("贴身期间没有生成子弹", _bullets().is_empty())

	var fired_after_backing_off := false
	for i in 200:
		await physics_frame
		if not _bullets().is_empty():
			fired_after_backing_off = true
			break
	_check("拉开距离后照常开枪", fired_after_backing_off)

	print("\n--- 第八幕：近战前摇和武器碰撞 ---")
	await _reload()
	var brawler := _enemy_of_kind("melee")
	player.global_position = brawler.global_position + Vector2(20, 0)
	await _settle()
	brawler.set_physics_process(true)
	for i in range(8):
		await physics_frame
	_check("贴近但前摇未结束时玩家存活", not bool(player.get("is_dead")))
	for i in range(40):
		await physics_frame
		if bool(player.get("is_dead")):
			break
	_check("武器实际挥中后玩家死亡", bool(player.get("is_dead")))
	_check("死亡面板已显示", (_control("HUD/DeathPanel")).visible)
	_check("玩家尸体在墙下", player.z_as_relative == false and _effective_z(player) < _effective_z(walls))

	print("\n--- 第九幕：寻路（不会再被墙卡住）---")
	await _reload()
	var pathing := _enemy_of_kind("melee")
	var walkable_cells: int = int(_level().call("walkable_cell_count"))
	_check("关卡运行时建好了寻路网格（%d 格可通行）" % walkable_cells, walkable_cells > 500)

	pathing.global_position = Vector2(140, 200)     # 左上房间、墙带上方、门口附近
	player.global_position = Vector2(632, 352)      # 右下房间，挪远免得它直接看见玩家
	await _settle()

	# 噪声点在下排左房间：(140,200) → (140,290) 之间隔着 y=14 的横墙带，
	# **唯一的通路就是 Door_03 那扇门** —— 所以这同时验证了"敌人会自己撞开门"。
	# 两点故意放得很近：近战兵 alert_time 只有 4 秒，路太长它会在半路放弃回岗位。
	var hidden := Vector2(140, 290)
	var door3 := _door(2) as Node2D
	var was_open: bool = bool(door3.get("is_open"))
	_events().emit_signal("noise_emitted", hidden, 320.0, null)
	_check("听到枪声后进入 ALERT", _state(pathing) == S_ALERT)

	pathing.set_physics_process(true)
	var best := 99999.0
	for i in 220:
		await physics_frame
		best = minf(best, pathing.global_position.distance_to(hidden))
		if i % 55 == 0:
			print("      追踪 帧%3d  pos=%s  距目标 %.0f  路径点 %d" % [
				i, str(pathing.global_position), pathing.global_position.distance_to(hidden),
				(pathing.get("_path") as PackedVector2Array).size()])
	_check("绕开墙走到枪声位置（最近 %.0f px）" % best, best < 24.0)
	_check("路上那扇门本来是关的", not was_open)
	_check("敌人自己撞开了门", bool(door3.get("is_open")))

	print("\n--- 第十幕：门（方向 / 惯性 / 反弹 / 自己关上 / 碰撞体积）---")
	await _reload()
	var door_box := _level().get_node_or_null("Doors")
	_check("测试关卡里有 Doors 容器", door_box != null)
	var door_count: int = door_box.get_child_count() if door_box != null else 0
	_check("测试关卡里有门可测（%d 扇）" % door_count, door_count >= 3)

	# Door_01 是 x=16 那面竖墙上的门：中心 (264, 80)，铰链在门洞上端
	var d1 := _door(0) as Node2D
	var mid: Vector2 = d1.global_position
	var west := mid + Vector2(-24, 0)
	var east := mid + Vector2(40, 0)
	_check("门初始是关着的（角度 %.2f）" % float(d1.get("angle")),
			absf(float(d1.get("angle"))) < 0.01)
	_check("关着的门挡视线 / 挡子弹", _ray_hits(west, east))

	# ① 方向 = 进入方向：玩家从西边**朝东走**进门，门就该往东甩
	var door_victim := _enemy("Enemy_01")
	door_victim.global_position = mid + Vector2(16, 0)
	player.global_position = mid + Vector2(-16, 0)
	for i in 6:
		player.set("velocity", Vector2(220, 0))
		await physics_frame
	var swung_east: float = float(d1.get("angle"))
	_check("朝东走进门 → 门往东甩（%.2f rad）" % swung_east, swung_east < -0.05)

	# ② 门不再"拍死人"：甩得够快只是把人**撞晕**，并打退一点。
	#    先把玩家定住（保留"推门"，但不再往前走），免得他走过去把晕眩的敌人
	#    提前补掉 —— 这样才能单独验证"撞晕"。
	player.set_physics_process(false)
	var victim_before: Vector2 = door_victim.global_position
	d1.call("push", -9.0)                 # 补一记，保证甩到会撞晕的角速度
	for i in 30:
		player.set("velocity", Vector2(220, 0))   # 仍然算"在推门"
		await physics_frame
	_check("扫到的人被撞晕而不是被杀",
			bool(door_victim.call("is_stunned")) and _state(door_victim) != S_DEAD)
	var knocked: float = door_victim.global_position.distance_to(victim_before)
	# 要求撞出去 1~2 格（16~32px）。放宽到 12~36 是给物理求解和撞墙留余量。
	_check("被门撞退 %.0f px（%.1f 格，要求 1~2 格）" % [knocked, knocked / 16.0],
			knocked >= 12.0 and knocked <= 36.0)

	# ②续 贴上去补刀：晕眩中的敌人被玩家一碰就死
	#     （被门撞退的方向是门板的切线方向，不一定在玩家的直线上 ——
	#      所以这里直接把玩家贴到晕眩的敌人身上，单独验证"接触补刀"）
	player.set_physics_process(true)
	player.global_position = door_victim.global_position
	for i in 6:
		player.set("velocity", Vector2.ZERO)
		await physics_frame
	_check("玩家贴上去补刀 → 击杀晕眩的敌人", _state(door_victim) == S_DEAD)

	# ③ 反方向：玩家从东边朝西走，门就该往西甩
	var d2 := _door(1) as Node2D
	player.global_position = d2.global_position + Vector2(16, 0)
	for i in 6:
		player.set("velocity", Vector2(-220, 0))
		await physics_frame
	_check("朝西走进门 → 门往西甩（%.2f rad）" % float(d2.get("angle")),
			float(d2.get("angle")) > 0.05)

	# ④ 惯性：一记大冲量 → 甩到极限 → 反弹 → 阻力让它停在某个角度（不会弹回原点）
	await _reload()
	var d4 := _door(3) as Node2D
	d4.call("push", 13.0)
	var peak := 0.0
	var bounced_at_limit := false
	var prev_sign := signf(float(d4.get("omega")))
	for i in 180:
		await physics_frame
		var a := float(d4.get("angle"))
		peak = maxf(peak, absf(a))
		var s := signf(float(d4.get("omega")))
		# 在**接近极限角度**的地方角速度反向 = 撞到门框弹回来了
		if s != 0.0 and prev_sign != 0.0 and s != prev_sign and absf(a) > 1.2:
			bounced_at_limit = true
		if s != 0.0:
			prev_sign = s
	_check("甩到了极限角度附近（峰值 %.2f rad，极限 %.2f）" % [peak, PI * 0.5], peak > 1.0)
	_check("撞到极限角度后反弹（角速度在极限处反向）", bounced_at_limit)
	# 没有回位弹簧：门停在哪就是哪，不会自己弹回关门位置
	_check("门不会弹回原点（阻力让它停在 %.2f rad）" % absf(float(d4.get("angle"))),
			absf(float(d4.get("angle"))) > 0.1 and absf(float(d4.get("omega"))) < 0.1)

	# ⑤ 门板碰撞体：朝向跟着转；**任何角度都挡子弹**（看得见就该挡得住）
	var d5 := _door(4) as Node2D
	var panel := d5.get_node("Hinge/Panel") as StaticBody2D
	var panel_cs := panel.get_node("CollisionShape2D") as CollisionShape2D
	_check("门板挂在独立的 door 层上（只挡子弹/视野，不挡人）", panel.collision_layer == 128)
	# 门对角色没有实体碰撞：玩家和敌人的碰撞掩码都不含 door 层
	_check("玩家不会被门挡住（掩码不含 door 层）", (player.collision_mask & 128) == 0)
	var any_enemy := _enemy("Enemy_02")
	_check("敌人不会被门挡住（掩码不含 door 层）", (any_enemy.collision_mask & 128) == 0)
	_check("关着时碰撞体启用", not panel_cs.disabled)
	d5.call("push", 6.0)
	for i in 8:
		await physics_frame
	_check("门板碰撞体的朝向跟着门一起转（不是只有贴图在动）",
			absf(panel.rotation - float(d5.get("angle"))) < 0.001)

	# 极限角度：门板仍然必须挡子弹。
	# 这里曾经有个 bug —— 门开到 63° 以上就关掉碰撞，于是门板明明横在眼前、
	# 子弹却从它身上穿过去（"看得见打不中"）。根因是那条逻辑属于门还占 world 层
	# 的时代（为了让打开的门不挡寻路），门挪到独立层之后就只剩副作用了。
	#
	# ⚠️ 直接把角度设到极限，不要"推一下再等 60 帧" —— 门撞到极限会反弹，
	#    等多久取到的角度都是随机的（写这版测试时踩过一次）。
	d5.set("angle", 1.55)          # open_angle = PI/2 ≈ 1.5708
	d5.set("omega", 0.0)
	d5.call("_apply_angle")
	await process_frame
	var limit_angle: float = float(d5.get("angle"))
	_check("门在极限角度（%.2f rad，极限 %.2f）" % [limit_angle, PI * 0.5],
			absf(limit_angle) > 1.4)
	_check("极限角度下碰撞体仍然启用", not panel_cs.disabled)

	# 真打一枪试试：沿门板法线横穿它
	var xf: Transform2D = d5.call("_panel_transform", limit_angle)
	var along: Vector2 = xf.x.normalized()
	var across: Vector2 = xf.y.normalized()
	var panel_mid: Vector2 = xf.origin - along * 6.0
	_check("极限角度下门板真的挡得住子弹",
			_ray_hits(panel_mid + across * 12.0, panel_mid - across * 12.0))

	# 关回去也该继续挡
	d5.set("angle", 0.0)
	d5.call("_apply_angle")
	await process_frame
	_check("关回去后碰撞仍然启用", not panel_cs.disabled)

	# ⑥ 敌人推开的门不会把自己人拍死
	#    （不然一屋子敌人会自相残杀 —— 很搞笑，但会毁掉关卡设计）
	await _reload()
	var d6 := _door(5) as Node2D
	var melees: Array = []
	for e in _enemies():
		if String(e.get_script().resource_path).contains("melee"):
			melees.append(e)
	_check("下排有两个近战兵可以拿来验证", melees.size() >= 2)
	if melees.size() >= 2:
		var ally: Node2D = melees[0]
		var buddy: Node2D = melees[1]
		ally.global_position = d6.global_position + Vector2(-10, 0)   # 贴到门板上
		buddy.global_position = d6.global_position + Vector2(16, 8)   # 门板的挥扫路径上
		for i in 40:
			ally.set("velocity", Vector2(240, 0))     # 朝东推门
			await physics_frame
		_check("敌人推门时门板确实甩起来了（%.2f rad）" % float(d6.get("angle")),
				absf(float(d6.get("angle"))) > 0.3)
		_check("敌人推门不会误伤自己人（同伴还活着）", _state(buddy) != S_DEAD)

	# ⑦ 贴着墙从门洞旁走过（不进门洞、离门板约 5px 间隙）不该把门带动。
	#    这是用户报告过的 bug：贴墙来回走，门会乱动 —— 根因是"贴墙"和
	#    "贴住门板"的中心距只差 5px，旧的距离阈值误判。用形状重叠查询后，
	#    只有真的接触门板才推。
	await _reload()
	var d7 := _door(6) as Node2D
	player.set_physics_process(false)                 # 只读速度、不真的移动
	player.global_position = d7.global_position + Vector2(14, 0)
	for i in 15:
		player.set("velocity", Vector2(-220, 0))       # 垂直于门板的方向来回走
		await physics_frame
	_check("贴着墙从门洞旁走过不推门（%.2f rad）" % float(d7.get("angle")),
			absf(float(d7.get("angle"))) < 0.05)
	player.set_physics_process(true)

	# ⑧ 开门不该"报点"：背对着门、看不见玩家的敌人，不该因为你进门就发现你。
	#    用户报告："敌人在角色进门的时候会光速发现角色，即使角色在视角盲区。"
	await _reload()
	var d8 := _door(2) as Node2D
	var watcher := _enemy("Enemy_03")
	var watcher_pos: Vector2 = d8.global_position + Vector2(0, 56)   # 门**南侧**
	watcher.global_position = watcher_pos
	watcher.set("_home", watcher_pos)                # 免得它掉头走回原岗位
	watcher.set("facing", Vector2.DOWN)              # 背对着门（面朝南）
	player.global_position = d8.global_position + Vector2(0, -20)    # 门北侧
	for i in 8:
		player.set("velocity", Vector2(0, 240))      # 朝南推门进门
		await physics_frame
	for i in 32:
		player.set("velocity", Vector2.ZERO)         # 停在门洞里继续推门
		await physics_frame
	_check("门确实被推开了（%.2f rad）" % float(d8.get("angle")),
			absf(float(d8.get("angle"))) > 0.3)
	_check("背对着门的敌人不会因为你进门就发现你（state=%s 看得见=%s）" % [
			str(_state(watcher)), str(watcher.call("can_see_player"))],
			_state(watcher) < S_ALERT and not bool(watcher.call("can_see_player")))

	# ⑨ 寻路要"走直线"：A* 给的是一格一格的中心点，不拉直的话斜向目标
	#    会走成楼梯形、沿墙走会一格格贴边 —— 表现出来就是敌人左右扭着走。
	await _reload()
	var p_from := Vector2(40, 40)
	var p_to := Vector2(230, 200)
	var route: PackedVector2Array = _level().call("find_path", p_from, p_to)
	var straight: float = p_from.distance_to(p_to)
	var walked := 0.0
	var prev := p_from
	for q in route:
		walked += prev.distance_to(q)
		prev = q
	walked += prev.distance_to(p_to)
	var ratio: float = walked / maxf(straight, 1.0)
	_check("斜向路径接近直线（绕行比 %.2f，拐点 %d 个）" % [ratio, route.size()],
			not route.is_empty() and ratio < 1.15 and route.size() <= 4)

	# 行为验证：让敌人在空旷房间里真的走一段斜线，量它扭不扭
	await _reload()
	player.global_position = Vector2(700, 400)          # 挪远，免得敌人看见玩家改去追
	player.set_physics_process(false)
	var walker := _enemy("Enemy_03")
	var start := Vector2(40, 40)
	walker.global_position = start
	walker.set("_home", start)
	walker.set("last_known_pos", Vector2(230, 200))
	walker.set("state", S_ALERT)
	walker.set("_alert_left", 9.0)
	for other in _enemies():
		if other != walker:
			other.set_physics_process(false)
	walker.set_physics_process(true)
	var travelled := 0.0
	var last: Vector2 = walker.global_position
	for i in 70:
		await physics_frame
		var now: Vector2 = walker.global_position
		travelled += last.distance_to(now)
		last = now
	var disp: float = start.distance_to(last)
	_check("敌人走斜线基本不扭（路程/位移 = %.2f）" % (travelled / maxf(disp, 1.0)),
			disp > 60.0 and travelled / maxf(disp, 1.0) < 1.15)

	# ⑩ 死后按左键重开，不该"开局白打一枪"。
	#     重开键就是开火键，而手枪是连发（automatic=true）：按键还按着的话，
	#     新角色出生的第一帧就会开枪。
	await _reload()
	Input.action_press("fire")              # 模拟"重开时左键还按着"
	await physics_frame
	_main.call("_load_level", 0)            # 重开
	await physics_frame
	await physics_frame
	await physics_frame
	var fresh := _player()
	var cap: int = int(fresh.call("capacity"))
	var held_ammo: int = int(fresh.get("ammo"))
	_check("正式关卡空手出生，按住重开键不会自动推击", fresh.get("weapon") == null and not bool(fresh.get("combat").get("swinging")))
	Input.action_release("fire")
	await physics_frame
	Input.action_press("fire")
	await physics_frame
	await physics_frame
	Input.action_release("fire")
	_check("松开后重新点击可以空手推击", bool(fresh.get("combat").get("swinging")))

	print("\n--- 第十一幕：全部关卡都能加载 ---")
	# 先把当前 Main 收掉，免得两套关卡同时在场
	if _main != null:
		_main.queue_free()
		_main = null
		await process_frame
		await process_frame

	var all_levels := _live_levels()
	var total_enemies := 0
	for path: String in all_levels:
		var ps := load(path) as PackedScene
		if ps == null:
			_check(path + " 能加载", false)
			continue
		var each_level := ps.instantiate() as Node2D
		get_root().add_child(each_level)
		await process_frame
		await physics_frame

		var has_player := each_level.get_node_or_null("Player") != null
		_check(path.get_file() + " 正式关卡空手出生且枪模型隐藏", each_level.get_node("Player").get("weapon") == null and not each_level.get_node("Player/Aim/Gun").visible)
		# 手工关卡的敌人可能挂在根节点；必须按实际组成员统计，不能漏测容器外的敌人。
		var level_enemies: Array = []
		for e in get_nodes_in_group("enemies"):
			if each_level.is_ancestor_of(e):
				level_enemies.append(e)
		var count: int = level_enemies.size()
		var walkable: int = int(each_level.call("walkable_cell_count"))
		total_enemies += count

		# 硬检查：关卡"结构上"能用（有玩家、地够多）
		_check("%s：玩家✓ 可通行 %d 格" % [path.get_file(), walkable],
				has_player and walkable > 500)
		# 硬检查：根节点名必须和文件名一致。
		# Level_02.tscn 的根以前被错写成 "Level_01"，害得"清场后进下一关"那条
		# 断言一直查不到正确的名字 —— 这条就是用来钉住它的。
		_check("%s 的根节点名与文件名一致（实际 '%s'）" % [
				path.get_file(), each_level.name],
				each_level.name == path.get_file().get_basename())
		# 敌人数量只作为**信息**，不作为失败条件：
		# 关卡是玩家随时在编辑的内容，测试不该替它规定"必须有几个敌人"。
		if count == 0:
			print("      ⚠️ %s：没有存活敌人，请确认这是否是空白关卡" % path.get_file())
		else:
			print("      %s：敌人 %d 个" % [path.get_file(), count])

		# 让这一关真的跑一会儿：任何脚本报错都会打到 stderr，
		# 同时检查敌人有没有因为碰撞/寻路问题跑出地图
		var rect: Rect2 = each_level.get("room_rect")
		for i in 90:
			await physics_frame
		var escaped := 0
		for e in level_enemies:
			if not rect.grow(32.0).has_point((e as Node2D).global_position):
				escaped += 1
		_check("%s：空跑 1.5 秒无异常（无敌人跑出地图）" % path.get_file(), escaped == 0)

		each_level.queue_free()
		await process_frame

	print("  实际 %d 关共 %d 个敌人（信息，不作为失败条件）" % [all_levels.size(), total_enemies])

	# ---------------- 第十二幕：声音 ----------------
	print("\n--- 第十二幕：声音 ---")
	var audio := get_root().get_node_or_null("Audio")
	_check("音频总管已注册为 Autoload（Audio）", audio != null)
	if audio != null:
		_check("8 个音效素材全部就位", bool(audio.call("all_loaded")))

		# 玩家开枪 → 玩家枪声
		await _reload()
		audio.call("clear_history")
		player.call("_fire")
		await physics_frame
		_check("玩家开枪 → 听得到玩家枪声", (audio.get("history") as Array).has("shot_player"))
		_check("枪声播放器确实挂进了场景树（%d 个子节点）" % audio.get_child_count(),
				audio.get_child_count() > 1)
		# Autoload 不是 CanvasItem —— 这里验证定位音效仍然按世界坐标解析，
		# 否则声音会全部挤在原点、左右声像也是错的
		var spatial: AudioStreamPlayer2D = null
		for child in audio.get_children():
			if child is AudioStreamPlayer2D:
				spatial = child
				break
		_check("定位音效落在世界坐标上（不是原点）",
				spatial != null and spatial.global_position.distance_to(player.global_position) < 200.0)

		# 敌人死亡 → 击杀音
		audio.call("clear_history")
		_enemy("Enemy_01").call("take_damage", 1, Vector2.ZERO)
		await physics_frame
		_check("敌人死亡 → 听得到击杀音", (audio.get("history") as Array).has("kill"))

		# 推门 → 门响；但"听得见"和"惊动敌人"是两回事
		await _reload()
		audio.call("clear_history")
		var audio_door := _door(0) as Node2D
		player.global_position = audio_door.global_position + Vector2(-16, 0)
		for i in 12:
			player.set("velocity", Vector2(220, 0))
			await physics_frame
		_check("推门 → 听得到门响", (audio.get("history") as Array).has("door"))
		_check("门响 ≠ 惊动敌人（门噪声半径仍为 0）",
				absf(float(audio_door.get("noise_radius"))) < 0.01)

		# 弹匣打空 → 换弹音（素材长度已按 reload_time 0.9s 对齐）
		await _reload()
		audio.call("clear_history")
		player.set("ammo", 0)
		player.call("_fire")
		await physics_frame
		_check("空枪改为挥击而不是装填", not (audio.get("history") as Array).has("reload") and bool(player.get("combat").get("swinging")))

		# 清场：**不再放**胜利音效 —— 改成了"最后一个击杀慢放"		await _reload()
		audio.call("clear_history")
		for e in _enemies():
			e.call("take_damage", 1, Vector2.ZERO)
		await physics_frame
		_check("清场不再放胜利音效（改成慢放了）",
				not (audio.get("history") as Array).has("clear"))
		await _wait_normal_time()
		await _reload()

	# ---------------- 第十三幕：打击感 ----------------
	print("\n--- 第十三幕：打击感 ---")
	await _wait_normal_time()
	var feel := get_root().get_node_or_null("Feel")
	_check("打击感总管已注册为 Autoload（Feel）", feel != null)
	var cam := get_first_node_in_group("game_camera")
	_check("相机挂上了震动脚本", cam != null and cam.has_method("add_trauma"))

	if feel != null and cam != null:
		# 视野：要能装下一个完整房间，但也不能大到看得见隔壁房间。
		# 关卡里的房间约 15 格宽 x 13 格高 = 240x208 px，**高度**是起决定作用的
		# 那个尺寸（16:9 横向天然看得更宽）。上限取 1.5 个房间高。
		var cam_zoom: float = cam.zoom.x
		var view_w: float = 640.0 / cam_zoom
		var view_h: float = 360.0 / cam_zoom
		_check("视野能装下一个完整房间（%.0fx%.0f px = %.1f x %.1f 格）" % [
				view_w, view_h, view_w / 16.0, view_h / 16.0],
				view_h >= 208.0 and view_h <= 312.0)

		# 开枪 → 定向后坐（朝瞄准反方向顶）+ 随机抖动
		#
		# ⚠️ trauma / _recoil / _zoom_punch 都是**逐帧衰减**的，所以要在发出信号的
		# **同一刻同步读取**。先 await 一帧再读的话，无头模式下偶尔一帧 delta 偏大
		# （几十毫秒）就会把它们衰减光 —— 测试会莫名其妙地飘红，而功能其实是好的。
		await _reload()
		cam = get_first_node_in_group("game_camera")
		cam.set("trauma", 0.0)
		cam.set("_recoil", Vector2.ZERO)
		player.call("_fire")
		var fire_trauma: float = float(cam.get("trauma"))
		var kick: Vector2 = cam.get("_recoil")
		var aim_dir: Vector2 = (player.get_node("Aim") as Node2D).global_transform.x.normalized()
		_check("开枪 → 相机震动（trauma=%.2f）" % fire_trauma, fire_trauma > 0.0)
		_check("开枪 → 定向后坐 %.1f px，且朝瞄准的反方向" % kick.length(),
				kick.length() > 3.0 and kick.normalized().dot(-aim_dir) > 0.9)

		# 击杀 → 顿帧 + 震屏 + 镜头推进 + 闪白放大
		cam.set("trauma", 0.0)
		cam.set("_zoom_punch", 0.0)
		var punch_target := _enemy("Enemy_01")
		punch_target.call("take_damage", 1, Vector2.ZERO)
		var kill_trauma: float = float(cam.get("trauma"))
		var punch: float = float(cam.get("_zoom_punch"))
		var vis := punch_target.get("visual") as Node2D
		var vis_scale: float = vis.scale.x
		var vis_bright: float = vis.modulate.r
		# ⚠️ 顿帧必须**同步**读，不能等一帧再读：
		# HIT_STOP_KILL 只有 0.08 秒，而且是**真实时间**计时的。
		# 中间但凡有一帧超过 80ms（比如上一幕刚跑完上千条射线抽样），
		# 等一帧再读就会读到 1.00，这条就变成偶发假失败。
		var kill_scale: float = Engine.time_scale
		await process_frame
		_check("击杀 → 顿帧（time_scale=%.2f）" % kill_scale, kill_scale < 0.5)
		_check("击杀 → 震屏（trauma=%.2f）" % kill_trauma, kill_trauma > 0.0)
		_check("击杀 → 镜头推进（_zoom_punch=%.3f）" % punch, punch > 0.03)
		_check("击杀 → 敌人闪白并放大（scale=%.2f 亮度=%.1f）" % [vis_scale, vis_bright],
				vis_scale > 1.1 and vis_bright > 1.0)

		# ⚠️ 最要紧的一条：顿帧必须自己弹回来。
		# 卡在 0.04 的话整个游戏会永远慢动作，而且是静默的。
		var waited := 0
		while Engine.time_scale < 0.99 and waited < 600:
			await process_frame
			waited += 1
		_check("顿帧会自己恢复（time_scale=%.2f，等了 %d 帧）" % [Engine.time_scale, waited],
				Engine.time_scale > 0.99)

		# 清场 → 慢动作
		await _reload()
		cam = get_first_node_in_group("game_camera")
		for e in _enemies():
			e.call("take_damage", 1, Vector2.ZERO)
		# 先等顿帧结束，剩下的应该是慢动作而不是 1.0
		var waited2 := 0
		while Engine.time_scale < 0.2 and waited2 < 600:
			await process_frame
			waited2 += 1
		_check("清场 → 进入慢动作（time_scale=%.2f）" % Engine.time_scale,
				Engine.time_scale > 0.2 and Engine.time_scale < 0.9)
		_check("慢动作连音频一起慢（playback_speed=%.2f）" % AudioServer.playback_speed_scale,
				AudioServer.playback_speed_scale < 0.9)
		await _wait_normal_time()
		_check("慢动作会自己恢复（画面 %.2f / 音频 %.2f）" % [
				Engine.time_scale, AudioServer.playback_speed_scale],
				Engine.time_scale > 0.99 and AudioServer.playback_speed_scale > 0.99)

	# 玩家死亡 → 比击杀更重的顿帧
	await _reload()
	Engine.time_scale = 1.0
	player.call("take_damage", 1, Vector2.ZERO)
	var death_scale: float = Engine.time_scale      # 同上：同步读，别等帧
	await process_frame
	_check("玩家死亡 → 重顿帧（time_scale=%.2f）" % death_scale, death_scale < 0.5)
	await _wait_normal_time()
	await _reload()

	# ---------------- 第十四幕：巡逻路线（用子节点当路点）----------------
	print("\n--- 第十四幕：巡逻路线 ---")
	await _reload()
	# 把玩家挪到天边，免得巡逻兵看见他改成追击
	player.global_position = Vector2(900, 900)
	var patroller := _enemy_of_kind("listener")
	_check("找得到巡逻兵", patroller != null)
	if patroller != null:
		# ① 没有路点就站岗，不能靠旧预设名字或偏移凭空生成巡逻路线。
		patroller.call("rebuild_route")
		var fallback: PackedVector2Array = patroller.call("patrol_route")
		_check("没放路点时只有岗位（%d 个点）" % fallback.size(), fallback.size() == 1)
		var home_pos: Vector2 = fallback[0]
		_check("没放路点时保持站岗", _state(patroller) == S_IDLE)

		# ② 加两个 Marker2D 子节点 → 路线 = 岗位 + 2 个路点
		for i in 2:
			var wp := Marker2D.new()
			wp.name = "Waypoint%d" % (i + 1)
			wp.position = Vector2(96.0 * (i + 1), 0.0)
			patroller.add_child(wp)
		patroller.call("rebuild_route")
		var patrol_path: PackedVector2Array = patroller.call("patrol_route")
		_check("加 2 个路点 → 路线 3 个点（岗位 + 2 路点）", patrol_path.size() == 3)
		_check("路点按子节点顺序、存的是相对出生点的偏移（%s / %s）" % [
				str((patrol_path[1] - home_pos).round()), str((patrol_path[2] - home_pos).round())],
				absf((patrol_path[1] - home_pos).x - 96.0) < 1.0
						and absf((patrol_path[2] - home_pos).x - 192.0) < 1.0)

		# ③ 行为：放开它，应该朝第 1 个路点走
		patroller.set_physics_process(true)
		var d_start: float = patroller.global_position.distance_to(patrol_path[1])
		for i in 40:
			await physics_frame
		var d_end: float = patroller.global_position.distance_to(patrol_path[1])
		_check("巡逻兵朝第 1 个路点走（%.0f → %.0f px）" % [d_start, d_end], d_end < d_start - 20.0)

		# ④ 闭环：站到最后一个路点上之后，应该绕回岗位而不是原地打转
		patroller.global_position = patrol_path[patrol_path.size() - 1]
		patroller.set("_route_index", patrol_path.size() - 1)
		await physics_frame
		var back_start: float = patroller.global_position.distance_to(patrol_path[0])
		for i in 12:
			await physics_frame
		var back_end: float = patroller.global_position.distance_to(patrol_path[0])
		_check("走到末尾后绕回岗位（%.0f → %.0f px）" % [back_start, back_end],
				back_end < back_start - 5.0)

		# ⑤ 够不到的路点不能把巡逻永久卡死：超时后自动跳下一个
		var idx_before: int = int(patroller.get("_route_index"))
		patroller.set("_waypoint_left", 0.05)
		for i in 10:
			await physics_frame
		_check("够不到的路点会超时跳过（下标 %d → %d）" % [
				idx_before, int(patroller.get("_route_index"))],
				int(patroller.get("_route_index")) != idx_before)

		# ⑥ 敌人被旋转过时，路点必须按旋转后的坐标系换算。
		#    以前直接 _home + m.position，敌人转 180° 时整条路线会镜像 ——
		#    "巡逻路径和我设置的对不上"就是这个。
		var spun := (load("res://scenes/enemies/EnemyMelee.tscn") as PackedScene).instantiate() as Node2D
		spun.set_physics_process(false)
		spun.position = Vector2(200, 200)
		spun.rotation = PI * 0.5                  # 转 90°：本地 +X 变成世界 +Y
		var mark := Marker2D.new()
		mark.name = "point"
		mark.position = Vector2(64, 0)
		spun.add_child(mark)
		get_root().add_child(spun)
		spun.call("rebuild_route")
		var spun_route: PackedVector2Array = spun.call("patrol_route")
		_check("旋转 90° 的敌人：路点算在世界 (200, 264)（实际 %s）" % (
				str(spun_route[1].round()) if spun_route.size() > 1 else "无"),
				spun_route.size() == 2 and spun_route[1].distance_to(Vector2(200, 264)) < 1.0)
		spun.queue_free()
		await process_frame
	# ---------------- 第十五幕：尸体（倒地声很小 + 看见尸体去查看）----------------
	print("\n--- 第十五幕：尸体 ---")
	await _reload()
	await _freeze_enemies(false)                  # 这一幕要真的跑 AI

	var corpse_seer: Node2D = null                # 会看见尸体的那个（远程兵）
	var corpse_body: Node2D = null                # 会死的那个（近战兵）
	var corpse_bystander: Node2D = null           # 另一个近战兵：离得远、还背对着
	for e in _enemies():
		var script_path := String((e as Node).get_script().resource_path)
		if script_path.contains("ranged") and corpse_seer == null:
			corpse_seer = e
		elif script_path.contains("melee") and corpse_body == null:
			corpse_body = e
		elif script_path.contains("melee") and corpse_bystander == null:
			corpse_bystander = e
	_check("这一幕需要 远程 + 近战 + 近战 三个敌人",
			corpse_seer != null and corpse_body != null and corpse_bystander != null)
	if corpse_seer != null and corpse_body != null and corpse_bystander != null:
		player.global_position = Vector2(900, 900)    # 玩家挪到天边，免得敌人改去追他
		for e in _enemies():                          # 其它敌人挪开并停掉，免得干扰
			if e != corpse_seer and e != corpse_body and e != corpse_bystander:
				e.set_physics_process(false)
				e.global_position = Vector2(40, 40)

		# corpse_seer 和 corpse_body 同房间、无遮挡、正对着
		corpse_seer.global_position = ROOM_TM_WEST
		corpse_seer.set("_home", ROOM_TM_WEST)
		corpse_seer.set("facing", Vector2.RIGHT)
		corpse_body.global_position = ROOM_TM_WEST + Vector2(80, 0)
		# bystander 在隔壁房间、离 130px、背对着 —— 既看不见、也该听不见
		# （倒地声只有 56px；旧值 150px 的话这条会失败）
		corpse_bystander.global_position = ROOM_TM_WEST + Vector2(-130, 0)
		corpse_bystander.set("_home", corpse_bystander.global_position)
		corpse_bystander.set("facing", Vector2.LEFT)
		await _settle()
		_check("查看前 corpse_seer 还是 IDLE（没凭空起疑）", _state(corpse_seer) == S_IDLE)

		corpse_body.call("take_damage", 1, Vector2.ZERO)
		await _settle()
		_check("尸体进了 corpses 组", corpse_body.is_in_group("corpses"))
		_check("尸体退出了 enemies 组", not corpse_body.is_in_group("enemies"))

		for i in 20:                                  # 检查周期 0.25s ≈ 15 帧
			await physics_frame
		_check("看见尸体的敌人进入 ALERT（去查看）", _state(corpse_seer) == S_ALERT)
		_check("它把尸体位置记成了查看目标（偏差 %.0fpx）" % (
				corpse_seer.get("last_known_pos") as Vector2).distance_to(corpse_body.global_position),
				(corpse_seer.get("last_known_pos") as Vector2).distance_to(corpse_body.global_position) < 2.0)
		_check("看过就记住、不会反复起疑（已记 %d 具）" % (
				corpse_seer.get("_seen_corpses") as Dictionary).size(),
				(corpse_seer.get("_seen_corpses") as Dictionary).size() == 1)

		# 反向：倒地声只有 56px —— 130px 外、又隔着墙的同伴不该被惊动
		_check("130px 外隔墙的同伴没听见倒地声（状态 %d）" % _state(corpse_bystander),
				_state(corpse_bystander) != S_ALERT and _state(corpse_bystander) != S_CHASE)
		# 反向：背对尸体看不见 → 不起疑（直接调一次检查，避免被 AI 走动干扰）
		corpse_bystander.set("_corpse_timer", 0.0)
		corpse_bystander.set("facing", Vector2.LEFT)
		corpse_bystander.call("_check_corpses", 0.0)
		_check("背对尸体不起疑", (corpse_bystander.get("_seen_corpses") as Dictionary).is_empty())

	await _weapon_system_regressions()
	await _reload()

	await _combat_throw_regressions()
	await _visual_regressions()
	print("")
	if _fail == 0:
		print(">>> 全部通过")
	else:
		print(">>> 失败 %d 项" % _fail)
	quit(_fail)


# ------------------------------------------------------------------ 工具

func _equip_case(actor: Node, kind: String, rounds: int = -1) -> RefCounted:
	var value: RefCounted = null
	if not kind.is_empty():
		value = load("res://scripts/weapons/weapon_state.gd").new(load("res://resources/weapons/%s.tres" % kind))
		if rounds >= 0:
			value.set("ammo", rounds)
	actor.call("equip_weapon", value)
	return value

func _visual_regressions() -> void:
	print("\n--- 第十八幕：分层显示 / 换图解耦 / 身份尸体 ---")
	await _weapon_arena()
	var av: Node2D = player.get_node("Body")
	av.set_process(false)
	var legs: AnimatedSprite2D = av.get("legs")
	var upper: AnimatedSprite2D = av.get("upper")
	var corpse: AnimatedSprite2D = av.get("corpse")
	var cases := {"idle": Vector2.ZERO, "forward": Vector2(130, 0), "backward": Vector2(-130, 0), "strafe_left": Vector2(0, -130), "strafe_right": Vector2(0, 130)}
	for mode: String in cases:
		av.call("update_state", cases[mode], 0.0, 260.0, false)
		_check("下身按相对瞄准速度选择 " + mode, String(av.get("locomotion")) == mode and String(legs.animation) == mode)
	av.call("update_state", Vector2(-130, 0), PI * 0.5, 260.0, false)
	_check("转向后侧移使用新的瞄准坐标系", String(av.get("locomotion")) == "strafe_right" and is_equal_approx(av.get_node("UpperRig").global_rotation, PI * 0.5))
	_check("移动动画播放速度随实际速度变化", is_equal_approx(legs.speed_scale, 0.5))
	_check("上身64px画布按4倍密度接入", upper.sprite_frames.get_frame_texture(upper.animation, 0).get_size() == Vector2(64, 64) and upper.scale == Vector2(0.25, 0.25))
	_check("尸体128px画布不改变玩家碰撞", corpse.sprite_frames.get_frame_texture("corpse", 0).get_size() == Vector2(128, 128) and player.get_node("CollisionShape2D").shape.size == Vector2(12, 12) and player.scale == Vector2.ONE)

	var knife := _equip_case(player, "knife")
	var view: Node2D = player.get_node("Aim/Gun")
	_check("持刀使用独立纹理显示而非碰撞多边形", not bool(view.get("using_fallback")) and view.get("displayed_id") == "knife")
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("melee_active")
	for i in range(7):
		frames.add_frame("melee_active", upper.sprite_frames.get_frame_texture("melee_active", 0))
	var appearance: Resource = av.get("appearance").duplicate()
	appearance.set("upper_frames", frames)
	av.call("set_appearance", appearance)
	av.call("receive_pose", {"kind": "melee", "phase": "active", "progress": 0.75, "angle": 0.2})
	_check("7帧攻击素材按玩法进度采样第5帧", upper.frame == 5 and String(upper.animation) == "melee_active")
	_check("部分交付保留缺失动作回退且不改原资源", upper.sprite_frames.has_animation("idle_melee") and not frames.has_animation("idle_melee"))
	_check("替换动画资源不创建新武器或改变弹药", player.get("weapon_instance") == knife and knife.get("ammo") == 0 and not bool(player.get("combat").get("swinging")))
	var poses := [0]
	var cb := func(_p: Dictionary) -> void: poses[0] += 1
	player.get("combat").pose_changed.connect(cb)
	var target := _case_enemy("EnemyMelee", Vector2(24, 0))
	var outside := _case_enemy("EnemyMelee", Vector2(40, 0))
	await _settle()
	player.get_node("Aim").global_rotation = 0.0
	# 故意换成尺寸与刀尖元数据都不同的贴图，伤害依然只能读显式几何。
	var display: Resource = knife.get("definition").duplicate()
	var profile: Resource = load("res://scripts/visuals/weapon_visual_data.gd").new()
	profile.set("texture", ImageTexture.create_from_image(Image.create(256, 64, false, Image.FORMAT_RGBA8)))
	profile.set("grip_px", Vector2(16, 32))
	profile.set("tip_px", Vector2(80, 32))
	display.set("visual_profile", profile)
	view.call("set_definition", display)
	player.call("_fire")
	player.get("combat").call("tick", 0.03)
	_check("更换帧数和贴图大小后前摇仍不伤人", _state(target) != S_DEAD and String(av.get("action_phase")) == "windup")
	player.get("combat").call("tick", 0.09)
	_check("更换显示后仍在既定有效期击中28px内目标", _state(target) == S_DEAD and _state(outside) != S_DEAD)
	_check("攻击轨迹由战斗模块持续输出给显示", poses[0] >= 3 and String(view.get("last_pose").get("phase")) == "active")
	_check("可见刀尖沿输出轨迹到达28px", is_equal_approx(view.position.length() + float(view.call("visual_tip")), 28.0))
	_check("显示替换没有更换实物或扣除刀的弹药", player.get("weapon_instance") == knife and knife.get("ammo") == 0)
	player.get("combat").pose_changed.disconnect(cb)

	await _weapon_arena()
	av = player.get_node("Body")
	var gun := _equip_case(player, "pistol", 5)
	view = player.get_node("Aim/Gun")
	var data: Resource = gun.get("definition")
	_check("手持武器显式握持点正确", view.get_node("Sprite").offset == -data.get("visual_profile").get("grip_px"))
	av.call("show_effect", "shoot")
	av.get_node("AnimationPlayer").advance(0.056)
	av.call("_process", 0.0)
	_check("武器挂点随上身反馈动作移动", not view.position.is_zero_approx())
	player.get_node("Aim").global_rotation = PI
	av.call("update_state", Vector2.ZERO, PI, 260.0, false)
	av.call("show_effect", "shoot")
	av.get_node("AnimationPlayer").advance(0.056)
	av.call("_process", 0.0)
	_check("朝左射击时后坐沿枪口反方向移动", view.global_position.x > player.global_position.x)
	player.call("_throw_weapon")
	var flying: Node2D = get_nodes_in_group("thrown_weapons")[0]
	_check("投掷显示保存原5发实物与正确身份", flying.get("weapon_instance") == gun and gun.get("ammo") == 5 and flying.get_node("Gun").displayed_id == "pistol")
	_check("飞行武器使用绝对z=-1", not flying.z_as_relative and flying.z_index == -1)
	_check("飞行和落地共用显式地面中心", flying.get_node("Gun/Sprite").offset == -data.get("visual_profile").get("ground_center_px"))
	flying.call("_land")
	flying.global_position = player.global_position
	player.call("_pickup_weapon")
	_check("落地拾取后仍为同一5发实例", player.get("weapon_instance") == gun and gun.get("ammo") == 5)
	player.call("take_damage", 1, Vector2.ZERO)
	var count := get_nodes_in_group("dropped_weapons").size()
	player.call("take_damage", 1, Vector2.ZERO)
	av.call("_process", 1.0)
	av.call("set_stunned", false)
	av.call("receive_pose", {"kind": "melee", "phase": "active", "progress": 0.5})
	_check("玩家死亡只播一次且保持身份尸体", av.get("death_play_count") == 1 and String(av.get("life_state")) == "corpse" and av.get_node("Corpse").visible and not av.get_node("UpperRig").visible)
	_check("玩家死亡即时掉落一次且原弹药不变", count == 1 and get_nodes_in_group("dropped_weapons").size() == count and get_nodes_in_group("dropped_weapons")[0].get("weapon_instance") == gun and gun.get("ammo") == 5)
	_check("掉落武器在玩家尸体上方", _effective_z(get_nodes_in_group("dropped_weapons")[0]) > _effective_z(player))
	var old_z := walls.z_index
	walls.z_index += 3
	_check("尸体层随墙移动且始终墙下两层", int(_level().call("corpse_z")) == _effective_z(walls) - 2)
	walls.z_index = old_z

	for id: String in ["knife", "dagger", "machete", "katana"]:
		await _weapon_arena()
		var blade := _equip_case(player, id)
		var blade_data: Resource = blade.get("definition")
		var victim := _case_enemy("EnemyMelee", Vector2(24, 0))
		await _settle()
		player.call("_fire")
		player.get("combat").call("tick", 0.3)
		_check(id + " 外观共用28px致命挥击及原有效段", _state(victim) == S_DEAD and blade_data.get("melee_inner") == 5.0 and blade_data.get("damage") == 1)
		player.get("combat").call("tick", 0.5)
		player.call("_throw_weapon")
		var item: Node2D = get_nodes_in_group("thrown_weapons")[0]
		_check(id + " 投出后身份与实物一致", item.get("weapon_instance") == blade and item.get_node("Gun").displayed_id == id and not bool(item.get_node("Gun").get("using_fallback")))

	await _weapon_arena()
	var enemy := _case_enemy("EnemyMelee", Vector2(100, 0))
	var ev: Node2D = enemy.get_node("Visual")
	_check("主角与敌人使用不同身份外观", player.get_node("Body").get("appearance").get("appearance_id") != ev.get("appearance").get("appearance_id"))
	enemy.call("take_damage", 1, player.global_position)
	count = get_nodes_in_group("dropped_weapons").size()
	enemy.call("take_damage", 1, player.global_position)
	ev.call("die")
	ev.call("_process", 1.0)
	ev.call("set_stunned", false)
	_check("敌人尸体为终态且死亡动画只播一次", ev.get("death_play_count") == 1 and String(ev.get("life_state")) == "corpse" and ev.get_node("Corpse").visible and not ev.get_node("UpperRig").visible)
	_check("敌人死亡动画不重复缴械掉落", count == 1 and get_nodes_in_group("dropped_weapons").size() == count)

	await _weapon_arena()
	enemy = _case_enemy("EnemyMelee", Vector2(24, 0))
	enemy.get_node("Aim").global_rotation = PI
	await _settle()
	enemy.get("combat").call("attack", Vector2.LEFT)
	enemy.get("combat").call("tick", 0.14)
	_check("敌人持械0.14秒仍为前摇且不伤人", not bool(player.get("is_dead")) and String(enemy.get("combat").get("model").get("last_pose").get("phase")) == "windup")
	enemy.get("combat").call("tick", 0.07)
	_check("敌人持械0.21秒进入有效期实际命中", bool(player.get("is_dead")) and String(enemy.get("combat").get("model").get("last_pose").get("phase")) == "active")
	enemy.get("combat").call("tick", 0.359)
	_check("敌人持械0.569秒仍在0.30秒后摇", bool(enemy.get("combat").get("swinging")))
	enemy.get("combat").call("tick", 0.002)
	_check("敌人持械0.571秒已结束动作", not bool(enemy.get("combat").get("swinging")))
	await _weapon_arena()
	enemy = _case_enemy("EnemyMelee", Vector2(20, 0))
	_equip_case(enemy, "")
	enemy.get_node("Aim").global_rotation = PI
	await _settle()
	enemy.get("combat").call("attack", Vector2.LEFT)
	enemy.get("combat").call("tick", 0.2)
	_check("敌人空手不随刀前摇缩短，0.2秒仍不击晕", not bool(player.call("is_stunned")))
	enemy.get("combat").call("tick", 0.15)
	_check("敌人空手0.30秒后才可实际推晕", bool(player.call("is_stunned")) and not bool(player.get("is_dead")))
	await _wait_normal_time()

func _weapon_arena() -> void:
	await _wait_normal_time()
	await _reload()
	player.set_physics_process(false)
	player.set_process(false)
	player.global_position = Vector2(1400, 1400)
	player.get_node("Aim").global_rotation = 0
	for e in _enemies():
		e.global_position = Vector2(3000, 3000)
	_equip_case(player, "")
	await _settle()

func _case_enemy(preset: String, offset: Vector2) -> Node2D:
	var e := load("res://scenes/enemies/%s.tscn" % preset).instantiate() as Node2D
	_level().add_child(e)
	e.global_position = player.global_position + offset
	e.set_physics_process(false)
	return e

func _case_wall(pos: Vector2, layer: int = 1) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = layer
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(2, 80)
	shape.shape = rect
	wall.add_child(shape)
	_level().add_child(wall)
	wall.global_position = pos
	return wall

func _weapon_system_regressions() -> void:
	print("\n--- 第十六幕：推倒 / 处决 / 挥击 / 有限弹药 / 缴械 ---")
	await _weapon_arena()
	var mark := _case_enemy("EnemyMelee", Vector2(10, 0))
	await _settle()
	player.call("_try_contact_kill")
	_check("触碰站立敌人不再自动暗杀", _state(mark) != S_DEAD)
	player.call("_fire")
	player.get("combat").call("tick", 0.04)
	_check("推击前摇中不会提前击晕", not mark.call("is_stunned"))
	player.get("combat").call("tick", 0.08)
	mark.set_physics_process(false)
	_check("空手有效期命中会击晕而不击杀", mark.call("is_stunned") and _state(mark) != S_DEAD)
	_check("击晕立即缴械", mark.get("weapon_instance") == null and get_nodes_in_group("dropped_weapons").size() == 1)
	player.call("_try_contact_kill")
	_check("刚推倒不会原地连成处决", _state(mark) != S_DEAD)
	player.global_position = mark.global_position - Vector2(20, 0)
	player.call("_try_contact_kill")
	player.global_position = mark.global_position - Vector2(10, 0)
	var wall := _case_wall((player.global_position + mark.global_position) * 0.5)
	await _settle()
	player.call("_try_contact_kill")
	_check("已经分离但有墙时不能处决", _state(mark) != S_DEAD)
	wall.queue_free()
	await _settle()
	player.call("_try_contact_kill")
	_check("分离后重新靠近可自动处决", _state(mark) == S_DEAD)
	_check("缴械后处决不重复掉落", get_nodes_in_group("dropped_weapons").size() == 1)

	await _weapon_arena()
	_equip_case(player, "knife")
	var upper := _case_enemy("EnemyMelee", Vector2(24, -8))
	var lower := _case_enemy("EnemyMelee", Vector2(24, 8))
	var behind := _case_enemy("EnemyMelee", Vector2(-20, 0))
	var far := _case_enemy("EnemyMelee", Vector2(40, 0))
	await _settle()
	player.call("_fire")
	player.get("combat").call("tick", 0.04)
	_check("挥刀前摇不造成伤害", _state(upper) != S_DEAD and _state(lower) != S_DEAD)
	player.get("combat").call("tick", 0.20)
	_check("一次挥动可扫中两名正面敌人", _state(upper) == S_DEAD and _state(lower) == S_DEAD)
	_check("背后与距离外的敌人不受伤", _state(behind) != S_DEAD and _state(far) != S_DEAD)
	_check("每个目标只结算一次击杀", int(_main.get("kills")) == 2)
	player.get("combat").call("tick", 0.4)
	_check("挥击后模型回到持有位置", is_zero_approx(player.get_node("Aim/Gun").rotation) and player.get_node("Aim/Gun").position == Vector2.ZERO)

	# 墙和门分别测真实物理遮挡，不能只测一个预先设置的阻挡标记。
	for layer in [1, 128]:
		await _weapon_arena()
		var protected := _case_enemy("EnemyMelee", Vector2(24, 0))
		_case_wall(player.global_position + Vector2(12, 0), layer)
		await _settle()
		player.call("_fire")
		player.get("combat").call("tick", 0.2)
		_check("物理层 %d 阻挡空手推击" % layer, not protected.call("is_stunned"))
		_equip_case(player, "knife")
		player.call("_fire")
		player.get("combat").call("tick", 0.3)
		_check("物理层 %d 阻挡刀刃挥击" % layer, _state(protected) != S_DEAD)

	await _weapon_arena()
	var attacker := _case_enemy("EnemyMelee", Vector2(24, 0))
	attacker.get_node("Aim").global_rotation = PI
	await _settle()
	attacker.get("combat").call("attack", Vector2.LEFT)
	attacker.get("combat").call("tick", float(attacker.get("combat").get("enemy_windup")) * 0.5)
	_check("敌人近战前摇给出躲避机会", not bool(player.get("is_dead")))
	player.global_position += Vector2(0, 40)
	await _settle()
	attacker.get("combat").call("tick", 0.3)
	_check("离开锁定的挥击轨迹后不会被击杀", not bool(player.get("is_dead")))
	attacker.get("combat").call("tick", 1.0)
	player.global_position -= Vector2(0, 40)
	await _settle()
	attacker.get("combat").call("attack", Vector2.LEFT)
	attacker.call("stun", Vector2.RIGHT, 160.0)
	attacker.set_physics_process(false)
	attacker.get("combat").call("tick", 0.6)
	_check("敌人被击晕会取消未完成挥击", not bool(player.get("is_dead")) and not bool(attacker.get("combat").get("swinging")))

	for kind: String in ["pistol", "smg", "shotgun"]:
		await _weapon_arena()
		var instance := _equip_case(player, kind)
		var data: Resource = instance.get("definition")
		var noises: Array = []
		var triggers := [0]
		var cb := func(_p: Vector2, radius: float, source: Node) -> void:
			if source == player:
				noises.append(radius)
		var shot_cb := func(_a: Vector2, _b: Vector2) -> void: triggers[0] += 1
		_events().noise_emitted.connect(cb)
		_events().bullet_fired.connect(shot_cb)
		player.call("_fire")
		var expected_noise: float = {"pistol": 0.0, "smg": 180.0, "shotgun": 200.0}[kind]
		_check(kind + " 每次扳机消耗一发", int(instance.get("ammo")) == int(data.get("magazine")) - 1)
		_check(kind + " 实际产生正确数量弹丸", get_nodes_in_group("player_bullets").size() == int(data.get("pellets")))
		_check(kind + " 每次扳机只有一次射击反馈", triggers[0] == 1)
		_check(kind + " 实际发出的噪声半径正确", noises.is_empty() if expected_noise == 0.0 else noises == [expected_noise])
		player.call("_fire")
		_check(kind + " 冷却内不能重复射击", triggers[0] == 1)
		_events().noise_emitted.disconnect(cb)
		_events().bullet_fired.disconnect(shot_cb)
		player.get("combat").call("tick", 1.0)
		player.set("ammo", 0)
		player.call("_fire")
		_check(kind + " 空枪自动开始挥枪动作", bool(player.get("combat").get("swinging")) and player.get("ammo") == 0)
		_check(kind + " HUD 显示空枪近战", "空枪近战" in String(_main.get_node("HUD/AmmoLabel").text))
		player.get("combat").call("tick", 2.0)
		_check(kind + " 等待也不会自动补弹", player.get("ammo") == 0)

	# 自动/半自动通过真实按键与物理帧验证，不能只断言资源里的 automatic 字段。
	for kind: String in ["pistol", "smg", "shotgun"]:
		await _weapon_arena()
		var value := _equip_case(player, kind)
		var initial: int = value.get("ammo")
		player.collision_layer = 0
		player.set_physics_process(true)
		Input.action_press("fire")
		for frame in range(110):
			await physics_frame
		Input.action_release("fire")
		player.set_physics_process(false)
		var used: int = initial - int(value.get("ammo"))
		_check(kind + " 按住左键的射击模式正确", used == 1 if kind == "shotgun" else used > 1)

	await _weapon_arena()
	var gunner := _case_enemy("EnemySMG", Vector2(80, 0))
	var original: RefCounted = gunner.get("weapon_instance")
	var sibling := _case_enemy("EnemySMG", Vector2(100, 100))
	for i in range(3):
		gunner.set("_cooldown_left", 0.0)
		gunner.get("combat").call("tick", 0.1)
		gunner.call("_fire")
	_check("敌人实际射击扣掉自己的三发", original.get("ammo") == 21)
	_check("同武器定义的另一敌人仍有完整弹药", sibling.get("ammo") == 24 and sibling.get("weapon_instance") != original)
	for bullet in get_nodes_in_group("enemy_bullets"):
		bullet.queue_free()
	gunner.call("stun", Vector2.RIGHT, 160.0)
	gunner.set_physics_process(false)
	gunner.call("stun", Vector2.RIGHT, 160.0)
	gunner.set_physics_process(false)
	_check("重复击晕只掉落一次", get_nodes_in_group("dropped_weapons").size() == 1)
	var item := get_nodes_in_group("dropped_weapons")[0] as Node2D
	_check("掉落的是原武器实例及剩余弹药", item.get("weapon_instance") == original and original.get("ammo") == 21)
	player.global_position = item.global_position - Vector2(20, 0)
	await _settle()
	player.call("_pickup_weapon")
	_check("玩家夺枪得到敌人打剩的21发", player.get("weapon_instance") == original and player.get("ammo") == 21)
	var loose := load("res://scenes/projectiles/ThrownWeapon.tscn").instantiate() as Node2D
	var knife: RefCounted = load("res://scripts/weapons/weapon_state.gd").new(load("res://resources/weapons/knife.tres"))
	loose.set("weapon_instance", knife)
	loose.set("landed", true)
	_level().add_child(loose)
	loose.global_position = player.global_position
	await _settle()
	player.call("_pickup_weapon")
	_check("持枪按E可交换成刀", player.get("weapon_instance") == knife)
	_check("被换下的枪仍保留21发", get_nodes_in_group("dropped_weapons").size() == 1 and get_nodes_in_group("dropped_weapons")[0].get("weapon_instance") == original)
	player.call("_throw_weapon")
	_check("刀也能投出并空手", player.get("weapon_instance") == null and get_nodes_in_group("thrown_weapons").size() == 1)
	_check("飞行刀仍保存原实例、外观身份与可见显示", get_nodes_in_group("thrown_weapons")[0].get("weapon_instance") == knife and get_nodes_in_group("thrown_weapons")[0].get_node("Gun").displayed_id == "knife" and get_nodes_in_group("thrown_weapons")[0].get_node("Gun").visible)
	player.call("_pickup_weapon")
	_check("交换投掷后再捡回弹药不重置", player.get("weapon_instance") == original and player.get("ammo") == 21)
	var before := get_nodes_in_group("dropped_weapons").size()
	gunner.call("take_damage", 1, player.global_position)
	_check("缴械后死亡不会复制枪", get_nodes_in_group("dropped_weapons").size() == before)

	for preset: String in ["EnemyRanged", "EnemySMG", "EnemyShotgun"]:
		await _weapon_arena()
		player.collision_layer = 0
		var shooter := _case_enemy(preset, Vector2(200, 0))
		shooter.set("move_speed", 0.0)
		shooter.set("aim_error_deg", 0.0)
		shooter.call("_on_attack_enter")
		var times: Array[float] = []
		var clock := [0.0]
		var cb := func(_p: Vector2) -> void: times.append(clock[0])
		_events().enemy_fired.connect(cb)
		for frame in range(130):
			clock[0] += 1.0 / 60.0
			shooter.get("combat").call("tick", 1.0 / 60.0)
			shooter.call("_ai_attack", 1.0 / 60.0)
		_events().enemy_fired.disconnect(cb)
		_check(preset + " 首发有0.4秒反应窗口", not times.is_empty() and times[0] >= 0.4)
		if preset == "EnemySMG":
			_check("冲锋枪敌人使用三发一轮", times.size() >= 4 and times[1] - times[0] >= 0.08 and times[2] - times[1] >= 0.08 and times[3] - times[2] >= 0.99)
		else:
			_check(preset + " 射击间隔至少1.2秒", times.size() >= 2 and times[1] - times[0] >= 1.19)
		var data: Resource = shooter.get("weapon")
		_check(preset + " 敌人弹药与实际扳机次数一致", shooter.get("ammo") == int(data.get("magazine")) - times.size())
		_check(preset + " 敌方实体弹丸数量正确", get_nodes_in_group("enemy_bullets").size() == times.size() * int(data.get("pellets")))

	await _weapon_arena()
	var empty := _case_enemy("EnemyRanged", Vector2(80, 0))
	_equip_case(empty, "pistol", 0)
	empty.set("facing", Vector2.LEFT)
	empty.call("_sync_aim")
	var initial_distance := player.global_position.distance_to(empty.global_position)
	empty.set_physics_process(true)
	for frame in range(15):
		await physics_frame
	_check("空枪敌人会追近玩家", player.global_position.distance_to(empty.global_position) < initial_distance - 5.0)
	_check("空枪敌人不会再射出子弹", get_nodes_in_group("enemy_bullets").is_empty())
	empty.set_physics_process(false)
	empty.global_position = player.global_position + Vector2(24, 0)
	empty.get_node("Aim").global_rotation = PI
	await _settle()
	empty.get("combat").call("attack", Vector2.LEFT)
	empty.get("combat").call("tick", 0.45)
	_check("空枪挥中后同样致命", bool(player.get("is_dead")))

	await _weapon_arena()
	var unarmed := _case_enemy("EnemyMelee", Vector2(20, 0))
	_equip_case(unarmed, "")
	unarmed.get_node("Aim").global_rotation = PI
	await _settle()
	unarmed.get("combat").call("attack", Vector2.LEFT)
	unarmed.get("combat").call("tick", 0.45)
	_check("缴械后的敌人空手只击晕玩家", player.call("is_stunned") and not bool(player.get("is_dead")))
	player.call("_physics_process", 1.01)
	_check("玩家击晕1秒后可恢复", not player.call("is_stunned"))
	unarmed.get("combat").call("tick", 0.8)
	_check("敌人长后摇避免无限连晕", not bool(unarmed.get("combat").call("attack", Vector2.LEFT)))
	await _wait_normal_time()

func _combat_throw_regressions() -> void:
	print("\n--- 第十七幕：门缝 / 身体弹道 / 武器投掷 ---")
	await _reload()
	player.set_physics_process(false)
	player.set_process(false)
	var observer := _enemy_of_kind("ranged")
	# 使用独立测试门，从门自身尺寸推导探测点，不依赖用户关卡布局。
	for horizontal in [true, false]:
		var door := load("res://scenes/props/Door.tscn").instantiate() as Node2D
		door.set("horizontal", horizontal)
		_level().add_child(door)
		door.global_position = Vector2(1400, 1400)
		door.set_physics_process(false)
		var span: float = door.get_node("Hinge/Panel/CollisionShape2D").shape.size.x
		for a in [0.0, 0.2, -0.2]:
			door.set("angle", a)
			door.call("_apply_angle")
			await _settle()
			for sign_x in [-1.0, 1.0]:
				var local_x: float = sign_x * (span * 0.5 - 0.5)
				var from := door.to_global(Vector2(local_x, -40))
				var to := door.to_global(Vector2(local_x, 40))
				_check("横门=%s 角度 %.1f 边缘 %d 不漏视" % [horizontal, a, sign_x], observer.call("_world_blocks", from, to))
		door.set("angle", door.get("open_angle"))
		door.call("_apply_angle")
		await _settle()
		_check("完全打开的门洞可见", not observer.call("_world_blocks", door.to_global(Vector2(0, -40)), door.to_global(Vector2(0, 40))))
		door.queue_free()
		await _settle()

	var thin_wall := StaticBody2D.new()
	thin_wall.collision_layer = 1
	var wall_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(4, 80)
	wall_shape.shape = rect
	thin_wall.add_child(wall_shape)
	_level().add_child(thin_wall)
	thin_wall.global_position = Vector2(1400, 1400)
	observer.global_position = thin_wall.global_position + Vector2(50, 0)
	player.global_position = thin_wall.global_position + Vector2(-8, 0)
	player.get_node("Aim").global_rotation = 0
	await _settle()
	_check("测试前提：枪口已经伸到薄墙另一侧", player.get_node("Aim/Muzzle").global_position.x > thin_wall.global_position.x + rect.size.x / 2)
	player.call("_fire")
	var shots := get_nodes_in_group("player_bullets")
	_check("玩家使用实体弹体", shots.size() == 1)
	if not shots.is_empty():
		_check("从身体中心生成", shots[0].global_position.distance_to(player.global_position) < 0.01)
		_check("子弹低于人物及枪模型", _effective_z(shots[0]) < _effective_z(player.get_node("Aim/Gun")))
	for frame in range(20):
		await physics_frame
	_check("枪口越墙也不能射杀墙后敌人", _state(observer) != S_DEAD)
	_check("子弹被薄墙消耗", get_nodes_in_group("player_bullets").is_empty())
	thin_wall.queue_free()
	observer.global_position = Vector2(2000, 2000)
	player.global_position = Vector2(1400, 1400)
	await _settle()
	var saved_weapon: Resource = player.get("weapon")
	player.set("ammo", 5)
	var quiet := [0]
	var noise_cb := func(_p: Vector2, _r: float, _s: Node) -> void: quiet[0] += 1
	_events().noise_emitted.connect(noise_cb)
	player.call("_throw_weapon")
	_check("投出后空手并隐藏枪模型", player.get("weapon") == null and not player.get_node("Aim/Gun").visible)
	player.call("_fire")
	_check("空手不能射击", get_nodes_in_group("player_bullets").is_empty())
	player.get("combat").call("cancel")
	var thrown := get_nodes_in_group("thrown_weapons")
	_check("生成唯一投掷武器", thrown.size() == 1)
	if not thrown.is_empty():
		var item := thrown[0] as Node2D
		var start := item.global_position
		player.call("_pickup_weapon")
		_check("飞行中不能捡回", player.get("weapon") == null)
		for frame in range(32):
			await physics_frame
		_check("飞满距离后落地", item.get("landed") and is_equal_approx(start.distance_to(item.global_position), float(item.get("max_distance"))))
		player.call("_pickup_weapon")
		_check("超出拾取半径不能捡", player.get("weapon") == null)
		player.global_position = item.global_position - Vector2(float(player.get("pickup_radius")) - 1, 0)
		await _settle()
		player.call("_pickup_weapon")
		_check("范围内捡回同一把枪", player.get("weapon") == saved_weapon and player.get_node("Aim/Gun").visible)
		_check("保留剩余弹药且不补满", player.get("ammo") == 5)
		await _settle()
		_check("拾取后移除落地武器", get_nodes_in_group("dropped_weapons").is_empty())
	# 命中测试使用真实敌人，验证眩晕和击退而非只检查落地标记。
	player.global_position = Vector2(1400, 1400)
	observer.global_position = player.global_position + Vector2(60, 0)
	await _settle()
	player.call("_throw_weapon")
	for frame in range(7):
		await physics_frame
	_check("投掷命中击晕而不致死", observer.call("is_stunned") and _state(observer) != S_DEAD)
	_check("命中产生向前击退", (observer.get("velocity") as Vector2).x > 0)
	observer.set_physics_process(false)
	_check("命中后投掷武器和被缴械的敌枪都可回收", get_nodes_in_group("dropped_weapons").size() == 2)
	_check("投出和落地没有 AI 噪声", quiet[0] == 0)
	_events().noise_emitted.disconnect(noise_cb)
	player.global_position = observer.global_position - Vector2(8, 0)
	await _settle()
	player.call("_try_contact_kill")
	_check("空手仍可补刀投掷击晕的敌人", _state(observer) == S_DEAD and player.get("weapon") == null)
	await _wait_normal_time()
	var ground := get_nodes_in_group("dropped_weapons")[0] as Node2D
	var pickup_wall := StaticBody2D.new()
	pickup_wall.collision_layer = 1
	var pickup_shape := CollisionShape2D.new()
	pickup_shape.shape = rect
	pickup_wall.add_child(pickup_shape)
	_level().add_child(pickup_wall)
	pickup_wall.global_position = ground.global_position - Vector2(12, 0)
	player.global_position = ground.global_position - Vector2(23, 0)
	await _settle()
	player.call("_pickup_weapon")
	_check("距离足够也不能隔墙捡枪", player.get("weapon") == null)
	pickup_wall.queue_free()
	await _settle()
	# 通过真实 Input 动作验证按键通路，不只调用内部函数。
	player.set_physics_process(true)
	Input.action_press("pickup")
	await physics_frame
	await physics_frame
	Input.action_release("pickup")
	player.set_physics_process(false)
	_check("E 动作可捡回武器", player.get("weapon") == saved_weapon)
	player.global_position = Vector2(1400, 1400)
	player.get_node("Aim").global_rotation = 0
	player.set_physics_process(true)
	Input.action_press("throw_weapon")
	await physics_frame
	await physics_frame
	Input.action_release("throw_weapon")
	player.set_physics_process(false)
	_check("右键动作可投出武器并空手", player.get("weapon") == null and get_nodes_in_group("thrown_weapons").size() == 1)
	var bound_right := false
	for event in InputMap.action_get_events("throw_weapon"):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
			bound_right = true
	_check("投掷动作绑定鼠标右键", bound_right)
	await _reload()

func _fresh_main() -> void:
	if _main != null:
		_main.queue_free()
		await process_frame
		await process_frame
	var ps := load(MAIN_SCENE) as PackedScene
	if ps == null:
		printerr("无法加载 ", MAIN_SCENE)
		quit(1)
		return
	_main = ps.instantiate()
	get_root().add_child(_main)
	await process_frame
	await physics_frame
	# ★ Main 自己的 _ready 会加载 LEVELS[0]（正式关卡）。这里立刻换成测试关卡 ——
	#   正式关卡是玩家会手工编辑的，测试的几何断言不能建立在那上面。
	_main.call("load_level_file", TEST_LEVEL)
	await process_frame
	await physics_frame


## 重新加载 Main（连带新关卡），并刷新所有常用引用。
## ⚠️ _fresh_main 之后上一幕的节点全部已释放，必须重新取，不能复用旧变量。
func _reload() -> void:
	await _fresh_main()
	player = _player()
	blood = _level().get_node("Blood") as Node2D
	walls = _level().get_node("Walls") as Node2D
	await _freeze_enemies(true)


## 等 Engine.time_scale 回到 1。
## 打击感的顿帧/慢动作是**真实时间**计时的，用 physics_frame 等不准（那些帧本身被压慢了）。
## 等时间缩放和音频速度都回到 1。
## 打击感的顿帧/慢动作是**真实时间**计时的，用 physics_frame 等不准
## （那些帧本身被压慢了）。
func _wait_normal_time() -> void:
	var guard := 0
	while (Engine.time_scale < 0.99 or AudioServer.playback_speed_scale < 0.99) and guard < 900:
		await process_frame
		guard += 1


## Main 在 _ready 里就把关卡加载好了，这里等它出现
func _level() -> Node:
	var host := _main.get_node("LevelHost")
	if host.get_child_count() == 0:
		return null
	return host.get_child(0)


func _player() -> Node2D:
	return _level().get_node("Player") as Node2D


func _enemy(node_name: String) -> Node2D:
	return _level().get_node("Enemies/" + node_name) as Node2D


## 从 Walls 图层里**现找**一对「地板格 → 紧邻墙格」，返回 [地板中心, 墙中心]。
## 这样不管关卡怎么改几何，这条射线都一定有墙可打 —— 不用把坐标写死。
func _find_wall_probe() -> Array:
	var layer := _level().get_node_or_null("Walls") as TileMapLayer
	if layer == null:
		return []
	var used := layer.get_used_cells()
	for cell: Vector2i in used:
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var nb: Vector2i = cell + d
			if not used.has(nb):
				return [_cell_center(nb), _cell_center(cell)]
	return []


## 现找一段「连续 5 格都不是墙、也不在门附近」的横线，返回 [起点中心, 终点中心]。
## 用来验证"空处射线不该命中"。要避开门，因为射线掩码里含 door 层。
func _find_open_probe() -> Array:
	var layer := _level().get_node_or_null("Walls") as TileMapLayer
	if layer == null:
		return []
	var used := layer.get_used_cells()
	var blocked := _door_areas()
	for cell: Vector2i in used:
		var start: Vector2i = cell + Vector2i.RIGHT
		var ok := true
		for i in 5:
			var q: Vector2i = start + Vector2i(i, 0)
			if used.has(q) or blocked.has(q):
				ok = false
				break
		if ok:
			return [_cell_center(start), _cell_center(start + Vector2i(4, 0))]
	return []


## 每扇门周围 3x3 的格子（门板可能扫到的范围），用来避开它们
func _door_areas() -> Dictionary:
	var out := {}
	for d in _doors():
		var c := _world_to_cell((d as Node2D).global_position)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				out[c + Vector2i(dx, dy)] = true
	return out


func _world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / 16.0), floori(p.y / 16.0))


func _cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * 16 + 8, c.y * 16 + 8)


## 独立标尺：把物理射线（敌人判定视线用的）和图块数据（A* 网格、Bresenham 视线）
## 对同一批"能不能看见"做交叉验证，返回 [抽样条数, 漏墙条数]。
##
## 只统计**物理说通、图块说隔着墙**这一个方向 —— 那才是"隔墙看到人"。
## 反方向（物理更严，比如关着的门）不算问题：图块数据里没有门。
func _count_los_leaks() -> Array:
	var lv := _level()
	var walls := lv.get_node_or_null("Walls") as TileMapLayer
	if walls == null:
		return [0, 0]
	var used := walls.get_used_cells()
	var space: PhysicsDirectSpaceState2D = lv.get_world_2d().direct_space_state
	var sampled := 0
	var leaks := 0
	for e in _enemies():
		var eye := e as Node2D
		var eye_cell: Vector2i = lv.call("world_to_cell", eye.global_position)
		for cell: Vector2i in used:
			for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
				var tgt: Vector2i = cell + d
				if used.has(tgt) or not bool(lv.call("is_walkable_cell", tgt)):
					continue
				var p := Vector2(tgt) * 16.0 + Vector2(8.0, 8.0)
				var q := PhysicsRayQueryParameters2D.create(eye.global_position, p)
				q.collision_mask = 1 | 128
				q.exclude = [eye.get_rid()]
				q.hit_from_inside = true
				sampled += 1
				if space.intersect_ray(q).is_empty() \
						and not bool(lv.call("_line_clear", eye_cell, tgt)):
					leaks += 1
				if sampled > 1200:
					return [sampled, leaks]
	return [sampled, leaks]


## 关卡清单。**实际存在哪些由 _live_levels() 决定** ——
## 关卡是玩家随时在增删的内容（Level_03~05 就被删过），
## 清单里留着一个不存在的文件不该让整条测试挂掉。
const ALL_LEVEL_PATHS: Array[String] = [
	"res://scenes/levels/Level_01.tscn",
	"res://scenes/levels/Level_02.tscn",
	"res://scenes/levels/Level_03.tscn",
]


## 一个 Node2D 的**有效** z：沿父链累加 z_index，直到遇到 z_as_relative = false。
## （和 enemy.gd / level.gd 里那两个是同一套算法）
func _effective_z(n: Node2D) -> int:
	if n == null:
		return 0
	var total := 0
	var cur: Node = n
	while cur is Node2D:
		var n2 := cur as Node2D
		total += n2.z_index
		if not n2.z_as_relative:
			break
		cur = n2.get_parent()
	return total


## 实际存在的关卡（按清单顺序）
func _live_levels() -> Array[String]:
	var out: Array[String] = []
	for p in ALL_LEVEL_PATHS:
		if ResourceLoader.exists(p):
			out.append(p)
		else:
			print("      （跳过不存在的关卡：%s）" % p.get_file())
	return out


## 按**容器顺序**取第 index 扇门（0 起）。
##
## 故意不按名字取（`Doors/Door_01`）：名字是生成器起的，手工编辑时很容易被改掉，
## 一改测试就找不到门。按顺序取则只依赖"门有几扇、顺序如何"。
func _door(index: int) -> Node2D:
	var holder := _level().get_node_or_null("Doors")
	if holder == null or index >= holder.get_child_count():
		return null
	return holder.get_child(index) as Node2D


## 关卡里所有门（按容器顺序）
func _doors() -> Array:
	var holder := _level().get_node_or_null("Doors")
	return holder.get_children() if holder != null else []


## 攻击类型按脚本查；听觉测试角色按夹具元数据查，不依赖已经删除的旧巡逻兵资源。
func _enemy_of_kind(kind: String) -> Node2D:
	for e in _enemies():
		var role := String(e.get_meta("test_role", ""))
		if kind == "listener" and role == "listener":
			return e as Node2D
		if role == "listener":
			continue
		var path := String((e as Node).get_script().resource_path)
		if path.contains(kind):
			return e as Node2D
	return null


func _enemies() -> Array:
	return get_nodes_in_group("enemies")


func _bullets() -> Array:
	return get_nodes_in_group("enemy_bullets")


func _events() -> Node:
	return get_root().get_node("Events")


func _label(path: String) -> Label:
	return _main.get_node(path) as Label


func _control(path: String) -> Control:
	return _main.get_node(path) as Control


func _state(enemy: Node2D) -> int:
	return int(enemy.get("state"))


func _can_see(enemy: Node2D) -> bool:
	return bool(enemy.call("can_see_player"))


func _freeze_enemies(frozen: bool) -> void:
	for e in _enemies():
		e.set_physics_process(not frozen)
	await process_frame


## 等物理服务器与节点变换同步（射线检测依赖它）
func _settle() -> void:
	await physics_frame
	await physics_frame


## 朝 world + door 层打一条射线，返回"是否命中"。
## 门在独立的 door 层（第 8 层）上：只挡射线，不挡角色。
func _ray_hits(from: Vector2, to: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(from, to)
	q.collision_mask = (1 << 0) | (1 << 7)
	return not get_root().get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func _check(label: String, ok: bool) -> void:
	if ok:
		print("  [OK]   ", label)
	else:
		_fail += 1
		print("  [FAIL] ", label)
