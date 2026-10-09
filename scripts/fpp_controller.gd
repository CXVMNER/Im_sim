extends CharacterBody3D

class_name Player

@onready var hud := $HUD
@export var health := 100
@export var max_health := 0 # 0 = use the starting health; used by fall damage scaling
@export var ammo := 0
# Changed to float to allow precise delta subtraction
@export var stamina : float = 100.0 
# New variable to control exact duration
@export var STAMINA_TIME : float = 5.0
@export var regen_rate : float = stamina / STAMINA_TIME
@export var depletion_rate : float = stamina / STAMINA_TIME
@export var regen_delay_accumulator : float = 10.0  # Start high so regen is ready immediately
@export var SENSITIVITY := 0.01

@onready var pause_menu: PauseMenu = $PauseMenu
@export var is_dead: bool = false # Flag for the player's death status

# Movement constants
var speed : float
const WALK_SPEED := 3.5
const SPRINT_SPEED := 6.0
const CROUCH_SPEED := 2.0
const JUMP_VELOCITY := 4.0
const BACKWARD_SPEED := 0.8  # 80% of normal speed when moving backwards
const push_force := 10

const CAMERA_SMOOTH_LIMIT := 0.75
const AIR_CONTROL_FACTOR := 0.5  # Controls how much air movement is allowed (0 = no control, 1 = full control)
const INERTIA_FACTOR := 10.0  # Controls how much the character slides. Higher the value the less slippery movement
var direction := Vector3.ZERO  # Stores the velocity i.e. at the moment of jumping etc.

@onready var interact_cast := $CameraController/pivotNode3D/Camera3D/InteractionManager/InteractShapeCast3D
@onready var grabbed_anchor := $CameraController/pivotNode3D/Camera3D/InteractionManager/SpringArm3D/GrabbedAnchor

var grabbed_object:RigidBody3D = null

# Variable to hold all collected key strings (The 'Pass Value' from power-up)
var keys_collected: Array[String] = []
var keys_collected_current: Array[String] = []
var total_keys_in_map := 0

# head bob variables
const BOB_FREQ := 2.0
const BOB_AMP := 0.05
var t_bob := 0.0

const MAX_STEP_HEIGHT := 0.25
var _snapped_to_stairs_last_frame := false
var _last_frame_was_on_floor := -INF

@export var CLIMB_SPEED := 3.5

var is_crouching := false
@export_range(5, 10, 0.1) var CROUCHING_SPEED : float = 7.0 # Animation speed
@export var TOGGLE_CROUCH : bool = true
@export var CROUCH_SHAPECAST : Node3D

@onready var ANIMATIONPLAYER := $AnimationPlayer

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity") # var gravity = 9.8

@onready var weapon_manager := $CameraController/pivotNode3D/Camera3D/GunHolder
var previous_weapon_state: WeaponManager.WeaponState = WeaponManager.WeaponState.NO_WEAPON

# Camera kick from shooting/landing. x = pitch, y = yaw (radians); recovers on its own
var recoil := Vector2.ZERO
@export var recoil_recovery := 9.0
var fall_damage: FallDamage

@onready var hit_audio_stream_player_3d = $HitAudioStreamPlayer3D

@onready var CameraController := $CameraController
@onready var pivot_node_3d := $CameraController/pivotNode3D
@onready var camera_3d : Camera3D = $CameraController/pivotNode3D/Camera3D # The same as %Camera3D
@export var camera_rotation_amount : float = 0.025
var camera_rotation_factor := 8

var mouse_captured := true

var is_paused := false

# Camera rotation values
var camera_yaw := 0.0
var camera_pitch := 0.0

# Function to handle the player dying
func die():
	if is_dead:
		return
	
	is_dead = true
	
	# Pause the game
	pause_game(true, true)
	
	# Show the "Game Over" label
	pause_menu.set_game_over(true)
	
	# Additional actions on death (e.g., disable movement, show cursor)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# MODIFIED: Refactor the pause_game function to accept a 'game_over' argument
