class_name FreeCamera
extends Node3D
## Touch-first camera rig (a Node3D holding a Camera3D): orbit around a pivot,
## pan, zoom with distance limits, twist to rotate, free-fly mode, focus/follow,
## terrain clearance and world bounds. All motion is exponentially smoothed;
## one-finger orbit keeps a little inertia — forgiving for imprecise fingers.
##
##   var cam := FreeCamera.new(); add_child(cam)
##   cam.attach_gestures(gestures)                    # GestureRecognizer → orbit/pan/zoom/twist
##   cam.set_height_provider(func(x, z): return world.height_at(x, z))
##   cam.set_bounds(AABB(Vector3(-256, -50, -256), Vector3(512, 400, 512)))
##   cam.focus(pos) ; cam.follow(agent, Vector3(0, 1, 0)) ; cam.unfollow()
##   cam.fly_mode = true ; cam.set_move_input(joystick.get_vector(), 0.0)
##   var ray := cam.screen_ray(tap_pos)               # {origin, dir} for picking
##   var p = cam.ground_point(tap_pos)                # Vector3 or null
##
## Gestures (attach_gestures): 1-finger drag = orbit (look in fly mode; pan if
## `one_finger_pans`), 2-finger drag = pan, pinch = zoom toward the fingers,
## twist = rotate, double tap = focus the tapped ground point.
## PC: right-drag orbit, middle-drag pan, wheel zoom; with `keyboard_enabled`:
## WASD/arrows pan (fly in fly mode), Q/E rotate, +/− zoom, Space/Ctrl up/down,
## Shift faster (InputActions). Sensitivity and invert-Y come from settings
## ("camera_sensitivity", "invert_y").
##
## Signals: follow_ended (manual pan broke follow), fly_mode_changed(on).

signal follow_ended
signal fly_mode_changed(on: bool)

@export var min_distance: float = 2.0
@export var max_distance: float = 600.0
@export var min_pitch_deg: float = -88.0
@export var max_pitch_deg: float = -4.0
## Approach rate of the smoothing (1/s). Higher = snappier.
@export var smoothing: float = 11.0
@export var orbit_deg_per_px: float = 0.28
@export var fly_speed: float = 14.0
@export var ground_clearance: float = 1.6
## Keep the pivot on the terrain while panning (needs a height provider).
@export var pivot_follows_ground: bool = true
## Fraction of a pinch that moves the pivot toward the fingers.
@export var zoom_to_point: float = 0.7
@export var inertia: bool = true
@export var inertia_decay: float = 6.0
@export var keyboard_enabled: bool = true
@export var one_finger_pans: bool = false
@export var double_tap_focus: bool = true

var camera: Camera3D
var fly_mode: bool = false:
	set(v):
		set_fly_mode(v)

# Targets (what input changes) and current (smoothed) state.
var pivot := Vector3.ZERO
var yaw: float = 0.0
var pitch: float = deg_to_rad(-45.0)
var distance: float = 30.0
var _c_pivot := Vector3.ZERO
var _c_yaw := 0.0
var _c_pitch := deg_to_rad(-45.0)
var _c_distance := 30.0

var _height: Callable
var _bounds := AABB()
var _has_bounds := false
var _follow: Node3D
var _follow_offset := Vector3.ZERO
var _move := Vector2.ZERO
var _vertical := 0.0
var _orbit_vel := Vector2.ZERO
var _fly := false


func _init() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = 60.0
	camera.near = 0.1
	camera.far = 4000.0
	add_child(camera)


func _ready() -> void:
	snap()


# --- Configuration ----------------------------------------------------------------------

## Callable(x: float, z: float) -> float terrain height; keeps the camera above ground.
func set_height_provider(provider: Callable) -> void:
	_height = provider


## Limits the pivot (and fly position) to `aabb`.
func set_bounds(aabb: AABB) -> void:
	_bounds = aabb
	_has_bounds = aabb.size != Vector3.ZERO


func clear_bounds() -> void:
	_has_bounds = false


