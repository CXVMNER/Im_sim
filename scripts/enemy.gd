extends CharacterBody3D

class_name Enemy

@onready var agent: NavigationAgent3D = $NavigationAgent3D

@export var color : Color
@export var fireSpeed := 0.2 # legacy, unused (see ranged_cooldown)
@export var attackPower := 20
@export var VIEW_ANGLE: float = 180.0

@export_group("Stats")
@export var health := 5.0
## Height above the enemy's feet (before scaling) that counts as a headshot. Capsule is 2 m tall.
@export var headshot_height := 1.6

@export_group("Senses")
@export var sight_range := 25.0
## Within this distance the enemy notices you even from behind
@export var close_sense_range := 2.5
## Sight range multiplier while the player is crouching
@export var crouch_sight_mult := 0.6
## Seconds of continuous visibility before the enemy is alerted
@export var reaction_time := 0.35
## Allies within this radius are alerted when this enemy spots the player
@export var alert_radius := 12.0

@export_group("Melee")
@export var attack_range: float = 1.5
@export var attack_windup := 0.45    # delay before the hit lands
@export var attack_cooldown := 0.9   # delay after the hit

@export_group("Ranged (off by default)")
@export var use_ranged := false
@export var ranged_damage := 8
@export var ranged_cooldown := 1.1
@export var ranged_range := 14.0
@export var ranged_inaccuracy := 3.0  # degrees
@export var projectile_speed := 28.0

@export_group("Movement")
@export var patrol_points: Array[Node3D] = []
@export var speed_walk: float = 1.7
@export var speed_run: float = 3.0
@export var investigate_wait_time: float = 4.0
@export var patrol_wait_time: float = 3.0
@export var update_interval: float = 0.2

@export_group("Stairs")
## Master switch for walking up/down stairs and small ledges (same technique as the player).
@export var use_stair_stepping := true
## Tallest step the enemy walks up/down, in world units (not affected by the enemy's scale).
## Stairs in the levels are 0.25 high; the extra 0.05 keeps float rounding from ever failing the check.
@export var max_step_height := 0.3
## Hide the instant jump of the body when it steps: the robot model eases back to its rest height
## (same idea as the player's camera smoothing).
@export var smooth_step_visuals := true

@export_group("Avoidance")
## Master switch. Off = old behaviour (walk straight through each other).
@export var use_avoidance := true
## Avoid radius. Roughly the capsule radius. enemy_2 is scaled x2, so bump it there.
@export var avoidance_radius := 0.6
## How far the agent looks for neighbours to avoid. Bigger = smoother but slower.
@export var avoidance_neighbor_distance := 6.0
## Upper bound on neighbours considered per frame.
@export var avoidance_max_neighbors := 8
## Seconds of lookahead used when steering around other agents.
@export var avoidance_time_horizon := 1.5

var bullet := preload("res://scenes/bullet.tscn")

@onready var vision_ray: RayCast3D = $VisionRay # used as the eye position
@onready var gun: Marker3D = $gun
@onready var engaged_timer := $EngagedTimer

@onready var death_audio_stream_player_3d := $DeathAudioStreamPlayer3D
@onready var hit_audio_stream_player_3d = $HitAudioStreamPlayer3D

@onready var model: Node3D = $CollisionShape3D/robot2
@onready var animation_player := $CollisionShape3D/robot2/AnimationPlayer
@onready var anim_player := $AnimPlayer

const SMOOTHING_FACTOR := 0.2
const SIGHT_CHECK_INTERVAL := 0.1
const LOSE_SIGHT_GRACE := 0.6
const PAIN_TIME := 0.25
const STEP_SMOOTH_LIMIT := 0.5 # max visual offset (model-local units) while smoothing a step

enum State { IDLE, PATROL, INVESTIGATE, CHASE, ATTACK, RETURN, SHOOT }
var state: State = State.IDLE

var is_dead := false
var max_health := 0.0 # read by FallDamage
var engaged := false
var is_attacking := false

