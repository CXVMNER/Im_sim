extends Control
class_name PauseMenu
## Pause and death overlay. One scene, two modes:
## set_game_over(false) shows PAUSED with Resume, set_game_over(true) shows YOU DIED with Restart.

@onready var _panel: PanelContainer = %Panel
@onready var _heading: Label = %Heading
@onready var _pause_buttons: VBoxContainer = %PauseButtons
@onready var _death_buttons: VBoxContainer = %DeathButtons
@onready var _options: OptionsMenu = %OptionsMenu
@onready var _resume_button: Button = %ResumeButton
@onready var _restart_button: Button = %RestartButton

var is_game_over := false


func _ready() -> void:
	_options.visible = false
	_options.closed.connect(_on_options_closed)
	visibility_changed.connect(_on_visibility_changed)
	set_game_over(false)


func set_game_over(state: bool) -> void:
	is_game_over = state
	_heading.text = "YOU DIED" if state else "PAUSED"
	_heading.modulate = Color(1.0, 0.35, 0.3) if state else Color.WHITE
	_pause_buttons.visible = not state
	_death_buttons.visible = state
	_options.visible = false
	_panel.visible = true
	if visible:
		_focus_first()


func _on_visibility_changed() -> void:
	if visible:
		_panel.visible = true
		_options.visible = false
		_focus_first()


func _focus_first() -> void:
	var first: Button = _restart_button if is_game_over else _resume_button
	first.grab_focus()


func _on_resume_button_pressed() -> void:
	if PlayerManager.player:
		PlayerManager.player.pause_game(false)


func _on_options_button_pressed() -> void:
	_panel.hide()
	_options.show()
	_options.focus_first()


func _on_options_closed() -> void:
	_options.hide()
	_panel.show()
	_focus_first()


func _on_restart_button_pressed() -> void:
	if PlayerManager.player:
		PlayerManager.player.prepare_restart()
	var main = GameManager.main_node
	if main:
		main.restart_level()


func _on_menu_button_pressed() -> void:
	get_tree().current_scene.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	GameManager.load_scene_with_loading_screen("res://scenes/main_menu.tscn")


func _on_exit_button_pressed() -> void:
	get_tree().quit()
