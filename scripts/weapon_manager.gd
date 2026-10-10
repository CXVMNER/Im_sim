extends Node3D

class_name WeaponManager

signal weapon_switched(new_weapon)
signal shot_fired(weapon)
signal dry_fired(weapon)

@onready var player := owner

enum WeaponState {
	NO_WEAPON,
	WEAPON_1,  # blaster-b  : rapid-fire blaster
	WEAPON_2   # blaster-m2 : scatter blaster (shotgun style)
}

enum Phase { READY, LOWERING, RAISING }

## Same mask as before (layers 1 + 4). Make sure enemies/crates are on one of them.
@export_flags_3d_physics var hit_mask: int = 9
## Animation speed multiplier for lowering/raising weapons
@export var switch_speed := 1.6
## A semi-auto click this close to the end of the cooldown is remembered
@export var shoot_buffer_time := 0.12
@export var show_tracers := true

@export_group("Viewmodel feel")
@export var kick_recovery := 14.0   # how fast the weapon settles after a shot
@export var sway_amount := 0.01     # weapon lag when turning the camera
@export var sway_smooth := 12.0
@export var bob_amount := 0.012     # walking bob (metres)

var current_weapon: WeaponState = WeaponState.NO_WEAPON # weapon currently in hand
var target_weapon: WeaponState = WeaponState.NO_WEAPON  # weapon we are switching to
var last_weapon: WeaponState = WeaponState.NO_WEAPON    # for quick-switch
var last_shot: float = 0.0
var weapons_data: Dictionary = {}
var unlocked := {
	WeaponState.WEAPON_1: true,
	WeaponState.WEAPON_2: true,
}

var can_shoot: bool:
	get:
		return _phase == Phase.READY

var _phase: Phase = Phase.READY
var _bloom := 0.0
var _shot_buffered := false
var _buffer_expires := 0.0

var _base_pos := Vector3.ZERO
var _base_rot := Vector3.ZERO
var _kick_pos := Vector3.ZERO
var _kick_rot := Vector3.ZERO
var _sway_rot := Vector3.ZERO
var _bob_time := 0.0
var _bob_blend := 0.0
var _prev_yaw := 0.0
var _prev_pitch := 0.0
var _sway_ready := false

const REF_SPEED := 6.0 # speed at which movement spread penalty is maxed

# Optional: melee weapon (sword already in scene)
@onready var sword_holder := $Sword

func _ready() -> void:
	_base_pos = position
	_base_rot = rotation
	_build_weapons_data()
	_update_weapon_visibility()

# ---------------------------------------------------------------- DATA
func _make_weapon(node_name: String, overrides: Dictionary) -> Dictionary:
	var data := {
		"name": node_name,
		"display_name": node_name, # shown on the HUD
		"holder": get_node_or_null(node_name),
		"barrel": get_node_or_null(node_name + "/MuzzleMarker3D"),
		"anim_player": get_node_or_null(node_name + "/AnimationPlayer"),
		"audio": get_node_or_null(node_name + "/AudioStreamPlayer"),
		"lowered_pos": Vector3(0, -1, 0),
		"lower_anim": "lower_blaster",
		"fire_anim": "shooting",
		"fire_speed": 0.2,        # seconds between shots
		"automatic": true,        # false = one shot per click
		"damage": 1.0,            # per pellet
		"ammo_cost": 1,
		"range": 50.0,
		"pellets": 1,
		"spread": 0.0,            # base cone half-angle in degrees
		"bloom": 0.0,             # extra spread added per shot...
		"bloom_max": 0.0,         # ...up to this much...
		"bloom_recovery": 5.0,    # ...and recovered at this many degrees/sec
		"falloff_start": 1.0,     # fraction of range where damage starts dropping (1 = never)
		"falloff_min": 1.0,       # damage multiplier at max range
		"headshot_mult": 2.0,
		"recoil_pitch": 0.01,     # radians of camera kick
		"recoil_yaw": 0.004,
		"impulse": 3.0,           # push applied to RigidBodies
		"kick_back": 0.03,       # viewmodel kick toward the camera (metres)
		"kick_pitch": 0.05,      # viewmodel muzzle-up rotation (radians)
		"noise": 25.0,            # radius enemies can hear a shot
		"tracer_color": Color(0.5, 0.85, 1.0),
		"flash_color": Color(0.5, 0.85, 1.0),
	}
	data.merge(overrides, true)
	return data

