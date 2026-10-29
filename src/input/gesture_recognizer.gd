class_name GestureRecognizer
extends Node
## Turns raw touch input (plus PC mouse wheel / right / middle drag and
## trackpad gestures) into high-level gestures for 3D views and canvases.
##
## Feeding events — pick one:
##   rec.attach_to(surface_control)       # connects its gui_input (recommended:
##                                        # a full-rect Control under the HUD)
##   rec.listen_unhandled = true          # uses _unhandled_input (viewport coords)
##   rec.handle_event(event)              # manual; returns true if consumed
## Positions are in the coordinate space of the events you feed (Control-local
## for gui_input).
##
## Classification (single finger):
##   * tap — released before `long_press_time` without moving `drag_threshold`;
##   * double_tap — second tap within `double_tap_time` / `double_tap_distance`
##     (the first one is reported as tap too, unless `exclusive_double_tap`);
##   * long_press — held still for `long_press_time` (fires while holding);
##   * drag_started/drag/drag_ended — after moving past `drag_threshold`;
##     after a long press, moving starts a drag with after_long_press = true.
## Two fingers: pinch (incremental scale factor, >1 = fingers apart),
## two_finger_drag (centre motion), two_finger_rotate (radians, + = clockwise
## on screen). Each component starts after its own threshold, then reports
## continuously; together the increments add up to the exact finger motion.
## After a two-finger gesture the remaining finger is ignored until all lift.
##
## PC: wheel → pinch (at cursor), right-drag → orbit_drag, right click without
## motion → secondary_tap, middle-drag → two_finger_drag, trackpad magnify →
## pinch, trackpad pan → two_finger_drag. Left mouse buttons and plain mouse
## motion are IGNORED: with `emulate_touch_from_mouse` the same click also
## arrives as a touch, and on phones touches also emulate the mouse.

signal tap(pos: Vector2)
signal double_tap(pos: Vector2)
signal long_press(pos: Vector2)
signal drag_started(pos: Vector2, after_long_press: bool)
signal drag(pos: Vector2, relative: Vector2)
signal drag_ended(pos: Vector2, velocity: Vector2)
signal two_finger_started(center: Vector2)
signal pinch(factor: float, center: Vector2)
signal two_finger_drag(relative: Vector2, center: Vector2)
signal two_finger_rotate(angle: float, center: Vector2)
signal two_finger_ended
signal orbit_drag(relative: Vector2, pos: Vector2)
signal secondary_tap(pos: Vector2)

enum State { IDLE, PENDING, DRAGGING, HELD, MULTI, BLOCKED }

@export var drag_threshold: float = 12.0
@export var long_press_time: float = 0.5
@export var double_tap_time: float = 0.3
@export var double_tap_distance: float = 40.0
## Delay single taps by double_tap_time so a double tap never also reports a tap.
@export var exclusive_double_tap: bool = false
## Relative finger-distance change that starts a pinch.
@export var pinch_threshold: float = 0.06
## Centre movement (px) that starts a two-finger pan.
@export var pan_threshold: float = 12.0
## Twist (degrees) that starts a rotation.
@export var rotate_threshold_deg: float = 10.0
## Zoom factor per wheel notch.
@export var wheel_step: float = 1.12
## Pixels per trackpad pan-gesture unit.
@export var pan_gesture_scale: float = 10.0
## Process `_unhandled_input` automatically.
@export var listen_unhandled: bool = false
## Multiply pixel thresholds by the UI scale when entering the tree.
@export var scale_thresholds: bool = true

var state: State = State.IDLE

var _touches: Dictionary = {}  # index → {start, pos, t0}
var _primary := -1
var _last_tap_t := -100.0
var _last_tap_pos := Vector2.ZERO
var _pending_tap := false
var _pending_tap_pos := Vector2.ZERO
var _pending_tap_t := 0.0
var _vel_samples: Array = []  # [[pos, t]]
# Two-finger state.
var _m_ids: Array[int] = []
var _m_start_dist := 1.0
var _m_start_angle := 0.0
var _m_start_center := Vector2.ZERO
var _m_last_dist := 1.0
var _m_last_angle := 0.0
var _m_last_center := Vector2.ZERO
var _pinch_on := false
var _pan_on := false
var _rot_on := false
# Mouse (PC).
var _rmb := false
var _rmb_start := Vector2.ZERO
var _rmb_moved := false
var _mmb := false
var _attached: Control


func _ready() -> void:
	if scale_thresholds:
		var k := UITheme.ui_scale()
		drag_threshold *= k
		double_tap_distance *= k
		pan_threshold *= k


