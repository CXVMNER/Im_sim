extends Node3D

@onready var interactable: InteractableComponent = $InteractableComponent

var picked_up: bool = false

func _ready() -> void:
	interactable.interacted.connect(_on_interacted)

func _on_interacted() -> void:
	if picked_up:
		return
	picked_up = true
	disappear()

func disappear() -> void:
	# Option 1: just hide it
	# visible = false

	# Option 2: remove from scene completely
	queue_free()
