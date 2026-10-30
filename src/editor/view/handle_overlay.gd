class_name HandleOverlay
extends Control
## On-screen handles drawn over the 3D view for the selected part:
##   joint dots   — tap selects the segment;
##   length       — drag along the bone: segment length;
##   radius       — drag across the bone: segment end radius;
##   move         — drag: slide the attachment over the parent surface;
##   rotate       — drag: aim the part (yaw / pitch) at the finger.
## Handles work in both gesture modes; they are hit-tested before picking.

const HIT_R := 26.0
const DOT_R := 14.0
const HANDLE_R := 17.0

var ctx: EditorContext
var stage: EditorStage
var dragger: PartDragger

var _handles: Array[Dictionary] = []
var _active := ""
var _scale := 1.0
var _hint_t := 0.0
var _axis_a := Vector3.ZERO
var _axis_dir := Vector3.UP
var _begin_len := 0.1
var _begin_rad := 0.1
var _begin_param := 1.0


func setup(c: EditorContext, s: EditorStage) -> void:
	ctx = c
	stage = s
	dragger = PartDragger.new(c, s)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	ctx.view_changed.connect(queue_redraw)


func _process(delta: float) -> void:
	_scale = UITheme.scale_of(self)
	_hint_t += delta
	_compute()
	queue_redraw()


## Instance index the handles act on.
func current_instance() -> int:
	var part := ctx.doc.selected_part()
	if part == null:
		return -1
	var m := ctx.doc.phenotype.anatomy
	var i := ctx.selected_instance
	if i >= 0 and i < m.instances.size() and m.instances[i].part_id == part.id:
		return i
	return PartPicker.first_instance(m, part.id)


func _compute() -> void:
	_handles.clear()
	if stage == null or stage.visual == null or not ctx.show_handles:
		return
	var part := ctx.doc.selected_part()
	if part == null or ctx.hint_part >= 0:
		return
	var m := ctx.doc.phenotype.anatomy
	var inst_idx := current_instance()
	if inst_idx < 0:
		return
	var inst := m.instances[inst_idx]
	var anchor := PartPicker.instance_center(m, inst_idx) if part.id == ctx.doc.plan().root_id else inst.anchor
	if part.is_spine() and ctx.mode in [&"shape", &"limbs", &"anatomy", &"organs", &"senses"]:
		_spine_handles(m, inst)
	if part.id != ctx.doc.plan().root_id:
		var a_scr := _scr(anchor)
		if a_scr.x > -1e5:
			_handles.append({"id": "move", "pos": a_scr, "r": HANDLE_R})
			var gpp := stage.geo_per_pixel(anchor)
			var dir := AttachMapper.instance_direction(m, inst_idx)
			var tip := anchor + dir * (58.0 * _scale * gpp)
			_handles.append({"id": "rotate", "pos": _scr(tip), "r": HANDLE_R, "from": a_scr})


func _spine_handles(m: AnatomyModel, inst: AnatomyModel.Instance) -> void:
	var cur := ctx.active_segment()
	for k in inst.bones.size():
		var b := m.bones[inst.bones[k]]
		var e := _scr(b.end)
		if e.x < -1e5:
			continue
		_handles.append({"id": "joint", "seg": k, "pos": e, "r": DOT_R, "active": k == cur})
	if cur >= inst.bones.size():
		return
	var bone := m.bones[inst.bones[cur]]
	var s0 := _scr(bone.start)
	var s1 := _scr(bone.end)
	var axis := s1 - s0
	var len_px := axis.length()
	var u := axis / len_px if len_px > 4.0 else Vector2.RIGHT
	_handles.append({"id": "length", "pos": s1 + u * 34.0 * _scale, "r": HANDLE_R, "u": u, "len_px": maxf(len_px, 24.0)})
	var mid := (bone.start + bone.end) * 0.5
	var mid_s := _scr(mid)
	var perp := Vector2(-u.y, u.x)
	var right := stage.cam_axes_geo().x
	var rad_px := maxf(mid_s.distance_to(_scr(mid + right * (bone.r0 + bone.r1) * 0.5)), 10.0)
	_handles.append({"id": "radius", "pos": mid_s + perp * (rad_px + 30.0 * _scale), "r": HANDLE_R, "u": perp, "len_px": rad_px, "mid": mid_s})


