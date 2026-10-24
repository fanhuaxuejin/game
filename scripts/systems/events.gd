extends Node
## 全局信号总线。在 Project Settings > Autoload 里注册为 `Events`。
##
## 为什么要有它：让各个系统通过信号通信，而不是互相 get_node 硬引用。
## 关卡重载时被释放的节点会被自动断开连接，不会留下野引用。

## 有人发出了声音。M2 的敌人会监听它来"听见"玩家 —— 这是本作的核心机制。
## `source` 是谁弄出的声音。开门的人不该被自己推门的动静重新定位（否则它会把
## 正在追的枪声位置忘掉，站在门口发呆），所以监听方要能认出自己。
signal noise_emitted(pos: Vector2, radius: float, source: Node)
## 射出实体子弹；终点表示瞄准方向，供枪声和后坐力使用。
signal bullet_fired(from: Vector2, to: Vector2)
## 子弹打中了某个东西。
signal bullet_impact(pos: Vector2, normal: Vector2)
## 敌人死亡。
signal enemy_died(pos: Vector2)
## 敌人开了一枪（远程兵）。用来放枪声 —— 玩家得能从声音分辨是谁在开枪。
signal enemy_fired(pos: Vector2)
## 敌人被门或投掷武器击晕；音效反馈不等于 AI 听觉噪声。
signal enemy_stunned(pos: Vector2)
## 门被撞开 / 甩动。`power` 是撞击力度（0~1），越狠声音越沉。
##
## ⚠️ 这和 `noise_emitted` 是**两回事**，别合并：
## 门对**玩家**永远听得见（这是反馈），但对**敌人**默认不产生噪声
## （否则背对着门的敌人也会转身过来，等于"一进门就暴露"）。
signal door_moved(pos: Vector2, power: float)
## 玩家死亡 —— 触发瞬间重开流程。
signal player_died
## 玩家进入场景。
signal player_spawned(player: Node2D)
## 弹药变化。capacity < 0 空手、=0 近战；current=0 的枪转为近战，不再装填。
signal ammo_changed(current: int, capacity: int)
## 先通知武器类型，再通知弹药；空手、刀与空枪不能继续显示成装填中。
signal weapon_changed(definition: Resource)
## 通关。
signal level_cleared(time_sec: float, kills: int)


## 半径为 0 表示"这次没有声音"，直接不发，省掉敌人一次无用判定。
func emit_noise(pos: Vector2, radius: float, source: Node = null) -> void:
	if radius <= 0.0:
		return
	noise_emitted.emit(pos, radius, source)
