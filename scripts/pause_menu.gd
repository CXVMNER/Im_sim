extends Control

class_name PauseMenu

@onready var game_over_label := $GameOverLabel
@onready var resume_v_box_container := $ResumeVBoxContainer

var is_game_over: bool = false # A flag to prevent unpausing

func set_game_over(state: bool) -> void:
	is_game_over = state
	game_over_label.visible = state # Show/Hide the "GAME OVER" label
	
	# Hide the "Resume" button if 'Game Over' is true
	if resume_v_box_container:
		resume_v_box_container.visible = !state

# To have logic to handle buttons like 'Resume', 
# we rely on the controller to prevent unpausing.

func _on_menu_button_pressed() -> void:
	get_tree().current_scene.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	GameManager.load_scene_with_loading_screen("res://scenes/main_menu.tscn")

func _on_exit_button_pressed() -> void:
	get_tree().quit()

func _on_resume_button_pressed() -> void:
	# Access the player instance and call the function Esc (Pause) uses
	if PlayerManager.player:
		PlayerManager.player.pause_game(false)