func _scr(p: Vector3) -> Vector2:
	if stage.is_behind(p):
		return Vector2(-1e6, -1e6)
	return stage.geo_to_screen(p)


# --- Interaction ----------------------------------------------------------------------

## Handle id under `pos` ("" = none). Joints are only hit when nothing else is.
func hit(pos: Vector2) -> String:
	var best := ""
	var bd := INF
	for h in _handles:
		var d := (h["pos"] as Vector2).distance_to(pos)
		var lim := (HIT_R if h["id"] != "joint" else DOT_R + 8.0) * _scale
		if d <= lim and d < bd - (6.0 if h["id"] == "joint" else 0.0):
			bd = d
			best = str(h["id"])
			if h["id"] == "joint":
				best = "joint:%d" % int(h["seg"])
	return best


## Taps on joint dots pick the segment. Returns true when consumed.
func tap(pos: Vector2) -> bool:
	var id := hit(pos)
	if id.begins_with("joint:"):
		ctx.set_segment(int(id.get_slice(":", 1)))
		return true
	return id != ""


func begin_drag(id: String, pos: Vector2) -> bool:
	if id.begins_with("joint:"):
		ctx.set_segment(int(id.get_slice(":", 1)))
		return false
	_active = id
	if id == "move":
		var part := ctx.doc.selected_part()
		return dragger.begin(part.id, current_instance())
	if id == "length" or id == "radius":
		return _begin_axis_drag(id, pos)
	return true


## Length / radius drags are measured in 3D against the bone axis, so they stay
## well-behaved when the bone is foreshortened on screen.
func _begin_axis_drag(id: String, pos: Vector2) -> bool:
	var m := ctx.doc.phenotype.anatomy
	var inst_idx := current_instance()
	var part := ctx.doc.selected_part()
	if inst_idx < 0 or part == null or part.segments.is_empty():
		_active = ""
		return false
	var inst := m.instances[inst_idx]
	var k := clampi(ctx.active_segment(), 0, inst.bones.size() - 1)
	var bone := m.bones[inst.bones[k]]
	_axis_a = bone.start
	_axis_dir = (bone.end - bone.start).normalized()
	var seg: BodySegment = part.segments[clampi(ctx.active_segment(), 0, part.segments.size() - 1)]
	_begin_len = seg.length
	_begin_rad = seg.radius
	_begin_param = _axis_measure(id, pos)
	if _begin_param < 1e-6:
		_active = ""
		return false
	return true


## Length: finger projection along the axis; radius: finger distance from the axis.
func _axis_measure(id: String, pos: Vector2) -> float:
	var ray := stage.ray_geo(pos)
	var o: Vector3 = ray["origin"]
	var d: Vector3 = ray["dir"]
	var pts := Geometry3D.get_closest_points_between_segments(o, o + d * 1.0e3, _axis_a - _axis_dir * 100.0, _axis_a + _axis_dir * 100.0)
	if id == "length":
		return (pts[1] - _axis_a).dot(_axis_dir)
	return (pts[0] as Vector3).distance_to(pts[1])


func drag(pos: Vector2, rel: Vector2) -> void:
	match _active:
		"move":
			dragger.update(pos)
		"length", "radius":
			var cur := _axis_measure(_active, pos)
			var ratio := clampf(cur / _begin_param, 0.1, 6.0)
			_set_segment(_active, _begin_len * ratio if _active == "length" else _begin_rad * ratio)
		"rotate":
			_rotate_to(pos)


func end_drag() -> void:
	match _active:
		"move":
			dragger.end()
		"length", "radius":
			ctx.doc.commit(TranslationServer.translate("Длина сегмента") if _active == "length" else TranslationServer.translate("Радиус сегмента"), &"shape")
		"rotate":
			ctx.doc.commit(TranslationServer.translate("Поворот части"), &"attach")
	_active = ""


