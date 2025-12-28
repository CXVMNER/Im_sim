extends Area3D

# This allows to set the path in the Inspector for different levels
@export_file("*.tscn") var target_level_path: String

func _ready() -> void:
	# Connect the signal to detect when something enters the area
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	# Check if the body that entered is the Player
	if body is Player:
		if target_level_path != "":
			# Call GameManager to load the next level into the Main container 
			GameManager.load_level_into_container(target_level_path)
		else:
			print("Warning: No target level path set on transition area.")