var patrol_index := 0
var patrol_timer := 0.0
var investigate_timer := 0.0
var investigate_position: Vector3
var return_position: Vector3
var home_position: Vector3
var last_seen_position: Vector3
var target: Node3D
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var update_timer := 0.0

var awareness := 0.0
var _sees_player := false
var _sight_timer := 0.0
var _lost_sight_time := 0.0
var _pain_timer := 0.0
var _last_shot_time := -100.0

## True while the agent is on a live navigation map and its callback will fire.
## If false, we call move_and_slide() ourselves so the enemy still works in
## levels that have no NavigationRegion3D.
var _avoidance_active := false

# Stair stepping (ported from the player controller)
var _snapped_to_stairs_last_frame := false
var _last_frame_was_on_floor := -INF
var _model_rest_y := 0.0      # model's resting local height, read in _ready
var _model_smoothing := false
var _model_saved_y := 0.0     # model's world height that smoothing is easing from

@onready var fall_damage: FallDamage = $FallDamage

func _ready() -> void:
	add_to_group("enemies")
	max_health = health
	_model_rest_y = model.position.y
	vision_ray.enabled = false # kept only as the eye position; sight uses direct ray queries now

	# Sync the agent with our exports. The .tscn can still override these at
	# design time (they'll just get overwritten here, which is the point).
	agent.avoidance_enabled = use_avoidance
	if use_avoidance:
		agent.radius = avoidance_radius
		agent.neighbor_distance = avoidance_neighbor_distance
		agent.max_neighbors = avoidance_max_neighbors
		agent.time_horizon_agents = avoidance_time_horizon

	home_position = global_position
	return_position = home_position
	target = PlayerManager.player
	# FallDamage is a child node in the scene; it applies landing damage to this body
	_enter_state(State.IDLE if patrol_points.is_empty() else State.PATROL)

func _physics_process(delta: float) -> void:
	if is_dead:
		return # Completely stop all AI/movement logic
	if target == null:
		target = PlayerManager.player

	_update_senses(delta)
	_update_path(delta)
	_pain_timer = maxf(_pain_timer - delta, 0.0)

	match state:
		State.IDLE:        _state_idle()
		State.PATROL:      _state_patrol(delta)
		State.INVESTIGATE: _state_investigate(delta)
		State.CHASE:       _state_chase(delta)
		State.ATTACK:      _state_attack(delta)
		State.RETURN:      _state_return(delta)
		State.SHOOT:       _state_shoot(delta)

	_apply_gravity(delta)

	# Hand the desired horizontal velocity to the agent. When the map is live,
	# the agent steers around its neighbours and calls us back on
	# velocity_computed, where we actually move the body. When the map is not
	# live (no NavigationRegion3D, or server hasn't ticked yet) we fall back to
	# moving the body directly, exactly like before.
	_avoidance_active = use_avoidance and _is_navigation_ready()
	if _avoidance_active:
		agent.set_velocity(Vector3(velocity.x, 0.0, velocity.z))
	else:
		_move_with_stairs()

## Called by NavigationAgent3D once per physics frame while avoidance is live.
## safe_velocity already has the other agents' contributions baked in.
func _on_navigation_agent_3d_velocity_computed(safe_velocity: Vector3) -> void:
	if is_dead or not _avoidance_active:
		return
	# Only the horizontal component is under avoidance control; gravity is ours.
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z
	_move_with_stairs()

## True when the agent's navigation map exists and has been updated at least
## once, which is when NavigationServer3D starts returning avoidance results.
func _is_navigation_ready() -> bool:
	var map := agent.get_navigation_map()
	return map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0

# --------------------
# STAIRS
# --------------------
# Same technique as the player: before moving, test whether a step <= max_step_height sits
# right ahead and hop onto it; after moving, glue back down if we just walked off a step.
# The two RayCast3D nodes the player uses are replaced by direct ray queries, so the enemy
# scenes (enemy.tscn / enemy_2.tscn) need no changes.