func pause_game(state: bool = true, game_over: bool = false):
	# If the game is in a Game Over state, we prevent unpausing.
	if is_dead and state == false and game_over == false:
		print("Cannot unpause: Game Over.")
		return
	
	is_paused = state # Variable has to be updated here to keep it synced
	
	if state:
		# Pause
		pause_menu.show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().paused = true
	else:
		# Unpause
		pause_menu.hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_tree().paused = false

func _input(event):
	if event is InputEventKey:
		if Input.is_action_just_pressed("pause") and !is_dead: 
			pause_game(!get_tree().paused)
	
	if is_paused:
		return
	
	# Weapon switching (event based: Input.is_action_just_pressed() inside _input fires
	# for every event in the same frame, which could start several switches at once)
	if not grabbed_object:
		if event.is_action_pressed("weapon_one"):
			weapon_manager.switch_weapon(WeaponManager.WeaponState.WEAPON_1)
		elif event.is_action_pressed("weapon_two"):
			weapon_manager.switch_weapon(WeaponManager.WeaponState.WEAPON_2)
		elif event.is_action_pressed("weapon_holster"):
			weapon_manager.switch_weapon(WeaponManager.WeaponState.NO_WEAPON)
		elif InputMap.has_action("weapon_last") and event.is_action_pressed("weapon_last"):
			weapon_manager.switch_to_last()
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				weapon_manager.cycle_weapon(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				weapon_manager.cycle_weapon(1)
	
	# Crouch logic
	if event.is_action_pressed("crouch") and is_on_floor() and _ladder == null and TOGGLE_CROUCH == true:
		_toggle_crouch()
	if event.is_action_pressed("crouch") and is_crouching == false and is_on_floor() and _ladder == null and TOGGLE_CROUCH == false: # Hold to crouch
		crouching(true)
	if event.is_action_pressed("crouch") and TOGGLE_CROUCH == false: # Release to uncrouch
		if CROUCH_SHAPECAST.is_colliding() == false:
			crouching(false)
		elif CROUCH_SHAPECAST.is_colliding() == true:
			uncrouch_check()

	if event.is_action_pressed("interact"):
		if grabbed_object:
			grabbed_object = null
			weapon_manager.switch_weapon(previous_weapon_state)
		elif interact_cast.is_colliding():
			var collided = interact_cast.get_collision_result()[0]["collider"]
			if collided is RigidBox:
				if !grabbed_object:
					try_grabbing(collided)
	elif event.is_action_pressed("interact_2"):
		if grabbed_object:
			throw_object()

func try_grabbing(collided:RigidBody3D):
	previous_weapon_state = weapon_manager.target_weapon
	weapon_manager.switch_weapon(WeaponManager.WeaponState.NO_WEAPON)
	grabbed_object = collided

func throw_object():
	const THROW_FORCE = 20.0 # Overall throwing power
	# Get the direction the camera is looking (forward direction)
	var forward_direction = -camera_3d.global_basis.z
	# Upward boost
	var upward_vector = Vector3(0.0, 10.0, 0.0)
	# Combine directions
	var impulse = (forward_direction * THROW_FORCE) + upward_vector
	# Apply impulse
	grabbed_object.apply_impulse(impulse)
	# Release the object
	grabbed_object = null
	weapon_manager.switch_weapon(previous_weapon_state)

func _ready() -> void:
	pause_menu.hide()
	# Get mouse input
	# Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	PlayerManager.player = self
	
	# Set default speed
	speed = WALK_SPEED

	# add crouch check shapecast collision exception for CharacterBody3D node
	CROUCH_SHAPECAST.add_exception(self)

	hud.health = health
	hud.ammo = ammo
	hud.stamina = stamina
	hud.updateHud()
	
	if max_health <= 0:
		max_health = health
	
	# Start from the scene's real camera angles so recoil never snaps the view
	camera_yaw = CameraController.rotation.y
	camera_pitch = pivot_node_3d.rotation.x
	
	# Every creature takes fall damage
	fall_damage = FallDamage.new()
	fall_damage.name = "FallDamage"
	add_child(fall_damage)
	fall_damage.landed.connect(_on_landed)

func _unhandled_input(event):
	if event is InputEventMouseMotion and mouse_captured:
		# Store RELATIVE rotations (immune to parent snapping)
		camera_yaw -= event.relative.x * SENSITIVITY
		camera_pitch -= event.relative.y * SENSITIVITY
		camera_pitch = clamp(camera_pitch, deg_to_rad(-89), deg_to_rad(89))
		
		# Apply rotations
		CameraController.rotation.y = camera_yaw
		pivot_node_3d.rotation.x = camera_pitch
	
	if event.is_action_pressed("toggle_mouse"):
		mouse_captured = !mouse_captured
		if mouse_captured:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta):
	if get_tree().paused: # if is_paused:
		return
	
	if is_on_floor():
		_last_frame_was_on_floor = Engine.get_physics_frames()
	
	# Handle gravity.
	if not is_on_floor() and _ladder == null:
		velocity.y -= gravity * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor() and _ladder == null:
		velocity.y = JUMP_VELOCITY
		# Store the horizontal velocity when the jump starts
		direction = Vector3(velocity.x, 0, velocity.z).normalized()

	# Sprint & Stamina
	var sprint_pressed := Input.is_action_pressed("sprint")
	var can_sprint := !is_crouching && stamina > 0 && _ladder == null  # Use local stamina for consistency
	var is_sprinting := sprint_pressed && can_sprint
	
	if is_sprinting:
		regen_delay_accumulator = 0.0
		speed = SPRINT_SPEED
		stamina -= depletion_rate * delta
		if stamina < 0:
			stamina = 0
		hud.stamina = stamina
		hud.updateHud()
	else:
		regen_delay_accumulator += delta
		speed = CROUCH_SPEED if is_crouching else WALK_SPEED
		if regen_delay_accumulator >= 2.5 && stamina < 100:
			stamina += regen_rate * delta
			if stamina > 100:
				stamina = 100
			hud.stamina = stamina
			hud.updateHud()
	
	# Get the input direction and handle the movement/deceleration.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	direction = (CameraController.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if not _handle_ladder(delta):
		# Modify movement based on whether the player is on the floor or in the air
		if is_on_floor() or _snapped_to_stairs_last_frame:
			# Normal movement control on the ground
			if direction:
				# Apply speed reduction when "move_backward" is pressed
				var current_speed := speed
				if Input.is_action_pressed("move_backward"):
					current_speed *= BACKWARD_SPEED
				velocity.x = direction.x * current_speed
				velocity.z = direction.z * current_speed
			else:
				velocity.x = lerp(velocity.x, 0.0, delta * INERTIA_FACTOR)
				velocity.z = lerp(velocity.z, 0.0, delta * INERTIA_FACTOR)
		elif _ladder_air_lock > 0.0:
			pass # keep the push from letting go of a ladder; air control would cancel it
		else:
			# Air control: Allow limited movement but clamp the maximum velocity
			if direction:
				var current_speed := speed
				# Apply speed reduction when "move_backward" is pressed in air
				if Input.is_action_pressed("move_backward"):
					current_speed *= BACKWARD_SPEED
				
				var control_add := direction * current_speed * AIR_CONTROL_FACTOR
				var target_vel := direction + control_add
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
	
	# Push rigidbodies
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		if c.get_collider() is RigidBody3D:
			c.get_collider().apply_central_impulse(-c.get_normal() * push_force)
	
	_slide_camera_smooth_back_to_origin(delta)
	
	if grabbed_object:
		_object_grabbing(grabbed_object, delta)
	
	camera_tilt(0.0 if (_ladder != null) else input_dir.x, delta)
	
	# Shooting
	if Input.is_action_pressed("attack"):
		weapon_manager.try_shoot(Input.is_action_just_pressed("attack"))

