extends Node3D

var speed := 40.0
var damage := 1
@onready var mesh_instance_3d = $MeshInstance3D
@onready var ray_cast_3d = $GunRayCast3D

func _ready():
	pass
	#linear_velocity = transform.basis * Vector3(0, 0, -speed)

#func _on_body_entered(body):
#	if body.get("health"):
#		body.takeDamage(damage)
#	queue_free()  # Delete the bullet after it hits something.

# This function makes sure the bullet gets deleted after a certain time if it hasn't hit anything.
# func _on_timer_timeout():
# 	if !is_queued_for_deletion():
# 		queue_free()

func _process(delta):
	position += transform.basis * Vector3(0, 0, -speed) * delta
	if ray_cast_3d.is_colliding():
		mesh_instance_3d.visible = false
		ray_cast_3d.enabled = false
		if ray_cast_3d.get_collider().is_in_group("enemies"):
			print("enemy hit by gun")
			ray_cast_3d.get_collider().takeDamage(1)
		queue_free()

func _on_timer_timeout():
	queue_free()