## The one place the enemy actually moves. Everything that used to call move_and_slide() goes through here.
func _move_with_stairs() -> void:
	if not use_stair_stepping:
		move_and_slide()
		return
	var delta := get_physics_process_delta_time()
	# is_on_floor() still describes last frame's move at this point
	if is_on_floor():
		_last_frame_was_on_floor = Engine.get_physics_frames()
	if not _snap_up_stairs_check(delta):
		# _snap_up_stairs_check moves the body manually when it succeeds, so we skip move_and_slide then.
		move_and_slide()
		_snap_down_to_stairs_check()
	_smooth_step_visuals(delta)

func is_surface_too_steep(normal: Vector3) -> bool:
	return normal.angle_to(Vector3.UP) > floor_max_angle

## Ray straight down from `from` (world space), ignoring ourselves.
func _ray_down(from: Vector3, length: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
			from, from + Vector3.DOWN * length, collision_mask, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)

func _snap_down_to_stairs_check() -> void:
	var did_snap := false
	# Called right after move_and_slide: if we just walked off the top of a step, is_on_floor() is false now
	var floor_hit := _ray_down(global_position, 1.0)
	var floor_below: bool = not floor_hit.is_empty() and not is_surface_too_steep(floor_hit["normal"])
	var was_on_floor_last_frame := Engine.get_physics_frames() == _last_frame_was_on_floor
	if not is_on_floor() and velocity.y <= 0.0 and (was_on_floor_last_frame or _snapped_to_stairs_last_frame) and floor_below:
		var body_test_result := KinematicCollision3D.new()
		if test_move(global_transform, Vector3(0.0, -max_step_height, 0.0), body_test_result):
			_save_model_pos_for_smoothing()
			global_position.y += body_test_result.get_travel().y
			apply_floor_snap()
			did_snap = true
	_snapped_to_stairs_last_frame = did_snap

func _snap_up_stairs_check(delta: float) -> bool:
	if not is_on_floor() and not _snapped_to_stairs_last_frame:
		return false
	# Not while rising (jump/knockback), and no need to look for steps when (almost) standing still
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if velocity.y > 0.0 or horizontal.length_squared() < 0.0001:
		return false
	var expected_move_motion := horizontal * delta
	# Probe from slightly above where we expect to end up, looking down for a step
	# (the extra height is clearance for the body).
	var step_pos_with_clearance := global_transform.translated(
			expected_move_motion + Vector3(0.0, max_step_height * 2.0, 0.0))
	var down_check_result := KinematicCollision3D.new()
	if not test_move(step_pos_with_clearance, Vector3(0.0, -max_step_height * 2.0, 0.0), down_check_result):
		return false
	# Only level geometry counts as a step: never hop onto crates, the player or other enemies
	var collider := down_check_result.get_collider()
	if collider == null or not (collider.is_class("StaticBody3D") or collider.is_class("CSGShape3D")):
		return false
	var step_height := ((step_pos_with_clearance.origin + down_check_result.get_travel()) - global_position).y
	# <= 0.01 is not a step (also avoids jitter when running into a ceiling)
	if step_height > max_step_height or step_height <= 0.01 \
			or (down_check_result.get_position() - global_position).y > max_step_height:
		return false
	# Make sure there is walkable ground just past the edge of the step (not just a wall top)
	var ahead_origin := down_check_result.get_position() \
			+ Vector3(0.0, max_step_height, 0.0) + expected_move_motion.normalized() * 0.1
	var ahead_hit := _ray_down(ahead_origin, max_step_height + 0.05)
	if ahead_hit.is_empty() or is_surface_too_steep(ahead_hit["normal"]):
		return false
	_save_model_pos_for_smoothing()
	global_position = step_pos_with_clearance.origin + down_check_result.get_travel()
	apply_floor_snap()
	_snapped_to_stairs_last_frame = true
	return true

