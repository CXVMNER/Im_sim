extends Control

class_name PauseMenu

@onready var label := $Label
@onready var game_over_label := $GameOverLabel

var is_game_over: bool = false # A flag to prevent unpausing

func set_game_over(state: bool) -> void:
	is_game_over = state
	game_over_label.visible = state # Show/Hide the "GAME OVER" label
	
	# Hide the "Paused" label if 'Game Over' is true
	if $Label:
		$Label.visible = !state

# To have logic to handle buttons like 'Resume', I'd need to modify them here as well.
# Since this script does not show have button logic, 
# we rely on the controller to prevent unpausing.
