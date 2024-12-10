extends RigidBody3D

var speed = 40.0
var damage = 1

func _ready():
	linear_velocity = transform.basis * Vector3(0, 0, -speed)

func _on_body_entered(body):
	if body.get("health"):
		body.takeDamage(damage)
	queue_free()  # Delete the bullet after it hits something.

# This function makes sure the bullet gets deleted after a certain time if it hasn't hit anything.
func _on_timer_timeout():
	if !is_queued_for_deletion():
		queue_free()
