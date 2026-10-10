extends Label
## Frame counter. Visibility is controlled by the HUD (F3 key or the options menu).


func _process(_delta: float) -> void:
	if not visible:
		return
	text = "%d FPS" % Engine.get_frames_per_second()
