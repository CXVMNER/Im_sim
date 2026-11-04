class_name LODGroup
extends Node3D
## Put your Sphere_LOD0, Sphere_LOD1, Sphere_LOD2 MeshInstance3D nodes as children
## (sorted by name). Attach this script to their parent Node3D.

## Distance (meters) where LOD1 takes over, then LOD2, etc.
@export var distances: PackedFloat32Array = [10.0, 25.0]
## Smooth dithered cross-fade between LODs. Turn OFF for the showcase so the pop is obvious.
@export var cross_fade: bool = false
@export var fade_margin: float = 2.0

const TINTS: Array[Color] = [
	Color(0.2, 1.0, 0.2, 0.45),  # LOD0 green
	Color(1.0, 0.9, 0.1, 0.45),  # LOD1 yellow
	Color(1.0, 0.2, 0.2, 0.45),  # LOD2 red
]

var _lods: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("lod_group")
	for c in get_children():
		if c is MeshInstance3D:
			_lods.append(c)
	_lods.sort_custom(func(a, b): return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	apply_ranges()


func apply_ranges() -> void:
	for i in _lods.size():
		var m := _lods[i]
		m.visible = true
		# begin = 0 -> no lower limit, end = 0 -> no upper limit
		m.visibility_range_begin = 0.0 if i == 0 else distances[i - 1]
		m.visibility_range_end = 0.0 if i == _lods.size() - 1 else distances[i]
		if cross_fade:
			m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			m.visibility_range_begin_margin = 0.0 if i == 0 else fade_margin
			m.visibility_range_end_margin = 0.0 if i == _lods.size() - 1 else fade_margin
		else:
			m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			m.visibility_range_begin_margin = 0.0
			m.visibility_range_end_margin = 0.0


## level >= 0: show only that LOD no matter the distance. level < 0: back to automatic.
func force_lod(level: int) -> void:
	if level < 0:
		apply_ranges()
		return
	level = mini(level, _lods.size() - 1)
	for i in _lods.size():
		var m := _lods[i]
		m.visibility_range_begin = 0.0
		m.visibility_range_end = 0.0
		m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		m.visible = (i == level)


## Transparent colored overlay per LOD (keeps your granite texture visible underneath).
func set_tint(on: bool) -> void:
	for i in _lods.size():
		if on:
			var mat := StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = TINTS[mini(i, TINTS.size() - 1)]
			_lods[i].material_overlay = mat
		else:
			_lods[i].material_overlay = null
