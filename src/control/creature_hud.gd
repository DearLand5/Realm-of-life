class_name CreatureHud
extends Control
## HUD of a possessed creature: joystick and context buttons laid out by
## ControlLayout (profiles first_person / third_person, left-handed mirroring),
## physiological feedback (health, energy, water, stamina bars), the current
## action, an exit button and direction hints for smell / hearing / vibration.

signal exit_requested

const BAR_KEYS := [&"health", &"energy", &"water", &"stamina"]

var layout: ControlLayout
var profile: StringName = &"third_person"
var stick: TouchJoystick
var buttons: Dictionary = {}          # layout id -> TouchButton
var exit_button: IconButton
var title_label: Label
var action_label: Label
var hint_label: Label
var look_surface: Control             # full-screen touch area for looking around (under the controls)

var _vitals := {"health": 1.0, "energy": 1.0, "water": 1.0, "stamina": 1.0, "temp": 0.0}
var _hints: Array = []                # [{angle, kind, strength}] relative to the view direction
var _compass_yaw: float = 0.0
var _layout_dirty := true
var _safe: Control


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(mode: StringName, control_layout: ControlLayout = null) -> void:
	profile = mode
	layout = control_layout if control_layout != null else ControlLayout.load_saved()
	# The default camera button collides with the first context button: tuck it under the exit button.
	layout.register_element(profile, &"btn_camera", {"icon": &"camera", "action": &"camera_mode", "label": "Вид",
		"base": Vector2(56, 56), "anchor": Vector2(1, 0), "offset": Vector2(-34, 96)})
	InputActions.register_defaults(false)
	UITheme.attach(self)
	look_surface = Control.new()
	look_surface.name = "LookSurface"
	look_surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	look_surface.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(look_surface)
	_safe = Control.new()
	_safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_safe)
	var top := VBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.position = Vector2(8, 8)
	title_label = Label.new()
	top.add_child(title_label)
	action_label = Label.new()
	action_label.modulate = Color(1, 1, 1, 0.85)
	top.add_child(action_label)
	_safe.add_child(top)
	_top_box = top
	exit_button = IconButton.make(&"exit", "", tr("Выйти из управления"))
	exit_button.custom_minimum_size = Vector2(56, 56)
	exit_button.pressed.connect(func() -> void: exit_requested.emit())
	_safe.add_child(exit_button)
	hint_label = Label.new()
	hint_label.modulate = Color(1, 1, 1, 0.8)
	hint_label.visible = false
	_safe.add_child(hint_label)
	_build_controls()
	resized.connect(func() -> void: _layout_dirty = true)


var _top_box: VBoxContainer


func _build_controls() -> void:
	for id in layout.element_ids(profile):
		var def := layout.definition(profile, id)
		if def.get("kind", &"button") == &"joystick":
			stick = TouchJoystick.new()
			stick.name = String(id)
			stick.mode = TouchJoystick.Mode.DYNAMIC
			stick.set_actions(&"move_left", &"move_right", &"move_forward", &"move_back")
			stick.knob_icon = &"move"
			add_child(stick)
			continue
		var b := TouchButton.make(def.get("icon", &"info"), def.get("action", &""), tr(str(def.get("label", ""))))
		b.name = String(id)
		b.visible = false
		add_child(b)
		buttons[id] = b


func _safe_rect() -> Rect2:
	var ins := SafeArea.insets_for(self)
	return Rect2(Vector2(ins.x, ins.y), size - Vector2(ins.x + ins.z, ins.y + ins.w))


## Positions the controls (call when the size, scale or handedness changes).
func layout_controls() -> void:
	_layout_dirty = false
	layout.left_handed = bool(UIApp.setting("left_handed", false))
	var area := _safe_rect()
	var sc := UITheme.ui_scale()
	var all := buttons.duplicate()
	if stick != null:
		all[&"joy_move"] = stick
		# The joystick zone covers the lower-left (or right) half so the finger can land anywhere there.
		var e := layout.element(profile, &"joy_move")
		var zone_w := area.size.x * 0.46
		var x := area.position.x if float((e["anchor"] as Vector2).x) < 0.5 else area.end.x - zone_w
		stick.position = Vector2(x, area.position.y + area.size.y * 0.38)
		stick.size = Vector2(zone_w, area.size.y * 0.62)
		stick.idle_anchor = Vector2(0.5 if float((e["anchor"] as Vector2).x) < 0.5 else 0.5, 0.7)
		all.erase(&"joy_move")
	var vis := {}
	for id in buttons:
		vis[id] = (buttons[id] as TouchButton).visible
	layout.apply(profile, buttons, area, sc)
	for id in buttons:
		(buttons[id] as TouchButton).visible = vis[id]
	exit_button.position = Vector2(area.end.x - 62.0 * sc, area.position.y + 6.0)
	exit_button.size = Vector2(56.0, 56.0) * sc
	hint_label.position = Vector2(area.position.x + 8.0, area.end.y - 120.0 * sc)


