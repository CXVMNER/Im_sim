extends Control
class_name LoadingScreen
## Shows while a scene loads on a background thread, then swaps it in.
## GameManager sets next_scene_path (via start_loading_scene) and, for level changes,
## turns off use_internal_swap and waits for scene_loaded_resource.

signal scene_loaded
signal scene_loaded_resource(resource: PackedScene)

@export var forced_delay: float = 0.0 ## Minimum time the screen stays up after loading finishes
@export var next_scene_path: String = ""
@export var use_internal_swap: bool = true ## true = change_scene_to_packed here, false = emit the resource
@export var tips: PackedStringArray = []

@onready var _progress_bar: ProgressBar = %ProgressBar
@onready var _percent_label: Label = %PercentLabel
@onready var _tip_label: Label = %TipLabel

var progress := [0.0]
var loaded_scene: PackedScene
var _finished := false


func _ready() -> void:
	if tips.size() > 0:
		_tip_label.text = tips[randi() % tips.size()]
	_progress_bar.value = 0.0
	_percent_label.text = "0%"


func start_loading_scene(path: String) -> void:
	next_scene_path = path
	ResourceLoader.load_threaded_request(next_scene_path)


func _process(_delta: float) -> void:
	if next_scene_path == "" or _finished:
		return

	var status := ResourceLoader.load_threaded_get_status(next_scene_path, progress)
	var fraction := clampf(progress[0], 0.0, 1.0)
	_progress_bar.value = fraction * 100.0
	_percent_label.text = "%d%%" % int(fraction * 100.0)

	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_finished = true # guard: _process keeps running during the wait below
		_progress_bar.value = 100.0
		_percent_label.text = "100%"
		await get_tree().create_timer(forced_delay).timeout
		loaded_scene = ResourceLoader.load_threaded_get(next_scene_path)
		if use_internal_swap:
			get_tree().change_scene_to_packed(loaded_scene)
		else:
			scene_loaded_resource.emit(loaded_scene)
		queue_free()
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_finished = true
		_percent_label.text = "Failed to load"
		push_error("Loading failed: " + next_scene_path)
