class_name CombatFX
extends RefCounted
## Small code-only visual helpers (tracers, impact sparks, muzzle flash).
## No art assets needed, so you can swap them for real particles/decals later.

static var _mat_cache := {}

static func _glow_material(color: Color) -> StandardMaterial3D:
	if _mat_cache.has(color):
		return _mat_cache[color]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.0
	_mat_cache[color] = m
	return m

## Random direction inside a cone of `spread_deg` (half-angle) around `dir`.
static func spread_direction(dir: Vector3, spread_deg: float) -> Vector3:
	if spread_deg <= 0.0:
		return dir
	var up_hint := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var right := dir.cross(up_hint).normalized()
	var up := right.cross(dir).normalized()
	var r := tan(deg_to_rad(spread_deg)) * sqrt(randf())
	var t := randf() * TAU
	return (dir + right * cos(t) * r + up * sin(t) * r).normalized()

static func spawn_tracer(parent: Node, from: Vector3, to: Vector3, color: Color, width := 0.012, life := 0.07) -> void:
	var length := from.distance_to(to)
	if length < 1.0:
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, width, length)
	mi.mesh = box
	mi.material_override = _glow_material(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = (from + to) * 0.5
	var dir := (to - from).normalized()
	var up_hint := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	mi.look_at(to, up_hint)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(0.0, 0.0, 1.0), life)
	tw.tween_callback(mi.queue_free)

static func spawn_impact(parent: Node, pos: Vector3, normal: Vector3, color := Color(1.0, 0.75, 0.3)) -> void:
	var p := CPUParticles3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.02
	sphere.height = 0.04
	sphere.radial_segments = 4
	sphere.rings = 2
	p.mesh = sphere
	p.material_override = _glow_material(color)
	p.one_shot = true
	p.amount = 8
	p.lifetime = 0.3
	p.explosiveness = 1.0
	p.direction = normal if normal.length() > 0.01 else Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -9.8, 0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(0.8, false).timeout.connect(p.queue_free)

static func muzzle_flash(muzzle: Node3D, color: Color, energy := 2.5, time := 0.05) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = 6.0
	l.shadow_enabled = false
	muzzle.add_child(l)
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.035
	sphere.height = 0.07
	flash.mesh = sphere
	flash.material_override = _glow_material(color)
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.scale = Vector3(1, 1, 1.8) * randf_range(0.8, 1.5)
	muzzle.add_child(flash)
	var tree := muzzle.get_tree()
	tree.create_timer(time, false).timeout.connect(l.queue_free)
	tree.create_timer(time, false).timeout.connect(flash.queue_free)
