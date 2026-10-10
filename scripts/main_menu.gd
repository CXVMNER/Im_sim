extends Control
class_name MainMenu


@onready var _menu_box: VBoxContainer = $MenuBox
@onready var _options: OptionsMenu = $OptionsMenu
@onready var _start_button: Button = $MenuBox/StartButton
@onready var _options_button: Button = $MenuBox/OptionsButton


func _ready() -> void:
	OptionsMenu.apply_saved_settings()
	_options.visible = false
	_options.closed.connect(_on_options_closed)
	_start_button.grab_focus()


func _on_start_button_pressed() -> void:
	GameManager.load_scene_with_loading_screen("res://scenes/main.tscn")


func _on_options_button_pressed() -> void:
	_menu_box.hide()
	_options.show()
	_options.focus_first()


func _on_options_closed() -> void:
	_options.hide()
	_menu_box.show()
	_options_button.grab_focus()


func _on_exit_button_pressed() -> void:
	get_tree().quit()
