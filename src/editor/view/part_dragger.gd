class_name PartDragger
extends RefCounted
## Slides the attachment of a part over its parent's surface: the finger ray
## is traced against the body SDF *without* the dragged subtree, the hit
## point is converted to attach_t / attach_angle / attach_depth
## (AttachMapper), optionally snapped (symmetry plane, angle steps, joints).
## Organs move through the body volume instead of its surface.

var ctx: EditorContext
var stage: EditorStage
var part_id: int = -1
var inst: int = -1
var active := false
var _excluded := {}


func _init(c: EditorContext, s: EditorStage) -> void:
	ctx = c
	stage = s


## True when the part can be dragged (not root, not locked, has a parent).
func can_drag(pid: int) -> bool:
	var p := ctx.doc.plan().get_part(pid)
	return p != null and pid != ctx.doc.plan().root_id and not p.locked


func begin(pid: int, inst_idx: int) -> bool:
	if not can_drag(pid):
		return false
	part_id = pid
	inst = inst_idx
	_excluded = SurfaceRay.subtree_ids(ctx.doc.plan(), pid)
	active = true
	return true


func update(pos: Vector2) -> void:
	if not active:
		return
	var plan := ctx.doc.plan()
	var m := ctx.doc.phenotype.anatomy
	var part := plan.get_part(part_id)
	if part == null or inst < 0 or inst >= m.instances.size():
		return
	var ray := stage.ray_geo(pos)
	var o: Vector3 = ray["origin"]
	var d: Vector3 = ray["dir"]
	var fm := SurfaceRay.filtered(m, _excluded)
	var p: Variant = SurfaceRay.volume_point(fm, o, d) if part.kind == &"organ" else SurfaceRay.surface_point(fm, o, d)
	if p == null:
		var par := m.instances[inst].parent_instance
		var center := PartPicker.instance_center(m, par)
		p = SurfaceRay.plane_point(o, d, center, -d)
	var ap := AttachMapper.params_for_drag(m, plan, inst, p)
	if not ap["ok"]:
		return
	if ctx.snapping:
		ap = AttachMapper.snap(ap, plan.get_part(part.parent_id), ctx.prefs.angle_step, 0.05)
	var keep_depth := part.kind != &"organ" and int(ap.get("cap", 0)) == 0
	var pid := part_id
	ctx.doc.live_edit(func(g: Genome) -> void:
		var q := g.body_plan.get_part(pid)
		if q == null:
			return
		q.attach_t = float(ap["t"])
		q.attach_angle = float(ap["angle"])
		if not keep_depth:
			q.attach_depth = clampf(float(ap["depth"]), 0.0, 1.2))


func end() -> void:
	if not active:
		return
	active = false
	ctx.doc.commit(TranslationServer.translate("Перемещение части"), &"attach")
