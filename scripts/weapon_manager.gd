extends Node

class_name WeaponManager

signal weapon_switched(new_weapon)

@onready var player := owner

enum WeaponState {
	NO_WEAPON,
	WEAPON_1,  # blaster-b
	WEAPON_2  # blaster-m2
}

var current_weapon: WeaponState = WeaponState.NO_WEAPON
var can_shoot: bool = true
var last_shot: float = 0.0

var weapons_data: Dictionary = {}
var bullet_scene := preload("res://scenes/bullet.tscn")

# Optional: melee weapon (sword already in scene)
@onready var sword_holder := $Sword

func _ready() -> void:
	_build_weapons_data()
	_update_weapon_visibility()

func _build_weapons_data() -> void:
	weapons_data = {
		WeaponState.NO_WEAPON: { "holder": null, "visible": false },
		WeaponState.WEAPON_1: {
			"holder": $"blaster-b",
			"barrel": $"blaster-b/MuzzleMarker3D",
			"anim_player": $"blaster-b/AnimationPlayer",
			"audio": $"blaster-b/AudioStreamPlayer",
			"lowered_pos": Vector3(0, -1, 0),
			"lower_anim": "lower_blaster",
			"fire_speed": 0.2,
			"damage": 1,
			"ammo_cost": 1
		},
		WeaponState.WEAPON_2: {
			"holder": $"blaster-m2",
			"barrel": $"blaster-m2/MuzzleMarker3D",
			"anim_player": $"blaster-m2/AnimationPlayer",
			"audio": $"blaster-m2/AudioStreamPlayer",
			"lowered_pos": Vector3(0, -1, 0),
			"lower_anim": "lower_blaster",
			"fire_speed": 0.5,
			"damage": 3,
			"ammo_cost": 2
		}
	}

func switch_weapon(new_weapon: WeaponState) -> void:
	if current_weapon == new_weapon:
		return
	can_shoot = false

	var current_data = weapons_data[current_weapon]
	
	# Play the "lower" animation on the CURRENT weapon's local AnimationPlayer
	if current_data.get("anim_player") and current_data.has("lower_anim"):
		current_data.anim_player.play(current_data.lower_anim)
		await current_data.anim_player.animation_finished

	current_weapon = new_weapon

	var new_data = weapons_data[new_weapon]
	if new_data.holder:
		new_data.holder.position = new_data.lowered_pos

	_update_weapon_visibility()

	# Play the "lower" animation BACKWARDS on the NEW weapon's local AnimationPlayer
	if new_data.get("anim_player") and new_data.has("lower_anim"):
		new_data.anim_player.play_backwards(new_data.lower_anim)
		await new_data.anim_player.animation_finished

	can_shoot = true
	emit_signal("weapon_switched", new_weapon)

func try_shoot() -> void:
	if !can_shoot || current_weapon == WeaponState.NO_WEAPON:
		return
	
	var data = weapons_data[current_weapon]
	# Get the specific cost for this weapon (defaults to 1 if missing)
	var cost = data.get("ammo_cost", 1)

	if player.ammo < cost:
		return

	var now := Time.get_ticks_msec() / 1000.0
	if now < last_shot + data.fire_speed:
		return

	last_shot = now

	# Uses the same local anim_player reference for shooting
	if data.anim_player and !data.anim_player.is_playing():
		data.anim_player.play("shooting")
	if data.audio:
		data.audio.play()

	_fire_bullet(data)

	player.ammo -= cost
	if player.hud:
		player.hud.ammo = player.ammo
		player.hud.updateHud()

func _fire_bullet(data: Dictionary) -> void:
	if not data.barrel.is_inside_tree():
		return
		
	var new_bullet := bullet_scene.instantiate()
	new_bullet.damage = data.damage
	
	player.get_parent().add_child(new_bullet)
	new_bullet.global_position = data.barrel.global_position
	
	# Use camera forward direction
	var shoot_direction = -player.camera_3d.global_basis.z.normalized()
	
	shoot_direction = (player.camera_3d.global_position + shoot_direction * 100.0 - data.barrel.global_position).normalized()
	
	new_bullet.set_direction(shoot_direction)

func _update_weapon_visibility() -> void:
	for ws in weapons_data:
		var data = weapons_data[ws]
		if data.holder:
			data.holder.visible = (ws == current_weapon)
	# Sword visible only in no-weapon state (or customize later)
	# sword_holder.visible = (current_weapon == WeaponState.NO_WEAPON)
