extends Node3D
## Enemy projectile. Moves in the physics step and sweeps a ray along its path,
## so it can't tunnel through thin walls. Damages anything with takeDamage().

@export var speed := 40.0
@export_flags_3d_physics var collision_mask := 0xFFFFFFFF
@export var impact_impulse := 2.0

var damage := 10.0
var velocity := Vector3.ZERO
var shooter: Node = null # Never hits its own shooter

@onready var bullet_mesh := get_node_or_null("BulletMesh")
@onready var ray_cast_3d := get_node_or_null("RayCast3D")

func _ready() -> void:
	# The old RayCast3D child isn't needed any more (direct space queries are used)
	if ray_cast_3d:
		ray_cast_3d.enabled = false

func set_direction(dir: Vector3) -> void:
	dir = dir.normalized()
	velocity = dir * speed
	var up_hint := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	look_at(global_position + dir * 10.0, up_hint)

func _physics_process(delta: float) -> void:
	if velocity == Vector3.ZERO:
		return
	var from := global_position
	var to := from + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	if shooter is CollisionObject3D:
		query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = to
		return
	global_position = hit["position"]
	_on_hit(hit["collider"], hit["position"], hit["normal"])

func _on_hit(collider: Object, pos: Vector3, normal: Vector3) -> void:
	var hurt := false
	if collider and collider.has_method("takeDamage"):
		collider.takeDamage(int(round(damage)), shooter, pos)
		hurt = true
	elif collider is RigidBody3D:
		collider.apply_impulse(velocity.normalized() * impact_impulse, pos - collider.global_position)
	CombatFX.spawn_impact(get_parent(), pos, normal, Color(1, 0.25, 0.2) if hurt else Color(1, 0.6, 0.3))
	velocity = Vector3.ZERO
	if bullet_mesh:
		bullet_mesh.visible = false
	queue_free()

# Called by the Timer node in bullet.tscn: cleanup if the bullet misses everything.
func _on_timer_timeout() -> void:
	queue_free()