func _object_grabbing(grabbed_object:RigidBody3D, delta) -> void:
	var target_pos:Vector3 = grabbed_anchor.global_position
	var current_pos:Vector3 = grabbed_object.global_position
	
	var new_direction = target_pos - current_pos
	
	var required_velocity = new_direction / delta
	
	var velocity_correction = required_velocity - grabbed_object.linear_velocity
	grabbed_object.linear_velocity = required_velocity
	
	grabbed_object.angular_velocity *= 0.5 # decreases the unwanted velocity

func _process(delta) -> void:
	_update_recoil(delta)
	_update_interaction_prompt()

func action_hint(action: String, fallback: String) -> String:
	if not InputMap.has_action(action):
		return fallback
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
			if code != KEY_NONE:
				return OS.get_keycode_string(code)
		elif event is InputEventMouseButton:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					return "LMB"
				MOUSE_BUTTON_RIGHT:
					return "RMB"
				MOUSE_BUTTON_MIDDLE:
					return "MMB"
	return fallback

func _update_interaction_prompt() -> void:
	if hud == null or not hud.has_method("set_interaction_prompt"):
		return
	if get_tree().paused or is_dead:
		hud.set_interaction_prompt("")
		return

	var prompt := ""
	if grabbed_object:
		prompt = "Press [%s] to drop    [%s] to throw" % [
			action_hint("interact", "E"),
			action_hint("interact_2", "F"),
		]
	else:
		var look := _read_look_target()
		var interactable: InteractableComponent = look.interactable
		prompt = look.prompt
		if interactable:
			interactable.hover_cursor(self)
			if Input.is_action_just_pressed("interact"):
				interactable.interact_with(self)

	hud.set_interaction_prompt(prompt)

