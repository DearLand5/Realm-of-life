class_name EditorGestures
extends Node
## Connects touch / mouse gestures on the 3D view to camera and editing.
##
##   two fingers (always)  pinch zoom, pan, twist; PC: wheel, right-drag orbit
##   one finger, camera mode  drag = orbit
##   one finger, edit mode    drag on a part = slide it over its parent;
##                            drag on empty space = orbit
##   handles                  drag a handle (any mode)
##   tap = select, double tap = focus (empty: fit), long press = add to selection

var ctx: EditorContext
var stage: EditorStage
var handles: HandleOverlay
var rec: GestureRecognizer
var _mode := &""     # &"orbit" | &"handle" | &"part"
var _dragger: PartDragger


func setup(c: EditorContext, s: EditorStage, h: HandleOverlay, surface: Control) -> void:
	ctx = c
	stage = s
	handles = h
	_dragger = PartDragger.new(c, s)
	rec = GestureRecognizer.new()
	rec.double_tap_time = 0.28
	add_child(rec)
	rec.attach_to(surface)
	rec.tap.connect(_on_tap)
	rec.double_tap.connect(_on_double_tap)
	rec.long_press.connect(_on_long_press)
	rec.drag_started.connect(_on_drag_started)
	rec.drag.connect(_on_drag)
	rec.drag_ended.connect(_on_drag_ended)
	rec.two_finger_started.connect(func(_c: Vector2) -> void: _finish_edit())
	rec.pinch.connect(func(f: float, p: Vector2) -> void: stage.cam.zoom(f, p))
	rec.two_finger_drag.connect(func(rel: Vector2, _p: Vector2) -> void: stage.cam.pan(rel))
	rec.two_finger_rotate.connect(func(a: float, _p: Vector2) -> void: stage.cam.rotate_yaw(a))
	rec.orbit_drag.connect(func(rel: Vector2, _p: Vector2) -> void: stage.cam.orbit(rel))


## Pick under a screen position: {hit, part_id, instance, ...}.
func pick(pos: Vector2) -> Dictionary:
	var m := ctx.doc.phenotype.anatomy
	if m == null or stage.visual == null:
		return {"hit": false}
	var ray := stage.ray_geo(pos)
	var gpp := stage.geo_per_pixel(m.aabb.get_center())
	var slop := gpp * 20.0
	var organs := ctx.xray or ctx.mode == &"anatomy"
	return PartPicker.pick(m, ray["origin"], ray["dir"], slop, organs, ctx.xray)


func _select_hit(h: Dictionary, additive: bool) -> void:
	if not h["hit"]:
		return
	ctx.selected_instance = int(h["instance"])
	ctx.hint_part = -1
	ctx.doc.select(int(h["part_id"]), additive)


func _on_tap(pos: Vector2) -> void:
	if handles.tap(pos):
		return
	var h := pick(pos)
	if h["hit"]:
		_select_hit(h, false)
	else:
		ctx.hint_part = -1
		ctx.doc.select(-1)


func _on_double_tap(pos: Vector2) -> void:
	var h := pick(pos)
	if h["hit"]:
		_select_hit(h, false)
		stage.focus_part(int(h["part_id"]))
	else:
		stage.fit_camera()


func _on_long_press(pos: Vector2) -> void:
	var h := pick(pos)
	if h["hit"]:
		_select_hit(h, true)


func _on_drag_started(pos: Vector2, after_long_press: bool) -> void:
	_mode = &"orbit"
	var hid := handles.hit(pos)
	if hid != "" and handles.begin_drag(hid, pos):
		_mode = &"handle"
		return
	if ctx.edit_gesture and not after_long_press:
		var h := pick(pos)
		if h["hit"] and _dragger.can_drag(int(h["part_id"])):
			_select_hit(h, false)
			if _dragger.begin(int(h["part_id"]), int(h["instance"])):
				_mode = &"part"


func _on_drag(pos: Vector2, rel: Vector2) -> void:
	match _mode:
		&"handle":
			handles.drag(pos, rel)
		&"part":
			_dragger.update(pos)
		_:
			stage.cam.orbit(rel)


func _on_drag_ended(_pos: Vector2, _vel: Vector2) -> void:
	_finish_edit()


func _finish_edit() -> void:
	match _mode:
		&"handle":
			handles.end_drag()
		&"part":
			_dragger.end()
	_mode = &""
