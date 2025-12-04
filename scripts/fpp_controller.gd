extends CharacterBody3D

class_name Player

@onready var gun_barrel = $"CameraController/pivotNode3D/Camera3D/GunHolder/blaster-b/RayCast3D"
@onready var gun_animation_player = $"CameraController/pivotNode3D/Camera3D/GunHolder/blaster-b/AnimationPlayer"
@onready var gun_audio_stream_player = $"CameraController/pivotNode3D/Camera3D/GunHolder/blaster-b/AudioStreamPlayer"

@onready var gun_barrel_m = $"CameraController/pivotNode3D/Camera3D/GunHolder/blaster-m2/RayCast3D"
@onready var gun_animation_player_m = $"CameraController/pivotNode3D/Camera3D/GunHolder/blaster-m2/AnimationPlayer"
@onready var gun_audio_stream_player_m = $"CameraController/pivotNode3D/Camera3D/GunHolder/blaster-m2/AudioStreamPlayer"

@onready var hud = $CameraController/HUD
@export var health := 100
@export var fireSpeed := 0.2
@export var attackPower := 1

@onready var aim_ray_cast_3d = $CameraController/pivotNode3D/Camera3D/AimRayCast3D
@onready var aim_ray_end = $CameraController/pivotNode3D/Camera3D/AimRayEnd

var regenStamina := false
var lastShot := 0.0

var bullet = load("res://scenes/bullet.tscn")
var instance

# Weapon switching
enum weapons {
	BLASTER_B,
	BLASTER_M
}
var weapon = weapons.BLASTER_B
var can_shoot = true


var speed : float
const WALK_SPEED := 3.5
const SPRINT_SPEED := 6.0
const CROUCH_SPEED := 2.0
const JUMP_VELOCITY := 4.25
const SENSITIVITY := 0.01
const BACKWARD_SPEED := 0.8  # 80% of normal speed when moving backwards

const CAMERA_SMOOTH_LIMIT := 0.75
const AIR_CONTROL_FACTOR := 0.5  # Controls how much air movement is allowed (0 = no control, 1 = full control)
const INERTIA_FACTOR := 10.0  # Controls how much the character slides. Higher the value the less slippery movement
var direction := Vector3.ZERO  # Stores the velocity i.e. at the moment of jumping etc.

var grabbed_object:RigidBody3D = null
@onready var grabbed_anchor = $CameraController/pivotNode3D/Camera3D/SpringArm3D/GrabbedAnchor


# head bob variables
const BOB_FREQ := 2.0
const BOB_AMP := 0.05
var t_bob := 0.0

const MAX_STEP_HEIGHT := 0.25
var _snapped_to_stairs_last_frame := false
var _last_frame_was_on_floor = -INF

@export var CLIMB_SPEED := 5.0

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
@onready var camera_3d = $CameraController/pivotNode3D/Camera3D # The same as %Camera3D
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

	if Input.is_action_just_pressed("interact"):
		if grabbed_object:
			grabbed_object = null
		elif %InteractShapeCast3D.is_colliding():
			var collided = %InteractShapeCast3D.get_collision_result()[0]["collider"]
			if collided is RigidBox:
				if !grabbed_object:
					try_grabbing(collided)
	elif Input.is_action_just_pressed("interact_2"):
		if grabbed_object:
			throw_object()


func try_grabbing(collided:RigidBody3D):
	grabbed_object = collided

func throw_object():
	# Define constants for control
	const THROW_FORCE = 5.0      # Overall throwing power
	const UPWARD_BIAS_FACTOR = 0.5  # How much to mix in a constant upward vector
	# Get the direction the camera is looking (forward direction)
	var forward_direction = -camera_3d.global_basis.z
	# Add an upward bias to the forward direction
	var upward_vector = Vector3.UP
	# Blend the forward direction and the upward vector
	var throw_direction = (forward_direction + upward_vector * UPWARD_BIAS_FACTOR).normalized()
	# Apply the impulse
	grabbed_object.apply_impulse(throw_direction * THROW_FORCE)
	# Release the object
	grabbed_object = null

# This function performs the melee attack logic (animation and hit detection)
func perform_melee_attack():
	ANIMATIONPLAYER.play("attack")
	hitbox.monitoring = true  # Enable hitbox to detect collisions for melee damage

