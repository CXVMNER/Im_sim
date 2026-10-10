extends Control
class_name OptionsMenu
## Settings screen shared by the main menu and the pause menu.
## Values are saved to user://settings.cfg and re-applied at startup.

signal closed

const SETTINGS_PATH := "user://settings.cfg"
## Slider value 5 maps to 0.005, the player's sensitivity in fpp_controller.tscn
const SENSITIVITY_PER_STEP := 0.001

@onready var _sensitivity_slider: HSlider = %SensitivitySlider
@onready var _sensitivity_value: Label = %SensitivityValue
@onready var _volume_slider: HSlider = %VolumeSlider
@onready var _volume_value: Label = %VolumeValue
@onready var _fullscreen_check: CheckBox = %FullscreenCheck
@onready var _fps_check: CheckBox = %FpsCheck


func _ready() -> void:
	# set_*_no_signal so loading the saved values does not write them back
	_sensitivity_slider.set_value_no_signal(get_saved("controls", "sensitivity", 5.0))
	_volume_slider.set_value_no_signal(get_saved("audio", "master_volume", 1.0) * 100.0)
	_fps_check.set_pressed_no_signal(get_saved("video", "show_fps", false))
	visibility_changed.connect(_on_visibility_changed)
	_sync_fullscreen_check()
	_refresh_labels()


func _on_visibility_changed() -> void:
	# Read the real window state each time the screen opens, in case F11 or the OS changed it
	if visible:
		_sync_fullscreen_check()


func focus_first() -> void:
	_sensitivity_slider.grab_focus()


func _on_sensitivity_changed(value: float) -> void:
	set_saved("controls", "sensitivity", value)
	_apply_sensitivity(value)
	_refresh_labels()


func _on_volume_changed(value: float) -> void:
	set_saved("audio", "master_volume", value / 100.0)
	_apply_volume(value / 100.0)
	_refresh_labels()


func _on_fullscreen_toggled(pressed: bool) -> void:
	set_saved("video", "fullscreen", pressed)
	_apply_fullscreen(pressed)


func _on_fps_toggled(pressed: bool) -> void:
	set_saved("video", "show_fps", pressed)
	_apply_show_fps(pressed)


func _on_back_pressed() -> void:
	closed.emit()


func _refresh_labels() -> void:
	_sensitivity_value.text = "%.1f" % _sensitivity_slider.value
	_volume_value.text = "%d%%" % roundi(_volume_slider.value)


func _sync_fullscreen_check() -> void:
	_fullscreen_check.set_pressed_no_signal(is_fullscreen())


# ---------------------------------------------------------------- SAVE / LOAD

static func get_saved(section: String, key: String, default_value: Variant) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return default_value
	return cfg.get_value(section, key, default_value)


static func set_saved(section: String, key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # fine if the file does not exist yet
	cfg.set_value(section, key, value)
	cfg.save(SETTINGS_PATH)


## Called once at startup (main menu and main scene) so saved values take effect.
static func apply_saved_settings() -> void:
	_apply_volume(get_saved("audio", "master_volume", 1.0))
	_apply_fullscreen(get_saved("video", "fullscreen", false))
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK and cfg.has_section_key("controls", "sensitivity"):
		_apply_sensitivity(cfg.get_value("controls", "sensitivity"))


# ---------------------------------------------------------------- WINDOW

static func _root_window() -> Window:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root if tree else null


static func is_fullscreen() -> bool:
	var root := _root_window()
	return root != null and root.mode == Window.MODE_FULLSCREEN


## Uses the Window's own mode, so the change applies to the window the game is actually drawn in.
## Borderless fullscreen: it keeps the desktop resolution, so the UI scales to the screen size.
static func _apply_fullscreen(on: bool) -> void:
	var root := _root_window()
	if root:
		root.mode = Window.MODE_FULLSCREEN if on else Window.MODE_WINDOWED


# ---------------------------------------------------------------- APPLY

static func _apply_volume(linear: float) -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(linear, 0.0001)))


static func _apply_sensitivity(steps: float) -> void:
	if PlayerManager.player:
		PlayerManager.player.SENSITIVITY = steps * SENSITIVITY_PER_STEP


static func _apply_show_fps(on: bool) -> void:
	if PlayerManager.player:
		var player = PlayerManager.player
		if player.get("hud"):
			player.hud.show_fps = on
