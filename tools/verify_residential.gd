extends SceneTree
## 验证真实移动、弹体和巡逻；不能靠检查掩码值代替实际行为。
var failures := 0
var checks := 0
var room: Node2D
var player: CharacterBody2D
var enemy: CharacterBody2D

func _initialize() -> void:
	call_deferred("_run")

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok: failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])

func _frames(count: int) -> void:
	for i in count: await physics_frame

func _run() -> void:
	room = load("res://scenes/preview/ResidentialPreview.tscn").instantiate()
	root.add_child(room)
	player = room.player
	player.set_physics_process(false)
	player.set_process(false)
	enemy = room.get_node("Enemies").get_child(0)
	await _frames(2)
	_check("住宅64素材格仍为16世界px", room.cell_center(Vector2i(1, 0)) - room.cell_center(Vector2i.ZERO) == Vector2(16, 0))
	for c in [Vector2i.ZERO, Vector2i(7, 5), Vector2i(-2, -1)]:
		_check("住宅坐标往返 %s" % c, room.world_to_cell(room.cell_center(c)) == c)
	room.position = Vector2(32, -48)
	_check("平移关卡后坐标仍正确", room.world_to_cell(room.cell_center(Vector2i(7, 5))) == Vector2i(7, 5))
	room.position = Vector2.ZERO
	await _frames(2)
	for guard: Node2D in room.get_node("Enemies").get_children():
		_check("%s 出生点与路点在可走地板" % guard.name, room.is_walkable_cell(room.world_to_cell(guard.position)) and room.is_walkable_cell(room.world_to_cell(guard.position + guard.get_node("point1").position)))
	_check("样板间引用独立TileSet资源", room.floor_layer.tile_set.resource_path == "res://resources/tiles/ResidentialTileSet.tres")
	var sofa := room.get_node("Furniture").get_child(0) as FurnitureProp
	var floor_map: TileMapLayer = room.floor_layer
	var origin := sofa.position
	var sofa_size: Vector2 = sofa.get_node("CollisionShape2D").shape.size
	var start := origin + Vector2(-32, sofa_size.y * 0.5)
	var end := origin + Vector2(sofa_size.x + 32, sofa_size.y * 0.5)
	var original_cell := floor_map.local_to_map(floor_map.to_local(origin + Vector2(1, 1)))
	for prop: FurnitureProp in room.get_node("Furniture").get_children():
		var cells := prop.occupied_cells(floor_map)
		var wanted := 6 if prop.scene_file_path.ends_with("Sofa.tscn") else 2
		_check("%s 占地格数与实际旋转一致" % prop.name, cells.size() == wanted)
		var blocked := true
		for c in cells: blocked = blocked and not room.is_walkable_cell(c)
		_check("%s 占地进入寻路障碍" % prop.name, blocked)
	# 其余两个直角方向也按同一碰撞体换算，避免只支持样板里碰巧摆出的朝向。
	for prop: FurnitureProp in [sofa, room.get_node("Furniture").get_child(1)]:
		var expected := prop.occupied_cells(floor_map).size()
		for angle in [PI, PI * 1.5]:
			prop.rotation = angle
			_check("%s 旋转%d度占地正确" % [prop.name, roundi(rad_to_deg(angle))], prop.occupied_cells(floor_map).size() == expected)
		prop.rotation = 0
	# 新缩放图层必须真的挡住射线，不能仅仅让A*认为它是墙。
	var tested_wall := false
	var wall_map: TileMapLayer = room.walls
	for c: Vector2i in wall_map.get_used_cells():
		for direction in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var neighbor: Vector2i = c + direction
			if not room.is_walkable_cell(neighbor): continue
			var query := PhysicsRayQueryParameters2D.create(room.cell_center(neighbor), room.cell_center(c), 1)
			var hit := room.get_world_2d().direct_space_state.intersect_ray(query)
			_check("住宅墙碰撞保持16px世界格", not hit.is_empty() and is_equal_approx(hit.position.distance_to(room.cell_center(neighbor)), 8.0))
			tested_wall = true
			break
		if tested_wall: break
	_check("样板间有可验证的墙格", tested_wall)
	var nav_path: PackedVector2Array = room.find_path(start, end)
	_check("路径会绕过沙发而非拉直穿过", nav_path.size() >= 2)
	for actor: CharacterBody2D in [player, enemy]:
		actor.global_position = start
		await _frames(1)
		var hit := actor.move_and_collide(end - start)
		_check("%s 实际移动被沙发挡住" % actor.name, hit != null and hit.get_collider() == sofa and actor.position.x < origin.x)
		actor.position = Vector2(240, 240)
	# 在旋转沙发上也实测碰撞，而不是只看占地数量。
	var rotated := room.get_node("Furniture").get_child(2) as FurnitureProp
	var rotated_center: Vector2 = rotated.get_node("CollisionShape2D").global_position
	player.position = rotated_center - Vector2(64, 0)
	await _frames(1)
	var rotated_hit := player.move_and_collide(Vector2(128, 0))
	_check("旋转90度沙发仍挡移动", rotated_hit != null and rotated_hit.get_collider() == rotated)
	player.position = Vector2(240, 240)
	enemy.position = start
	enemy.facing = Vector2.RIGHT
	await _frames(1)
	_check("敌人隔沙发仍能看见目标点", enemy.can_see_point(end))
	_check("战斗交互检测可越过家具", player.combat.clear_path(start, end))
	enemy.position = Vector2(64, 224)
	await _frames(1)
	for friendly in [false, true]:
		var bullet = load("res://scenes/projectiles/EnemyBullet.tscn").instantiate()
		bullet.configure(friendly, 1, 900)
		room.get_node("Projectiles").add_child(bullet)
		bullet.position = start
		bullet.set_physics_process(false)
		bullet.launch(Vector2.RIGHT)
		bullet._physics_process(0.08)
		_check("%s子弹实际越过沙发" % ("玩家" if friendly else "敌人"), not bullet.is_queued_for_deletion() and bullet.position.x > origin.x + sofa_size.x)
		bullet.free()
	var thrown = load("res://scenes/projectiles/ThrownWeapon.tscn").instantiate()
	thrown.weapon_instance = load("res://scripts/weapons/weapon_state.gd").new(load("res://resources/weapons/pistol.tres"))
	thrown.weapon_instance.ammo = 3
	room.get_node("Projectiles").add_child(thrown)
	thrown.position = start
	thrown.set_physics_process(false)
	thrown.launch(Vector2.RIGHT)
	thrown._physics_process(0.2)
	_check("投掷武器越过沙发且保持弹药", not thrown.landed and thrown.position.x > origin.x + sofa_size.x and thrown.weapon_instance.ammo == 3)
	thrown.free()
	# 明确让敌人沿既有移动逻辑完成绕行，期间记录有没有偏离被家具挡住的直线。
	enemy.position = start
	enemy.velocity = Vector2.ZERO
	var target := end + Vector2(8, 8)
	var detoured := false
	for i in 150:
		enemy._move_toward_point(target, 1.0 / 60.0)
		detoured = detoured or absf(enemy.position.y - start.y) > 16
		await physics_frame
	_check("敌人实际绕行并到达沙发另一侧", detoured and enemy.position.distance_to(target) < 18)
	# 移走家具再刷新，不得留下旧_walkable状态。
	sofa.position += Vector2(0, 64)
	room.rebuild_navigation()
	_check("刷新导航后原沙发格可通行", room.is_walkable_cell(original_cell))
	sofa.position -= Vector2(0, 64)
	room.rebuild_navigation()
	_check("刷新导航后新障碍重新生效", not room.is_walkable_cell(original_cell))
	await _terrain_test()
	room.free()
	await process_frame
	# 用未修改的固定夹具验证老TileSet及接口兼容。
	var old: Node2D = load("res://scenes/levels/Level_test.tscn").instantiate()
	root.add_child(old)
	for e in get_nodes_in_group("enemies"): e.set_physics_process(false)
	old.player.set_physics_process(false)
	_check("旧16px图层坐标与尺寸保持一致", old.cell_center(Vector2i(2, 3)) == Vector2(40, 56) and old.world_to_cell(Vector2(40, 56)) == Vector2i(2, 3))
	old.free()
	await process_frame
	print(">>> %s：住宅 %d 项检查，失败 %d" % ["全部通过" if failures == 0 else "失败", checks, failures])
	quit(1 if failures else 0)

func _terrain_test() -> void:
	var tiles: TileSet = load("res://resources/tiles/ResidentialTileSet.tres")
	var layer := TileMapLayer.new()
	layer.tile_set = tiles
	root.add_child(layer)
	# 含16种邻居组合的独立簇，验证编辑器Terrain实际能选到完整连接形状。
	var dirs := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
	for mask in 16:
		var center := Vector2i(mask * 5, 0)
		var cells: Array[Vector2i] = [center]
		for i in 4:
			if mask & (1 << i): cells.append(center + dirs[i])
		layer.set_cells_terrain_connect(cells, 0, 0, false)
		var data := layer.get_cell_tile_data(center)
		var actual := 0
		if data != null:
			for pair in [[0, 1], [4, 2], [8, 4], [12, 8]]:
				if data.get_terrain_peering_bit(pair[0]) == 0: actual |= pair[1]
		_check("Terrain自动拼接连接 %d" % mask, data != null and actual == mask)
	layer.free()
