extends Label

func _ready():
	var tween = get_tree().create_tween()
	tween.parallel().tween_property(self, "posotion", Vector2(0, -60), 2)
	tween.parallel().tween_property(self, "modulate:a", 0, 2)
	tween.tween_callback(queue_free)
