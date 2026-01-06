extends CharacterBody3D

class_name Enemy
 
@onready var agent := $NavigationAgent3D
 
@export var color : Color
@export var fireSpeed := 0.2
@export var attackPower := 20
@export var VIEW_ANGLE: float = 180.0

var is_dead := false

@export var health := 5
var bullet := preload("res://scenes/bullet.tscn")

@onready var vision_ray := $VisionRay
@onready var gun := $gun
@onready var engaged_timer := $EngagedTimer

@onready var death_audio_stream_player_3d := $DeathAudioStreamPlayer3D

var lastShot := 0.0
var engaged := false

const SMOOTHING_FACTOR := 0.2
@onready var animation_player := $CollisionShape3D/robot2/AnimationPlayer
@onready var anim_player := $AnimPlayer

# --------------------
# CONFIG
# --------------------
@export var patrol_points: Array[Node3D] = []
@export var speed_walk: float = 1.7
@export var speed_run: float = 3.0
@export var attack_range: float = 1.5
@export var investigate_wait_time: float = 4.0
@export var patrol_wait_time: float = 3.0
@export var update_interval: float = 0.2

# --------------------
# STATE MACHINE
# --------------------
enum State { IDLE, PATROL, INVESTIGATE, CHASE, ATTACK, RETURN }
var state: State = State.IDLE

var patrol_index := 0
var patrol_timer := 0.0
var investigate_timer := 0.0
var investigate_position: Vector3
var return_position: Vector3
var target: Node3D
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var update_timer := 0.0

var is_attacking := false

func _ready() -> void:
	target = PlayerManager.player
	_enter_state(State.IDLE if patrol_points.is_empty() else State.PATROL)

func _physics_process(delta: float) -> void:
	if is_dead:
		return # Completely stop all AI/movement logic
	
	_update_path(delta)
 
	match state:
		State.IDLE:        _state_idle()
		State.PATROL:      _state_patrol(delta)
		State.INVESTIGATE: _state_investigate(delta)
		State.CHASE:       _state_chase(delta)
		State.ATTACK:      _state_attack()
		State.RETURN:      _state_return(delta)
 
	_looking()
	_apply_gravity(delta)
	move_and_slide()

# --------------------
# STATE HANDLERS
# --------------------
func _state_idle() -> void:
	if _can_see_player():
		_enter_state(State.CHASE)

func _state_patrol(delta: float) -> void:
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
	if _can_see_player():
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
	if _can_see_player():
		_enter_state(State.CHASE)

func _state_chase(delta: float) -> void:
	if not target:
		_enter_state(State.RETURN)
		return
	_walk_to(agent.get_next_path_position(), speed_run)
	if global_transform.origin.distance_to(target.global_transform.origin) < attack_range and not is_attacking:
		_enter_state(State.ATTACK)
	elif not _can_see_player():
		investigate_position = target.global_transform.origin
		_enter_state(State.INVESTIGATE)

func _state_attack() -> void:
	if is_attacking:
		return
	is_attacking = true
	velocity = Vector3.ZERO
	animation_player.play("attackwithhand")
	await animation_player.animation_finished
	deal_attack_damage()
	if target:
		var current_dist = global_transform.origin.distance_to(target.global_transform.origin)
		if current_dist > attack_range:
			_enter_state(State.CHASE)
	is_attacking = false

func deal_attack_damage() -> void:
	if is_dead or is_attacking == false:  # extra safety
		return
	if target and target.has_method("takeDamage"):
		if global_position.distance_to(target.global_position) <= attack_range + 0.3:
			target.takeDamage(attackPower)

func _state_return(delta: float) -> void:
	if agent.is_navigation_finished():
		_enter_state(State.PATROL)
	elif _can_see_player():
		_enter_state(State.CHASE)
	else:
		_walk_to(agent.get_next_path_position(), speed_walk)

# --------------------
# HELPERS
# --------------------
func _enter_state(new_state: State) -> void:
	state = new_state
	match state:
		State.PATROL:
			patrol_timer = 0
			_go_to_next_patrol_point()
		State.INVESTIGATE:
			investigate_timer = 0.0
			agent.set_target_position(investigate_position)
		State.CHASE, State.INVESTIGATE:
			return_position = global_transform.origin

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

func _walk_to(next_pos: Vector3, speed: float) -> void:
	animation_player.play("walking")
	_move_towards(next_pos, speed)

func _stop_and_idle() -> void:
	velocity = Vector3.ZERO
	animation_player.play("iddle")

func _go_to_next_patrol_point() -> void:
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
	var current_facing := -global_transform.basis.z
	var new_dir := current_facing.slerp(dir, 0.12).normalized()
	look_at(global_transform.origin + new_dir, Vector3.UP)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed

func _update_path(delta) -> void:
	update_timer -= delta
	if update_timer <= 0.0:
		_update_agent_target()
		update_timer = update_interval

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

# --------------------
# VISION
# --------------------
func _can_see_player() -> bool:
	return target and vision_ray.is_colliding() and vision_ray.get_collider() == target

func _looking() -> void:
	if not target:
		return
	var target_eye_pos = target.get_eye_position() # Function from fpp_controller.gd
	var to_player = (target_eye_pos - vision_ray.global_transform.origin).normalized()
	var forward := -global_transform.basis.z
	var angle_deg := rad_to_deg(acos(clamp(forward.dot(to_player), -1.0, 1.0)))
	if angle_deg > VIEW_ANGLE * 0.5:
		return
	var ray_forward = -vision_ray.global_transform.basis.z
	var new_dir = ray_forward.slerp(to_player, SMOOTHING_FACTOR).normalized()
	vision_ray.look_at(vision_ray.global_transform.origin + new_dir, Vector3.UP)

# --------------------
# SOUND & DAMAGE
# --------------------
func hear_noise(pos: Vector3) -> void:
	if state not in [State.CHASE, State.ATTACK]:
		investigate_position = pos
		_enter_state(State.INVESTIGATE)

func takeDamage(dmg: int) -> void:
	health -= dmg
	print("Enemy hit! Damage: %d | Health Left: %d" % [dmg, health])
	engaged = true
	engaged_timer.start()
	if health < 1 and not is_dead:
		_die()
		# anim_player.play("death")
		# $CollisionShape3D.set_deferred("disabled", true)
		# agent.set_deferred("navigation_enabled", false)
		# queue_free()
	# var tween = get_tree().create_tween()
	# tween.tween_property(material, "emission", Color(2, 1, 1, 1), 0.02)
	# tween.tween_property(material, "emission", Color(0, 0, 0, 1), 0.2)

func _die() -> void:
	is_dead = true
	velocity = Vector3.ZERO
	$CollisionShape3D.set_deferred("disabled", true)
	if agent: agent.set_deferred("navigation_enabled", false)
	set_physics_process(false)
	death_audio_stream_player_3d.play()
	anim_player.play("death")

func _on_anim_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "death":
		queue_free()

func _fire() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < lastShot + fireSpeed:
		return
	lastShot = now
	var b := bullet.instantiate() # Create the bullet instance.
	b.damage = attackPower # Set the bullet's damage value.
	b.shooter = self # Assign the enemy as the shooter of the bullet.
	b.global_transform = gun.global_transform # Position the bullet at the gun's location.
	get_parent().add_child(b) # Add the bullet to the scene.

func _hit_finished() -> void:
	target.hit()

func _on_engaged_timeout() -> void:
	engaged = false
