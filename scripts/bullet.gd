extends Node3D

var speed := 40.0
var damage := 1
var velocity := Vector3.ZERO
var shooter = null # Prevents bullet from hitting the player immediately

@onready var mesh_instance_3d := $MeshInstance3D
@onready var ray_cast_3d := $GunRayCast3D

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	# 1. Calculate the travel vector for this frame
	var motion = velocity * delta
	
	# Set the ray's target to the end of the travel path for the sweep test
	var forward_dir = ray_cast_3d.target_position.normalized()
	ray_cast_3d.target_position = forward_dir * motion.length() 
	ray_cast_3d.force_raycast_update()
	
	if ray_cast_3d.is_colliding():
		var collider = ray_cast_3d.get_collider()
		
		# 2. Collision detected: Apply damage and clean up
		if collider != shooter:
			# If the object has a takeDamage method (Enemy, Crates, etc.), call it
			if collider.has_method("takeDamage"):
				collider.takeDamage(damage)
			
			# Move bullet to the exact collision point for visual accuracy
			var collision_point: Vector3 = ray_cast_3d.get_collision_point()
			var distance_to_hit: float = ray_cast_3d.global_position.distance_to(collision_point)
			position += velocity.normalized() * distance_to_hit

			# Cleanup
			mesh_instance_3d.visible = false
			ray_cast_3d.enabled = false
			queue_free()
			return
	
	# 3. No collision, move the bullet forward
	position += motion
	
func _set_velocity(target) -> void:
	# Align the bullet's forward (-Z) with the direction to the target
	look_at(target)
	velocity = position.direction_to(target) * speed

# Function called by the Timer node (set to 10.0s in bullet.tscn)
# This handles the cleanup if the bullet misses everything.
func _on_timer_timeout() -> void:
	# Safely delete the bullet after the timer runs out
	queue_free()