func _read_look_target() -> Dictionary:
	var result := {"interactable": null, "prompt": ""}
	for i in interact_cast.get_collision_count():
		if i > 0 and interact_cast.get_collider(0) != self:
			break
		var collider: Object = interact_cast.get_collider(i)
		if collider == null or collider == self:
			continue
		var comp: Node = collider.get_node_or_null("InteractableComponent") if collider is Node else null
		if comp is InteractableComponent:
			result.interactable = comp
			result.prompt = _prompt_for_interactable(comp)
			break
		if collider.has_method("get_interaction_prompt"):
			result.prompt = str(collider.get_interaction_prompt(self))
			break
		if collider is RigidBox:
			result.prompt = "Press [%s] to pick up" % action_hint("interact", "E")
			break
		if collider is CollisionObject3D and not (collider is Area3D):
			break
	return result

func _prompt_for_interactable(comp: InteractableComponent) -> String:
	var parent := comp.get_parent()
	if parent and parent.has_method("get_interaction_prompt"):
		return str(parent.get_interaction_prompt(self))
	if comp.has_method("get_interaction_prompt"):
		return str(comp.get_interaction_prompt(self))
	return "Press [%s] to interact" % action_hint("interact", "E")

func get_interactable_component_at_shapecast() -> InteractableComponent:
	for i in interact_cast.get_collision_count():
		# Allow colliding with player
		if i > 0 and interact_cast.get_collider(0) != $".":
			return null
		var collider = interact_cast.get_collider(i)
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

# ======================================================================
# LADDERS
# ======================================================================
# States: NONE -> MOUNTING (short glide onto the rungs) -> CLIMBING
#         CLIMBING -> DISMOUNTING (pull yourself over the top) -> NONE
enum LadderControl {
	LOOK_DIRECTION, # Half-Life style: forward climbs when looking up/level, descends when looking down
	FORWARD_IS_UP,  # forward always climbs, back always descends (look around freely)
}

@export var ladder_control: LadderControl = LadderControl.LOOK_DIRECTION
## Sideways speed on the ladder, as a fraction of CLIMB_SPEED
@export var ladder_strafe_factor := 0.5
## LOOK_DIRECTION: looking above this pitch = forward climbs, below (neutral - band) = forward descends
@export var ladder_look_neutral_deg := -15.0
@export var ladder_look_band_deg := 10.0
## Jumping off: push away from the ladder and a small hop
@export var ladder_let_go_push := 2.5
@export var ladder_let_go_hop := 2.5