func _build_weapons_data() -> void:
	weapons_data = {
		WeaponState.NO_WEAPON: { "holder": null },
		WeaponState.WEAPON_1: _make_weapon("blaster-b", {
			"display_name": "Rapid blaster",
			"fire_speed": 0.2, "automatic": true, "damage": 1.0, "ammo_cost": 1, "range": 50.0,
			"spread": 0.0, "bloom": 0.6, "bloom_max": 3.5, "bloom_recovery": 5.0,
			"recoil_pitch": 0.010, "recoil_yaw": 0.004, "noise": 25.0,
		}),
		WeaponState.WEAPON_2: _make_weapon("blaster-m2", {
			"display_name": "Scatter blaster",
			"fire_speed": 0.55, "automatic": false, "damage": 1.0, "ammo_cost": 2, "range": 15.0,
			"pellets": 7, "spread": 4.5, "bloom": 0.0, "bloom_max": 0.0,
			"falloff_start": 0.3, "falloff_min": 0.25,
			"recoil_pitch": 0.045, "recoil_yaw": 0.012, "impulse": 6.0, "noise": 40.0,
			"kick_back": 0.10, "kick_pitch": 0.20,
			"tracer_color": Color(1.0, 0.7, 0.3), "flash_color": Color(1.0, 0.7, 0.3),
		}),
	}

func unlock_weapon(ws: WeaponState) -> void:
	unlocked[ws] = true

## Current cone half-angle in degrees (bloom, movement and stance). The HUD crosshair reads this.
func get_current_spread() -> float:
	if current_weapon == WeaponState.NO_WEAPON or player == null or not weapons_data.has(current_weapon):
		return 0.0
	return _current_spread(weapons_data[current_weapon])

# ---------------------------------------------------------------- SWITCHING
## Safe to spam: the latest request always wins, no overlapping animations.
func switch_weapon(new_weapon: WeaponState) -> void:
	if not unlocked.get(new_weapon, new_weapon == WeaponState.NO_WEAPON):
		return
	if new_weapon == target_weapon:
		return
	last_weapon = target_weapon
	target_weapon = new_weapon
	_shot_buffered = false
	if _phase == Phase.READY:
		_run_switch()

func cycle_weapon(dir: int) -> void:
	var list: Array = []
	for ws in [WeaponState.WEAPON_1, WeaponState.WEAPON_2]:
		if unlocked.get(ws, false):
			list.append(ws)
	if list.is_empty():
		return
	var idx := list.find(target_weapon)
	if idx == -1:
		idx = 0 if dir > 0 else list.size() - 1
	else:
		idx = posmod(idx + dir, list.size())
	switch_weapon(list[idx])

func switch_to_last() -> void:
	if last_weapon != target_weapon:
		switch_weapon(last_weapon)

func _run_switch() -> void:
	while current_weapon != target_weapon:
		if not is_inside_tree():
			_phase = Phase.READY
			return
		_phase = Phase.LOWERING
		await _play_transition(current_weapon, true)
		current_weapon = target_weapon # latest request wins, even if it changed mid-lower
		var new_data: Dictionary = weapons_data[current_weapon]
		var holder: Node3D = new_data["holder"]
		if holder:
			holder.position = new_data["lowered_pos"]
		_update_weapon_visibility()
		_bloom = 0.0
		_phase = Phase.RAISING
		await _play_transition(current_weapon, false)
	_phase = Phase.READY
	weapon_switched.emit(current_weapon)

# Uses a timer instead of awaiting animation_finished so a missing/odd
# animation can never leave the player unable to shoot.
func _play_transition(ws: WeaponState, lowering: bool) -> void:
	var data: Dictionary = weapons_data[ws]
	var holder: Node3D = data["holder"]
	if holder == null:
		return
	var anim: AnimationPlayer = data["anim_player"]
	var anim_name: String = data["lower_anim"]
	var duration := 0.2
	if anim and anim.has_animation(anim_name):
		duration = anim.get_animation(anim_name).length / switch_speed
		if lowering:
			anim.play(anim_name, -1.0, switch_speed)
		else:
			anim.play(anim_name, -1.0, -switch_speed, true)
	await get_tree().create_timer(duration).timeout # process_always, like this node (player is PROCESS_MODE_ALWAYS)

func _update_weapon_visibility() -> void:
	for ws in weapons_data:
		var holder: Node3D = weapons_data[ws]["holder"]
		if holder:
			holder.visible = (ws == current_weapon)

# ---------------------------------------------------------------- SHOOTING
func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _cooldown_remaining(data: Dictionary) -> float:
	return last_shot + float(data["fire_speed"]) - _now()

