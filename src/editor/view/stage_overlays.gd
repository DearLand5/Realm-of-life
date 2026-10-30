class_name StageOverlays
extends Node3D
## 3D annotations on the stage: translucent field-of-view fans of the eyes
## (horizontal sectors at eye height, selected eye brighter). Rebuilt on every
## document change, only when visible, as one ArrayMesh.

var visual_scale: float = 1.0

var _fans: MeshInstance3D
var _mat: StandardMaterial3D


func _init() -> void:
	_fans = MeshInstance3D.new()
	_fans.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fans)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.no_depth_test = false
	_fans.material_override = _mat


func refresh(ctx: EditorContext, model: AnatomyModel, scale_factor: float) -> void:
	visual_scale = scale_factor
	var sel := ctx.doc.selected_part()
	var want := ctx.show_fov and model != null and (ctx.mode == &"senses" or (sel != null and sel.kind == &"eye"))
	_fans.visible = want
	if not want:
		_fans.mesh = null
		return
	_fans.mesh = _build(ctx, model)


func _build(ctx: EditorContext, model: AnatomyModel) -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var plan := ctx.doc.plan()
	var sp := ctx.doc.phenotype.senses
	var reach := fan_reach(sp.vision_range)
	for a in model.accessories:
		if a.type != &"eye":
			continue
		var part := plan.get_part(a.part_id)
		if part == null:
			continue
		var fov := float(part.get_param("fov", 120.0))
		var selected := ctx.doc.is_selected(a.part_id)
		var dir := a.transform.basis.y
		var h := Vector3(dir.x, 0.0, dir.z)
		if h.length() < 0.25:
			continue
		h = h.normalized()
		var c := a.transform.origin * visual_scale
		var base := atan2(h.x, h.z)   # angle of h measured from +Z around Y
		var half := deg_to_rad(clampf(fov, 10.0, 360.0) * 0.5)
		var steps := maxi(6, int(fov / 6.0))
		var col := Color(0.95, 0.78, 0.38, 0.5 if selected else 0.26)
		var rim := Color(col.r, col.g, col.b, 0.02)
		var prev := Vector3.ZERO
		for i in steps + 1:
			var ang := base - half + 2.0 * half * float(i) / float(steps)
			var p := c + Vector3(sin(ang), 0.0, cos(ang)) * reach
			if i > 0:
				verts.append(c)
				verts.append(prev)
				verts.append(p)
				cols.append(col)
				cols.append(rim)
				cols.append(rim)
			prev = p
	if verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Display radius of a fan in stage units (qualitative; exact range is in the panel).
static func fan_reach(vision_range: float) -> float:
	return EditorStage.TARGET_EXTENT * (0.45 + 0.9 * clampf(vision_range / 60.0, 0.0, 1.0))
