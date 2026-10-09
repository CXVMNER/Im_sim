class_name FallDamage
extends Node
## Attach as a child of ANY CharacterBody3D (player, enemies, NPCs...) and it
## deals fall damage on landing by calling the parent's takeDamage(dmg).
## Damage is based on the equivalent fall height (v^2 / 2g) at impact, so it
## doesn't matter whether the creature jumped, walked off a ledge or was thrown.
##
## Tuning: nothing below `safe_fall_height` hurts; at `lethal_fall_height` the
## fall is guaranteed lethal; in between damage scales linearly with the
## creature's max_health (falls back to its current health).

signal landed(fall_height: float, damage: int)

@export var enabled := true
@export var safe_fall_height := 3.0
@export var lethal_fall_height := 11.0
## Landings from at least this height emit `landed` even if they do no damage.
@export var landing_event_height := 0.8

var body: CharacterBody3D
var _airborne := false
var _armed := false # only counts falls after the first touchdown (spawning in mid-air is free)
var _peak_down_speed := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	body = get_parent() as CharacterBody3D
	if body == null:
		push_warning("FallDamage must be a child of a CharacterBody3D")
		set_physics_process(false)

## Call after teleporting a creature so stale fall speed isn't counted.
func reset() -> void:
	_airborne = false
	_peak_down_speed = 0.0

## Call after teleporting: the next landing is ignored, as if freshly spawned.
func disarm() -> void:
	reset()
	_armed = false

func _physics_process(_delta: float) -> void:
	if not enabled or body == null:
		return
	if body.get("is_dead") == true:
		reset()
		return
	if body.is_on_floor():
		if _airborne and _armed:
			_land(_peak_down_speed)
		_armed = true
		reset()
	elif _armed:
		_airborne = true
		_peak_down_speed = maxf(_peak_down_speed, -body.velocity.y)

func _land(speed: float) -> void:
	var fall_height := (speed * speed) / (2.0 * _gravity)
	var dmg := calculate_damage(fall_height)
	if dmg > 0 and body.has_method("takeDamage"):
		body.takeDamage(dmg)
	if fall_height >= landing_event_height:
		landed.emit(fall_height, dmg)

func calculate_damage(fall_height: float) -> int:
	if fall_height <= safe_fall_height:
		return 0
	var current = body.get("health")
	var vitality = body.get("max_health")
	if vitality == null:
		vitality = current
	if vitality == null:
		vitality = 100.0
	var t := clampf((fall_height - safe_fall_height) / maxf(lethal_fall_height - safe_fall_height, 0.01), 0.0, 1.0)
	if t >= 1.0:
		# Lethal, even if the creature is over its max health
		return ceili(maxf(float(vitality), float(current if current != null else 0.0)))
	return maxi(1, ceili(float(vitality) * t))
