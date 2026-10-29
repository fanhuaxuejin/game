extends RefCounted
## 处决使用玩法时钟；显示只采样进度，绝不从动画帧回调结算生命。
const STRIKES := [0.20, 0.45, 0.70]
const DURATION := 0.90
var actor: Node2D
var target: Node2D
var elapsed := 0.0
var strikes := 0
var active := false
var direction := Vector2.RIGHT
var head_distance := 14.0
var prompt: Label

func candidate() -> Node2D:
	var nearest: Node2D
	var best: float = actor.execution_radius
	for enemy: Node2D in actor.get_tree().get_nodes_in_group("enemies"):
		var distance := actor.global_position.distance_to(enemy.global_position)
		if enemy.is_stunned() and enemy.execution_owner == null and distance <= best and actor.combat.clear_path(actor.global_position, enemy.global_position):
			nearest = enemy
			best = distance
	return nearest

func update_prompt() -> void:
	if prompt == null:
		prompt = Label.new()
		prompt.text = preload("res://scripts/ui/controls_help.gd").binding(&"execute") + " 处决"
		prompt.add_theme_font_size_override("font_size", 10)
		prompt.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		prompt.position = Vector2(-17, -28)
		actor.add_child(prompt)
	prompt.visible = not active and not actor.is_dead and not actor.is_stunned() and not actor.combat.swinging and candidate() != null

func start() -> bool:
	if active or actor.is_dead or actor.is_stunned() or actor.combat.swinging:
		return false
	target = candidate()
	if target == null: return false
	active = true
	elapsed = 0.0
	strikes = 0
	direction = (target.visual.head_world_position() - actor.global_position).normalized()
	head_distance = actor.global_position.distance_to(target.visual.head_world_position())
	actor.aim.global_rotation = direction.angle()
	actor.velocity = Vector2.ZERO
	target.execution_owner = actor
	target.velocity = Vector2.ZERO
	target._stun_vel = Vector2.ZERO
	actor.get_node("Aim/Gun").hide()
	actor.actor_visual.update_state(Vector2.ZERO, direction.angle(), actor.speed, false)
	actor.actor_visual.execution_pose(0.0, head_distance)
	return true

func tick(delta: float) -> void:
	if not active: return
	if not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion():
		cancel()
		return
	if strikes < 3 and (target.state == target.State.DEAD or not target.is_stunned() or not actor.combat.clear_path(actor.global_position, target.global_position)):
		cancel()
		return
	actor.velocity = Vector2.ZERO
	target.velocity = Vector2.ZERO
	elapsed += delta
	actor.actor_visual.execution_pose(elapsed / DURATION, head_distance)
	while strikes < STRIKES.size() and elapsed >= STRIKES[strikes]:
		strikes += 1
		var point: Vector2 = target.visual.head_world_position()
		if strikes == 3:
			target.take_damage(1, actor.global_position, &"execution")
		else:
			target.visual.receive_impact(direction)
			actor.get_node("/root/Events").hit_resolved.emit(target, point, direction, &"execution", false)
	if elapsed >= DURATION: cancel()

func cancel() -> void:
	if is_instance_valid(target): target.execution_owner = null
	target = null
	if active:
		actor.actor_visual.end_execution()
		actor.get_node("Aim/Gun").visible = actor.weapon_instance != null and not actor.is_dead
	active = false