const LADDER_TOP_STEP_HEIGHT := 0.5 # feet this close to the top = climb over onto the ledge
const LADDER_RAIL_MARGIN := 0.2 # keep the capsule between the rails
const LADDER_GRAB_REACH := 0.05 # how far past the hanging spot you can be and still get grabbed
const LADDER_DISMOUNT_REACH := 1.6 # horizontal reach to an exit marker
const LADDER_DISMOUNT_USE_REACH := 2.5 # reach when using the interact key

var _ladder: Ladder = null # the ladder we're on (null = not on one)
var _ladder_gliding := false # mid mount/dismount animation
var _ladder_cooldown := 0.0 # can't grab a ladder again until this runs out
var _ladder_air_lock := 0.0 # after letting go, air control can't cancel the push
var _ladder_up_locked := false # after stepping on from the ledge, "up" is ignored until released

# Returns true when the ladder code has fully handled this frame's movement
# (including move_and_slide), so normal walking must be skipped.
func _handle_ladder(delta: float) -> bool:
	_ladder_cooldown = maxf(_ladder_cooldown - delta, 0.0)
	_ladder_air_lock = maxf(_ladder_air_lock - delta, 0.0)

	if _ladder == null:
		_try_grab_ladder()
		if _ladder == null:
			return false

	# Ease the head-bob offset out while on a ladder
	camera_3d.transform.origin = camera_3d.transform.origin.lerp(Vector3.ZERO, minf(delta * 10.0, 1.0))

	if _ladder_gliding:
		velocity = Vector3.ZERO
		return true
	return _ladder_climb()

# x = strafe (-1 left .. 1 right), y = climb (-1 down .. 1 up)
func _ladder_input() -> Vector2:
	var fwd := Input.get_action_strength("move_forward") - Input.get_action_strength("move_backward")
	var side := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var climb := fwd
	if ladder_control == LadderControl.LOOK_DIRECTION:
		var pitch_deg := rad_to_deg(camera_pitch)
		climb *= clampf((pitch_deg - ladder_look_neutral_deg) / ladder_look_band_deg, -1.0, 1.0)
	return Vector2(side, climb)

func _try_grab_ladder() -> void:
	if _ladder_cooldown > 0.0 or is_dead or is_crouching:
		return
	var wish := Vector3(direction.x, 0.0, direction.z)
	if wish.length_squared() < 0.01:
		return # grabbing needs intent: you have to be pushing somewhere
	wish = wish.normalized()
	var look: Vector3 = -CameraController.global_basis.z
	look.y = 0.0
	look = look.normalized()
	var input := _ladder_input()

	for node in get_tree().get_nodes_in_group("ladders"):
		var ladder := node as Ladder
		if ladder == null:
			continue
		var n := ladder.outward()
		var rail := ladder.half_width() - LADDER_RAIL_MARGIN
		var l := ladder.to_local_pos(global_position) # feet, in ladder space
		if absf(l.x) > rail + 0.1: # must actually be at the ladder, not beside it
			continue
		var x := clampf(l.x, -rail, rail)

		# --- Grab from the front: walking into it (or falling past it) while facing it
		if l.z > 0.0 and l.z < ladder.climb_offset + LADDER_GRAB_REACH:
			if l.y > -ladder.half_height - 0.1 and l.y < ladder.half_height - 0.6:
				if wish.dot(-n) > 0.7 and look.dot(-n) > 0.6:
					# Standing on the floor you only grab it if you'd actually go UP
					# (otherwise looking down + forward would instantly re-grab at the bottom)
					if is_on_floor() and input.y <= 0.2:
						continue
					var to := ladder.to_world_pos(Vector3(x, l.y, ladder.climb_offset))
					# Duration scales with the pull distance, so a long reach is not a violent yank
					_grab_ladder(ladder, [to], clampf(global_position.distance_to(to) * 0.7, 0.1, 0.4))
					return

		# --- Step onto it from the ledge above, to climb down: over the lip, then lower down
		if ladder.allow_top_entry and is_on_floor() and l.z < 0.0 and l.z > -0.7:
			if absf(l.y - ladder.half_height) < 0.3:
				if wish.dot(n) > 0.5 and look.dot(n) > 0.5:
					var lip := ladder.to_world_pos(Vector3(x, ladder.half_height, ladder.climb_offset))
					var down := ladder.to_world_pos(Vector3(x, ladder.half_height - 0.9, ladder.climb_offset))
					_grab_ladder(ladder, [lip, down], 0.65, true)
					return