func _process(_delta: float) -> void:
	update()


func _unhandled_input(event: InputEvent) -> void:
	if listen_unhandled and handle_event(event):
		get_viewport().set_input_as_handled()


## Routes `control.gui_input` into this recognizer (accepting consumed events).
func attach_to(control: Control) -> void:
	if _attached != null and _attached.gui_input.is_connected(_on_attached_input):
		_attached.gui_input.disconnect(_on_attached_input)
	_attached = control
	control.gui_input.connect(_on_attached_input)


func _on_attached_input(event: InputEvent) -> void:
	if handle_event(event) and is_instance_valid(_attached):
		_attached.accept_event()


func active_touch_count() -> int:
	return _touches.size()


## Forgets all touches (e.g. when the view loses focus).
func reset() -> void:
	if state == State.DRAGGING and _touches.has(_primary):
		drag_ended.emit(_touches[_primary]["pos"], Vector2.ZERO)
	elif state == State.MULTI:
		two_finger_ended.emit()
	_touches.clear()
	_primary = -1
	_m_ids.clear()
	state = State.IDLE
	_rmb = false
	_mmb = false


static func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0


## Feeds one event. `now` (seconds) overrides the clock (tests). Returns true if consumed.
func handle_event(event: InputEvent, now: float = -1.0) -> bool:
	var t := now if now >= 0.0 else _now()
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch, t)
		return true
	if event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag, t)
		return true
	if event is InputEventMouseButton:
		return _on_mouse_button(event as InputEventMouseButton)
	if event is InputEventMouseMotion:
		return _on_mouse_motion(event as InputEventMouseMotion)
	if event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		if mg.factor > 0.0:
			pinch.emit(mg.factor, mg.position)
		return true
	if event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		two_finger_drag.emit(-pg.delta * pan_gesture_scale, pg.position)
		return true
	return false


## Time-based recognition (long press, deferred taps). Called every frame when
## in the tree; tests call it with an explicit `now`.
func update(now: float = -1.0) -> void:
	var t := now if now >= 0.0 else _now()
	if state == State.PENDING and _touches.has(_primary):
		var tp: Dictionary = _touches[_primary]
		if t - float(tp["t0"]) >= long_press_time:
			state = State.HELD
			long_press.emit(tp["start"])
	if _pending_tap and t - _pending_tap_t > double_tap_time:
		_pending_tap = false
		tap.emit(_pending_tap_pos)


# --- Touch ----------------------------------------------------------------------------

func _on_touch(e: InputEventScreenTouch, t: float) -> void:
	if e.canceled:
		reset()
		return
	if e.pressed:
		_touches[e.index] = {"start": e.position, "pos": e.position, "t0": t}
		match _touches.size():
			1:
				if state == State.IDLE or state == State.BLOCKED:
					state = State.PENDING
					_primary = e.index
					_vel_samples = [[e.position, t]]
			2:
				if state == State.DRAGGING:
					drag_ended.emit(_touches[_primary]["pos"], Vector2.ZERO)
				_begin_multi()
			_:
				if state != State.MULTI:
					_begin_multi()
		return
	if not _touches.has(e.index):
		return
	var info: Dictionary = _touches[e.index]
	info["pos"] = e.position
	_touches.erase(e.index)
	match state:
		State.PENDING:
			if e.index == _primary:
				if t - float(info["t0"]) >= long_press_time:
					long_press.emit(info["start"])
				else:
					_register_tap(info["start"], t)
				state = State.IDLE
		State.DRAGGING:
			if e.index == _primary:
				drag_ended.emit(e.position, _velocity())
				state = State.IDLE
		State.HELD:
			if e.index == _primary:
				state = State.IDLE
		State.MULTI:
			if _m_ids.has(e.index):
				two_finger_ended.emit()
				_m_ids.clear()
				state = State.BLOCKED if not _touches.is_empty() else State.IDLE
	if _touches.is_empty():
		state = State.IDLE
		_primary = -1


func _register_tap(pos: Vector2, t: float) -> void:
	var is_double := t - _last_tap_t <= double_tap_time and pos.distance_to(_last_tap_pos) <= double_tap_distance
	if is_double:
		_last_tap_t = -100.0
		_pending_tap = false
		double_tap.emit(pos)
		return
	_last_tap_t = t
	_last_tap_pos = pos
	if exclusive_double_tap:
		_pending_tap = true
		_pending_tap_pos = pos
		_pending_tap_t = t
	else:
		tap.emit(pos)


