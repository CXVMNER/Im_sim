extends CharacterBody3D

@export var PlayerPath : NodePath
@export var color : Color
@export var aggroRange := 5.0 
@export var fireSpeed := 0.2 
@export var attackPower := 1 

var health = 20
var material
var player = null 
var bullet = preload("res://scenes/bullet.tscn") 

@onready var gun = $gun 
@onready var sight = $sight 
@onready var engagedTimer = $engaged

var lastShot := 0.0 
var speed := 1.0  

var startPos 
var engaged = false 

@onready var nav_agent = $NavigationAgent3D
@onready var detection_area = $Area3D

var SPEED = 3.0
var player_detected = false

func _ready():
	player = get_node(PlayerPath)
	startPos = global_position
	var mat = StandardMaterial3D.new()
	mat.set_albedo(color)
	mat.emission_enabled = true
	$%body.set_surface_override_material(0,mat)
	$%nose.set_surface_override_material(0,mat)
	material = mat
	detection_area.connect("body_entered", Callable(self, "_on_area_3d_body_entered"))
	detection_area.connect("body_exited", Callable(self, "_on_area_3d_body_exited"))

func takeDamage(dmg):
	health -= dmg
	engaged = true
	engagedTimer.start()
	if health < 1:
		queue_free()
	var tween = get_tree().create_tween()
	tween.tween_property(material, "emission", Color(2, 1, 1, 1), 0.02)
	tween.tween_property(material, "emission", Color(0, 0, 0, 1), 0.2)

func _fire():
	var now := Time.get_ticks_msec() / 1000.0
	if now < lastShot + fireSpeed:
		return
	
	lastShot = now
	var b = bullet.instantiate()
	b.damage = attackPower
	b.global_transform = gun.global_transform
	get_parent().add_child(b)

func _process(delta):
	velocity = Vector3.ZERO
	if global_position.distance_to(player.global_position) < aggroRange and player.health > 0 or engaged: 
		nav_agent.set_target_position(player.global_transform.origin)
		# Check if sight is valid and player is in sight
		if sight.is_colliding() and sight.get_collider() == player:
			_fire()
		look_at(Vector3(player.global_position.x, player.global_position.y, player.global_position.z), Vector3.UP)
	elif global_position.distance_to(startPos) > 5:
		nav_agent.set_target_position(startPos)
		look_at(Vector3(startPos.x, startPos.y, startPos.z), Vector3.UP)
	
	var nextPos = nav_agent.get_next_path_position()
	velocity = (nextPos - global_transform.origin).normalized()
	move_and_slide()

func _physics_process(delta):
	if !player_detected: # Check if player is not detected
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

func _on_engaged_timeout():
	engaged = false
