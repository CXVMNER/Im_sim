extends Control

@onready var overlay := $Overlay
@onready var updates := $HUDUpdate
@onready var interaction_label := $InteractionLabel

@onready var healthValue := $%health
@onready var ammoValue := $%ammo
@onready var staminaValue := $%stamina

@onready var keys_label := $MarginContainer2/VBoxContainer/HBoxContainer/KeysLabel

var health : int
var ammo : int
var stamina : int

var item := preload("res://scenes/hud_item.tscn")

var hitmarker: Label
var _hit_tween: Tween

func _ready() -> void:
	healthValue.text = str(health)
	ammoValue.text = str(ammo)
	staminaValue.text = str(stamina)
	_configure_interaction_label()
	_build_hitmarker()

func _configure_interaction_label() -> void:
	if interaction_label == null:
		return
	interaction_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	interaction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	interaction_label.add_theme_font_size_override("font_size", 18)
	interaction_label.add_theme_color_override("font_color", Color(0.94, 0.96, 0.94, 0.95))
	interaction_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	interaction_label.add_theme_constant_override("outline_size", 6)
	interaction_label.set_anchors_preset(Control.PRESET_CENTER)
	interaction_label.offset_left = -240.0
	interaction_label.offset_top = 26.0
	interaction_label.offset_right = 240.0
	interaction_label.offset_bottom = 90.0
	interaction_label.text = ""
	interaction_label.visible = false

func set_interaction_prompt(text: String) -> void:
	if interaction_label == null:
		return
	var next := text.strip_edges()
	if interaction_label.text == next and interaction_label.visible == (next != ""):
		return
	interaction_label.text = next
	interaction_label.visible = next != ""

# Crosshair hit confirmation, built in code so no scene changes are needed
func _build_hitmarker() -> void:
	hitmarker = Label.new()
	hitmarker.text = "×"
	hitmarker.add_theme_font_size_override("font_size", 40)
	hitmarker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hitmarker.modulate.a = 0.0
	add_child(hitmarker)
	hitmarker.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hitmarker.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hitmarker.grow_vertical = Control.GROW_DIRECTION_BOTH
	hitmarker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hitmarker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func show_hitmarker(killed := false, headshot := false) -> void:
	if hitmarker == null:
		return
	if killed:
		hitmarker.modulate = Color(1, 0.15, 0.1, 1)
	elif headshot:
		hitmarker.modulate = Color(1, 0.85, 0.2, 1)
	else:
		hitmarker.modulate = Color(1, 1, 1, 1)
	if _hit_tween:
		_hit_tween.kill()
	_hit_tween = create_tween()
	_hit_tween.tween_property(hitmarker, "modulate:a", 0.0, 0.25)

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

func update_keys(current_keys: Array[String], collected_keys: Array[String], total_in_level: int) -> void:
	var text := "Keys to collect %d/%d\nCollected keys:\n" % [current_keys.size(), total_in_level]
	for key_name in collected_keys:
		text += " - %s\n" % key_name
	keys_label.text = text
