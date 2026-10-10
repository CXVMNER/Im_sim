extends Control
## HUD driver.
## Layout, fonts and colours live in scenes/HUD.tscn and ui_theme.tres.
## This script only pushes values into those widgets. The player keeps setting
## health, ammo and stamina exactly as before, and each setter refreshes its widget.

const TICK_LENGTH := 8.0
const KEYCAP_FORMAT := "[bgcolor=#2b3442][color=#ffd166][b] $1 [/b][/color][/bgcolor]"
const COLOR_WARN := Color(1.0, 0.85, 0.45)
const COLOR_DANGER := Color(1.0, 0.3, 0.25)
const COLOR_HIT_KILL := Color(1.0, 0.2, 0.15)
const COLOR_HIT_HEAD := Color(1.0, 0.85, 0.25)
const DAMAGE_LABEL := "Damage" # addUpdate() lines with this text are shown in red

@export_group("Vitals")
@export var max_stamina := 100.0
## Health fraction at or below which the screen edges pulse red
@export_range(0.0, 1.0) var low_health_threshold := 0.3

@export_group("Crosshair")
## Pixels between the centre and each tick when the weapon is perfectly accurate
@export var crosshair_base_gap := 6.0
## Extra pixels per degree of weapon spread
@export var crosshair_px_per_degree := 5.0

@export_group("Notifications")
@export var notification_scene: PackedScene
@export var max_notifications := 5

@export_group("Debug")
@export var show_fps := false:
	set(value):
		show_fps = value
		if is_node_ready():
			_fps_counter.visible = value

@onready var _damage_flash: TextureRect = %DamageFlash
@onready var _vignette: TextureRect = %LowHealthVignette
@onready var _damage_direction: Control = %DamageDirection
@onready var _crosshair: Control = %Crosshair
@onready var _tick_top: ColorRect = %CrosshairTop
@onready var _tick_bottom: ColorRect = %CrosshairBottom
@onready var _tick_left: ColorRect = %CrosshairLeft
@onready var _tick_right: ColorRect = %CrosshairRight
@onready var _hit_marker: Control = %HitMarker
@onready var _alert_panel: Control = %AlertPanel
@onready var _alert_status: Label = %AlertStatus
@onready var _detect_meter: ProgressBar = %DetectMeter
@onready var _objective_text: Label = %ObjectiveText
@onready var _key_list: HBoxContainer = %KeyList
@onready var _key_template: Control = %KeySlotTemplate
@onready var _notification_stack: VBoxContainer = %NotificationStack
@onready var _prompt_panel: Control = %InteractionPrompt
@onready var _prompt_text: RichTextLabel = %PromptText
@onready var _health_value: Label = %HealthValue
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_trail: ProgressBar = %HealthTrail
@onready var _stamina_bar: ProgressBar = %StaminaBar
@onready var _armor_bar: ProgressBar = %ArmorBar
@onready var _armor_value: Label = %ArmorValue
@onready var _weapon_panel: Control = %WeaponPanel
@onready var _weapon_name: Label = %WeaponName
@onready var _fire_mode: Label = %FireMode
@onready var _ammo_row: Control = %AmmoRow
@onready var _ammo_value: Label = %AmmoValue
@onready var _no_ammo_label: Label = %NoAmmoLabel
@onready var _fps_counter: Label = %FPSCounter

var player: Node = null

var health := 100.0:
	set(value):
		health = value
		_refresh_vitals()

var max_health := 100.0:
	set(value):
		max_health = maxf(value, 1.0)
		_refresh_vitals()

var stamina := 100.0:
	set(value):
		stamina = value
		_refresh_stamina()

var armor := 0.0:
	set(value):
		armor = value
		_refresh_armor()

var max_armor := 100.0:
	set(value):
		max_armor = maxf(value, 1.0)
		_refresh_armor()

var ammo := 0:
	set(value):
		ammo = value
		_refresh_ammo()

var _keycap_regex := RegEx.new()
var _weapon_state := 0
var _prompt_raw := ""
var _key_slots: Array[Control] = []
var _gap := 0.0
var _threat_level := 0
var _threat_meter := 0.0
var _threat_scan_timer := 0.0
var _time := 0.0

var _flash_tween: Tween
var _hit_tween: Tween
var _dir_tween: Tween
var _trail_tween: Tween
var _prompt_tween: Tween
var _no_ammo_tween: Tween


