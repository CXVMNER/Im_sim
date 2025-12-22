extends Control

@onready var overlay := $Overlay
@onready var updates := $HUDUpdate
@onready var interaction_label := $InteractionLabel

@onready var healthValue := $%health
@onready var ammoValue := $%ammo
@onready var staminaValue := $%stamina

var health : int
var ammo : int
var stamina : int

var item := preload("res://scenes/hud_item.tscn")

func _ready() -> void:
	healthValue.text = str(health)
	ammoValue.text = str(ammo)
	staminaValue.text = str(stamina)
	
func updateHud() -> void:
	healthValue.text = str(health)
	ammoValue.text = str(ammo)
	staminaValue.text = str(stamina)
	
func addUpdate(qty, text, color) -> void:
	var lab := item.instantiate()
	lab.text = str(qty) + " " + text
	lab.set_modulate(color)
	updates.add_child(lab)

func screenGlow(color) -> void:
	var tween := get_tree().create_tween()
	tween.tween_property(overlay, "color", color, 0.1)
	tween.tween_property(overlay, "color", Color(1,0,0,0), 0.7)
