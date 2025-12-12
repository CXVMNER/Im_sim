extends Area3D

enum Type {
	health,
	ammo,
	key
}

@export var type := Type.health

@export var qty: int

# $Mesh (pack) is the rotating parent node for all visuals and the label.
@onready var pack = $Mesh
@onready var respawnTimer = $respawn
@onready var label = $Mesh/Label

# Specific models are children of the rotating parent.
@onready var health_kit_2 = $Mesh/HealthKit2
@onready var crate_small_2 = $"Mesh/crate-small2"
@onready var keycard = $Mesh/keycard

@onready var pickup_sound = $PickupSound
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
	# 1. Hide the generic pack's mesh visual (the prism) by setting its mesh to null.
	#    The 'pack' node remains visible to handle rotation and the label.
#	pack.mesh = null
	
	# 2. Hide all specific models initially.
	health_kit_2.visible = false
	crate_small_2.visible = false
	keycard.visible = false
	
	# 3. Make ONLY the correct specific model visible based on the 'type'.
	var active_node = get_active_visual_node()
	if active_node:
		active_node.visible = true
	
	# 4. Set the label text.
	match type:
		Type.health:
			label.text = "Health"
		Type.ammo:
			label.text = "Ammo"
		Type.key:
			label.text = "Key"

func _process(delta):
	# This rotates the parent node, which rotates the active specific model and the label.
	pack.rotation.y += 1 * delta

func _on_body_entered(body):
	if not collectable:
		return
	
	match type:
		Type.health:
			body.gainHealth(qty)
		Type.ammo:
			body.gainAmmo(qty)
		Type.key:
			pass
	
	# 1. Find the active visual node and hide it.
	var active_node = get_active_visual_node()
	if active_node:
		active_node.visible = false
		
	# 2. Hide the label.
	label.visible = false
	
	collectable = false
	pickup_sound.play()
	respawnTimer.start()

func _on_respawn_timeout():
	collectable = true
	
	# 1. Find the active visual node and show it again.
	var active_node = get_active_visual_node()
	if active_node:
		active_node.visible = true
		
	# 2. Show the label.
	label.visible = true
