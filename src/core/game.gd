extends Node
## Global application state (autoload "Game").
##   * service registry — the active world registers its systems here so UI and
##     tools find them without hard node paths;
##   * scene transitions with a payload (e.g. which species to edit);
##   * persistent user settings and the player's species library.

const VERSION := "0.1.5"
const SCENE_MENU := "res://scenes/main_menu.tscn"
const SCENE_EDITOR := "res://scenes/creature_editor.tscn"
const SCENE_WORLD := "res://scenes/world.tscn"

const DEFAULT_SETTINGS := {
	"quality": "auto",          # auto | low | medium | high
	"creature_shading": "auto", # auto (simple on phones) | full | lite
	"ui_scale": 1.0,
	"text_scale": 1.0,
	"language": "ru",
	"fps_cap": 60,
	"battery_saver": false,
	"show_tutorial": true,
	"colorblind_mode": "none",  # none | deuteranopia | protanopia | tritanopia
	"camera_sensitivity": 1.0,
	"invert_y": false,
	"high_contrast": false,
	"show_perf": false,
	"left_handed": false,
	"music_volume": 0.6,
	"sfx_volume": 0.8,
}

## Transient data passed between scenes (cleared by the receiver).
var pending: Dictionary = {}
var settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
var _services: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var loaded := SaveSystem.load_settings()
	for k in loaded:
		settings[k] = loaded[k]
	apply_settings()
	_enter_immersive()
	add_child(AndroidImmersive.new())


## Phones: keep the status and navigation bars hidden (immersive fullscreen);
## Android shows them again after a swipe or when the app comes back.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_enter_immersive()


func _enter_immersive() -> void:
	if OS.has_feature("mobile") and DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func register_service(id: StringName, obj: Object) -> void:
	_services[id] = obj


func unregister_service(id: StringName, obj: Object = null) -> void:
	if obj == null or _services.get(id) == obj:
		_services.erase(id)


func service(id: StringName) -> Object:
	var s = _services.get(id)
	if s != null and not is_instance_valid(s):
		_services.erase(id)
		return null
	return s


func has_service(id: StringName) -> bool:
	return service(id) != null


func setting(key: String):
	return settings.get(key, DEFAULT_SETTINGS.get(key))


func set_setting(key: String, value) -> void:
	settings[key] = value
	apply_settings()
	SaveSystem.save_settings(settings)
	EventBus.settings_changed.emit(key, value)


func apply_settings() -> void:
	var cap := int(settings.get("fps_cap", 60))
	if bool(settings.get("battery_saver", false)):
		cap = mini(cap, 30)
	Engine.max_fps = cap
	var shading := str(settings.get("creature_shading", "auto"))
	CreatureMaterials.lite = shading == "lite" or (shading == "auto" and OS.has_feature("mobile"))


## Changes scene with a payload readable via `Game.take_pending()`.
func goto_scene(path: String, payload: Dictionary = {}) -> void:
	pending = payload
	get_tree().paused = false
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Game.goto_scene: cannot open %s (%s)" % [path, error_string(err)])
		EventBus.notify.emit("Не удалось открыть сцену", &"error")


func take_pending() -> Dictionary:
	var p := pending
	pending = {}
	return p


func notify(text: String, level: StringName = &"info") -> void:
	EventBus.notify.emit(text, level)
