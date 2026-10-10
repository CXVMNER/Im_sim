extends PanelContainer
## One line in the HUD notification stack. Fades in, holds, fades out, then removes itself.

@export var hold_time := 2.2
@export var fade_time := 0.6

@onready var _text: Label = %Text


func show_text(text: String, color: Color) -> void:
	_text.text = text
	if color == Color.WHITE:
		_text.remove_theme_color_override("font_color")
	else:
		_text.add_theme_color_override("font_color", color)
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.12)
	tween.tween_interval(hold_time)
	tween.tween_property(self, "modulate:a", 0.0, fade_time)
	tween.tween_callback(queue_free)