func _grab_ladder(ladder: Ladder, path: Array, time: float, lock_up := false) -> void:
	_ladder = ladder
	_ladder_up_locked = lock_up
	# Hanging on a ladder is not falling: no landing thud / damage when you step off
	fall_damage.reset()
	fall_damage.enabled = false
	# Can't climb while carrying a crate
	if grabbed_object:
		grabbed_object = null
		weapon_manager.switch_weapon(previous_weapon_state)
	_ladder_glide(path, time, Callable())

# Move the player along a short path (no collisions) over `time`, then call on_done.
# The first leg eases in and the last eases out, so multi-leg paths don't stop in the middle.
func _ladder_glide(path: Array, time: float, on_done: Callable) -> void:
	_ladder_gliding = true
	velocity = Vector3.ZERO
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	for i in path.size():
		var leg := tween.tween_property(self, "global_position", path[i], time / path.size())
		leg.set_trans(Tween.TRANS_SINE)
		if path.size() == 1:
			leg.set_ease(Tween.EASE_IN_OUT)
		else:
			leg.set_ease(Tween.EASE_IN if i == 0 else Tween.EASE_OUT)
	tween.tween_callback(_ladder_glide_done.bind(on_done))

func _ladder_glide_done(on_done: Callable) -> void:
	_ladder_gliding = false
	if on_done.is_valid():
		on_done.call()

func _ladder_climb() -> bool:
	var ladder := _ladder
	var input := _ladder_input()
	var l := ladder.to_local_pos(global_position)
	var rail := ladder.half_width() - LADDER_RAIL_MARGIN

	# --- Let go -------------------------------------------------------
	if Input.is_action_just_pressed("jump"):
		return _let_go(ladder.outward() * ladder_let_go_push + Vector3.UP * ladder_let_go_hop)
	if Input.is_action_just_pressed("crouch"):
		return _let_go(ladder.outward() * 0.5) # just drop

	# --- Climb / strafe velocity in ladder space ---------------------------
	var climb := input.y * CLIMB_SPEED
	var strafe := input.x * _ladder_strafe_sign(ladder) * CLIMB_SPEED * ladder_strafe_factor
	if (l.x >= rail and strafe > 0.0) or (l.x <= -rail and strafe < 0.0):
		strafe = 0.0

	# Right after stepping on from the ledge, ignore "up" until the player lets go of it;
	# otherwise forward while looking level would pull you straight back over the top.
	if _ladder_up_locked:
		if input.y > 0.0:
			climb = minf(climb, 0.0)
		else:
			_ladder_up_locked = false

	# --- Leaving the ladder at an end or side ----------------------------------
	# Authored LadderDismount markers win; without any, probe for a ledge above.
	var near_top := l.y >= ladder.half_height - LADDER_TOP_STEP_HEIGHT
	var exit_feet: Variant = null
	if ladder.has_dismounts():
		exit_feet = _pick_dismount(ladder, climb, Input.is_action_just_pressed("interact"))
	elif ladder.allow_top_exit and climb > 0.0 and near_top:
		exit_feet = _find_ledge(ladder, l)
	if exit_feet != null:
		# One smooth diagonal pull-up (rising first and then stepping over means a fast forward shove)
		_ladder_glide([exit_feet], 0.5, _release_ladder.bind(Vector3.ZERO))
		return true
	if climb > 0.0 and near_top:
		climb = 0.0 # nowhere to go: stop at the top

	# --- Bottom of the ladder (nothing to stand on) -------------------------
	if climb < 0.0 and l.y <= -ladder.half_height + 0.02:
		return _let_go(Vector3.ZERO)

	# Ease towards the correct hanging distance instead of snapping (no jitter)
	var hold := clampf((ladder.climb_offset - l.z) * 15.0, -3.0, 3.0)
	velocity = ladder.global_basis * Vector3(strafe, climb, hold)
	move_and_slide()

	# Climbed down onto the floor: just walk off
	if climb < 0.0 and is_on_floor():
		_release_ladder(Vector3.ZERO)
	return true

