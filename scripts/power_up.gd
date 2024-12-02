extends Area3D

enum Type {
	health,
	ammo
}

@export var type := Type.health

@export var qty:int

@onready var pack = $Mesh
@onready var respawnTimer = $respawn
@onready var label = $Mesh/Label

var collectable = true

func _ready():
	var mat = StandardMaterial3D.new()
	if type == Type.health:
		label.text = "Health"
		mat.set_albedo(Color(0,1,0,1))
	if type == Type.ammo:
		label.text = "Ammo"
		mat.set_albedo(Color(1,0,0,1))
	
	pack.set_surface_override_material(0, mat)

func _process(delta):
	pack.rotation.y += 1 * delta

func _on_body_entered(body):
	if type == Type.health:
		body.gainHealth(qty)
	elif type == Type.ammo:
		body.gainAmmo(qty)
	pack.visible = false
	respawnTimer.start()

func _on_respawn_timeout():
	collectable = true
	pack.visible = true
