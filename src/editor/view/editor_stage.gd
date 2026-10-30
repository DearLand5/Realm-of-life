class_name EditorStage
extends Node3D
## The 3D side of the editor: soft-lit stage with a ground that receives the
## creature's shadow, the FreeCamera, the current CreatureVisual and the sense
## overlays. It never edits data; it renders `ctx.doc.phenotype` and answers
## geometry queries (rays, projections) for the gesture layer.
##
## Live rebuild: the phenotype is recompiled synchronously by the document; the
## mesh is requested asynchronously through CreatureMeshCache (LOD2 while a drag
## is in progress, LOD0 once idle). Only one request is in flight — the newest
## model always wins — and the old visual stays on screen until the new one is
## ready, so the view never flickers or freezes.

signal visual_swapped

const TARGET_EXTENT := 2.2          # stage units the creature is normalised to
const LIVE_LOD := 2
const IDLE_LOD := 0
const IDLE_DELAY := 0.35

var ctx: EditorContext
var cam: FreeCamera
var visual: CreatureVisual
var stage_scale: float = 1.0
var overlays: StageOverlays
var driver: TestDriver

var _model: AnatomyModel
var _wanted_lod: int = IDLE_LOD
var _inflight := false
var _idle := -1.0
var _ground: MeshInstance3D
var _ground_mat: ShaderMaterial
var _sun: DirectionalLight3D
var _view_rect := Rect2()
var _first := true
## No mesh building (headless tests: no renderer, no worker threads).
var skip_meshes := DisplayServer.get_name() == "headless"


func setup(context: EditorContext) -> void:
	ctx = context
	_build_environment()
	cam = FreeCamera.new()
	cam.min_distance = 0.6
	cam.max_distance = 22.0
	cam.min_pitch_deg = -88.0
	cam.max_pitch_deg = 12.0
	cam.ground_clearance = 0.0
	cam.keyboard_enabled = false
	cam.double_tap_focus = false
	add_child(cam)
	overlays = StageOverlays.new()
	add_child(overlays)
	driver = TestDriver.new()
	add_child(driver)
	ctx.doc.changed.connect(_on_doc_changed)
	ctx.doc.selection_changed.connect(_refresh_highlight)
	ctx.view_changed.connect(_on_view_changed)
	ctx.mode_changed.connect(func(_m: StringName) -> void: _refresh_overlays())
	_on_doc_changed(&"load")
	cam.yaw = deg_to_rad(35.0)
	cam.pitch = deg_to_rad(-22.0)
	fit_camera(true)


func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.075, 0.13, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.72, 0.74)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	_sun.light_energy = 1.25
	_sun.light_color = Color(1.0, 0.96, 0.9)
	_sun.shadow_enabled = true
	_sun.shadow_blur = 2.0
	_sun.directional_shadow_max_distance = 14.0
	_sun.shadow_bias = 0.04
	add_child(_sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, 145.0, 0.0)
	fill.light_energy = 0.4
	fill.light_color = Color(0.7, 0.85, 1.0)
	add_child(fill)
	var disc := CylinderMesh.new()
	disc.top_radius = 6.0
	disc.bottom_radius = 6.0
	disc.height = 0.02
	disc.radial_segments = 64
	disc.rings = 1
	_ground = MeshInstance3D.new()
	_ground.mesh = disc
	_ground.position.y = -0.011
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = load("res://src/editor/view/editor_ground.gdshader") as Shader
	_ground_mat.set_shader_parameter("radius", 6.0)
	_ground.material_override = _ground_mat
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ground)


# --- Document → visual ---------------------------------------------------------

func _on_doc_changed(reason: StringName) -> void:
	_model = ctx.doc.phenotype.anatomy
	driver.set_phenotype(ctx.doc.phenotype)
	if reason == &"load":
		_first = true
		_update_scale(true)
	else:
		_update_scale(false)
	if reason == &"live":
		_wanted_lod = LIVE_LOD
		_idle = IDLE_DELAY
	else:
		_wanted_lod = IDLE_LOD
		_idle = -1.0
	_kick()
	_refresh_overlays()
	if reason == &"load":
		fit_camera(true)


func _on_view_changed() -> void:
	if visual != null:
		visual.set_xray(ctx.xray)
	_refresh_overlays()


func _process(delta: float) -> void:
	if _idle >= 0.0:
		_idle -= delta
		if _idle < 0.0:
			_wanted_lod = IDLE_LOD
			_kick()
	_apply_view_offset()


func _update_scale(force: bool) -> void:
	var bb := _model.aabb
	var ext := maxf(maxf(bb.size.x, bb.size.y), maxf(bb.size.z, 0.001))
	var cur := ext * stage_scale
	if force or cur > TARGET_EXTENT * 1.9 or cur < TARGET_EXTENT * 0.45:
		var old := stage_scale
		stage_scale = clampf(TARGET_EXTENT / ext, 0.01, 2000.0)
		if not force and old > 0.0 and cam != null:
			cam.distance *= stage_scale / old
			cam.pivot *= stage_scale / old
			cam.snap()


