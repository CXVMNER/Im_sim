extends Area3D

class_name PowerUp

enum Type {
	health,
	ammo,
	key
}

@export var type := Type.health
@export var qty: int
# Exported value for keys, allowing designers to specify which key it is (e.g., "red_door", "level_2")
@export var pass_value: String = ""

# $Mesh (pack) is the rotating parent node for all visuals and the label.
@onready var pack := $Mesh
@onready var respawnTimer := $respawn
@onready var label := $Mesh/Label

# Specific models are children of the rotating parent.
@onready var health_kit_2 := $Mesh/HealthKit2
@onready var crate_small_2 := $"Mesh/crate-small2"
@onready var keycard := $Mesh/keycard

@onready var pickup_sound := $PickupSound
@onready var key_pickup_sound := $KeyPickupSound # New Key pickup sound node

var collectable := true

# Helper function to return the currently intended visual node
func get_active_visual_node():
	match type:
		Type.health:
			return health_kit_2
		Type.ammo:
			return crate_small_2
		Type.key:
			return keycard
	return null

func _ready():
	add_to_group("power_ups")
	# Hide all specific models initially.
	health_kit_2.visible = false
	crate_small_2.visible = false
	keycard.visible = false
	
	# Make ONLY the correct specific model visible based on the 'type'.
	var active_node = get_active_visual_node()
	if active_node:
		active_node.visible = true
	
	# Set the label text.
	match type:
		Type.health:
			label.text = "Health"
		Type.ammo:
			label.text = "Ammo"
		Type.key:
			label.text = "Key: " + pass_value # Display the pass value on the key label

func _process(delta):
	# This rotates the parent node, which rotates the active specific model and the label.
	pack.rotation.y += 1 * delta

func _on_body_entered(body):
	if not collectable:
		return
		
	# Process pickup logic
	match type:
		Type.health:
			body.gainHealth(qty)
			
		Type.ammo:
			body.gainAmmo(qty)
			
		Type.key:
			# Pass the key's unique value to the player
			if body.has_method("collect_key"):
				body.collect_key(pass_value)
				
	# --- VISUALS & CLEANUP ---
	
	# Find the active visual node and hide it.
	var active_node = get_active_visual_node()
	if active_node:
		active_node.visible = false
		
	# Hide the label.
	label.visible = false
	
	collectable = false
	
	# Determine sound, respawn, and deletion logic based on type.
	if type == Type.key:
		key_pickup_sound.play()
		# Reparent the sound player to the root so it can finish playing.
		key_pickup_sound.reparent(get_tree().get_root())
		# Schedule the sound player to delete itself when it finishes.
		key_pickup_sound.finished.connect(key_pickup_sound.queue_free, CONNECT_ONE_SHOT)
		
		# Delete the main power-up node immediately (sound will continue playing).
		queue_free()
	else:
		pickup_sound.play() # Play the generic pickup sound
		# Health and Ammo respawn.
		respawnTimer.start()

# This function is only called for Type.health and Type.ammo items now.
func _on_respawn_timeout() -> void:
	collectable = true
	
	# Find the active visual node and show it again.
	var active_node = get_active_visual_node()
	if active_node:
		active_node.visible = true
		
	# Show the label.
	label.visible = true