## just_pressed: pass true on the frame the button went down. Semi-auto weapons
## only fire on that frame; automatic weapons fire while held.
func try_shoot(just_pressed: bool = true) -> void:
	if _phase != Phase.READY or current_weapon == WeaponState.NO_WEAPON:
		return
	if player == null or player.is_dead:
		return
	var data: Dictionary = weapons_data[current_weapon]
	if not data["automatic"] and not just_pressed:
		return
	if player.ammo < int(data["ammo_cost"]):
		if just_pressed:
			dry_fired.emit(current_weapon)
		return
	var remaining := _cooldown_remaining(data)
	if remaining > 0.0:
		if just_pressed and remaining <= shoot_buffer_time:
			_shot_buffered = true
			_buffer_expires = _now() + shoot_buffer_time
		return
	_fire(data)

# Procedural weapon motion on top of the existing animations (kick, sway, bob).
# Applied to this node (GunHolder), which nothing else animates.
func _process(delta: float) -> void:
	if player == null or get_tree().paused:
		return
	var k := 1.0 - exp(-kick_recovery * delta)
	_kick_pos = _kick_pos.lerp(Vector3.ZERO, k)
	_kick_rot = _kick_rot.lerp(Vector3.ZERO, k)

	# Sway: the weapon lags slightly behind camera turns
	var yaw: float = player.camera_yaw
	var pitch: float = player.camera_pitch
	if not _sway_ready:
		_prev_yaw = yaw
		_prev_pitch = pitch
		_sway_ready = true
	var yaw_rate := wrapf(yaw - _prev_yaw, -PI, PI) / maxf(delta, 0.0001)
	var pitch_rate := (pitch - _prev_pitch) / maxf(delta, 0.0001)
	_prev_yaw = yaw
	_prev_pitch = pitch
	var sway_target := Vector3(
		clampf(-pitch_rate * sway_amount, -0.08, 0.08),
		clampf(-yaw_rate * sway_amount, -0.08, 0.08),
		clampf(yaw_rate * sway_amount * 0.5, -0.05, 0.05))
	_sway_rot = _sway_rot.lerp(sway_target, 1.0 - exp(-sway_smooth * delta))

	# Bob: only while walking on the ground
	var flat_speed := 0.0
	if player.is_on_floor():
		flat_speed = Vector2(player.velocity.x, player.velocity.z).length()
	_bob_blend = lerpf(_bob_blend, clampf(flat_speed / REF_SPEED, 0.0, 1.0), 1.0 - exp(-8.0 * delta))
	_bob_time += delta * (5.0 + flat_speed * 1.2)
	var bob := Vector3(cos(_bob_time) * bob_amount, sin(_bob_time * 2.0) * bob_amount * 0.6, 0.0) * _bob_blend
	if player.is_crouching:
		bob *= 0.5

	position = _base_pos + _kick_pos + bob
	rotation = _base_rot + _kick_rot + _sway_rot

func _physics_process(delta: float) -> void:
	if current_weapon == WeaponState.NO_WEAPON:
		_bloom = 0.0
		return
	var data: Dictionary = weapons_data[current_weapon]
	_bloom = move_toward(_bloom, 0.0, float(data["bloom_recovery"]) * delta)
	if _shot_buffered:
		if _now() > _buffer_expires or _phase != Phase.READY:
			_shot_buffered = false
		elif _cooldown_remaining(data) <= 0.0:
			_fire(data)

func _fire(data: Dictionary) -> void:
	var cost: int = data["ammo_cost"]
	if player.ammo < cost:
		_shot_buffered = false
		return
	_shot_buffered = false
	last_shot = _now()
	player.ammo -= cost
	if player.hud:
		player.hud.ammo = player.ammo
		player.hud.updateHud()

	_play_fire_effects(data)
	_fire_rays(data)

	_bloom = minf(_bloom + float(data["bloom"]), float(data["bloom_max"]))
	if player.has_method("add_recoil"):
		player.add_recoil(float(data["recoil_pitch"]), float(data["recoil_yaw"]) * randf_range(-1.0, 1.0))
	_kick_pos += Vector3(randf_range(-0.004, 0.004), randf_range(0.0, 0.006), float(data["kick_back"]))
	_kick_rot += Vector3(float(data["kick_pitch"]), randf_range(-0.03, 0.03), randf_range(-0.04, 0.04))
	_kick_pos.z = minf(_kick_pos.z, 0.12)
	_kick_rot.x = minf(_kick_rot.x, 0.25)
	_emit_noise(float(data["noise"]))
	shot_fired.emit(current_weapon)

