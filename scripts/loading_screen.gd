extends Control

class_name LoadingScreen

signal scene_loaded

@export var forced_delay:float = 0.0 # Can be set to 1.0 to showcase the loading screen
@export var next_scene_path:String = ""
var scene_load_status = 0
var progress := [0.0]
var loaded_scene:PackedScene
@onready var progress_label := $ColorRect/ProgressLabel

signal scene_loaded_resource(resource: PackedScene)
var use_internal_swap: bool = true # Default behavior

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass

func _process(delta: float) -> void:
	if next_scene_path == "":
		return
	
	scene_load_status = ResourceLoader.load_threaded_get_status(next_scene_path, progress)
	var actual_progress = progress[0] * 100
	var rounded_progress := int(floor(actual_progress))
	
	if scene_load_status == ResourceLoader.THREAD_LOAD_LOADED:
		await get_tree().create_timer(forced_delay).timeout
		loaded_scene = ResourceLoader.load_threaded_get(next_scene_path)
	
		if use_internal_swap:
			get_tree().change_scene_to_packed(loaded_scene)
		else:
			scene_loaded_resource.emit(loaded_scene)
	
		queue_free()
	elif scene_load_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		progress_label.text = str(rounded_progress) + "%"
		
func start_loading_scene(path:String) -> void:
	await get_tree().create_timer(forced_delay).timeout
	next_scene_path = path
	print("loading scene " + path)
	ResourceLoader.load_threaded_request(next_scene_path)
