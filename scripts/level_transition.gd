extends Area3D

# This allows to set the path in the Inspector for different levels
@export_file("*.tscn") var target_level_path: String
# Toggle this ON for full scene transitions
@export var is_full_scene_change: bool = false 

func _ready() -> void:
	# Connect the signal to detect when something enters the area
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	# Check if the body that entered is the Player
	if body is Player:
		if target_level_path != "":
			if is_full_scene_change:
				# Use the method that changes the entire tree (e.g., for Main Menu)
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE) # Free the mouse for Main Menu
				GameManager.load_scene_with_loading_screen(target_level_path) 
			else:
				# Use the method that swaps levels inside the Main container 
				GameManager.load_level_into_container(target_level_path)
		else:
			print("Warning: No target level path set on transition area.")