func _ready() -> void:
	_keycap_regex.compile("\\[([^\\]]+)\\]")
	_gap = crosshair_base_gap
	_place_ticks(_gap)
	show_fps = OptionsMenu.get_saved("video", "show_fps", false)
	_fps_counter.visible = show_fps
	updateHud()


# ---------------------------------------------------------------- SETUP

## Called once by the player after it is ready. Lets the HUD listen to weapon events.
func setup(new_player: Node) -> void:
	player = new_player
	var wm = player.get("weapon_manager")
	if wm == null:
		return
	if not wm.weapon_switched.is_connected(_on_weapon_switched):
		wm.weapon_switched.connect(_on_weapon_switched)
		wm.dry_fired.connect(_on_dry_fired)
	_on_weapon_switched(wm.current_weapon)


## Full refresh. Kept for the existing player code, which calls it after changing values.
func updateHud() -> void:
	_refresh_vitals()
	_refresh_armor()
	_refresh_stamina()
	_refresh_ammo()


# ---------------------------------------------------------------- VITALS

func _refresh_vitals() -> void:
	if not is_node_ready():
		return
	var frac := clampf(health / max_health, 0.0, 1.0)
	var target := frac * 100.0
	_health_value.text = str(ceili(maxf(health, 0.0)))
	_health_bar.value = target
	_health_bar.modulate = _health_tint(frac)
	_update_trail(target)


func _health_tint(frac: float) -> Color:
	if frac <= low_health_threshold:
		return COLOR_DANGER
	if frac < 0.6:
		return COLOR_WARN
	return Color.WHITE


## The red "damage trail" lags behind the real bar when health drops, then catches up.
func _update_trail(target: float) -> void:
	if _trail_tween:
		_trail_tween.kill()
	if target >= _health_trail.value:
		_health_trail.value = target
		return
	_trail_tween = create_tween()
	_trail_tween.tween_interval(0.35)
	_trail_tween.tween_property(_health_trail, "value", target, 0.45)


func _refresh_armor() -> void:
	if not is_node_ready():
		return
	_armor_value.text = str(ceili(maxf(armor, 0.0)))
	_armor_bar.value = clampf(armor / max_armor, 0.0, 1.0) * 100.0


func _refresh_stamina() -> void:
	if not is_node_ready():
		return
	var frac := clampf(stamina / max_stamina, 0.0, 1.0)
	_stamina_bar.value = frac * 100.0
	var tint := Color.WHITE if frac > 0.25 else COLOR_WARN
	tint.a = 0.35 if frac >= 1.0 else 1.0
	_stamina_bar.modulate = tint


# ---------------------------------------------------------------- WEAPON AND AMMO

func _on_weapon_switched(ws: int) -> void:
	_weapon_state = ws
	var data := _weapon_data(ws)
	var armed := ws != WeaponManager.WeaponState.NO_WEAPON and not data.is_empty()
	_set_crosshair_ticks(armed)
	if armed:
		_weapon_name.text = str(data.get("display_name", "WEAPON")).to_upper()
		_fire_mode.text = "AUTO" if data.get("automatic", false) else "SEMI"
	else:
		_weapon_name.text = "UNARMED"
	_fire_mode.visible = armed
	_ammo_row.visible = armed
	_refresh_ammo()


## Four lines only while a weapon is drawn. Unarmed, the crosshair is just the centre dot.
func _set_crosshair_ticks(on: bool) -> void:
	_tick_top.visible = on
	_tick_bottom.visible = on
	_tick_left.visible = on
	_tick_right.visible = on


func _weapon_data(ws: int) -> Dictionary:
	if player == null:
		return {}
	var wm = player.get("weapon_manager")
	if wm == null:
		return {}
	var all: Dictionary = wm.weapons_data
	return all.get(ws, {})


## Text colour goes through the font colour, not modulate, so each tint is exact.
## White removes the override and keeps the theme default.
func _set_text_color(label: Label, color: Color) -> void:
	if color == Color.WHITE:
		label.remove_theme_color_override("font_color")
	else:
		label.add_theme_color_override("font_color", color)


func _refresh_ammo() -> void:
	if not is_node_ready():
		return
	_ammo_value.text = str(ammo)
	var empty := ammo <= 0
	_set_text_color(_ammo_value, COLOR_DANGER if empty else Color.WHITE)
	if _no_ammo_tween and _no_ammo_tween.is_running():
		return  # keep the dry-fire message on screen until its timer ends
	_no_ammo_label.visible = empty and _weapon_state != WeaponManager.WeaponState.NO_WEAPON