func _on_drag(e: InputEventScreenDrag, t: float) -> void:
	if not _touches.has(e.index):
		return
	var info: Dictionary = _touches[e.index]
	var prev: Vector2 = info["pos"]
	info["pos"] = e.position
	match state:
		State.PENDING, State.HELD:
			if e.index == _primary and e.position.distance_to(info["start"]) > drag_threshold:
				var after_hold := state == State.HELD
				state = State.DRAGGING
				_vel_samples = [[info["start"], float(info["t0"])]]
				drag_started.emit(info["start"], after_hold)
				drag.emit(e.position, e.position - info["start"])
				_push_vel(e.position, t)
		State.DRAGGING:
			if e.index == _primary:
				drag.emit(e.position, e.position - prev)
				_push_vel(e.position, t)
		State.MULTI:
			if _m_ids.has(e.index):
				_update_multi()


func _push_vel(p: Vector2, t: float) -> void:
	_vel_samples.append([p, t])
	while _vel_samples.size() > 2 and t - float(_vel_samples[0][1]) > 0.1:
		_vel_samples.pop_front()


func _velocity() -> Vector2:
	if _vel_samples.size() < 2:
		return Vector2.ZERO
	var a: Array = _vel_samples.front()
	var b: Array = _vel_samples.back()
	var dt := float(b[1]) - float(a[1])
	if dt <= 0.0001:
		return Vector2.ZERO
	return ((b[0] as Vector2) - (a[0] as Vector2)) / dt


func _begin_multi() -> void:
	var ids: Array = _touches.keys()
	ids.sort()
	_m_ids.clear()
	_m_ids.append(int(ids[0]))
	_m_ids.append(int(ids[1]))
	var pa: Vector2 = _touches[_m_ids[0]]["pos"]
	var pb: Vector2 = _touches[_m_ids[1]]["pos"]
	_m_start_dist = maxf(pa.distance_to(pb), 1.0)
	_m_start_angle = (pb - pa).angle()
	_m_start_center = (pa + pb) * 0.5
	_m_last_dist = _m_start_dist
	_m_last_angle = _m_start_angle
	_m_last_center = _m_start_center
	_pinch_on = false
	_pan_on = false
	_rot_on = false
	state = State.MULTI
	two_finger_started.emit(_m_start_center)


func _update_multi() -> void:
	var pa: Vector2 = _touches[_m_ids[0]]["pos"]
	var pb: Vector2 = _touches[_m_ids[1]]["pos"]
	var d := maxf(pa.distance_to(pb), 1.0)
	var ang := (pb - pa).angle()
	var c := (pa + pb) * 0.5
	if not _pinch_on and absf(d / _m_start_dist - 1.0) > pinch_threshold:
		_pinch_on = true
	if not _pan_on and c.distance_to(_m_start_center) > pan_threshold:
		_pan_on = true
	if not _rot_on and absf(wrapf(ang - _m_start_angle, -PI, PI)) > deg_to_rad(rotate_threshold_deg):
		_rot_on = true
	if _pinch_on and not is_equal_approx(d, _m_last_dist):
		pinch.emit(d / _m_last_dist, c)
		_m_last_dist = d
	if _pan_on and c != _m_last_center:
		two_finger_drag.emit(c - _m_last_center, c)
		_m_last_center = c
	if _rot_on:
		var da := wrapf(ang - _m_last_angle, -PI, PI)
		if absf(da) > 0.00001:
			two_finger_rotate.emit(da, c)
			_m_last_angle = ang


# --- Mouse (PC only) ------------------------------------------------------------------------

func _on_mouse_button(e: InputEventMouseButton) -> bool:
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				var steps := e.factor if e.factor > 0.0 else 1.0
				var f := pow(wheel_step, steps)
				pinch.emit(f if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / f, e.position)
			return true
		MOUSE_BUTTON_RIGHT:
			if e.pressed:
				_rmb = true
				_rmb_start = e.position
				_rmb_moved = false
			else:
				if _rmb and not _rmb_moved:
					secondary_tap.emit(e.position)
				_rmb = false
			return true
		MOUSE_BUTTON_MIDDLE:
			_mmb = e.pressed
			return true
	return false  # left button: handled as emulated touch


func _on_mouse_motion(e: InputEventMouseMotion) -> bool:
	var mask := e.button_mask
	if _rmb and (mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
		if not _rmb_moved and e.position.distance_to(_rmb_start) > drag_threshold * 0.5:
			_rmb_moved = true
		orbit_drag.emit(e.relative, e.position)
		return true
	if _mmb and (mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
		two_finger_drag.emit(e.relative, e.position)
		return true
	return false  # plain / left-drag motion: ignored (touch emulation covers it)
