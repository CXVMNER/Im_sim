extends CharacterBody3D

class_name Player

@onready var gun = $CameraController/pivotNode3D/Camera3D/WeaponHolder/gun
@onready var hud = $CameraController/HUD
@export var health := 10
@export var fireSpeed := 0.2
@export var attackPower := 1

var regenStamina := false
var lastShot := 0.0

var bullet = preload("res://scenes/bullet.tscn")

var speed : float
const WALK_SPEED := 4.0
const SPRINT_SPEED := 7.0
const CROUCH_SPEED := 2.0
const JUMP_VELOCITY := 4.0
const SENSITIVITY := 0.01
const BACKWARD_SPEED := 0.8  # 80% of normal speed when moving backwards


const AIR_CONTROL_FACTOR := 0.3  # Controls how much air movement is allowed (0 = no control, 1 = full control)
const INERTIA_FACTOR := 9.0
var stored_horizontal_velocity := Vector3.ZERO  # To store the velocity at the moment of jumping

# head bob variables
const BOB_FREQ := 2.0
const BOB_AMP := 0.06
var t_bob := 0.0

const MAX_STEP_HEIGHT := 0.25
var _snapped_to_stairs_last_frame := false
var _last_frame_was_on_floor = -INF


var is_crouching := false
@export_range(5, 10, 0.1) var CROUCHING_SPEED : float = 7.0 # Animation speed
@export var TOGGLE_CROUCH : bool = true
@export var CROUCH_SHAPECAST : Node3D

@onready var ANIMATIONPLAYER = $AnimationPlayer
@onready var hitbox = $CameraController/pivotNode3D/Camera3D/WeaponHolder/WeaponMesh/Hitbox

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity") # var gravity = 9.8

@onready var staminaRegenTimer = $staminaRegen

@onready var CameraController = $CameraController
@onready var pivot_node_3d = $CameraController/pivotNode3D
@onready var camera_3d = $CameraController/pivotNode3D/Camera3D
@export var camera_rotation_amount : float = 0.025
var camera_rotation_factor := 8

var mouse_captured := true

func _input(event):
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
	# Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Set default speed
	speed = WALK_SPEED

	# add crouch check shapecast collision exception for CharacterBody3D node
	CROUCH_SHAPECAST.add_exception(self)

	hud.health = health
	hud.updateHud()

