extends Camera3D

# The "safe" aspect ratio you want to target (16:10 = 1.6)
const BASE_ASPECT_RATIO : = 16.0 / 10.0

# The vertical FOV you want at that 16:10 ratio
@export var base_vertical_fov : float = 75.0

func _ready() -> void:
	# Update camera on start and whenever the window resizes
	get_tree().root.size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()

func _on_viewport_size_changed() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	var current_aspect : float = viewport_size.x / viewport_size.y
	
	if current_aspect >= BASE_ASPECT_RATIO:
		# WIDER than 16:10: Keep the height fixed, let width expand.
		keep_aspect = Camera3D.KEEP_HEIGHT
		fov = base_vertical_fov
	else:
		# TALLER than 16:10: Keep the width fixed, let height expand.
		keep_aspect = Camera3D.KEEP_WIDTH
		# When using KEEP_WIDTH, the 'fov' property represents Horizontal FOV.
		# We must calculate the H-FOV that matches our base V-FOV at the 16:10 ratio.
		fov = _get_horizontal_fov(base_vertical_fov, BASE_ASPECT_RATIO)

func _get_horizontal_fov(vertical_fov_deg: float, aspect_ratio: float) -> float:
	# Formula: tan(h_fov / 2) = aspect * tan(v_fov / 2)
	var v_fov_rad : float = deg_to_rad(vertical_fov_deg)
	var h_fov_rad : float = 2.0 * atan(aspect_ratio * tan(v_fov_rad / 2.0))
	return rad_to_deg(h_fov_rad)
