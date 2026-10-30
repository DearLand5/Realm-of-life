class_name ControlLayoutDefaults
extends RefCounted
## Default on-screen control layouts per mode (data for ControlLayout).
##
## Element definition keys:
##   kind: &"joystick" | &"button"     icon: StringName    action: StringName (InputMap)
##   label: String                     base: Vector2 — size in canvas px at UI scale 1
##   anchor: Vector2 — point of the safe area (0..1) the element hangs from
##   offset: Vector2 — element centre relative to the anchor point (px at scale 1)
##   size: float (multiplier)          opacity: float          visible: bool
## Right-handed reference; left-handed play mirrors x (ControlLayout.mirror).

const MODE_LABELS := {
	&"observer": "Наблюдатель", &"first_person": "От первого лица",
	&"third_person": "От третьего лица", &"editor": "Редактор",
}


static func _btn(icon: StringName, action: StringName, label: String, anchor: Vector2, offset: Vector2, base: float = 72.0) -> Dictionary:
	return {"kind": &"button", "icon": icon, "action": action, "label": label, "base": Vector2(base, base),
		"anchor": anchor, "offset": offset, "size": 1.0, "opacity": 0.9, "visible": true}


static func _stick(anchor: Vector2, offset: Vector2, label: String) -> Dictionary:
	return {"kind": &"joystick", "icon": &"move", "action": &"", "label": label, "base": Vector2(240, 240),
		"anchor": anchor, "offset": offset, "size": 1.0, "opacity": 0.85, "visible": true}


static func _creature() -> Dictionary:
	var br := Vector2(1, 1)
	var mid := Vector2(1, 0.5)
	return {
		&"joy_move": _stick(Vector2(0, 1), Vector2(160, -160), "Движение"),
		&"btn_jump": _btn(&"jump", &"jump", "Прыжок", br, Vector2(-92, -100), 96.0),
		&"btn_attack": _btn(&"claw", &"attack", "Атака", br, Vector2(-92, -232), 76.0),
		&"btn_interact": _btn(&"pointer", &"interact", "Действие", br, Vector2(-212, -205), 70.0),
		&"btn_sprint": _btn(&"sprint", &"sprint", "Бег", br, Vector2(-220, -82), 76.0),
		&"btn_fly": _btn(&"bird", &"fly_toggle", "Полёт", br, Vector2(-335, -190), 68.0),
		&"btn_dive": _btn(&"dive", &"dive", "Нырнуть", br, Vector2(-335, -82), 68.0),
		&"btn_eat": _btn(&"leaf", &"eat", "Есть", mid, Vector2(-66, -200), 64.0),
		&"btn_drink": _btn(&"drop", &"drink", "Пить", mid, Vector2(-66, -126), 64.0),
		&"btn_mate": _btn(&"heart", &"mate", "Спаривание", mid, Vector2(-66, -52), 64.0),
		&"btn_call": _btn(&"sound", &"call", "Зов", mid, Vector2(-66, 22), 64.0),
		&"btn_rest": _btn(&"zzz", &"rest", "Отдых", mid, Vector2(-142, -200), 64.0),
		&"btn_ascend": _btn(&"chevron_up", &"ascend", "Вверх", Vector2(0, 1), Vector2(345, -235), 68.0),
		&"btn_descend": _btn(&"chevron_down", &"descend", "Вниз", Vector2(0, 1), Vector2(345, -140), 68.0),
		&"btn_camera": _btn(&"camera", &"camera_mode", "Вид", Vector2(1, 0), Vector2(-66, 150), 60.0),
	}


## mode → {id → definition}
static func all() -> Dictionary:
	return {
		&"observer": {
			&"joy_move": _stick(Vector2(0, 1), Vector2(160, -160), "Полёт камеры"),
			&"btn_up": _btn(&"chevron_up", &"cam_up", "Выше", Vector2(1, 1), Vector2(-80, -235), 72.0),
			&"btn_down": _btn(&"chevron_down", &"cam_down", "Ниже", Vector2(1, 1), Vector2(-80, -145), 72.0),
		},
		&"first_person": _creature(),
		&"third_person": _creature(),
		&"editor": {
			&"btn_undo": _btn(&"undo", &"", "Отменить", Vector2(0, 1), Vector2(56, -56), 60.0),
			&"btn_redo": _btn(&"redo", &"", "Повторить", Vector2(0, 1), Vector2(130, -56), 60.0),
			&"btn_focus": _btn(&"eye", &"", "К существу", Vector2(1, 1), Vector2(-56, -56), 60.0),
		},
	}