func _on_dry_fired(_weapon: int) -> void:
	_shake(_weapon_panel)
	_no_ammo_label.visible = true
	if _no_ammo_tween:
		_no_ammo_tween.kill()
	_no_ammo_tween = create_tween()
	_no_ammo_tween.tween_interval(0.9)
	_no_ammo_tween.tween_callback(_end_dry_fire)


func _end_dry_fire() -> void:
	_no_ammo_label.visible = ammo <= 0 and _weapon_state != WeaponManager.WeaponState.NO_WEAPON


func _shake(ctrl: Control) -> void:
	var base_x := ctrl.position.x
	var tween := create_tween()
	for offset in [-6.0, 6.0, -4.0, 4.0, 0.0]:
		tween.tween_property(ctrl, "position:x", base_x + offset, 0.035)


# ---------------------------------------------------------------- CROSSHAIR AND HIT FEEDBACK

func _update_crosshair(delta: float) -> void:
	var spread := 0.0
	var wm = player.get("weapon_manager") if player else null
	if wm and wm.has_method("get_current_spread"):
		spread = float(wm.get_current_spread())
	var target := crosshair_base_gap + spread * crosshair_px_per_degree
	_gap = lerpf(_gap, target, 1.0 - exp(-14.0 * delta))
	_place_ticks(_gap)


func _place_ticks(gap: float) -> void:
	_set_rect(_tick_top, -1.0, -gap - TICK_LENGTH, 1.0, -gap)
	_set_rect(_tick_bottom, -1.0, gap, 1.0, gap + TICK_LENGTH)
	_set_rect(_tick_left, -gap - TICK_LENGTH, -1.0, -gap, 1.0)
	_set_rect(_tick_right, gap, -1.0, gap + TICK_LENGTH, 1.0)


func _set_rect(ctrl: Control, x0: float, y0: float, x1: float, y1: float) -> void:
	ctrl.offset_left = x0
	ctrl.offset_top = y0
	ctrl.offset_right = x1
	ctrl.offset_bottom = y1


## Called by the weapon code when a shot lands on a damageable target.
func show_hitmarker(killed := false, headshot := false) -> void:
	if not is_node_ready():
		return
	var c := Color.WHITE
	if killed:
		c = COLOR_HIT_KILL
	elif headshot:
		c = COLOR_HIT_HEAD
	_hit_marker.modulate = c
	_hit_marker.scale = Vector2.ONE * 1.35
	if _hit_tween:
		_hit_tween.kill()
	_hit_tween = create_tween().set_parallel(true)
	_hit_tween.tween_property(_hit_marker, "modulate:a", 0.0, 0.3).set_delay(0.08)
	_hit_tween.tween_property(_hit_marker, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Red edge flash. Kept under its old name so the player code still works.
func screenGlow(color: Color) -> void:
	if not is_node_ready():
		return
	_damage_flash.modulate = color
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_damage_flash, "modulate:a", 0.0, 0.7)


## Shows a wedge on the screen edge pointing toward where the damage came from.
func show_damage_from(world_pos: Vector3) -> void:
	if not is_node_ready():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	var to := world_pos - cam.global_position
	to.y = 0.0
	if fwd.length_squared() < 0.0001 or to.length_squared() < 0.0001:
		return
	# Positive angle = turn left, so the screen rotation (clockwise = right) is its negative
	var theta := fwd.normalized().signed_angle_to(to.normalized(), Vector3.UP)
	_damage_direction.rotation = -theta
	if _dir_tween:
		_dir_tween.kill()
	_damage_direction.modulate.a = 1.0
	_dir_tween = create_tween()
	_dir_tween.tween_property(_damage_direction, "modulate:a", 0.0, 1.0)


# ---------------------------------------------------------------- PER-FRAME

func _process(delta: float) -> void:
	_time += delta
	_update_low_health()
	_update_crosshair(delta)
	_threat_scan_timer -= delta
	if _threat_scan_timer <= 0.0:
		_threat_scan_timer = 0.15
		_scan_threats()
	_update_alert_visuals()


func _update_low_health() -> void:
	if health / max_health > low_health_threshold:
		_vignette.modulate.a = 0.0
		return
	_vignette.modulate.a = 0.5 + 0.2 * sin(_time * 5.0)