## Per-frame refresh. `visible_ids`: layout id -> bool (ControlScheme.visible_buttons).
func refresh(agent: CreatureAgent, visible_ids: Dictionary, hints: Array, view_yaw: float, toggles: Dictionary) -> void:
	if _layout_dirty:
		layout_controls()
	var st := agent.get_status()
	_vitals["health"] = float(st["health"])
	_vitals["energy"] = float(st["energy_frac"])
	_vitals["water"] = clampf(float(st["hydration"]), 0.0, 1.0)
	_vitals["stamina"] = float(st["stamina"])
	title_label.text = "%s" % st["name"]
	action_label.text = str(st["action"])
	for id in buttons:
		var b: TouchButton = buttons[id]
		var want := bool(visible_ids.get(id, false))
		if b.visible != want:
			b.visible = want
		if toggles.has(id):
			b.toggled_on = bool(toggles[id])
	_hints = hints
	_compass_yaw = view_yaw
	queue_redraw()


func _draw() -> void:
	var sc := UITheme.ui_scale()
	var area := _safe_rect()
	# Vitals: four bars with icons under the title (top-left).
	var x0 := area.position.x + 8.0
	var y0 := area.position.y + 78.0 * sc
	var w := 150.0 * sc
	var h := 11.0 * sc
	var icons := {&"health": &"heart", &"energy": &"leaf", &"water": &"drop", &"stamina": &"sprint"}
	var i := 0
	for key in BAR_KEYS:
		var v := clampf(float(_vitals[key]), 0.0, 1.0)
		var y := y0 + float(i) * (h + 9.0 * sc)
		var col := _bar_color(key, v)
		Icons.draw(self, icons[key], Rect2(x0, y - 4.0 * sc, 20.0 * sc, 20.0 * sc), Color(1, 1, 1, 0.9))
		var bx := x0 + 26.0 * sc
		draw_rect(Rect2(bx, y, w, h), Color(0, 0, 0, 0.4))
		draw_rect(Rect2(bx, y, w * v, h), col)
		draw_rect(Rect2(bx, y, w, h), Color(1, 1, 1, 0.35), false, 1.0)
		i += 1
	# Direction hints (smell / hearing / vibration) as small markers around the centre.
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.36
	for hnt in _hints:
		var ang: float = float(hnt["angle"])
		var p := c + Vector2(sin(ang), -cos(ang)) * r
		var col2 := _hint_color(hnt["kind"])
		col2.a = clampf(float(hnt["strength"]), 0.25, 0.95)
		var d := Vector2(sin(ang), -cos(ang))
		var n := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([p + d * 10.0 * sc, p - d * 6.0 * sc + n * 7.0 * sc, p - d * 6.0 * sc - n * 7.0 * sc]), col2)


func _bar_color(key: StringName, v: float) -> Color:
	var good := UITheme.color(self, &"good")
	var warn := UITheme.color(self, &"warn")
	var bad := UITheme.color(self, &"bad")
	var info := UITheme.color(self, &"info")
	var base := good
	match key:
		&"water":
			base = info
		&"stamina":
			base = Color(0.95, 0.85, 0.35)
	if v < 0.15:
		return bad
	if v < 0.35:
		return warn
	return base


func _hint_color(kind: StringName) -> Color:
	match kind:
		&"smell":
			return Color(0.55, 0.9, 0.45)
		&"hearing":
			return Color(0.95, 0.85, 0.4)
		&"vibration":
			return Color(0.75, 0.6, 0.45)
	return Color(0.8, 0.8, 0.8)