func _ready():
	# Get mouse input
	# Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	PlayerManager.player = self
	
	# Set default speed
	speed = WALK_SPEED

	# add crouch check shapecast collision exception for CharacterBody3D node
	CROUCH_SHAPECAST.add_exception(self)

	hud.health = health
	hud.updateHud()

# Camera rotation values
var camera_yaw := 0.0
var camera_pitch := 0.0

func _unhandled_input(event):
	if event.is_action_pressed("exit"):
		get_tree().quit()
	
	if event is InputEventMouseMotion and mouse_captured:
		# Store RELATIVE rotations (immune to parent snapping)
		camera_yaw -= event.relative.x * SENSITIVITY
		camera_pitch -= event.relative.y * SENSITIVITY
		camera_pitch = clamp(camera_pitch, deg_to_rad(-90), deg_to_rad(90))
		
		# Apply rotations
		CameraController.rotation.y = camera_yaw
		pivot_node_3d.rotation.x = camera_pitch
	
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
		direction = Vector3(velocity.x, 0, velocity.z).normalized()

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
	direction = (CameraController.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if not _handle_ladder_physics():
		# Modify movement based on whether the player is on the floor or in the air
		if is_on_floor() or _snapped_to_stairs_last_frame:
			# Normal movement control on the ground
			if direction:
				# Apply speed reduction when "move_backward" is pressed
				var current_speed = speed
				if Input.is_action_pressed("move_backward"):
					current_speed *= BACKWARD_SPEED
				velocity.x = direction.x * current_speed
				velocity.z = direction.z * current_speed
			else:
				velocity.x = lerp(velocity.x, 0.0, delta * INERTIA_FACTOR)
				velocity.z = lerp(velocity.z, 0.0, delta * INERTIA_FACTOR)
		else:
			# Air control: Allow limited movement but clamp the maximum velocity
			if direction:
				var current_speed = speed
				# Apply speed reduction when "move_backward" is pressed in air
				if Input.is_action_pressed("move_backward"):
					current_speed *= BACKWARD_SPEED
				
				var control_add = direction * current_speed * AIR_CONTROL_FACTOR
				var target_vel = direction + control_add
				# Allow limited air control by blending stored velocity with input direction
				velocity.x = lerp(velocity.x, target_vel.x, AIR_CONTROL_FACTOR)
				velocity.z = lerp(velocity.z, target_vel.z, AIR_CONTROL_FACTOR)
			else:
				# Light air drag when no input
				velocity.x = lerp(velocity.x, 0.0, delta * 1.0)
				velocity.z = lerp(velocity.z, 0.0, delta * 1.0)

		# Head bob (only when on the ground)
		t_bob += delta * velocity.length() * float(is_on_floor())
		camera_3d.transform.origin = _headbob(t_bob)

		if not _snap_up_stairs_check(delta):
			# Because _snap_up_stairs_check moves the body manually, don't call move_and_slide
			# This should be fine since we ensure with the body_test_motion that it doesn't 
			# collide with anything except the stairs it's moving up to.
			move_and_slide()
			_snap_down_to_stairs_check()
	
	_slide_camera_smooth_back_to_origin(delta)
	
	if grabbed_object:
		_object_grabbing(grabbed_object, delta)
	
	camera_tilt(input_dir.x, delta)
	
	if Input.is_action_pressed("attack_2") and can_shoot:
		match weapon:
			weapons.BLASTER_B:
				_shoot_B()
			weapons.BLASTER_M:
				_shoot_M()
	
	if Input.is_action_just_pressed("weapon_one") and weapon != weapons.BLASTER_B:
		_raise_weapon(weapons.BLASTER_B)
	if Input.is_action_just_pressed("weapon_two") and weapon != weapons.BLASTER_M:
		_raise_weapon(weapons.BLASTER_M)

func _object_grabbing(grabbed_object:RigidBody3D, delta):
	var target_pos:Vector3 = grabbed_anchor.global_position
	var current_pos:Vector3 = grabbed_object.global_position
	
	var new_direction = target_pos - current_pos
	
	var required_velocity = new_direction / delta
	
	var velocity_correction = required_velocity - grabbed_object.linear_velocity
	grabbed_object.linear_velocity = required_velocity
	
	grabbed_object.angular_velocity *= 0.5 # decreases the unwanted velocity


func _shoot_B():
	if !gun_animation_player.is_playing():
		gun_animation_player.play("shooting")
		gun_audio_stream_player.play()
		_fire(gun_barrel) # Pass the correct barrel RayCast3D

func _shoot_M():
	if !gun_animation_player_m.is_playing():
		gun_animation_player_m.play("shooting")
		gun_audio_stream_player_m.play()
		_fire(gun_barrel_m) # Pass the correct barrel RayCast3D

func _fire(gun_barrel_raycast):
	var now := Time.get_ticks_msec()/1000.0
	if hud.ammo < 1: return
	if now < lastShot + fireSpeed: return

	if not gun_barrel_raycast.is_inside_tree() or not camera_3d.is_inside_tree():
		return

	lastShot = now
	
	var new_bullet = bullet.instantiate()
	new_bullet.damage = attackPower
	
	# Set the position to the barrel's global position (This was the previous error line, now protected)
	new_bullet.global_position = gun_barrel_raycast.global_position

	# IMPORTANT: Add the bullet to the scene tree *before* calling _set_velocity()
	get_parent().add_child(new_bullet)
	
	# Calculate and set the bullet's velocity
	var target_position: Vector3
	
	if aim_ray_cast_3d.is_colliding():
		target_position = aim_ray_cast_3d.get_collision_point()
	else:
		target_position = camera_3d.global_position - camera_3d.global_transform.basis.z * 101.0
	
	new_bullet._set_velocity(target_position)
		
	hud.ammo -= 1
	hud.updateHud()

@onready var inc = $"CameraController/pivotNode3D/Camera3D/GunHolder/blaster-b"
@onready var incm = $"CameraController/pivotNode3D/Camera3D/GunHolder/blaster-m2"

func _lower_weapon():
	match weapon:
		weapons.BLASTER_B:
			ANIMATIONPLAYER.play("lower_blaster_b")
		weapons.BLASTER_M:
			ANIMATIONPLAYER.play("lower_blaster_m")

func _raise_weapon(new_weapon):
	can_shoot = false
	_lower_weapon()
	await get_tree().create_timer(0.3).timeout # Wait for the lowering animation (0.3s)
	match new_weapon:
		weapons.BLASTER_B:
			inc.visible = true # INSTANTLY show the new weapon at the lowered position
			ANIMATIONPLAYER.play_backwards("lower_blaster_b") # Start the raising animation
			await ANIMATIONPLAYER.animation_finished # Wait for the raise to finish
		weapons.BLASTER_M:
			incm.visible = true # INSTANTLY show the new weapon at the lowered position
			ANIMATIONPLAYER.play_backwards("lower_blaster_m") # Start the raising animation
			await ANIMATIONPLAYER.animation_finished # Wait for the raise to finish
	weapon = new_weapon
	can_shoot = true

# We can remove the redundant input checks from _process here.
func _process(_delta):
	if get_interactable_component_at_shapecast():
		get_interactable_component_at_shapecast().hover_cursor(self)
		if Input.is_action_just_pressed("interact"):
			get_interactable_component_at_shapecast().interact_with(self)
	
	# Releasing sprint initiates stamina regeneration
	if Input.is_action_just_released("sprint"):
		speed = WALK_SPEED
		staminaRegenTimer.start()

func get_interactable_component_at_shapecast() -> InteractableComponent:
	for i in %InteractShapeCast3D.get_collision_count():
		# Allow colliding with player
		if i > 0 and %InteractShapeCast3D.get_collider(0) != $".":
			return null
		var collider = %InteractShapeCast3D.get_collider(i)
		if collider and collider.get_node_or_null("InteractableComponent") is InteractableComponent:
			return collider.get_node_or_null("InteractableComponent")
	return null

var _saved_camera_global_pos = null

func _save_camera_pos_for_smoothing():
	if _saved_camera_global_pos == null:
		_saved_camera_global_pos = %pivotNode3D.global_position

func _slide_camera_smooth_back_to_origin(delta):
	if _saved_camera_global_pos == null: return
	%pivotNode3D.global_position.y = _saved_camera_global_pos.y
	%pivotNode3D.position.y = clampf(%pivotNode3D.position.y, -CAMERA_SMOOTH_LIMIT, CAMERA_SMOOTH_LIMIT) # Clamp incase teleported
	var move_amount = max(self.velocity.length() * delta, WALK_SPEED/2 * delta) # 
	%pivotNode3D.position.y = move_toward(%pivotNode3D.position.y, 0.0, move_amount)
	_saved_camera_global_pos = %pivotNode3D.global_position
	if %pivotNode3D.position.y == 0:
		_saved_camera_global_pos = null # Stop smoothing camera

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
			_save_camera_pos_for_smoothing()
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
			_save_camera_pos_for_smoothing()
			self.global_position = step_pos_with_clearance.origin + down_check_result.get_travel()
			apply_floor_snap()
			_snapped_to_stairs_last_frame = true
			return true
	return false

var _cur_ladder_climbing : Area3D = null
func _handle_ladder_physics() -> bool:
	# Keep track of whether already on ladder. If not already, check if overlapping a ladder area3d.
	var was_climbing_ladder := _cur_ladder_climbing and _cur_ladder_climbing.overlaps_body(self)
	if not was_climbing_ladder:
		_cur_ladder_climbing = null
		for ladder in get_tree().get_nodes_in_group("ladder_area3d"):
			if ladder.overlaps_body(self):
				_cur_ladder_climbing = ladder
				break
	if _cur_ladder_climbing == null:
		return false
	
	# Set up variables. Most of this is going to be dependent on the player's relative position/velocity/input to the ladder.
	var ladder_gtransform : Transform3D = _cur_ladder_climbing.global_transform
	var pos_rel_to_ladder := ladder_gtransform.affine_inverse() * self.global_position
	
	var forward_move := Input.get_action_strength("move_forward") - Input.get_action_strength("move_backward")
	var side_move := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var ladder_forward_move = ladder_gtransform.affine_inverse().basis * %Camera3D.global_transform.basis * Vector3(0, 0, -forward_move)
	var ladder_side_move = ladder_gtransform.affine_inverse().basis * %Camera3D.global_transform.basis * Vector3(side_move, 0, 0)
	
	# Strafe velocity is simple. Just take x component rel to ladder of both
	var ladder_strafe_vel : float = CLIMB_SPEED * (ladder_side_move.x + ladder_forward_move.x)
	# For climb velocity, there are a few things to take into account:
	# If strafing directly into the ladder, go up, if strafing away, go down
	var ladder_climb_vel : float = CLIMB_SPEED * -ladder_side_move.z
	# When pressing forward & facing the ladder, the player likely wants to move up. Vice versa with down.
	# So we will bias the direction (up/down) towards where we are looking by 45 degrees to give a greater margin for up/down detect.
	var up_wish := Vector3.UP.rotated(Vector3(1,0,0), deg_to_rad(-45)).dot(ladder_forward_move)
	ladder_climb_vel += CLIMB_SPEED * up_wish
	
	# Only begin climbing ladders when moving towards them & prevent sticking to top of ladder when dismounting
	# Trying to best match the player's intention when climbing on ladder
	var should_dismount = false
	if not was_climbing_ladder:
		var mounting_from_top = pos_rel_to_ladder.y > _cur_ladder_climbing.get_node("TopOfLadder").position.y
		if mounting_from_top:
			# They could be trying to get on from the top of the ladder, or trying to leave the ladder.
			if ladder_climb_vel > 0: should_dismount = true
		else:
			# If not mounting from top, they are either falling or on floor.
			# In which case, only stick to ladder if intentionally moving towards
			if (ladder_gtransform.affine_inverse().basis * direction).z >= 0: should_dismount = true
		# Only stick to ladder if very close. Helps make it easier to get off top & prevents camera jitter
		if abs(pos_rel_to_ladder.z) > 0.1: should_dismount = true
	
	# Let player step off onto floor
	if is_on_floor() and ladder_climb_vel <= 0: should_dismount = true
	
	if should_dismount:
		_cur_ladder_climbing = null
		return false
	
	# Allow jump off ladder mid climb
	if was_climbing_ladder and Input.is_action_just_pressed("jump"):
		self.velocity = _cur_ladder_climbing.global_transform.basis.z * JUMP_VELOCITY * 1.5
		_cur_ladder_climbing = null
		return false
	
	self.velocity = ladder_gtransform.basis * Vector3(ladder_strafe_vel, ladder_climb_vel, 0)
	self.velocity = self.velocity.limit_length(CLIMB_SPEED) # Comment this line to turn on ladder boosting
	
	# Snap player onto ladder
	pos_rel_to_ladder.z = 0
	self.global_position = ladder_gtransform * pos_rel_to_ladder
	
	move_and_slide()
	return true

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