func _unhandled_input(event):
	if event.is_action_pressed("exit"):
		get_tree().quit()
	
	if event is InputEventMouseMotion and mouse_captured:
		CameraController.rotate_y(-event.relative.x * SENSITIVITY)
		pivot_node_3d.rotate_x(-event.relative.y * SENSITIVITY)
		pivot_node_3d.rotation.x = clamp(pivot_node_3d.rotation.x, deg_to_rad(-90), deg_to_rad(90))
	
	if event.is_action_pressed("toggle_mouse"):
		mouse_captured = not mouse_captured
		if mouse_captured:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta):
	if is_on_floor(): _last_frame_was_on_floor = Engine.get_physics_frames()
	
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

	# Stamina regeneration logic (triggered by the timer)
	if regenStamina and hud.stamina < 100:
		hud.stamina += 1
		hud.updateHud()

	# Adjust speed for crouching.
	if is_crouching:
		speed = CROUCH_SPEED

	# Get the input direction and handle the movement/deceleration.
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (CameraController.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Modify movement based on whether the player is on the floor or in the air
	if is_on_floor() or _snapped_to_stairs_last_frame:
		# Normal movement control on the ground
		if direction:
			# Apply speed reduction when "move_backward" is pressed
			var effective_speed = speed
			if Input.is_action_pressed("move_backward"):
				effective_speed = speed * BACKWARD_SPEED
			velocity.x = direction.x * effective_speed
			velocity.z = direction.z * effective_speed
		else:
			velocity.x = lerp(velocity.x, direction.x * speed, delta * INERTIA_FACTOR)
			velocity.z = lerp(velocity.z, direction.z * speed, delta * INERTIA_FACTOR)
	else:
		# Air control: Allow limited movement but clamp the maximum velocity
		if direction:
			# Apply speed reduction when "move_backward" is pressed in air
			if Input.is_action_pressed("move_backward"):
				speed *= BACKWARD_SPEED
			# Allow limited air control by blending stored velocity with input direction
			var air_control_velocity = stored_horizontal_velocity + (direction * speed * AIR_CONTROL_FACTOR)
			velocity.x = lerp(velocity.x, air_control_velocity.x, AIR_CONTROL_FACTOR)
			velocity.z = lerp(velocity.z, air_control_velocity.z, AIR_CONTROL_FACTOR)

	# Head bob (only when on the ground)
	t_bob += delta * velocity.length() * float(is_on_floor())
	camera_3d.transform.origin = _headbob(t_bob)
	
	if not _snap_up_stairs_check(delta):
		# Because _snap_up_stairs_check moves the body manually, don't call move_and_slide
		# This should be fine since we ensure with the body_test_motion that it doesn't 
		# collide with anything except the stairs it's moving up to.
		move_and_slide()
		_snap_down_to_stairs_check()
	camera_tilt(input_dir.x, delta)

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

func _snap_down_to_stairs_check() -> void:
	var did_snap := false
	# Since it is called after move_and_slide, _last_frame_was_on_floor should still be current frame number.
	# After move_and_slide off top of stairs, on floor should then be false. Update raycast incase it's not already.
	%StairsBelowRayCast3D.force_raycast_update()
	var floor_below : bool = %StairsBelowRayCast3D.is_colliding() and not is_surface_too_steep(%StairsBelowRayCast3D.get_collision_normal())
	var was_on_floor_last_frame = Engine.get_physics_frames() == _last_frame_was_on_floor
	if not is_on_floor() and velocity.y <= 0 and (was_on_floor_last_frame or _snapped_to_stairs_last_frame) and floor_below:
		var body_test_result = KinematicCollision3D.new()
		if self.test_move(self.global_transform, Vector3(0, -MAX_STEP_HEIGHT, 0), body_test_result):
			var translate_y = body_test_result.get_travel().y
			self.position.y += translate_y
			apply_floor_snap()
			did_snap = true
	_snapped_to_stairs_last_frame = did_snap
	
func _snap_up_stairs_check(delta) -> bool:
	if not is_on_floor() and not _snapped_to_stairs_last_frame: return false
	# Don't snap stairs if trying to jump, also no need to check for stairs ahead if not moving
	if self.velocity.y > 0 or (self.velocity * Vector3(1,0,1)).length() == 0: return false
	var expected_move_motion = self.velocity * Vector3(1,0,1) * delta
	var step_pos_with_clearance = self.global_transform.translated(expected_move_motion + Vector3(0, MAX_STEP_HEIGHT * 2, 0))
	# Run a body_test_motion slightly above the pos we expect to move to, towards the floor.
	#  We give some clearance above to ensure there's ample room for the player.
	#  If it hits a step <= MAX_STEP_HEIGHT, we can teleport the player on top of the step
	#  along with their intended motion forward.
	var down_check_result = KinematicCollision3D.new()
	if (self.test_move(step_pos_with_clearance, Vector3(0,-MAX_STEP_HEIGHT*2,0), down_check_result)
	and (down_check_result.get_collider().is_class("StaticBody3D") or down_check_result.get_collider().is_class("CSGShape3D"))):
		var step_height = ((step_pos_with_clearance.origin + down_check_result.get_travel()) - self.global_position).y
		# Note I put the step_height <= 0.01 in just because I noticed it prevented some physics glitchiness
		# 0.02 was found with trial and error. Too much and sometimes get stuck on a stair. Too little and can jitter if running into a ceiling.
		# The normal character controller (both jolt & default) seems to be able to handled steps up of 0.1 anyway
		if step_height > MAX_STEP_HEIGHT or step_height <= 0.01 or (down_check_result.get_position() - self.global_position).y > MAX_STEP_HEIGHT: return false
		%StairsAheadRayCast3D.global_position = down_check_result.get_position() + Vector3(0,MAX_STEP_HEIGHT,0) + expected_move_motion.normalized() * 0.1
		%StairsAheadRayCast3D.force_raycast_update()
		if %StairsAheadRayCast3D.is_colliding() and not is_surface_too_steep(%StairsAheadRayCast3D.get_collision_normal()):
			# _save_camera_pos_for_smoothing()
			self.global_position = step_pos_with_clearance.origin + down_check_result.get_travel()
			apply_floor_snap()
			_snapped_to_stairs_last_frame = true
			return true
	return false

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

func is_surface_too_steep(normal : Vector3) -> bool:
	return normal.angle_to(Vector3.UP) > self.floor_max_angle

func camera_tilt(input_x, delta):
	if camera_3d:
		camera_3d.rotation.z = lerp(camera_3d.rotation.z, -input_x * camera_rotation_amount, delta * camera_rotation_factor)

# func _run_body_test_motion(from : Transform3D, motion : Vector3, result = null) -> bool:
# 	if not result: result = PhysicsTestMotionResult3D.new()
# 	var params = PhysicsTestMotionParameters3D.new()
# 	params.from = from
# 	params.motion = motion
# 	return ww.body_test_motion(self.get_rid(), params, result)

# func _on_fallzone_body_entered(body):
# 	get_tree().change_scene_to_file("res://scenes/level_01.tscn")

# func _on_new_level_body_entered(body):
# 	get_tree().change_scene_to_file("res://scenes/level_02.tscn")