# Which authored exit (if any) does the player want right now? Returns the feet position or null.
#  - exit above you: climbing up and within reach of it
#  - exit below you: climbing down and within reach of it
#  - any exit: look at it and press interact (Valve's "use key" dismount)
func _pick_dismount(ladder: Ladder, climb: float, use_pressed: bool) -> Variant:
	var feet: Vector3 = global_position
	var view: Vector3 = -camera_3d.global_basis.z
	var best: Variant = null
	var best_dist := INF
	for d: LadderDismount in ladder.dismounts:
		var p: Vector3 = d.global_position
		var dy: float = p.y - feet.y
		var dist: float = feet.distance_to(p)
		var wanted := false
		if use_pressed:
			var aim: Vector3 = (p + Vector3.UP - camera_3d.global_position).normalized()
			wanted = dist <= LADDER_DISMOUNT_USE_REACH and view.dot(aim) > 0.5
		elif not d.use_key_only and Vector2(p.x - feet.x, p.z - feet.z).length() <= LADDER_DISMOUNT_REACH:
			if dy > 0.05:
				wanted = climb > 0.0 and dy <= LADDER_TOP_STEP_HEIGHT
			elif dy < -0.05:
				wanted = climb < 0.0 and -dy <= 0.3
		if wanted and dist < best_dist:
			best = p + Vector3.UP * 0.02
			best_dist = dist
	return best

func _let_go(release_velocity: Vector3) -> bool:
	_release_ladder(release_velocity)
	move_and_slide()
	return true

func _release_ladder(release_velocity: Vector3) -> void:
	_ladder = null
	_ladder_cooldown = 0.35
	if release_velocity != Vector3.ZERO:
		_ladder_air_lock = 0.4
	velocity = release_velocity
	fall_damage.enabled = true # falling is counted again from this moment

# A strafe key moves you towards that side of YOUR view, even if you've turned around
func _ladder_strafe_sign(ladder: Ladder) -> float:
	return -1.0 if CameraController.global_basis.x.dot(ladder.global_basis.x) < -0.2 else 1.0