# The body teleports up/down a step in one frame. The robot model is parented to it, so it would
# visibly pop; instead keep it at its old world height and ease it back to rest.
func _save_model_pos_for_smoothing() -> void:
	if not smooth_step_visuals or _model_smoothing:
		return
	_model_smoothing = true
	_model_saved_y = model.global_position.y # called before the body moves

func _smooth_step_visuals(delta: float) -> void:
	if not _model_smoothing:
		return
	model.global_position.y = _model_saved_y
	var offset := clampf(model.position.y - _model_rest_y, -STEP_SMOOTH_LIMIT, STEP_SMOOTH_LIMIT)
	var speed := maxf(Vector2(velocity.x, velocity.z).length(), speed_walk * 0.5)
	offset = move_toward(offset, 0.0, speed * delta)
	model.position.y = _model_rest_y + offset
	_model_saved_y = model.global_position.y
	if is_zero_approx(offset):
		_model_smoothing = false

# --------------------
# SENSES
# --------------------
func _update_senses(delta: float) -> void:
	_sight_timer -= delta
	if _sight_timer <= 0.0:
		_sight_timer = SIGHT_CHECK_INTERVAL
		_sees_player = _check_line_of_sight()
	if _sees_player:
		last_seen_position = target.global_position
		awareness = minf(awareness + delta / maxf(reaction_time, 0.01), 1.0)
	else:
		awareness = maxf(awareness - delta * 0.5, 0.0)

## True once the enemy has seen the player long enough to be alerted
func _noticed() -> bool:
	return _sees_player and awareness >= 1.0

func _check_line_of_sight() -> bool:
	if target == null or target.get("is_dead") == true:
		return false
	var eye: Vector3 = vision_ray.global_position
	var target_eye: Vector3 = target.get_eye_position()
	var to_target := target_eye - eye
	var dist := to_target.length()

	var max_dist := sight_range
	if target.get("is_crouching") == true:
		max_dist *= crouch_sight_mult
	if dist > max_dist:
		return false

	if dist > close_sense_range:
		var flat := Vector3(to_target.x, 0.0, to_target.z)
		if flat.length() > 0.01:
			var angle := rad_to_deg((-global_basis.z).angle_to(flat.normalized()))
			if angle > VIEW_ANGLE * 0.5:
				return false

	# Closed doors, crates, walls... all block sight. Check head and torso.
	var space := get_world_3d().direct_space_state
	for point in [target_eye, target.global_position + Vector3(0, 0.6, 0)]:
		var query := PhysicsRayQueryParameters3D.create(eye, point)
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and hit["collider"] == target:
			return true
	return false

# --------------------
# STATE HANDLERS
# --------------------
func _state_idle() -> void:
	if _noticed():
		_enter_state(State.CHASE)

func _state_patrol(delta: float) -> void:
	if patrol_points.is_empty():
		_enter_state(State.IDLE)
		return
	if agent.is_navigation_finished():
		if patrol_timer <= 0.0:
			patrol_timer = patrol_wait_time
			_stop_and_idle()
		else:
			patrol_timer -= delta
			if patrol_timer <= 0.0:
				_go_to_next_patrol_point()
	else:
		_walk_to(agent.get_next_path_position(), speed_walk)
	if _noticed():
		_enter_state(State.CHASE)

func _state_investigate(delta: float) -> void:
	if agent.is_navigation_finished():
		if investigate_timer <= 0.0:
			investigate_timer = investigate_wait_time
			_stop_and_idle()
		else:
			investigate_timer -= delta
			if investigate_timer <= 0.0:
				_enter_state(State.RETURN)
	else:
		_walk_to(agent.get_next_path_position(), speed_walk)
	if _noticed():
		_enter_state(State.CHASE)

