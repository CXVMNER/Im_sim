extends Control

class_name PauseMenu

@onready var label := $Label
@onready var game_over_label := $GameOverLabel

var is_game_over: bool = false # A flag to prevent unpausing

func set_game_over(state: bool) -> void:
	is_game_over = state
	game_over_label.visible = state # Show/Hide the "GAME OVER" label
	
	# Hide the "Paused" label if 'Game Over' is true
	if $Label:
		$Label.visible = !state

# To have logic to handle buttons like 'Resume', 
# we rely on the controller to prevent unpausing.

func _on_menu_button_pressed() -> void:
	get_tree().current_scene.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	GameManager.load_scene_with_loading_screen("res://scenes/main_menu.tscn")

func _on_exit_button_pressed() -> void:
	get_tree().quit()
