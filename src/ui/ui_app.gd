class_name UIApp
extends RefCounted
## Late-bound access to the `Game` / `EventBus` autoloads for UI-kit code.
##
## Scripts run with `godot -s` (tools, previews) compile their dependencies
## before autoload names exist, so kit classes never reference `Game` or
## `EventBus` by identifier; they go through these helpers instead. Gameplay
## scenes may keep using the autoloads directly.

static func _root() -> Window:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root if tree != null else null


static func game() -> Node:
	var r := _root()
	return r.get_node_or_null(^"Game") if r != null else null


static func bus() -> Node:
	var r := _root()
	return r.get_node_or_null(^"EventBus") if r != null else null


## Game.setting(key) with a fallback when Game is unavailable or the key is unset.
static func setting(key: String, fallback: Variant = null) -> Variant:
	var g := game()
	if g == null:
		return fallback
	var v: Variant = g.call(&"setting", key)
	return fallback if v == null else v


## Game.set_setting(key, value) (persists and applies).
static func set_setting(key: String, value: Variant) -> void:
	var g := game()
	if g != null:
		g.call(&"set_setting", key, value)


## Emits EventBus.notify(text, level); level: &"info", &"success", &"warning", &"error".
static func notify(text: String, level: StringName = &"info") -> void:
	var b := bus()
	if b != null:
		b.emit_signal(&"notify", text, level)
	else:
		print("[notify:%s] %s" % [level, text])


## Connects `callable` to an EventBus signal (no-op without the autoload).
static func listen(signal_name: StringName, callable: Callable) -> void:
	var b := bus()
	if b != null and b.has_signal(signal_name) and not b.is_connected(signal_name, callable):
		b.connect(signal_name, callable)


static func scene_path(id: String) -> String:
	var g := game()
	if g == null:
		return ""
	return str(g.get(id))


## Game.goto_scene with an existence check: missing scenes show a toast instead
## of failing. `scene_const` is a Game constant name ("SCENE_WORLD", "SCENE_EDITOR",
## "SCENE_MENU") or a res:// path. Returns true if the change was started.
static func goto_scene(scene_const: String, payload: Dictionary = {}) -> bool:
	var path := scene_const if scene_const.begins_with("res://") else scene_path(scene_const)
	if path == "" or not ResourceLoader.exists(path):
		notify(TranslationServer.translate("Этот раздел пока недоступен в текущей сборке"), &"warning")
		return false
	var g := game()
	if g == null:
		return false
	g.call(&"goto_scene", path, payload)
	return true


static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
