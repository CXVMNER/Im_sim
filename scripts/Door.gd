extends AnimatableBody3D

@export var open := false :
	set(value):
		if value != open:
			open = value
			update_door()

# Exported variable for the specific key ID required to open this door
@export var required_key: String = ""

@onready var label_3d: Label3D = $DoorLabel3D

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
	
	print("Door is locked. Interaction denied.")

func _ready() -> void:
	add_to_group("doors")
	if label_3d:
		label_3d.visible = false

func set_label_visibility(is_visible: bool, player: Player) -> void:
	if not label_3d:
		return
		
	label_3d.visible = is_visible
	
	if is_visible:
		update_label_text(player)

func update_label_text(player: Player) -> void:
	# If the door is already open, we don't need the locked message
	if open:
		label_3d.text = "Press [E] to Close"
		return

	# If no key is required, or the player has the required key
	if required_key == "" or player.has_key(required_key):
		label_3d.text = "Press [E] to Open"
	else:
		# Dynamic message for missing key
		label_3d.text = "Door locked, required key: " + required_key
