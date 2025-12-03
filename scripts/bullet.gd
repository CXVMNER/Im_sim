extends Node3D

var speed := 40.0
var damage := 1
var velocity := Vector3.ZERO
var shooter = null # Added to prevent bullet hitting the shooter immediately

@onready var mesh_instance_3d = $MeshInstance3D
@onready var ray_cast_3d = $GunRayCast3D

func _ready():
	pass

func _process(delta):
	# Calculate the travel vector for this frame
	var motion = velocity * delta
	
	# The RayCast3D is used for a continuous sweep test along the path.
	# 1. Set the ray's target to the end of the travel path for the sweep test.
	var forward_dir = ray_cast_3d.target_position.normalized()
	# The RayCast's length is set to the distance the bullet will travel this frame.
	ray_cast_3d.target_position = forward_dir * motion.length() 
	ray_cast_3d.force_raycast_update()
	
	if ray_cast_3d.is_colliding():
		var collider = ray_cast_3d.get_collider()
		
		# 2. Collision detected: Apply damage and clean up.
		
		# Get the collision point and calculate the distance traveled before impact.
		var collision_point: Vector3 = ray_cast_3d.get_collision_point()
		# Distance to hit is the distance between the bullet's current position and the hit point.
		var distance_to_hit: float = ray_cast_3d.global_position.distance_to(collision_point) 

		# Check if the bullet is hitting an enemy (and not the shooter)
		if collider != shooter:
			if collider.is_in_group("enemies"):
				print("enemy hit by gun")
				collider.takeDamage(damage)
			elif collider.has_method("takeDamage"):
				# Handle other damageable objects
				collider.takeDamage(damage)
			
			# Move the bullet to the exact collision point for visual accuracy
			# We use the calculated distance_to_hit to move the bullet along its velocity vector.
			position += velocity.normalized() * distance_to_hit

			# Hide the visual and remove the raycast before queuing for deletion
			mesh_instance_3d.visible = false
			ray_cast_3d.enabled = false
			queue_free()
			return # Stop processing after collision
	
	# 3. No collision, move the bullet forward for this frame.
	position += motion
	
func _set_velocity(target):
	# Align the bullet's forward (-Z) with the direction to the target
	look_at(target)
	velocity = position.direction_to(target) * speed

# Function called by the Timer node (set to 10.0s in bullet.tscn)
# This handles the cleanup if the bullet misses everything.
func _on_timer_timeout():
	# Safely delete the bullet after the timer runs out
	queue_free()
