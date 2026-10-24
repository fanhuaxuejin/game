extends SceneTree
## 不依赖关卡：验证近战、手枪都按 point 巡逻，战斗仍按武器执行。
## 用真实物理帧量移动、检查射出的子弹，避免只查状态标记却漏掉实际行为。

const S_IDLE := 0
const S_PATROL := 1
const S_ALERT := 2
const S_ATTACK := 4
const S_DEAD := 5
const ENEMY_SCENES := [
	"res://scenes/enemies/EnemyMelee.tscn",
	"res://scenes/enemies/EnemyRanged.tscn",
	"res://scenes/enemies/EnemySMG.tscn",
	"res://scenes/enemies/EnemyShotgun.tscn",
]

var _fail: int = 0
var _player: Node2D
var _projectiles: Node2D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_player = (load("res://scenes/player/Player.tscn") as PackedScene).instantiate() as Node2D
	_player.position = Vector2(900, 900)
	_player.set_physics_process(false)
	_player.set_process(false)
	# 战斗用真实子弹验证，但不让测试靶死亡触发全局顿帧、干扰后续物理计时。
	_player.collision_layer = 0
	_player.get_node("Camera2D").set("enabled", false)
	get_root().add_child(_player)
	_projectiles = Node2D.new()
	_projectiles.add_to_group("projectile_parent")
	get_root().add_child(_projectiles)
	print("--- 攻击方式与巡逻解耦 ---")
	for path: String in ENEMY_SCENES:
		await _verify_enemy(path)
	_projectiles.free()
	_player.free()
	await process_frame
	print("")
	if _fail == 0:
		print(">>> 巡逻路线逻辑全部通过")
	else:
		print(">>> 失败 %d 项" % _fail)
	quit(_fail)