func is_dragging() -> bool:
	return _active != ""


func _find(id: String) -> Dictionary:
	for h in _handles:
		if h["id"] == id:
			return h
	return {}


func _set_segment(which: String, value: float) -> void:
	var pid := ctx.doc.selected_id
	var seg := ctx.active_segment()
	ctx.doc.live_edit(func(g: Genome) -> void:
		var p := g.body_plan.get_part(pid)
		if p == null or p.segments.is_empty():
			return
		var s: BodySegment = p.segments[clampi(seg, 0, p.segments.size() - 1)]
		if which == "length":
			s.length = clampf(value, 0.005, 20.0)
		else:
			s.radius = clampf(value, 0.001, 10.0))


func _rotate_to(pos: Vector2) -> void:
	var m := ctx.doc.phenotype.anatomy
	var inst_idx := current_instance()
	if inst_idx < 0:
		return
	var inst := m.instances[inst_idx]
	var ray := stage.ray_geo(pos)
	var cam_fwd: Vector3 = ray["dir"]
	var target := SurfaceRay.plane_point(ray["origin"], cam_fwd, inst.anchor, -cam_fwd)
	var o := AttachMapper.orientation_for_direction(m, ctx.doc.plan(), inst_idx, target - inst.anchor)
	if not o["ok"]:
		return
	var yaw := float(o["yaw"])
	var pitch := float(o["pitch"])
	if ctx.snapping:
		yaw = snappedf(yaw, 5.0)
		pitch = snappedf(pitch, 5.0)
	var pid := ctx.doc.selected_id
	ctx.doc.live_edit(func(g: Genome) -> void:
		var q := g.body_plan.get_part(pid)
		if q != null:
			q.yaw = yaw
			q.pitch = pitch)


# --- Drawing -----------------------------------------------------------------------------

func _draw() -> void:
	if _handles.is_empty():
		return
	var accent := UITheme.color(self, &"accent")
	var hl := UITheme.color(self, &"highlight")
	var dark := Color(0.03, 0.08, 0.08, 0.85)
	for h in _handles:
		if h["id"] == "rotate":
			draw_line(h["from"], h["pos"], Color(accent, 0.55), 2.0 * _scale, true)
	for h in _handles:
		var pos: Vector2 = h["pos"]
		var id := str(h["id"])
		if id == "joint":
			var on: bool = h.get("active", false)
			draw_circle(pos, (DOT_R * 0.55 if not on else DOT_R * 0.8) * _scale, dark)
			draw_circle(pos, (DOT_R * 0.4 if not on else DOT_R * 0.62) * _scale, hl if on else Color(accent, 0.85))
			continue
		var r := float(h["r"]) * _scale
		var active := _active == id
		draw_circle(pos, r + 2.0 * _scale, dark)
		draw_circle(pos, r, Color(hl, 0.95) if active else Color(accent, 0.92))
		var fg := Color(0.03, 0.12, 0.1)
		match id:
			"move":
				Icons.draw(self, &"move", Rect2(pos - Vector2.ONE * r * 0.75, Vector2.ONE * r * 1.5), fg)
			"rotate":
				Icons.draw(self, &"rotate", Rect2(pos - Vector2.ONE * r * 0.75, Vector2.ONE * r * 1.5), fg)
			"length", "radius":
				var u: Vector2 = h["u"]
				_arrows(pos, u, r * 0.72, fg)


func _arrows(c: Vector2, u: Vector2, size: float, col: Color) -> void:
	var p := Vector2(-u.y, u.x)
	for sgn in [-1.0, 1.0]:
		var tip: Vector2 = c + u * size * sgn
		var base: Vector2 = c + u * size * 0.2 * sgn
		draw_colored_polygon(PackedVector2Array([tip, base + p * size * 0.55, base - p * size * 0.55]), col)
	draw_line(c - u * size * 0.25, c + u * size * 0.25, col, 2.0 * _scale)