func _state_chase(delta: float) -> void:
	if target == null or target.get("is_dead") == true:
		_enter_state(State.RETURN)
		return
	var dist := global_position.distance_to(target.global_position)

	if _sees_player:
		_lost_sight_time = 0.0
		if use_ranged and dist > attack_range * 1.5 and dist <= ranged_range:
			_enter_state(State.SHOOT)
			return
	else:
		_lost_sight_time += delta
		if _lost_sight_time >= LOSE_SIGHT_GRACE:
			# Go where we LAST saw the player (not where they are now)
			investigate_position = last_seen_position
			_enter_state(State.INVESTIGATE)
			return

	if dist < attack_range and not is_attacking:
		_enter_state(State.ATTACK)
		return
	_walk_to(agent.get_next_path_position(), speed_run)

func _state_attack(delta: float) -> void:
	_face_target(delta)
	if is_attacking:
		return
	if target == null or target.get("is_dead") == true:
		_enter_state(State.RETURN)
		return
	if global_position.distance_to(target.global_position) > attack_range + 0.3:
		_enter_state(State.CHASE)
		return
	_do_melee_attack()

func _do_melee_attack() -> void:
	is_attacking = true
	velocity.x = 0.0
	velocity.z = 0.0
	animation_player.play("attackwithhand")
	await get_tree().create_timer(attack_windup, false).timeout
	if is_dead:
		return
	deal_attack_damage()
	await get_tree().create_timer(attack_cooldown, false).timeout
	is_attacking = false

func deal_attack_damage() -> void:
	if is_dead or not is_attacking:
		return
	if target and target.has_method("takeDamage"):
		if global_position.distance_to(target.global_position) <= attack_range + 0.3:
			var to_target := (target.global_position - global_position).normalized()
			if (-global_basis.z).normalized().dot(to_target) > 0.3: # must actually be facing the player
				target.takeDamage(attackPower, self, global_position)

func _state_shoot(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_face_target(delta, 10.0)
	if target == null or target.get("is_dead") == true:
		_enter_state(State.RETURN)
		return
	if not _sees_player:
		investigate_position = last_seen_position
		_enter_state(State.INVESTIGATE)
		return
	var dist := global_position.distance_to(target.global_position)
	if dist < attack_range:
		_enter_state(State.ATTACK)
		return
	if dist > ranged_range * 1.15:
		_enter_state(State.CHASE)
		return
	_play_anim("iddle")
	if _now() - _last_shot_time >= ranged_cooldown:
		_fire()

func _state_return(_delta: float) -> void:
	if agent.is_navigation_finished():
		_enter_state(State.PATROL)
	elif _noticed():
		_enter_state(State.CHASE)
	else:
		_walk_to(agent.get_next_path_position(), speed_walk)

# --------------------
# HELPERS
# --------------------
func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _enter_state(new_state: State) -> void:
	var previous := state
	state = new_state
	match state:
		State.PATROL:
			patrol_timer = 0
			_go_to_next_patrol_point()
		State.INVESTIGATE:
			investigate_timer = 0.0
			agent.set_target_position(investigate_position)
		State.CHASE:
			_lost_sight_time = 0.0
			if previous not in [State.CHASE, State.ATTACK, State.SHOOT]:
				_alert_allies()
		State.RETURN:
			agent.set_target_position(return_position)

func _update_agent_target() -> void:
	match state:
		State.PATROL:
			if patrol_points.size() > 0:
				agent.set_target_position(patrol_points[patrol_index].global_transform.origin)
		State.INVESTIGATE:
			agent.set_target_position(investigate_position)
		State.CHASE:
			if target:
				agent.set_target_position(target.global_transform.origin)
		State.RETURN:
			agent.set_target_position(return_position)

func _play_anim(anim_name: String) -> void:
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name)

func _walk_to(next_pos: Vector3, speed: float) -> void:
	_play_anim("walking")
	_move_towards(next_pos, speed * (0.4 if _pain_timer > 0.0 else 1.0))

func _stop_and_idle() -> void:
	velocity = Vector3.ZERO
	_play_anim("iddle")

