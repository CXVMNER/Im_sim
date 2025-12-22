extends Control

@onready var overlay := $Overlay
@onready var updates := $HUDUpdate
@onready var interaction_label := $InteractionLabel

@onready var healthValue := $%health
@onready var ammoValue := $%ammo
@onready var staminaValue := $%stamina

@onready var keys_label = $MarginContainer2/VBoxContainer/HBoxContainer/KeysLabel

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
	
func update_keys(collected_keys: Array[String], total_keys: int) -> void:
	var text := "Keys collected %d/%d:\n" % [collected_keys.size(), total_keys]
	for key_name in collected_keys:
		text += " - %s\n" % key_name
	keys_label.text = text