func _verify_enemy(path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		_check("能加载 " + path, false)
		return
	var label := path.get_file().get_basename()
	var e := scene.instantiate() as Node2D
	e.position = Vector2(100, 100)
	get_root().add_child(e)
	var home := e.global_position
	var melee: bool = int(e.get("weapon").get("kind")) == 1
	var initial_instance: RefCounted = e.get("weapon_instance")
	var hearing: float = e.get("hearing_multiplier")
	_check(label + " 无 point 出生即站岗", int(e.get("state")) == S_IDLE)
	_check(label + " 枪口等嵌套 Marker2D 不算路点", _route(e).size() == 1)
	await _frames(20)
	_check(label + " 无 point 时实际留在岗位", e.global_position.distance_to(home) < 1.0)

	var dummy := Node2D.new()
	dummy.name = "point_fake"
	e.add_child(dummy)
	e.call("rebuild_route")
	_check(label + " 普通节点即使命名 point 也不巡逻", int(e.get("state")) == S_IDLE)
	var point1 := _add_point(e, "point1", Vector2(96, 0))
	e.call("rebuild_route")
	_check(label + " 一个 point 加岗位形成两点路线", _route(e).size() == 2)
	await _frames(35)
	_check(label + " 加 point 后实际朝路点移动", e.global_position.distance_to(home + point1.position) < 76.0)
	_check(label + " 巡逻不替换武器或改变听力", e.get("weapon_instance") == initial_instance
			and is_equal_approx(float(e.get("hearing_multiplier")), hearing))
	e.set_physics_process(false)
	var point2 := _add_point(e, "point2", Vector2(96, 96))
	e.call("rebuild_route")
	var route := _route(e)
	_check(label + " 两个 point 加岗位形成三点路线", route.size() == 3
			and route[0].is_equal_approx(home) and route[2].is_equal_approx(home + point2.position))
	e.move_child(point2, point1.get_index())
	e.call("rebuild_route")
	_check(label + " 子节点顺序决定路线顺序", _route(e)[1].is_equal_approx(home + point2.position))
	# 人走动后重建路线仍按出生岗位，不把已移动的角色当作新原点。
	_check(label + " 重建路线不会跟着角色当前位置漂移", _route(e)[0].is_equal_approx(home))
	e.global_position = _route(e)[2]
	# 测试直接传送到末点时也停住身体，否则旧的前进惯性会吃掉短短的返回观察窗口。
	e.set("velocity", Vector2.ZERO)
	e.set("_route_index", 2)
	var back_start := e.global_position.distance_to(home)
	e.set_physics_process(true)
	await _frames(12)
	_check(label + " 到末尾后实际朝岗位返回（%.1f → %.1f，目标下标 %d）" % [
			back_start, e.global_position.distance_to(home), int(e.get("_route_index"))],
			e.global_position.distance_to(home) < back_start - 5.0)
	e.set("_waypoint_left", 0.0)
	var before: int = e.get("_route_index")
	await _frames(2)
	_check(label + " 路点超时会跳过", int(e.get("_route_index")) != before)

	var noise_pos := e.global_position + Vector2(0, 96)
	e.call("_on_noise", noise_pos, 200.0, null)
	_check(label + " 听声打断巡逻并定位噪声", int(e.get("state")) == S_ALERT
			and (e.get("last_known_pos") as Vector2).is_equal_approx(noise_pos))
	var noise_start := e.global_position.distance_to(noise_pos)
	await _frames(18)
	_check(label + " 警觉时实际走向噪声", e.global_position.distance_to(noise_pos) < noise_start - 5.0)
	e.call("rebuild_route")
	_check(label + " 重建路线不会打断警觉", int(e.get("state")) == S_ALERT)
	e.set("_alert_left", 0.0)
	await _frames(2)
	_check(label + " 警觉结束回到巡逻", int(e.get("state")) == S_PATROL)
	var resume_pos := e.global_position
	await _frames(12)
	_check(label + " 警觉后实际恢复沿路线移动", e.global_position.distance_to(resume_pos) > 3.0)

	# 持枪巡逻兵仍要射出实体子弹；近战巡逻兵仍要冲向玩家，不能只进入 ATTACK。
	_player.global_position = e.global_position + Vector2(100, 0)
	e.set("facing", Vector2.RIGHT)
	e.call("_sync_aim")
	var attack_start := e.global_position.distance_to(_player.global_position)
	await _frames(10)
	_check(label + " 看见玩家后中断巡逻进入战斗", int(e.get("state")) == S_ATTACK)
	if melee:
		_check(label + " 近战巡逻敌人实际冲向玩家", e.global_position.distance_to(_player.global_position) < attack_start - 5.0
				and _projectiles.get_child_count() == 0)
	else:
		# 霰弹射程短，若只看第 35 帧，子弹已经正常飞到终点而消失。
		# 逐帧观察真正生成的弹体，不能把“子弹没有一直留着”误判成没开枪。
		var saw_projectile := false
		for frame in range(35):
			await _frames(1)
			if _projectiles.get_child_count() > 0:
				saw_projectile = true
		_check(label + " 持枪巡逻敌人实际射出子弹", saw_projectile)
		_check(label + " 持枪巡逻不变成接触致死", not bool(_player.get("is_dead")))
	_player.global_position = Vector2(900, 900)
	await _frames(2)
	e.set_physics_process(false)
	e.set("_alert_left", 0.0)
	e.call("_ai_alert", 0.0)
	for mark in [point1, point2]:
		e.remove_child(mark)
		mark.free()
	e.call("rebuild_route")
	_check(label + " 移除全部 point 后恢复站岗", int(e.get("state")) == S_IDLE and _route(e).size() == 1)
	var at_home := _add_point(e, "point_at_home", Vector2.ZERO)
	e.call("rebuild_route")
	_check(label + " 只有与岗位重合的 point 仍站岗", int(e.get("state")) == S_IDLE)
	e.remove_child(at_home)
	at_home.free()
	e.rotation = PI * 0.5
	_add_point(e, "point_rotated", Vector2(64, 0))
	e.call("rebuild_route")
	_check(label + " 旋转路点按同一坐标系换算", _route(e)[1].is_equal_approx(home + Vector2(0, 64)))
	e.set("state", S_DEAD)
	e.call("rebuild_route")
	_check(label + " 重建路线不会复活尸体", int(e.get("state")) == S_DEAD)
	e.free()
	for bullet in _projectiles.get_children():
		bullet.free()
	await process_frame

	# 在入树前就摆好路点，验证编辑器场景的出生行为，而非只测运行时重建。
	var placed := scene.instantiate() as Node2D
	placed.position = Vector2(100, 100)
	placed.set_physics_process(false)
	_add_point(placed, "point", Vector2(96, 0))
	get_root().add_child(placed)
	_check(label + " 场景自带 point 时出生即巡逻", int(placed.get("state")) == S_PATROL)
	placed.free()
	await process_frame


func _route(e: Node) -> PackedVector2Array:
	return e.call("patrol_route")


func _add_point(e: Node, node_name: String, offset: Vector2) -> Marker2D:
	var mark := Marker2D.new()
	mark.name = node_name
	mark.position = offset
	e.add_child(mark)
	return mark


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(label: String, ok: bool) -> void:
	if ok:
		print("  [OK]   " + label)
	else:
		print("  [FAIL] " + label)
		_fail += 1