func _go_to_next_patrol_point() -> void:
	if patrol_points.is_empty():
		return
	patrol_index = (patrol_index + 1) % patrol_points.size()
	agent.set_target_position(patrol_points[patrol_index].global_transform.origin)

func _move_towards(next_pos: Vector3, speed: float) -> void:
	var dir := (next_pos - global_transform.origin)
	dir.y = 0.0
	if is_zero_approx(dir.length()):
		velocity.x = lerp(velocity.x, 0.0, SMOOTHING_FACTOR)
		velocity.z = lerp(velocity.z, 0.0, SMOOTHING_FACTOR)
		return
	dir = dir.normalized()
	var current_facing := (-global_transform.basis.z).normalized()
	var new_dir := current_facing.slerp(dir, 0.12).normalized()
	look_at(global_transform.origin + new_dir, Vector3.UP)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

func _face_target(delta: float, turn_speed := 8.0) -> void:
	if target == null:
		return
	var dir := target.global_position - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return
	var desired := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, desired, clampf(turn_speed * delta, 0.0, 1.0))

func _update_path(delta: float) -> void:
	update_timer -= delta
	if update_timer <= 0.0:
		_update_agent_target()
		update_timer = update_interval

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

func _alert_allies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and e.global_position.distance_to(global_position) <= alert_radius \
				and e.has_method("hear_noise"):
			e.hear_noise(last_seen_position)

# --------------------
# RANGED ATTACK
# --------------------
func _fire() -> void:
	_last_shot_time = _now()
	var origin: Vector3 = gun.global_position
	var aim_point: Vector3 = target.get_eye_position() - Vector3(0, 0.3, 0)
	var dir := CombatFX.spread_direction((aim_point - origin).normalized(), ranged_inaccuracy)
	var b := bullet.instantiate()
	b.damage = ranged_damage
	b.shooter = self
	b.speed = projectile_speed
	get_parent().add_child(b)
	b.global_position = origin
	b.set_direction(dir)
	CombatFX.muzzle_flash(gun, Color(1.0, 0.3, 0.2))

# --------------------
# SOUND & DAMAGE
# --------------------
func hear_noise(pos: Vector3) -> void:
	if is_dead:
		return
	if state not in [State.CHASE, State.ATTACK, State.SHOOT]:
		investigate_position = pos
		_enter_state(State.INVESTIGATE)

func is_headshot(hit_pos: Vector3) -> bool:
	return hit_pos.y - global_position.y >= headshot_height * global_basis.get_scale().y # enemy_2 is scaled x2

# Damage convention used by everything damageable in the game:
# takeDamage(dmg, source = who did it, hit_pos = where it landed)
func takeDamage(dmg: float, source: Node = null, _hit_pos: Vector3 = Vector3.ZERO) -> void:
	if is_dead:
		return
	health -= dmg
	hit_audio_stream_player_3d.play()
	engaged = true
	engaged_timer.start()
	_pain_timer = PAIN_TIME
	if health <= 0.0:
		_die()
		return
	# Being shot makes us react even if we can't see the shooter
	if source is Node3D:
		last_seen_position = source.global_position
		awareness = maxf(awareness, 0.6)
		if state not in [State.CHASE, State.ATTACK, State.SHOOT]:
			investigate_position = source.global_position
			_enter_state(State.INVESTIGATE)

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	_model_smoothing = false
	remove_from_group("enemies")
	velocity = Vector3.ZERO
	# Stop asking the agent for safe velocities; our callback would just no-op anyway.
	agent.avoidance_enabled = false
	$CollisionShape3D.set_deferred("disabled", true)
	set_physics_process(false)
	death_audio_stream_player_3d.play()
	anim_player.play("death")

func _on_anim_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "death":
		queue_free()

func _hit_finished() -> void:
	# Kept for animation call-tracks; damage is now dealt by the melee timer
	if target and target.has_method("hit"):
		target.hit()

func _on_engaged_timeout() -> void:
	engaged = false
