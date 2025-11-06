extends CharacterBody3D
 
@onready var agent = $NavigationAgent3D
 
@export var color : Color
# @export var aggroRange := 5.0
@export var fireSpeed := 0.2
@export var attackPower := 1

var health := 10
var material
var bullet = preload("res://scenes/bullet.tscn")

@onready var vision_ray = $VisionRay
@onready var gun = $gun
@onready var engaged_timer = $EngagedTimer

var lastShot := 0.0
var engaged := false

const ATTACK_RANGE := 2.5

const UPDATE_TIME := 0.2
const SPEED := 150
const VIEW_ANGLE: float = 190.0
const SMOOTHING_FACTOR := 0.2
 
# --------------------
# STATE MACHINE
# --------------------
enum State { IDLE, PATROL, INVESTIGATE, CHASE, ATTACK, RETURN }
var state: State = State.IDLE

var target
var update_timer := 0.0
 
func _ready():
	target = PlayerManager.player
	var mat = StandardMaterial3D.new()
	mat.emission_enabled = true
	$%body.set_surface_override_material(0, mat)
	$%nose.set_surface_override_material(1, mat)
	material = mat
 
func _physics_process(delta):
	move_to_agent(delta)
 
func set_target(pos = target.position):
	agent.set_target_position(pos)
 
func move_to_agent(delta: float, speed: float = SPEED):
	update_timer -= delta
	if update_timer <= 0.0:
		update_timer = UPDATE_TIME
		if target:
			set_target(target.position)
 
	if not is_on_floor():
		velocity += get_gravity() * delta
		move_and_slide()
		return
 
	if agent.is_navigation_finished():
		return
 
	var next_pos = agent.get_next_path_position()
	var dir = (next_pos - global_position).normalized()
	dir.y = 0
 
	var current_facing = -global_transform.basis.z
	var new_dir = current_facing.slerp(dir, SMOOTHING_FACTOR).normalized()
	look_at(global_position + new_dir, Vector3.UP)
 
	velocity = velocity.lerp(dir * speed * delta, SMOOTHING_FACTOR)
	move_and_slide()

func takeDamage(dmg):
	health -= dmg
	engaged = true
	engaged_timer.start()
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
	var b = bullet.instantiate() # Create the bullet instance.
	b.damage = attackPower # Set the bullet's damage value.
	b.shooter = self # Assign the enemy as the shooter of the bullet.
	b.global_transform = gun.global_transform # Position the bullet at the gun's location.
	get_parent().add_child(b) # Add the bullet to the scene.

func _target_in_range():
	return global_position.distance_to(target.global_position) < ATTACK_RANGE

func _hit_finished():
	target.hit()

func _on_engaged_timeout():
	engaged = false
