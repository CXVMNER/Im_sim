extends CharacterBody3D

@onready var nav_agent = $NavigationAgent3D
@onready var player = $"../CharacterBody3D"
@onready var detection_area = $Area3D

var SPEED = 3.0
# var DETECTION_RADIUS = 8.0
var player_detected = false

var max_hp = 50
var current_hp = max_hp
var attack_damage = 10

func _ready():
	detection_area.connect("body_entered", Callable(self, "_on_area_3d_body_entered"))
	detection_area.connect("body_exited", Callable(self, "_on_area_3d_body_exited"))
	
func _physics_process(delta):
	if!player_detected: # Check if player is not detected
		nav_agent.set_velocity(Vector3.ZERO) # Stop moving
		return
	
	var current_location = global_transform.origin # Current enemy location
	var player_location = player.global_transform.origin # Player location
	
	update_target_location(player_location)
	
	var next_location = nav_agent.get_next_path_position() # Next location the nav agent is directing towards
	var new_velocity = (next_location - current_location).normalized() * SPEED # Calculate velocity between current and next location
	
	nav_agent.set_velocity(new_velocity)
	
	# Rotate to face the player
	face_player(player_location)
	
	# move_and_slide() # Uncomment if you need enemy movement

func update_target_location(target_location):
	nav_agent.set_target_position(target_location)

func _on_navigation_agent_3d_velocity_computed(safe_velocity):
	velocity = velocity.move_toward(safe_velocity, 0.25)
	move_and_slide()

func _on_area_3d_body_entered(body):
	if body is CharacterBody3D and body.name == "CharacterBody3D":
		player = body
		player_detected = true

func _on_area_3d_body_exited(body):
	if body is CharacterBody3D and body.name == "CharacterBody3D":
		player_detected = false
		player = null

func face_player(player_location):
	var direction_to_player = player_location - global_transform.origin
	direction_to_player.y = 0 # Ignore the vertical component
	direction_to_player = direction_to_player.normalized()
	
	var target_rotation = Vector3(0, atan2(direction_to_player.x, direction_to_player.z), 0)
	rotation = target_rotation
