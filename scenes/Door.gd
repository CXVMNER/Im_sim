extends AnimatableBody3D

@export var open := false :
	set(value):
		if value != open:
			open = value
			update_door()
	
func update_door():
	if open:
		$AnimationPlayer.play("open")
	else:
		$AnimationPlayer.play_backwards("open")
	$AnimationPlayer.set_active(true)
	
func toggle_open():
	open = !open