func _kick() -> void:
	if _inflight or _model == null or skip_meshes:
		return
	var m := _model
	var lod := _wanted_lod
	if CreatureMeshCache.get_cached(m.morph_key, lod) != null:
		_swap(m, lod)
		return
	_inflight = true
	CreatureMeshCache.request(m, lod, func(_s: CreatureMeshSet) -> void:
		_inflight = false
		if not is_inside_tree():
			return
		if m == _model and lod == _wanted_lod:
			_swap(m, lod)
		else:
			_kick())


func _swap(m: AnatomyModel, lod: int) -> void:
	var v := CreatureVisual.new()
	v.async_build = false
	v.setup(m, 7, lod)
	v.scale = Vector3.ONE * stage_scale
	add_child(v)
	if visual != null:
		EditorUI.dispose(visual)
	visual = v
	v.set_xray(ctx.xray)
	driver.attach(v, ctx.doc.phenotype)
	_refresh_highlight()
	overlays.visual_scale = stage_scale
	visual_swapped.emit()


func _refresh_highlight() -> void:
	if visual == null:
		return
	visual.clear_highlight()
	var ids: Array[int] = []
	if ctx.hint_part >= 0:
		ids.append(ctx.hint_part)
	else:
		for id in ctx.doc.selection:
			ids.append(id)
	for id in ids:
		visual.set_highlight(id, true)
	_refresh_overlays()


func _refresh_overlays() -> void:
	if overlays != null:
		overlays.refresh(ctx, _model, stage_scale)


# --- Camera ------------------------------------------------------------------------

func fit_camera(instant: bool = false) -> void:
	if _model == null or cam == null:
		return
	var bb := _model.aabb
	var c := (bb.get_center()) * stage_scale
	var ext := maxf(maxf(bb.size.x, bb.size.y), bb.size.z) * stage_scale
	var vp := get_viewport().get_visible_rect().size
	var tan_half := tan(deg_to_rad(cam.camera.fov) * 0.5)
	var share := 1.0
	if _view_rect.size.x > 1.0:
		share = clampf(minf(_view_rect.size.x, _view_rect.size.y) / maxf(vp.y, 1.0), 0.15, 1.0)
	var dist := ext * 1.6 / (2.0 * tan_half * share)
	cam.focus(c, clampf(dist, cam.min_distance, cam.max_distance), instant)
	if instant:
		cam.snap()


func focus_part(part_id: int) -> void:
	var idx := PartPicker.first_instance(_model, part_id)
	if idx < 0:
		return
	cam.focus(PartPicker.instance_center(_model, idx) * stage_scale, -1.0, false)


## Region of the screen not covered by panels; the creature is centred in it.
func set_view_rect(r: Rect2) -> void:
	_view_rect = r


func _apply_view_offset() -> void:
	if cam == null or _view_rect.size.x <= 1.0:
		return
	var vp := get_viewport().get_visible_rect().size
	var shift := _view_rect.get_center() - vp * 0.5
	var wpp := 2.0 * cam.distance * tan(deg_to_rad(cam.camera.fov) * 0.5) / maxf(vp.y, 1.0)
	cam.camera.h_offset = -shift.x * wpp
	cam.camera.v_offset = shift.y * wpp


# --- Geometry queries ------------------------------------------------------------------

## Camera ray through a screen position in GEOMETRY space {origin, dir}.
func ray_geo(screen_pos: Vector2) -> Dictionary:
	var r := cam.screen_ray(screen_pos)
	if visual == null:
		return r
	var inv := visual.global_transform.affine_inverse()
	var o: Vector3 = inv * (r["origin"] as Vector3)
	var d: Vector3 = (inv.basis * (r["dir"] as Vector3)).normalized()
	return {"origin": o, "dir": d}


func geo_to_screen(p: Vector3) -> Vector2:
	var w := visual.global_transform * p if visual != null else p * stage_scale
	return cam.camera.unproject_position(w)


func is_behind(p: Vector3) -> bool:
	var w := visual.global_transform * p if visual != null else p * stage_scale
	return cam.camera.is_position_behind(w)


## Geometry units covered by one screen pixel at a geometry point.
func geo_per_pixel(p: Vector3) -> float:
	var w := visual.global_transform * p if visual != null else p * stage_scale
	var dist := cam.camera.global_position.distance_to(w)
	var vp := get_viewport().get_visible_rect().size
	return 2.0 * dist * tan(deg_to_rad(cam.camera.fov) * 0.5) / maxf(vp.y, 1.0) / maxf(stage_scale, 1e-6)


## Camera right/up axes in geometry space.
func cam_axes_geo() -> Basis:
	var b := cam.camera.global_transform.basis
	if visual != null:
		b = visual.global_transform.basis.orthonormalized().inverse() * b
	return b
