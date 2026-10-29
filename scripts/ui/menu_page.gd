extends Control
## 换肤只需替换场景或资源，保留此意图信号和show_page接口；不直接改游戏状态。
signal action_requested(action: StringName)
@export var page_theme: Theme
@export var background_texture: Texture2D
@onready var background: TextureRect = $Background
@onready var heading: Label = $Margin/Column/Heading
@onready var buttons: VBoxContainer = $Margin/Column/Body/Buttons

func _ready() -> void:
	if page_theme != null:
		theme = page_theme
	background.texture = background_texture
	for button: Button in buttons.get_children():
		var action := StringName(button.get_meta("action"))
		button.pressed.connect(func() -> void: action_requested.emit(action))

func show_page(title: String = "", help_text: String = "") -> void:
	if not title.is_empty(): heading.text = title
	var help := get_node_or_null("Margin/Column/Body/Help/HelpText") as Label
	if help != null: help.text = help_text
	show()
	_focus_first.call_deferred()

func _focus_first() -> void:
	# 同帧快速返回/继续时，旧页面的延迟请求不能抢走新页面焦点。
	if is_visible_in_tree():
		(buttons.get_child(0) as Button).grab_focus()
