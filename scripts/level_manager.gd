extends Node3D

var player: Player

func _ready() -> void:
	if GameManager.main_node != null:
		player = GameManager.main_node.player
	
	if player == null:
		return
	
	# Reset the "Current Level" trackers before counting
	if player.has_method("reset_keys_for_level"):
		player.reset_keys_for_level()
	
	var total_keys := count_all_keys() 
	if player.has_method("set_total_keys"):
		player.set_total_keys(total_keys)

func count_all_keys() -> int:
	var count := 0
	# Get every node tagged in the "power_ups" group
	var all_powerups := get_tree().get_nodes_in_group("power_ups")
	
	for p in all_powerups:
		# Check if the power-up type is 'key' (Index 2 in enum)
		if p.get("type") == 2: 
			count += 1
	return count
