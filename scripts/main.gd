extends Node3D

@onready var level_container: Node3D = $LevelContainer
@onready var player: Player = $Player

func _ready() -> void:
	# GameManager now handles level loading instead of changing scenes entirely
	GameManager.main_node = self 
	change_level("res://scenes/level_01.tscn")

func change_level(level_path: String) -> void:
	# Defer actual loading to GameManager
	# We avoid clearing the container here so the old level remains visible
	# until the loading screen covers it
	GameManager.load_level_into_container(level_path)

func finalize_level_load(loaded_scene: PackedScene) -> void:
	# Clear the previous level immediately to prevent overlap/memory leaks
	for child in level_container.get_children():
		child.free()
	
	print("Successfully loaded map: ", loaded_scene.resource_path)
	
	# Add the new level
	var new_level = loaded_scene.instantiate()
	level_container.add_child(new_level)
	
	# Reposition player at the designated spawn point if it exists
	var spawn = new_level.get_node_or_null("SpawnPoint")
	if spawn:
		player.global_position = spawn.global_position
		player.global_rotation = spawn.global_rotation
