extends Node

var main_node: Node3D = null

func load_level_into_container(path_to_scene: String) -> void:
	var loading_screen = preload("res://scenes/loading_screen.tscn").instantiate()
	get_tree().root.add_child(loading_screen)
	
	# Tell the loading screen NOT to change the scene automatically
	loading_screen.use_internal_swap = false 
	loading_screen.start_loading_scene(path_to_scene)
	
	# Wait for the loading screen to finish
	var loaded_resource = await loading_screen.scene_loaded_resource
	
	if main_node:
		main_node.finalize_level_load(loaded_resource)

func load_scene_with_loading_screen(path_to_scene:String) -> void:
	var loading_screen := preload("uid://c0mbffiaup51v").instantiate()
	get_tree().root.add_child(loading_screen)
	loading_screen.start_loading_scene(path_to_scene)
