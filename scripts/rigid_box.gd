extends RigidBody3D
class_name RigidBox

@export var groundDampSpeed: float = 1.0

#func _physics_process(delta):
#	if get_colliding_bodies().size() > 0:
#		linear_velocity = lerp(linear_velocity, Vector3.ZERO, groundDampSpeed * delta)