# Is there a ledge to stand on just past the top of the ladder?
# Returns the feet position to end up at, or null.
func _find_ledge(ladder: Ladder, l: Vector3) -> Variant:
	var rail := ladder.half_width() - LADDER_RAIL_MARGIN
	var spot := ladder.to_world_pos(Vector3(clampf(l.x, -rail, rail), ladder.half_height, -0.35))
	var query := PhysicsRayQueryParameters3D.create(
			spot + Vector3.UP * 0.6, spot + Vector3.DOWN * 0.4, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or is_surface_too_steep(hit.normal):
		return null
	var feet := Vector3(spot.x, hit.position.y + 0.02, spot.z)
	if test_move(Transform3D(global_basis, feet), Vector3.ZERO):
		return null # no headroom / something in the way
	return feet

func add_recoil(pitch: float, yaw: float) -> void:
	recoil.x = clampf(recoil.x + pitch, -0.2, 0.35)
	recoil.y += yaw

func _update_recoil(delta: float) -> void:
	if recoil == Vector2.ZERO:
		return
	recoil = recoil.lerp(Vector2.ZERO, 1.0 - exp(-recoil_recovery * delta))
	if recoil.length() < 0.0001:
		recoil = Vector2.ZERO
	CameraController.rotation.y = camera_yaw + recoil.y
	pivot_node_3d.rotation.x = clampf(camera_pitch + recoil.x, deg_to_rad(-89), deg_to_rad(89))

# Landing thud: the camera dips proportionally to the drop
func _on_landed(fall_height: float, _damage: int) -> void:
	add_recoil(-clampf(fall_height * 0.012, 0.0, 0.12), 0.0)

func gainAmmo(qty: int) -> void:
	ammo += qty
	print("Player gained ammo: ", qty, " | Ammo: ", ammo)
	hud.ammo = ammo
	hud.addUpdate(qty, "Ammo", Color(0,0,1,1))
	hud.updateHud()

func gainHealth(qty: int) -> void:
	health += qty
	print("Player gained health: ", qty, " | Health: ", health)
	hud.health = health
	hud.addUpdate(qty, "Health", Color(0,1,0,1))
	hud.updateHud()

func takeDamage(dmg: int, _source: Node = null, _hit_pos: Vector3 = Vector3.ZERO) -> void:
	if is_dead or dmg <= 0:
		return
	
	health -= dmg
	print("Player took damage: ", dmg, " | Health: ", health)
	hit_audio_stream_player_3d.play()
	
	# Update HUD data
	hud.health = health
	hud.addUpdate(dmg, "Damage", Color(1, 0, 0, 1))
	hud.updateHud()
	if hud.has_method("screenGlow"):
		hud.screenGlow(Color(1, 0, 0, 0.35))
	
	if health <= 0:
		health = 0
		die()

func _headbob(time) -> Vector3:
	var pos = Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	pos.x = cos(time * BOB_FREQ / 2) * BOB_AMP
	return pos

func _toggle_crouch() -> void:
	if is_crouching:
		# Only uncrouch if there's no obstacle above
		if CROUCH_SHAPECAST.is_colliding() == false:
			crouching(false)
	else:
		crouching(true)

func uncrouch_check() -> void:
	if CROUCH_SHAPECAST.is_colliding() == false:
		crouching(false)

func crouching(state : bool) -> void:
	match state:
		true:
			ANIMATIONPLAYER.play("crouch", 0, CROUCHING_SPEED)
			set_movement_speed("crouching")
			is_crouching = true
		false:
			ANIMATIONPLAYER.play("crouch", 0, -CROUCHING_SPEED, true)
			set_movement_speed("walking")
			is_crouching = false  # Mark as not crouching

func _on_animation_player_animation_started(anim_name) -> void:
	if anim_name == "crouch":
		is_crouching = !is_crouching

# Set movement speed
func set_movement_speed(state : String) -> void:
	match state:
		"walking":
			speed = WALK_SPEED
		"crouching":
			speed = CROUCH_SPEED

func is_surface_too_steep(normal : Vector3) -> bool:
	return normal.angle_to(Vector3.UP) > self.floor_max_angle

func camera_tilt(input_x, delta) -> void:
	if camera_3d:
		camera_3d.rotation.z = lerp(camera_3d.rotation.z, -input_x * camera_rotation_amount, delta * camera_rotation_factor)

# This is a safe function to expose the point where the enemy should be looking.
# It automatically accounts for standing and crouching height.
func get_eye_position() -> Vector3:
	var camera_controller := camera_3d 
	return camera_controller.global_transform.origin

func reset_keys_for_level() -> void:
	keys_collected_current.clear()
	total_keys_in_map = 0
	if hud.has_method("update_keys"):
		hud.update_keys(keys_collected_current, keys_collected, total_keys_in_map)

# Function to add a key password to the player's inventory
func collect_key(key_value: String) -> void:
	keys_collected.append(key_value)
	keys_collected_current.append(key_value)
	print("Collected key: ", key_value)
	# Update the HUD list and counter
	if hud.has_method("update_keys"):
		hud.update_keys(keys_collected_current, keys_collected, total_keys_in_map)

# Function to check if the player has a specific password
func has_key(key_value: String) -> bool:
	return keys_collected.has(key_value)
	
func set_total_keys(total: int) -> void:
	total_keys_in_map = total
	# Immediately update the HUD with the initial count
	if hud.has_method("update_keys"):
		hud.update_keys(keys_collected_current, keys_collected, total_keys_in_map)
