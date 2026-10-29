extends Node
## 应用外壳一直响应菜单；游戏容器必须显式PAUSABLE，否则会继承外壳的ALWAYS。
signal quit_requested
@export var game_scene: PackedScene = preload("res://scenes/main/Main.tscn")
@export var title_page_scene: PackedScene = preload("res://scenes/ui/TitleMenu.tscn")
@export var pause_page_scene: PackedScene = preload("res://scenes/ui/PauseMenu.tscn")
@export var placeholder_page_scene: PackedScene = preload("res://scenes/ui/PlaceholderPage.tscn")
const HELP := preload("res://scripts/ui/controls_help.gd")
var game: Node2D
var state: StringName = &"title"
var page_origin: StringName = &"title"
var title_page: Control
var pause_page: Control
var placeholder_page: Control
@onready var game_host: Node = $GameHost

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game_host.process_mode = Node.PROCESS_MODE_PAUSABLE
	for scene: PackedScene in [title_page_scene,pause_page_scene,placeholder_page_scene]:
		var view := scene.instantiate() as Control
		$MenuLayer.add_child(view)
		view.action_requested.connect(_on_action)
		view.hide()
		if title_page == null: title_page = view
		elif pause_page == null: pause_page = view
		else: placeholder_page = view
	quit_requested.connect(_quit_application)
	get_tree().paused = false
	Feel.reset_session()
	title_page.show_page()

func _input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	match state:
		&"playing": pause_game()
		&"paused": resume_game()
		&"placeholder": back()

func _hide_pages() -> void:
	for view in [title_page,pause_page,placeholder_page]: view.hide()
	get_viewport().gui_release_focus()

func start_game() -> void:
	if is_instance_valid(game): return
	_hide_pages()
	get_tree().paused = false
	Feel.reset_session()
	game = game_scene.instantiate() as Node2D
	game_host.add_child(game)
	game.resume_from_menu()
	state = &"playing"

func pause_game() -> void:
	if state != &"playing" or not is_instance_valid(game): return
	game.set_menu_paused(true)
	get_tree().paused = true
	_hide_pages()
	state = &"paused"
	pause_page.show_page("暂停", HELP.text())

func resume_game() -> void:
	if state != &"paused" or not is_instance_valid(game): return
	_hide_pages()
	game.set_menu_paused(false)
	game.resume_from_menu()
	get_tree().paused = false
	state = &"playing"

func open_placeholder(title: String) -> void:
	if state not in [&"title",&"paused"]: return
	page_origin = state
	_hide_pages()
	state = &"placeholder"
	placeholder_page.show_page(title)

func back() -> void:
	if state != &"placeholder": return
	_hide_pages()
	state = page_origin
	if state == &"paused": pause_page.show_page("暂停", HELP.text())
	else: title_page.show_page()

func return_to_title() -> void:
	get_tree().paused = false
	if is_instance_valid(game):
		game_host.remove_child(game)
		game.queue_free()
	game = null
	Feel.reset_session()
	# 音效跨关卡存活，但结束整次游戏后不应继续在主菜单响。
	Audio.stop_session_audio()
	_hide_pages()
	state = &"title"
	title_page.show_page()

func _on_action(action: StringName) -> void:
	match action:
		&"start": start_game()
		&"tutorial": open_placeholder("教程")
		&"settings": open_placeholder("设置")
		&"resume": resume_game()
		&"main_menu": return_to_title()
		&"back": back()
		&"quit": quit_requested.emit()

func _quit_application() -> void:
	get_tree().paused = false
	Feel.reset_session()
	get_tree().quit()

func _exit_tree() -> void:
	if get_tree() != null: get_tree().paused = false
