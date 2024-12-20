extends Control

var change_scene_to : String

# Called when the node enters the scene tree for the first time.
func _ready():
	$Timer.start()

func _on_timer_timeout():
	print("Loaded")
	get_tree().change_scene_to_file(change_scene_to)
	# Global.Loading_Screen.queue_free()