# ---------------------------------------------------------------- THREAT STATE

## Reads enemy state through public properties, so enemy.gd does not need to change.
func _scan_threats() -> void:
	var level := 0
	var meter := 0.0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var st = enemy.get("state")
		if st == null:
			continue
		if st == Enemy.State.CHASE or st == Enemy.State.ATTACK or st == Enemy.State.SHOOT:
			level = maxi(level, 3)
		elif st == Enemy.State.INVESTIGATE:
			level = maxi(level, 1)
		if enemy.get("_sees_player") == true:
			level = maxi(level, 2)
			meter = maxf(meter, float(enemy.get("awareness")))
	_threat_level = level
	_threat_meter = meter
	_apply_threat()


func _apply_threat() -> void:
	_alert_panel.visible = _threat_level > 0
	_detect_meter.visible = _threat_level == 2
	_detect_meter.value = _threat_meter * 100.0
	match _threat_level:
		1:
			_alert_status.text = "SUSPICIOUS"
			_set_text_color(_alert_status, COLOR_WARN)
		2:
			_alert_status.text = "DETECTED"
			_set_text_color(_alert_status, Color(1.0, 0.7, 0.3))
		3:
			_alert_status.text = "ALERT"
			_set_text_color(_alert_status, COLOR_DANGER)


func _update_alert_visuals() -> void:
	if _threat_level == 3:
		_alert_status.modulate.a = 0.6 + 0.4 * sin(_time * 12.0)
	else:
		_alert_status.modulate.a = 1.0


# ---------------------------------------------------------------- KEYS AND OBJECTIVE

## Called by the player whenever keys change. One slot per key the level needs.
func update_keys(current_keys: Array[String], _all_keys: Array[String], total_in_level: int) -> void:
	if not is_node_ready():
		return
	for slot in _key_slots:
		slot.queue_free()
	_key_slots.clear()
	_key_list.visible = total_in_level > 0
	for i in total_in_level:
		var slot: Control = _key_template.duplicate()
		slot.visible = true
		_key_list.add_child(slot)
		var label: Label = slot.get_node("KeyLabel")
		if i < current_keys.size():
			var key_name := current_keys[i]
			label.text = key_name.to_upper()
			slot.self_modulate = Color.WHITE
		else:
			label.text = "?"
			slot.self_modulate = Color(1, 1, 1, 0.35)
		_key_slots.append(slot)


func set_objective(text: String) -> void:
	if is_node_ready():
		_objective_text.text = text


# ---------------------------------------------------------------- INTERACTION PROMPT

## Accepts the same strings as before, e.g. "Press [E] to open".
## Anything inside square brackets is drawn as a keycap.
func set_interaction_prompt(text: String) -> void:
	if not is_node_ready():
		return
	var next := text.strip_edges()
	if next == _prompt_raw:
		return
	_prompt_raw = next
	_prompt_text.text = _keycap_regex.sub(next, KEYCAP_FORMAT, true) if next != "" else ""
	if _prompt_tween:
		_prompt_tween.kill()
	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt_panel, "modulate:a", 1.0 if next != "" else 0.0, 0.12)


# ---------------------------------------------------------------- NOTIFICATIONS

## Shows a line on the notification stack. Pickups and system messages are always white.
func notify(text: String, _color: Color = Color.WHITE) -> void:
	_push_notice(text, Color.WHITE)


## Old entry point used by the player: addUpdate(3, "Ammo", color) shows "3 Ammo".
## Damage lines are red, everything else is white. The colour argument is kept for compatibility.
func addUpdate(qty: Variant, text: String, _color: Color) -> void:
	var tint := COLOR_DANGER if text == DAMAGE_LABEL else Color.WHITE
	_push_notice("%s %s" % [str(qty), text], tint)


func _push_notice(text: String, color: Color) -> void:
	if not is_node_ready() or notification_scene == null:
		return
	var item = notification_scene.instantiate()
	_notification_stack.add_child(item)
	if item.has_method("show_text"):
		item.show_text(text, color)
	while _notification_stack.get_child_count() > max_notifications:
		var oldest = _notification_stack.get_child(0)
		_notification_stack.remove_child(oldest)
		oldest.queue_free()


# ---------------------------------------------------------------- INPUT

func _unhandled_input(event) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		show_fps = not show_fps
		get_viewport().set_input_as_handled()
