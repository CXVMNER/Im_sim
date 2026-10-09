class_name Ladder
extends Node3D
## A climbable ladder. The player does all the maths against this node (no Area3D needed).
##
## Ladder space: +Z = the side you climb from ("outward"), X = width, Y = up.
## The origin is the CENTRE of the ladder. The floor you step onto at the top is on the -Z
## side, flush with the top of the ladder.

@export var height := 15.0
@export var width := 1.4
## Distance from the ladder plane to the middle of the player while hanging on it.
## (The collider's face is at z = 0.1 and the player capsule radius is 0.25.)
@export var climb_offset := 0.4
## Can the player step from the ledge above onto the ladder to climb down?
@export var allow_top_entry := true
## Can the player climb over the top onto the ledge? (if no, climbing just stops at the top)
@export var allow_top_exit := true

var half_height: float:
	get: return height * 0.5

## Authored exits (LadderDismount children). Empty = automatic ledge probe at the top.
var dismounts: Array[LadderDismount] = []

func _ready() -> void:
	add_to_group("ladders")
	for child in get_children():
		var dismount := child as LadderDismount
		if dismount != null:
			dismounts.append(dismount)

func has_dismounts() -> bool:
	return not dismounts.is_empty()

func outward() -> Vector3:
	return global_basis.z

func half_width() -> float:
	return width * 0.5

func to_local_pos(world_pos: Vector3) -> Vector3:
	return global_transform.affine_inverse() * world_pos

func to_world_pos(local_pos: Vector3) -> Vector3:
	return global_transform * local_pos
