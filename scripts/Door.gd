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

func set_label_visibility(_is_visible: bool, _player: Player = null) -> void:
	if label_3d:
		label_3d.visible = false

func get_interaction_prompt(player: Player) -> String:
	var key := "E"
	if player and player.has_method("action_hint"):
		key = player.action_hint("interact", "E")

	if open:
		return "Press [%s] to close" % key

	if required_key == "" or (player and player.has_method("has_key") and player.has_key(required_key)):
		return "Press [%s] to open" % key

	return "Locked — requires %s" % required_key
