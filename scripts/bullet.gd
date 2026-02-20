extends Node3D

var speed := 40.0
var velocity := Vector3.ZERO
var shooter = null # Prevents bullet from hitting the player immediately

@onready var bullet_mesh := $BulletMesh
@onready var ray_cast_3d := $RayCast3D

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	# Calculate the travel vector for this frame
	var motion := velocity * delta
	
	# Set the ray's target to the end of the travel path for the sweep test
	var forward_dir = ray_cast_3d.target_position.normalized()
	ray_cast_3d.target_position = forward_dir * motion.length() 
	ray_cast_3d.force_raycast_update()
	
	if ray_cast_3d.is_colliding():
		var collider = ray_cast_3d.get_collider()
		
		# Collision detected: Apply damage and clean up
		if collider != shooter:
			# If the object has a takeDamage method (Enemy, Crates, etc.), call it
# 			if collider.has_method("takeDamage"):
# 				collider.takeDamage(damage)
			
			# Move bullet to the exact collision point for visual accuracy
			var collision_point: Vector3 = ray_cast_3d.get_collision_point()
			var distance_to_hit: float = ray_cast_3d.global_position.distance_to(collision_point)
			position += velocity.normalized() * distance_to_hit

			# Cleanup
			bullet_mesh.visible = false
			ray_cast_3d.enabled = false
			queue_free()
			return
	
	# No collision, move the bullet forward
	position += motion
	
func set_direction(dir: Vector3) -> void:
	velocity = dir * speed
	
	# Optional: rotate visual mesh/bullet model to face travel direction
	# (only if bullet mesh looks better when rotated)
	look_at(global_position + dir * 10.0, Vector3.UP)

# Function called by the Timer node (set to 10.0s in bullet.tscn)
# This handles the cleanup if the bullet misses everything.
func _on_timer_timeout() -> void:
	# Safely delete the bullet after the timer runs out
	queue_free()
