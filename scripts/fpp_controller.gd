extends CharacterBody3D

class_name Player

@onready var gun = $CameraController/Camera3D/WeaponHolder/gun
@onready var hud = $CameraController/HUD
@export var health := 10
@export var fireSpeed := 0.2
@export var attackPower := 1

var regenStamina = false
var lastShot := 0.0

var bullet = preload("res://scenes/bullet.tscn")

var speed : float
const WALK_SPEED = 5.0
const SPRINT_SPEED = 8.0
const CROUCH_SPEED = 3.0
const JUMP_VELOCITY = 4.0
const SENSITIVITY = 0.01

const AIR_CONTROL_FACTOR = 0.3  # Controls how much air movement is allowed (0 = no control, 1 = full control)
var stored_horizontal_velocity = Vector3.ZERO  # To store the velocity at the moment of jumping

# head bob variables
const BOB_FREQ = 2.0
const BOB_AMP = 0.08
var t_bob = 0.0

var is_crouching = false
@export_range(5, 10, 0.1) var CROUCHING_SPEED : float = 7.0 # Animation speed
@export var TOGGLE_CROUCH : bool = true
@export var CROUCH_SHAPECAST : Node3D

@onready var ANIMATIONPLAYER = $AnimationPlayer
@onready var hitbox = $CameraController/Camera3D/WeaponHolder/WeaponMesh/Hitbox

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity") # var gravity = 9.8

@onready var staminaRegenTimer = $staminaRegen

@onready var CameraController = $CameraController
@onready var camera = $CameraController/Camera3D

func _input(event):
	if event.is_action_pressed("exit"):
		get_tree().quit()

	# Melee attack (animation and hitbox enablement)
	if event.is_action_pressed("attack"):
		perform_melee_attack()

	# Crouch logic
	if event.is_action_pressed("crouch") and is_on_floor() and TOGGLE_CROUCH == true:
		_toggle_crouch()
	if event.is_action_pressed("crouch") and is_crouching == false and is_on_floor() and TOGGLE_CROUCH == false: # Hold to crouch
		crouching(true)
	if event.is_action_pressed("crouch") and TOGGLE_CROUCH == false: # Release to uncrouch
		if CROUCH_SHAPECAST.is_colliding() == false:
			crouching(false)
		elif CROUCH_SHAPECAST.is_colliding() == true:
			uncrouch_check()

# This function performs the melee attack logic (animation and hit detection)
func perform_melee_attack():
	ANIMATIONPLAYER.play("attack")
	hitbox.monitoring = true  # Enable hitbox to detect collisions for melee damage

func _ready():
	# Get mouse input
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Set default speed
	speed = WALK_SPEED

	# add crouch check shapecast collision exception for CharacterBody3D node
	CROUCH_SHAPECAST.add_exception(self)

	hud.health = health
	hud.updateHud()

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		CameraController.rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))

func _physics_process(delta):
	# Handle gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		# Store the horizontal velocity when the jump starts
		stored_horizontal_velocity.x = velocity.x
		stored_horizontal_velocity.z = velocity.z

	# Handle sprint.
	if Input.is_action_pressed("sprint") and not is_crouching:
		if hud.stamina > 0:
			regenStamina = false
			speed = SPRINT_SPEED
			hud.stamina -= 1
			hud.updateHud()  # Update the HUD after sprinting
		else:
			speed = WALK_SPEED  # Prevent sprinting if no stamina

	elif not is_crouching:
		speed = WALK_SPEED

	# Adjust speed for crouching.
	if is_crouching:
		speed = CROUCH_SPEED

	# Get the input direction and handle the movement/deceleration.
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (CameraController.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Modify movement based on whether the player is on the floor or in the air
	if is_on_floor():
		# Normal movement control on the ground
		if direction:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
		else:
			velocity.x = move_toward(velocity.x, 0, speed)
			velocity.z = move_toward(velocity.z, 0, speed)
	else:
		# Air control: Allow limited movement but clamp the maximum velocity
		if direction:
			# Allow limited air control by blending stored velocity with input direction
			var air_control_velocity = stored_horizontal_velocity + (direction * speed * AIR_CONTROL_FACTOR)
			velocity.x = lerp(velocity.x, air_control_velocity.x, AIR_CONTROL_FACTOR)
			velocity.z = lerp(velocity.z, air_control_velocity.z, AIR_CONTROL_FACTOR)

	# Head bob (only when on the ground)
	t_bob += delta * velocity.length() * float(is_on_floor())
	camera.transform.origin = _headbob(t_bob)

	move_and_slide()

	# Stamina regeneration logic (triggered by the timer)
	if regenStamina and hud.stamina < 100:
		hud.stamina += 1
		hud.updateHud()

func _fire():
	var now := Time.get_ticks_msec()/1000.0
	if hud.ammo < 1: return
	if now < lastShot + fireSpeed: return

	lastShot = now
	var b = bullet.instantiate()
	b.damage = attackPower
	b.global_transform = gun.global_transform
	get_parent().add_child(b)
	hud.ammo -= 1
	hud.updateHud()

# We can remove the redundant input checks from _process here.
func _process(_delta):
	if Input.is_action_pressed("attack_2"):
		_fire()

	# Releasing sprint initiates stamina regeneration
	if Input.is_action_just_released("sprint"):
		speed = WALK_SPEED
		staminaRegenTimer.start()

func gainAmmo(qty):
	hud.ammo += qty
	hud.addUpdate(qty, "Ammo", Color(0,0,1,1))
	hud.screenGlow(Color(1,0.843137,0,1))
	hud.updateHud()

func gainHealth(qty):
	health += qty
	hud.health = health
	hud.addUpdate(qty, "Health", Color(0,1,0,1))
	hud.screenGlow(Color(1,0.843137,0,1))
	hud.updateHud()

func takeDamage(qty):
	health -= qty
	hud.health = health
	if health <=0:
		hud.gameOver()
		get_tree().set_pause(true)
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		hud.addUpdate(qty, "Damage", Color(1,0,0,1))
		hud.screenGlow(Color(1,0,0,0.7))
		hud.updateHud()

func _headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP
	return pos

func _toggle_crouch():
	if is_crouching:
		# Only uncrouch if there's no obstacle above
		if CROUCH_SHAPECAST.is_colliding() == false:
			crouching(false)
	else:
		crouching(true)

func uncrouch_check():
	if CROUCH_SHAPECAST.is_colliding() == false:
		crouching(false)

func crouching(state : bool):
	match state:
		true:
			ANIMATIONPLAYER.play("crouch", 0, CROUCHING_SPEED)
			set_movement_speed("crouching")
			is_crouching = true
		false:
			ANIMATIONPLAYER.play("crouch", 0, -CROUCHING_SPEED, true)
			set_movement_speed("walking")
			is_crouching = false  # Mark as not crouching

func _on_animation_player_animation_started(anim_name):
	if anim_name == "crouch":
		is_crouching = !is_crouching

# Set movement speed
func set_movement_speed(state : String):
	match state:
		"walking":
			speed = WALK_SPEED
		"crouching":
			speed = CROUCH_SPEED

func _on_animation_player_animation_finished(anim_name):
	if anim_name == "attack":
		ANIMATIONPLAYER.play("idle")
		hitbox.monitoring = false

func _on_hitbox_body_entered(body):
	# print("Collision detected with", body)
	if body.is_in_group("enemies"):
		print("enemy hit")

func _on_stamina_regen_timeout():
	regenStamina = true
