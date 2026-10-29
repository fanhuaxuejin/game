extends RefCounted
## 只列正在使用的操作；旧melee/slowmo和预览调试键不应误导玩家。
static func binding(action: StringName) -> String:
	var names: Array[String] = []
	for event: InputEvent in InputMap.action_get_events(action):
		var label := ""
		if event is InputEventKey:
			label = OS.get_keycode_string(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
		elif event is InputEventMouseButton:
			label = {MOUSE_BUTTON_LEFT: "鼠标左键", MOUSE_BUTTON_RIGHT: "鼠标右键", MOUSE_BUTTON_MIDDLE: "鼠标中键"}.get(event.button_index, event.as_text())
		if not label.is_empty() and not names.has(label):
			names.append(label)
	return " / ".join(names)

static func text() -> String:
	return "移动  %s · %s · %s · %s\n瞄准  移动鼠标\n攻击  %s\n投掷手中武器  %s\n拾取 / 交换  %s\n手动处决  %s\n自动锁定开关  %s\n切换目标（锁定开启时）  %s\n重开当前关卡  %s\n暂停 / 继续  %s\n\n锁定开启后自动选择进入相机画面的敌人，\n不受人物朝向限制；墙和门仍阻挡锁定。\n处决：靠近倒地敌人，按处决键三次砸头。\n空手：推倒敌人，再手动处决。\n持刀：挥击命中直接击杀。\n有弹枪：射击；弹药用完自动挥枪。\n投掷命中可击晕敌人，武器随之碎裂。" % [binding("move_up"),binding("move_left"),binding("move_down"),binding("move_right"),binding("fire"),binding("throw_weapon"),binding("pickup"),binding("execute"),binding("lock"),binding("cycle_target"),binding("restart"),binding("ui_cancel")]
