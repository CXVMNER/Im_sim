extends AnimatableBody3D

@export var open := false :
	set(value):
		if value != open:
			open = value
			update_door()

# NEW: Exported variable for the specific key ID required to open this door
@export var required_key: String = ""

func update_door():
	if open:
		$AnimationPlayer.play("open")
	else:
		$AnimationPlayer.play_backwards("open")
	$AnimationPlayer.set_active(true)
	
func toggle_open():
	open = !open