func _play_fire_effects(data: Dictionary) -> void:
	var anim: AnimationPlayer = data["anim_player"]
	if anim and anim.has_animation(data["fire_anim"]):
		anim.stop()
		anim.play(data["fire_anim"])
	var audio = data["audio"]
	if audio:
		audio.pitch_scale = randf_range(0.94, 1.06)
		audio.play()
	var barrel: Node3D = data["barrel"]
	if barrel:
		CombatFX.muzzle_flash(barrel, data["flash_color"])

# Spread grows with bloom and movement, shrinks when crouched
func _current_spread(data: Dictionary) -> float:
	var s: float = float(data["spread"]) + _bloom
	if player.is_crouching:
		s *= 0.6
	if not player.is_on_floor():
		s *= 2.0
	else:
		var flat_speed := Vector2(player.velocity.x, player.velocity.z).length()
		s *= 1.0 + clampf(flat_speed / REF_SPEED, 0.0, 1.0) * 0.8
	return s

func _fx_root() -> Node:
	var scene := get_tree().current_scene
	return scene if scene else get_tree().root

func _fire_rays(data: Dictionary) -> void:
	var camera: Camera3D = player.camera_3d
	if camera == null:
		return
	var origin := camera.global_position
	var forward := -camera.global_basis.z.normalized()
	var max_range: float = data["range"]
	var spread := _current_spread(data)
	var space := get_world_3d().direct_space_state
	var barrel: Node3D = data["barrel"]
	var muzzle_pos: Vector3 = barrel.global_position if barrel else origin + forward * 0.5

	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * max_range, hit_mask)
	query.exclude = [player.get_rid()]

	var damaged := false
	var killed := false
	var headshot := false
	for i in int(data["pellets"]):
		var dir := CombatFX.spread_direction(forward, spread)
		query.to = origin + dir * max_range
		var end_pos: Vector3 = query.to
		var result := space.intersect_ray(query)
		if not result.is_empty():
			end_pos = result["position"]
			var outcome := _handle_hit(data, result, dir, origin)
			damaged = damaged or outcome["damaged"]
			killed = killed or outcome["killed"]
			headshot = headshot or outcome["headshot"]
		if show_tracers:
			CombatFX.spawn_tracer(_fx_root(), muzzle_pos, end_pos, data["tracer_color"])

	if damaged and player.hud and player.hud.has_method("show_hitmarker"):
		player.hud.show_hitmarker(killed, headshot)

func _handle_hit(data: Dictionary, result: Dictionary, dir: Vector3, origin: Vector3) -> Dictionary:
	var out := { "damaged": false, "killed": false, "headshot": false }
	var collider: Object = result["collider"]
	var hit_pos: Vector3 = result["position"]
	var normal: Vector3 = result["normal"]
	var fx_color := Color(1.0, 0.75, 0.3)

	if collider and collider.has_method("takeDamage"):
		var dmg := _damage_at_distance(data, origin.distance_to(hit_pos))
		var head: bool = collider.has_method("is_headshot") and collider.is_headshot(hit_pos)
		if head:
			dmg *= float(data["headshot_mult"])
		var was_dead: bool = collider.get("is_dead") == true
		# Convention for everything damageable: takeDamage(dmg, source, hit_pos)
		collider.takeDamage(dmg, player, hit_pos)
		out["damaged"] = true
		out["headshot"] = head
		out["killed"] = (not was_dead) and collider.get("is_dead") == true
		fx_color = Color(1.0, 0.2, 0.15)
	elif collider is RigidBody3D:
		collider.apply_impulse(dir * float(data["impulse"]), hit_pos - collider.global_position)

	CombatFX.spawn_impact(_fx_root(), hit_pos, normal, fx_color)
	return out

func _damage_at_distance(data: Dictionary, dist: float) -> float:
	var dmg: float = data["damage"]
	var max_range: float = data["range"]
	var start := max_range * float(data["falloff_start"])
	if dist > start and max_range > start:
		var t := clampf((dist - start) / (max_range - start), 0.0, 1.0)
		dmg *= lerpf(1.0, float(data["falloff_min"]), t)
	return dmg

# Gunshots are loud: nearby enemies go and investigate
func _emit_noise(radius: float) -> void:
	var pos: Vector3 = player.global_position
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(pos) <= radius and e.has_method("hear_noise"):
			e.hear_noise(pos)
