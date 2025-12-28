extends Control

class_name MainMenu

func _on_start_button_pressed() -> void:
	GameManager.load_scene_with_loading_screen("res://scenes/main.tscn")
	#get_tree().change_scene_to_file("res://scenes/level_01.tscn")


func _on_options_button_pressed() -> void:
	print("Options pressed")


func _on_exit_button_pressed() -> void:
	get_tree().quit()
