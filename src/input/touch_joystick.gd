class_name TouchJoystick
extends Control
## On-screen analog stick for touch ("virtual joystick"; named TouchJoystick
## because Godot 4.7 ships an unrelated native VirtualJoystick class).
## Multi-touch safe: it captures the first finger that lands on it and follows
## only that finger's index, so other fingers can use buttons or look around.
##
##   FIXED   — the base sits at the centre of the control;
##   DYNAMIC — the base appears where the finger lands (the control is a touch
##             zone, e.g. the lower-left quarter); with `follow_finger` the base
##             is dragged along when the finger goes past the rim.
##
## Output (`value`, `get_vector()`): length 0..1, screen convention (x right,
## y down — push up gives y = −1, like Input.get_vector). The dead zone is
## removed and the rest rescaled so output ramps smoothly from 0.
##
##   var stick := TouchJoystick.new()
##   stick.set_actions(&"move_left", &"move_right", &"move_forward", &"move_back")  # PC fallback
##   var move := stick.get_vector()
##
## Signals: changed(value), pressed, released.

signal changed(value: Vector2)
signal pressed
signal released

enum Mode { FIXED, DYNAMIC }

@export var mode: Mode = Mode.DYNAMIC
## Fraction of the radius that produces no output.
@export_range(0.0, 0.9) var dead_zone: float = 0.15
## Base radius at UI scale 1 (canvas px).
@export var base_radius: float = 76.0
## DYNAMIC: drag the base along when the finger leaves the rim.
@export var follow_finger: bool = true
## Where the idle base is drawn in DYNAMIC mode (fraction of the control size).
@export var idle_anchor: Vector2 = Vector2(0.5, 0.62)
## Opacity of the idle hint in DYNAMIC mode.
@export var idle_alpha: float = 0.45
## Icon in the knob (optional).
@export var knob_icon: StringName = &""

var value: Vector2 = Vector2.ZERO
var is_active: bool = false

var _touch := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO
var _actions: Array[StringName] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


## Keyboard / gamepad fallback when no finger is on the stick (PC).
func set_actions(left: StringName, right: StringName, up: StringName, down: StringName) -> void:
	_actions.assign([left, right, up, down])


## Pure stick maths: output for a finger at `touch` around `origin`.
static func compute(touch: Vector2, origin: Vector2, radius: float, dz: float) -> Vector2:
	var d := touch - origin
	var len_norm := d.length() / maxf(radius, 0.001)
	if len_norm <= dz:
		return Vector2.ZERO
	var mag := clampf((len_norm - dz) / maxf(1.0 - dz, 0.001), 0.0, 1.0)
	return d.normalized() * mag


func radius_px() -> float:
	return base_radius * UITheme.scale_of(self)


func get_vector() -> Vector2:
	if is_active or _actions.size() < 4:
		return value
	for a in _actions:
		if not InputMap.has_action(a):
			return value
	return Input.get_vector(_actions[0], _actions[1], _actions[2], _actions[3])


func _idle_center() -> Vector2:
	if mode == Mode.FIXED:
		return size * 0.5
	var r := radius_px()
	return Vector2(clampf(size.x * idle_anchor.x, r, maxf(r, size.x - r)), clampf(size.y * idle_anchor.y, r, maxf(r, size.y - r)))


func _gui_input(event: InputEvent) -> void:
	var st := event as InputEventScreenTouch
	if st != null:
		if st.pressed and _touch < 0:
			_touch = st.index
			is_active = true
			_origin = _idle_center() if mode == Mode.FIXED else _clamp_origin(st.position)
			_move_to(st.position)
			pressed.emit()
			accept_event()
		elif not st.pressed and st.index == _touch:
			_release()
			accept_event()
		return
	var sd := event as InputEventScreenDrag
	if sd != null and sd.index == _touch:
		_move_to(sd.position)
		accept_event()


func _clamp_origin(p: Vector2) -> Vector2:
	var r := radius_px() * 0.6
	return Vector2(clampf(p.x, r, maxf(r, size.x - r)), clampf(p.y, r, maxf(r, size.y - r)))


func _move_to(p: Vector2) -> void:
	var r := radius_px()
	if mode == Mode.DYNAMIC and follow_finger:
		var d := p - _origin
		if d.length() > r:
			_origin = p - d.normalized() * r
	var off := (p - _origin).limit_length(r)
	_knob = off
	var v := compute(p, _origin, r, dead_zone)
	if v != value:
		value = v
		changed.emit(v)
	queue_redraw()


func _release() -> void:
	_touch = -1
	is_active = false
	_knob = Vector2.ZERO
	if value != Vector2.ZERO:
		value = Vector2.ZERO
		changed.emit(value)
	released.emit()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and _touch >= 0:
		_release()
	elif what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var r := radius_px()
	var c := _origin if is_active else _idle_center()
	var a := 1.0 if is_active or mode == Mode.FIXED else idle_alpha
	var panel := UITheme.color(self, &"panel")
	var border := UITheme.color(self, &"border_strong")
	var accent := UITheme.color(self, &"accent")
	draw_circle(c, r, Color(panel, 0.55 * a), true, -1.0, true)
	draw_arc(c, r - 1.0, 0.0, TAU, 64, Color(border, border.a * a * 1.4), maxf(1.5, 2.0 * UITheme.scale_of(self)), true)
	# Dead-zone ring and direction ticks help aim without looking.
	draw_arc(c, r * dead_zone, 0.0, TAU, 32, Color(border, 0.35 * a), 1.0, true)
	for i in 4:
		var d := Vector2.from_angle(TAU * float(i) / 4.0)
		draw_line(c + d * r * 0.78, c + d * r * 0.9, Color(border, 0.5 * a), maxf(1.0, 2.0 * UITheme.scale_of(self)), true)
	var kr := r * 0.42
	var kc := c + _knob
	var kcol := accent if is_active else UITheme.color(self, &"surface_hover")
	draw_circle(kc + Vector2(0, 2), kr, Color(0, 0, 0, 0.25 * a), true, -1.0, true)
	draw_circle(kc, kr, Color(kcol, 0.92 * a), true, -1.0, true)
	if knob_icon != &"":
		var ic := UITheme.color(self, &"accent_text") if is_active else UITheme.color(self, &"text")
		Icons.draw(self, knob_icon, Rect2(kc - Vector2(kr, kr) * 0.55, Vector2(kr, kr) * 1.1), Color(ic, a))
