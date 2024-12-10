extends RigidBody3D

var speed = 40.0
var damage = 1
var shooter : CharacterBody3D = null  # Reference to the enemy who shot this bullet.

func _ready():
	linear_velocity = transform.basis * Vector3(0, 0, -speed)

# Detect collisions with other bodies (e.g., the enemy who shot this bullet)
func _on_body_entered(body):
	# If the body that was hit has a 'health' property (which means it's a character), check for the shooter.
	if body.get("health") and body != shooter:
		body.takeDamage(damage)  # Damage the character that was hit, but not the shooter.
	elif body == shooter:
		# If the bullet hits the shooter (the enemy who shot it), apply damage to the shooter (suicide).
		shooter.takeDamage(damage)
	
	queue_free()  # Delete the bullet after it hits something.

# This function makes sure the bullet gets deleted after a certain time if it hasn't hit anything.
func _on_timer_timeout():
	if !is_queued_for_deletion():
		queue_free()
