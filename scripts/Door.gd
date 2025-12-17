extends AnimatableBody3D

@export var open := false :
	set(value):
		if value != open:
			open = value
			update_door()

# NEW: Exported variable for the specific key ID required to open this door
@export var required_key: String = ""

func update_door() -> void:
	if open:
		$AnimationPlayer.play("open")
	else:
		$AnimationPlayer.play_backwards("open")
	$AnimationPlayer.set_active(true)

# Buttons don't open the doors with keys anymore
func toggle_open() -> void:
	# If no key is required, just open
	if required_key == "":
		open = !open
		return
	
	# If a key IS required, we check if the player is currently interacting
	var interactable = get_node_or_null("InteractableComponent") 
	if interactable:
		var character = interactable.get_character_hovered_by_cur_camera() 
		if character and character.has_method("has_key"):
			if character.has_key(required_key):
				open = !open
				return
	
	print("Door is locked. Interaction from this source (Button/Player) denied.")
