extends Control

@export var ammo := 200
@export var stamina := 100

@onready var healthValue = $"%health"
@onready var ammoValue = $"%ammo"
@onready var staminaValue = $"%stamina"

@onready var updates = $HUDUpdate
@onready var overlay = $Overlay

var health
var item = preload("res://scenes/hud_item.tscn")

func _ready():
	healthValue.text = str(health)
	ammoValue.text = str(ammo)
	staminaValue.text = str(stamina)
	
func updateHud():
	healthValue.text = str(health)
	ammoValue.text = str(ammo)
	staminaValue.text = str(stamina)
	
func addUpdate(qty, text, color):
	var lab = item.instantiate()
	lab.text = str(qty) + " " + text
	lab.set_modulate(color)
	updates.add_child(lab)

func screenGlow(color):
	var tween = get_tree().create_tween()
	tween.tween_property(overlay, "color", color, 0.1)
	tween.tween_property(overlay, "color", Color(1,0,0,0), 0.7)
	
func gameOver():
	var tween = get_tree().create_tween()
	tween.tween_property(overlay, "color", Color(1,0,0,1), 0.1)
	$Reset.visible = true

func _on_reset_pressed():
	get_tree().set_pause(false)
	get_tree().reload_current_scene()