func set_fly_mode(on: bool) -> void:
	if on == _fly:
		return
	var eye := camera.global_position if is_inside_tree() else _eye(_c_pivot, _c_yaw, _c_pitch, _c_distance)
	_fly = on
	if on:
		# Keep the eye where it is; the pivot becomes the eye.
		pivot = eye
		_c_pivot = eye
		distance = 0.0
		_c_distance = 0.0
	else:
		var fwd := _basis(_c_yaw, _c_pitch) * Vector3.FORWARD
		var d := 20.0
		var gp: Variant = _ray_ground(eye, fwd, 400.0)
		if gp != null:
			d = clampf(eye.distance_to(gp), min_distance, max_distance)
		pivot = eye + fwd * d
		_c_pivot = pivot
		distance = d
		_c_distance = d
		pitch = clampf(pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	fly_mode_changed.emit(on)


func is_fly_mode() -> bool:
	return _fly


## Joystick input: x = strafe, y = forward/back in screen convention (up = −1);
## `vertical` = up/down. Fly mode flies; orbit mode pans the pivot.
func set_move_input(v: Vector2, vertical: float = 0.0) -> void:
	_move = v.limit_length(1.0)
	_vertical = clampf(vertical, -1.0, 1.0)


# --- Commands ------------------------------------------------------------------------------

## Rotates by a screen drag delta (px). In fly mode this looks around.
func orbit(delta_px: Vector2) -> void:
	var k := deg_to_rad(orbit_deg_per_px) * _sensitivity()
	yaw -= delta_px.x * k
	var dy := delta_px.y * (-1.0 if _invert_y() else 1.0)
	pitch -= dy * k
	_clamp_pitch()


## Pans by a screen drag delta (px): the ground follows the fingers.
func pan(delta_px: Vector2) -> void:
	if _follow != null:
		unfollow()
	var vp_h := _viewport_height()
	var mpp := 2.0 * maxf(_c_distance, 2.0) * tan(deg_to_rad(camera.fov) * 0.5) / vp_h
	var b := _basis(yaw, pitch)
	var right := Vector3(b.x.x, 0.0, b.x.z).normalized()
	var fwd := Vector3(-b.z.x, 0.0, -b.z.z).normalized()
	var fwd_k := 1.0 / maxf(sin(absf(pitch)), 0.35) if not _fly else 1.0
	pivot += -right * delta_px.x * mpp + fwd * delta_px.y * mpp * fwd_k


## factor > 1 zooms in. With a screen point, the view zooms toward it.
func zoom(factor: float, screen_pos: Variant = null) -> void:
	if factor <= 0.0:
		return
	if _fly:
		var fwd := _basis(yaw, pitch) * Vector3.FORWARD
		pivot += fwd * (factor - 1.0) * 10.0
		return
	var old := distance
	distance = clampf(distance / factor, min_distance, max_distance)
	if screen_pos != null and zoom_to_point > 0.0 and _follow == null and not is_equal_approx(old, distance):
		var gp: Variant = ground_point(screen_pos)
		if gp != null:
			var frac := (1.0 - distance / old) * zoom_to_point
			pivot += ((gp as Vector3) - pivot) * frac


func rotate_yaw(angle: float) -> void:
	yaw += angle


## Smoothly moves the pivot to `pos` (and optionally sets the distance).
func focus(pos: Vector3, dist: float = -1.0, instant: bool = false) -> void:
	unfollow()
	if _fly:
		set_fly_mode(false)
	pivot = pos
	if dist > 0.0:
		distance = clampf(dist, min_distance, max_distance)
	if instant:
		snap()


## Keeps the pivot on `node` (+ offset) until unfollow() or a manual pan.
func follow(node: Node3D, offset: Vector3 = Vector3(0, 1, 0), dist: float = -1.0) -> void:
	if _fly:
		set_fly_mode(false)
	_follow = node
	_follow_offset = offset
	if dist > 0.0:
		distance = clampf(dist, min_distance, max_distance)


func unfollow() -> void:
	if _follow != null:
		_follow = null
		follow_ended.emit()


func is_following() -> bool:
	return _follow != null and is_instance_valid(_follow)


## Jumps the smoothed state to the targets (no animation).
func snap() -> void:
	_clamp_targets()
	_c_pivot = pivot
	_c_yaw = yaw
	_c_pitch = pitch
	_c_distance = distance
	_apply_transform()


## Saveable view state.
func get_state() -> Dictionary:
	return {"pivot": Serial.v3(pivot), "yaw": yaw, "pitch": pitch, "distance": distance, "fly": _fly}


func set_state(d: Dictionary) -> void:
	set_fly_mode(Serial.b(d, "fly"))
	pivot = Serial.to_v3(d.get("pivot"), pivot)
	yaw = Serial.f(d, "yaw", yaw)
	pitch = Serial.f(d, "pitch", pitch)
	distance = Serial.f(d, "distance", distance)
	snap()


# --- Picking ----------------------------------------------------------------------------------

## World ray through a screen point (viewport/canvas coordinates of input events).
func screen_ray(screen_pos: Vector2) -> Dictionary:
	return {"origin": camera.project_ray_origin(screen_pos), "dir": camera.project_ray_normal(screen_pos)}


## Ground point under a screen position (height provider, else the y = 0 plane), or null.
func ground_point(screen_pos: Vector2) -> Variant:
	var r := screen_ray(screen_pos)
	return _ray_ground(r["origin"], r["dir"], maxf(max_distance * 3.0, 500.0))


func _ray_ground(origin: Vector3, dir: Vector3, max_len: float) -> Variant:
	if not _height.is_valid():
		if absf(dir.y) < 1e-5:
			return null
		var t := -origin.y / dir.y
		return origin + dir * t if t > 0.0 and t < max_len else null
	var step := clampf(max_len / 160.0, 0.5, 8.0)
	var prev := origin
	var t2 := 0.0
	while t2 < max_len:
		t2 += step * (1.0 + t2 / 200.0)
		var p := origin + dir * t2
		if p.y <= float(_height.call(p.x, p.z)):
			var a := prev
			var b := p
			for i in 12:
				var m := (a + b) * 0.5
				if m.y <= float(_height.call(m.x, m.z)):
					b = m
				else:
					a = m
			return b
		prev = p
	return null


# --- Gestures --------------------------------------------------------------------------------

## Connects a GestureRecognizer's camera gestures.
func attach_gestures(g: GestureRecognizer) -> void:
	g.drag.connect(func(_p: Vector2, rel: Vector2) -> void:
		if one_finger_pans and not _fly:
			pan(rel)
		else:
			orbit(rel))
	g.drag_started.connect(func(_p: Vector2, _h: bool) -> void: _orbit_vel = Vector2.ZERO)
	g.drag_ended.connect(func(_p: Vector2, vel: Vector2) -> void:
		if inertia and not one_finger_pans:
			_orbit_vel = vel.limit_length(2500.0) * 0.35)
	g.two_finger_started.connect(func(_c: Vector2) -> void: _orbit_vel = Vector2.ZERO)
	g.two_finger_drag.connect(func(rel: Vector2, _c: Vector2) -> void: pan(rel))
	g.pinch.connect(func(f: float, c: Vector2) -> void: zoom(f, c))
	g.two_finger_rotate.connect(func(a: float, _c: Vector2) -> void: rotate_yaw(a))
	g.orbit_drag.connect(func(rel: Vector2, _p: Vector2) -> void: orbit(rel))
	g.double_tap.connect(func(p: Vector2) -> void:
		if double_tap_focus and not _fly:
			var gp: Variant = ground_point(p)
			if gp != null:
				focus(gp, maxf(min_distance, distance * 0.6)))


# --- Update ----------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_keyboard(delta)
	_apply_move(delta)
	if _orbit_vel.length_squared() > 1.0:
		orbit(_orbit_vel * delta)
		_orbit_vel *= exp(-inertia_decay * delta)
	else:
		_orbit_vel = Vector2.ZERO
	if _follow != null:
		if is_instance_valid(_follow) and _follow.is_inside_tree():
			pivot = _follow.global_position + _follow_offset
		else:
			unfollow()
	_clamp_targets()
	var k := 1.0 - exp(-smoothing * delta)
	_c_pivot = _c_pivot.lerp(pivot, k)
	_c_yaw = lerpf(_c_yaw, yaw, k)
	_c_pitch = lerpf(_c_pitch, pitch, k)
	_c_distance = lerpf(_c_distance, distance, k)
	_apply_transform()


func _keyboard(delta: float) -> void:
	if not keyboard_enabled or not InputMap.has_action(&"move_forward"):
		return
	var vp := get_viewport()
	if vp != null and vp.gui_get_focus_owner() is LineEdit:
		return
	var mv := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var fast := 2.5 if Input.is_action_pressed(&"sprint") else 1.0
	if mv != Vector2.ZERO:
		if _fly:
			_fly_step(mv, 0.0, delta * fast)
		else:
			pan(-mv * delta * 900.0 * fast)
	var turn := Input.get_axis(&"cam_yaw_right", &"cam_yaw_left")
	if turn != 0.0:
		yaw += turn * delta * 1.6
	var zm := Input.get_axis(&"cam_zoom_out", &"cam_zoom_in")
	if zm != 0.0:
		zoom(pow(1.9, zm * delta))
	var vert := Input.get_axis(&"cam_down", &"cam_up")
	if vert != 0.0 and _fly:
		_fly_step(Vector2.ZERO, vert, delta * fast)


func _apply_move(delta: float) -> void:
	if _move == Vector2.ZERO and _vertical == 0.0:
		return
	if _fly:
		_fly_step(_move, _vertical, delta)
	else:
		pan(-_move * delta * 700.0)
		if _vertical != 0.0:
			distance = clampf(distance * (1.0 - _vertical * delta), min_distance, max_distance)


func _fly_step(mv: Vector2, vert: float, dt: float) -> void:
	var b := _basis(yaw, pitch)
	var fwd := -b.z
	var right := b.x
	var h := 0.0
	if _height.is_valid():
		h = pivot.y - float(_height.call(pivot.x, pivot.z))
	var speed := fly_speed * (1.0 + clampf(h, 0.0, 400.0) / 40.0)
	pivot += (fwd * -mv.y + right * mv.x + Vector3.UP * vert) * speed * dt


func _clamp_pitch() -> void:
	if _fly:
		pitch = clampf(pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
	else:
		pitch = clampf(pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))


func _clamp_targets() -> void:
	_clamp_pitch()
	if not _fly:
		distance = clampf(distance, min_distance, max_distance)
	if _has_bounds:
		pivot = pivot.clamp(_bounds.position, _bounds.end)
	if _height.is_valid():
		var g := float(_height.call(pivot.x, pivot.z))
		if _fly:
			pivot.y = maxf(pivot.y, g + ground_clearance)
		elif pivot_follows_ground and _follow == null:
			pivot.y = g


func _apply_transform() -> void:
	if camera == null:
		return
	var b := _basis(_c_yaw, _c_pitch)
	var eye := _eye(_c_pivot, _c_yaw, _c_pitch, _c_distance)
	var lifted := false
	if _height.is_valid():
		var floor_y := float(_height.call(eye.x, eye.z)) + ground_clearance
		if eye.y < floor_y:
			eye.y = floor_y
			lifted = true
	if _has_bounds:
		var top := _bounds.end.y + max_distance
		eye.y = minf(eye.y, top)
	var xf := Transform3D(b, eye)
	if lifted and _c_distance > 0.05:
		xf = xf.looking_at(_c_pivot, Vector3.UP)
	if is_inside_tree():
		camera.global_transform = xf
	else:
		camera.transform = xf


static func _basis(y: float, p: float) -> Basis:
	return Basis(Vector3.UP, y) * Basis(Vector3.RIGHT, p)


static func _eye(pv: Vector3, y: float, p: float, d: float) -> Vector3:
	return pv + _basis(y, p).z * d


func _viewport_height() -> float:
	var vp := get_viewport()
	return maxf(vp.get_visible_rect().size.y if vp != null else 720.0, 1.0)


func _sensitivity() -> float:
	return clampf(float(UIApp.setting("camera_sensitivity", 1.0)), 0.1, 5.0)


func _invert_y() -> bool:
	return bool(UIApp.setting("invert_y", false))
