class_name InputActions
extends RefCounted
## Game actions registered in InputMap at runtime (not in project.godot), with
## PC keyboard defaults on PHYSICAL keys (WASD works on ЙЦУКЕН/AZERTY too),
## Russian labels, icons for touch buttons, remapping and persistence
## (key "bindings" of SaveSystem controls file).
##
##   InputActions.register_defaults()        # once at startup (idempotent; loads saved remaps)
##   if Input.is_action_just_pressed(&"eat"): ...
##   InputActions.rebind(&"jump", key_event) ; InputActions.save_bindings()
##   InputActions.key_text(&"sprint")        # "Shift"
##
## Touch: TouchButton(action = &"jump") presses the same actions.

const CONTEXT: Array[StringName] = [
	&"eat", &"drink", &"attack", &"jump", &"sprint", &"call", &"mate", &"rest",
	&"fly_toggle", &"dive", &"ascend", &"descend", &"interact",
]
const MOVEMENT: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right"]
const CAMERA: Array[StringName] = [&"cam_yaw_left", &"cam_yaw_right", &"cam_zoom_in", &"cam_zoom_out", &"cam_up", &"cam_down", &"camera_mode"]

## action → {label, icon, keys: Array[Key] (physical)}
const DEFS := {
	&"move_forward": {"label": "Вперёд", "icon": &"chevron_up", "keys": [KEY_W, KEY_UP]},
	&"move_back": {"label": "Назад", "icon": &"chevron_down", "keys": [KEY_S, KEY_DOWN]},
	&"move_left": {"label": "Влево", "icon": &"chevron_left", "keys": [KEY_A, KEY_LEFT]},
	&"move_right": {"label": "Вправо", "icon": &"chevron_right", "keys": [KEY_D, KEY_RIGHT]},
	&"eat": {"label": "Есть", "icon": &"leaf", "keys": [KEY_F]},
	&"drink": {"label": "Пить", "icon": &"drop", "keys": [KEY_G]},
	&"attack": {"label": "Атака", "icon": &"claw", "keys": [KEY_R]},
	&"jump": {"label": "Прыжок", "icon": &"jump", "keys": [KEY_SPACE]},
	&"sprint": {"label": "Бег", "icon": &"sprint", "keys": [KEY_SHIFT]},
	&"call": {"label": "Зов", "icon": &"sound", "keys": [KEY_C]},
	&"mate": {"label": "Спаривание", "icon": &"heart", "keys": [KEY_M]},
	&"rest": {"label": "Отдых", "icon": &"zzz", "keys": [KEY_H]},
	&"fly_toggle": {"label": "Полёт", "icon": &"bird", "keys": [KEY_X]},
	&"dive": {"label": "Нырнуть", "icon": &"dive", "keys": [KEY_CTRL]},
	&"ascend": {"label": "Вверх", "icon": &"chevron_up", "keys": [KEY_Q]},
	&"descend": {"label": "Вниз", "icon": &"chevron_down", "keys": [KEY_Z]},
	&"interact": {"label": "Действие", "icon": &"pointer", "keys": [KEY_E]},
	&"cam_yaw_left": {"label": "Камера: поворот влево", "icon": &"rotate", "keys": [KEY_Q]},
	&"cam_yaw_right": {"label": "Камера: поворот вправо", "icon": &"rotate", "keys": [KEY_E]},
	&"cam_zoom_in": {"label": "Камера: приблизить", "icon": &"plus", "keys": [KEY_EQUAL, KEY_KP_ADD]},
	&"cam_zoom_out": {"label": "Камера: отдалить", "icon": &"minus", "keys": [KEY_MINUS, KEY_KP_SUBTRACT]},
	&"cam_up": {"label": "Камера: выше", "icon": &"chevron_up", "keys": [KEY_SPACE]},
	&"cam_down": {"label": "Камера: ниже", "icon": &"chevron_down", "keys": [KEY_CTRL]},
	&"camera_mode": {"label": "Вид от 1-го / 3-го лица", "icon": &"camera", "keys": [KEY_V]},
}


static func all() -> Array[StringName]:
	var out: Array[StringName] = []
	out.append_array(MOVEMENT)
	out.append_array(CONTEXT)
	out.append_array(CAMERA)
	return out


static func label(action: StringName) -> String:
	return TranslationServer.translate(str(DEFS.get(action, {}).get("label", action)))


static func icon(action: StringName) -> StringName:
	return DEFS.get(action, {}).get("icon", &"info")


## Adds missing actions with default keys, then applies saved remaps. Safe to call repeatedly.
static func register_defaults(load_saved: bool = true) -> void:
	for a in all():
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.2)
			for k in DEFS[a]["keys"]:
				InputMap.action_add_event(a, key_event(k))
	if load_saved:
		load_bindings()


static func key_event(physical: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = physical
	return e


## Replaces the keyboard bindings of `action` with `event` (other device events stay).
static func rebind(action: StringName, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
	InputMap.action_add_event(action, event)


static func reset(action: StringName) -> void:
	if not DEFS.has(action):
		return
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, 0.2)
	for k in DEFS[action]["keys"]:
		InputMap.action_add_event(action, key_event(k))


static func reset_all() -> void:
	for a in all():
		reset(a)


## "Space", "W / Up" — readable key names of an action's keyboard bindings.
static func key_text(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	var parts := PackedStringArray()
	for e in InputMap.action_get_events(action):
		var k := e as InputEventKey
		if k != null:
			var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			parts.append(OS.get_keycode_string(code))
	return " / ".join(parts)


## {action: [physical keycodes]} for keyboard bindings that differ from defaults.
static func to_dict() -> Dictionary:
	var out := {}
	for a in all():
		if not InputMap.has_action(a):
			continue
		var codes: Array = []
		for e in InputMap.action_get_events(a):
			var k := e as InputEventKey
			if k != null:
				codes.append(int(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode))
		var defaults: Array = []
		for dk in DEFS[a]["keys"]:
			defaults.append(int(dk))
		if codes != defaults:
			out[String(a)] = codes
	return out


static func from_dict(d: Dictionary) -> void:
	for key in d:
		var a := StringName(str(key))
		if not DEFS.has(a) or not (d[key] is Array):
			continue
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.2)
		for e in InputMap.action_get_events(a):
			if e is InputEventKey:
				InputMap.action_erase_event(a, e)
		for code in d[key]:
			InputMap.action_add_event(a, key_event(int(code)))


static func save_bindings() -> void:
	var all_controls := SaveSystem.load_controls()
	all_controls["bindings"] = to_dict()
	SaveSystem.save_controls(all_controls)


static func load_bindings() -> void:
	var c := SaveSystem.load_controls()
	var b: Variant = c.get("bindings", {})
	if b is Dictionary:
		from_dict(b)
