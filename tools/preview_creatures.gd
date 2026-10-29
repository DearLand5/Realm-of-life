extends SceneTree
## Renders finished creatures (CreatureVisual) for visual checks.
##   tools/shot.sh tools/preview_creatures.gd -- lineup  [out.png] [lod]
##   tools/shot.sh tools/preview_creatures.gd -- closeup [out.png] [lod]
##   tools/shot.sh tools/preview_creatures.gd -- pose    [out.png] [lod]
##   tools/shot.sh tools/preview_creatures.gd -- single <preset> [out.png] [lod] [yaw] [xray]
##   tools/shot.sh tools/preview_creatures.gd -- all     (writes the three sheets to screenshots/)

const CLOSEUP_IDS: Array[StringName] = [&"grazer", &"predator", &"bird", &"fish", &"octopus", &"insect"]
const POSE_IDS: Array[StringName] = [&"grazer", &"predator", &"bird", &"octopus"]
const TILE := Vector2i(640, 480)

var _stage: Node3D
var _cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "lineup"
	_stage = Node3D.new()
	get_root().add_child(_stage)
	_add_environment(_stage)
	_cam = Camera3D.new()
	_stage.add_child(_cam)
	await process_frame
	match mode:
		"lineup":
			await _lineup(_arg(args, 1, "res://screenshots/tmp/creatures_lineup.png"), int(_arg(args, 2, "0")))
		"closeup":
			await _closeup(_arg(args, 1, "res://screenshots/tmp/creatures_closeup.png"), int(_arg(args, 2, "0")))
		"pose":
			await _pose(_arg(args, 1, "res://screenshots/tmp/creatures_pose.png"), int(_arg(args, 2, "0")))
		"single":
			var id := StringName(_arg(args, 1, "grazer"))
			var img := await _render_single(id, int(_arg(args, 3, "0")), float(_arg(args, 4, "145")), TILE * 2, _arg(args, 5, "") == "xray")
			_save(img, _arg(args, 2, "res://screenshots/tmp/creature_%s.png" % id))
		"gallery":
			await _gallery(_arg(args, 1, "res://screenshots/tmp/creatures_gallery.png"), int(_arg(args, 2, "0")),
				float(_arg(args, 3, "145")), _arg(args, 4, "") == "xray")
		"all":
			await _lineup("res://screenshots/creatures_lineup.png", 0)
			await _closeup("res://screenshots/creatures_closeup.png", 0)
			await _pose("res://screenshots/creatures_pose.png", 0)
	quit()


## Every preset framed individually (5 × 3 tiles).
func _gallery(out: String, lod: int, yaw: float, xray: bool) -> void:
	var tile := Vector2i(512, 384)
	var sheet := Image.create(tile.x * 5, tile.y * 3, false, Image.FORMAT_RGBA8)
	var ids := BodyPlanPresets.IDS
	for i in ids.size():
		var img := await _render_single(ids[i], lod, yaw, tile, xray)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, tile), Vector2i((i % 5) * tile.x, (i / 5) * tile.y))
	_save(sheet, out)


func _arg(args: PackedStringArray, i: int, def: String) -> String:
	return args[i] if args.size() > i and args[i] != "" else def


# --- Scenes ------------------------------------------------------------------------------

func _lineup(out: String, lod: int) -> void:
	var holder := Node3D.new()
	_stage.add_child(holder)
	var cols := 5
	var spacing := 2.3
	var ids := BodyPlanPresets.IDS
	for i in ids.size():
		var v := _make_creature(ids[i], i * 7919 + 13, lod)
		var fit := _fit_scale(v.model, 1.55)
		v.scale = Vector3.ONE * fit
		var row := i / cols
		var col := i % cols
		var pos := Vector3((col - (cols - 1) * 0.5) * spacing, 0.0, (row - 1) * spacing * 1.05)
		v.position = pos - Vector3(v.model.aabb.get_center().x, 0, v.model.aabb.get_center().z) * fit
		if v.model.body_axis == &"vertical":
			v.position.y += 0.05
		v.rotation_degrees.y = 145.0
		holder.add_child(v)
		var lab := Label3D.new()
		lab.text = BodyPlanPresets.label(ids[i])
		lab.font_size = 44
		lab.pixel_size = 0.0045
		lab.outline_size = 10
		lab.modulate = Color(0.95, 0.95, 0.92)
		lab.position = pos + Vector3(0, -0.02, 0.85)
		lab.rotation_degrees.x = -60.0
		holder.add_child(lab)
	_cam.fov = 50.0
	_cam.look_at_from_position(Vector3(0, 7.6, 7.4), Vector3(0, 0.2, 0.25))
	_cam.make_current()
	await _settle()
	var img := await _grab()
	_save(img, out)
	holder.queue_free()
	await process_frame


func _closeup(out: String, lod: int) -> void:
	var sheet := Image.create(TILE.x * 3, TILE.y * 2, false, Image.FORMAT_RGBA8)
	for i in CLOSEUP_IDS.size():
		var img := await _render_single(CLOSEUP_IDS[i], lod, 145.0, TILE, false)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, TILE), Vector2i((i % 3) * TILE.x, (i / 3) * TILE.y))
	_save(sheet, out)


func _pose(out: String, lod: int) -> void:
	var sheet := Image.create(TILE.x * 2, TILE.y * 2, false, Image.FORMAT_RGBA8)
	for i in POSE_IDS.size():
		var img := await _render_single(POSE_IDS[i], lod, 120.0, TILE, false, true)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, TILE), Vector2i((i % 2) * TILE.x, (i / 2) * TILE.y))
	_save(sheet, out)


## Renders one creature framed in a viewport of `size`.
func _render_single(id: StringName, lod: int, yaw: float, size: Vector2i, xray: bool, posed: bool = false) -> Image:
	get_root().size = size
	var v := _make_creature(id, 4242, lod)
	_stage.add_child(v)
	v.rotation_degrees.y = yaw
	if xray:
		v.set_xray(true)
	if posed:
		_apply_test_pose(v)
	var bb := v.model.aabb
	var ext := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
	var center := v.global_transform * bb.get_center()
	_cam.fov = 32.0
	var dist := ext * 2.05
	_cam.look_at_from_position(center + Vector3(0.0, ext * 0.55, dist), center + Vector3(0, -ext * 0.04, 0))
	_cam.make_current()
	var lab := Label3D.new()
	lab.text = BodyPlanPresets.label(id) + ("  (поза)" if posed else "")
	lab.font_size = 36
	lab.pixel_size = ext * 0.0016
	lab.outline_size = 8
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.position = center + Vector3(0, ext * 0.62, 0)
	_stage.add_child(lab)
	_ground_scale(ext)
	await _settle()
	var img := await _grab()
	v.queue_free()
	lab.queue_free()
	await process_frame
	return img


func _make_creature(id: StringName, seed_value: int, lod: int) -> CreatureVisual:
	var m := AnatomyCompiler.compile(BodyPlanPresets.create(id))
	var v := CreatureVisual.new()
	v.setup(m, seed_value, lod)
	return v


## Skinning test: bend neck/tail/legs, flap wings, curl tentacles.
func _apply_test_pose(v: CreatureVisual) -> void:
	var sk := v.get_skeleton()
	var m := v.model
	for b in m.bones:
		if b.index == 0:
			continue
		var ang := 0.0
		var axis := Vector3.RIGHT
		match b.kind:
			&"neck":
				ang = -22.0
			&"head":
				ang = -10.0 if b.segment == 0 else 0.0
			&"tail":
				ang = 16.0
				axis = Vector3.UP
			&"limb":
				if b.segment == 0:
					ang = 28.0 if (b.side > 0) == (b.start.z < m.aabb.get_center().z) else -24.0
				elif b.segment == 1:
					ang = -30.0
			&"wing":
				if b.segment == 0:
					ang = -38.0 * float(b.side)
					axis = Vector3.FORWARD
				elif b.segment == 1:
					ang = 18.0 * float(b.side)
					axis = Vector3.FORWARD
			&"tentacle":
				ang = 22.0
				axis = (b.end - b.start).cross(Vector3.UP).normalized()
		if ang == 0.0 or axis.length_squared() < 0.5:
			continue
		var g := SkeletonBuilder.global_rest(m, b.index).basis
		var local_axis := (g.inverse() * axis).normalized()
		var rest := sk.get_bone_rest(b.index).basis.get_rotation_quaternion()
		sk.set_bone_pose_rotation(b.index, rest * Quaternion(local_axis, deg_to_rad(ang)))
	# Torso bulge to show muscle deformation.
	for b in m.bones:
		if b.kind == &"limb" and b.segment == 0 and b.side > 0:
			v.set_muscle_bulge(b.index, 0.25)


# --- Environment -------------------------------------------------------------------------

var _ground: MeshInstance3D


func _add_environment(root: Node3D) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.36, 0.5, 0.68)
	sm.sky_horizon_color = Color(0.7, 0.74, 0.76)
	sm.ground_bottom_color = Color(0.25, 0.24, 0.22)
	sm.ground_horizon_color = Color(0.62, 0.62, 0.6)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.68, 0.78)
	e.ambient_light_energy = 0.55
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.95
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 150, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.75, 0.85, 1.0)
	root.add_child(fill)
	_ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	_ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.35, 0.32)
	gm.roughness = 0.95
	gm.metallic_specular = 0.2
	_ground.material_override = gm
	root.add_child(_ground)


func _ground_scale(_ext: float) -> void:
	_ground.position = Vector3(0, -0.0005, 0)


func _fit_scale(m: AnatomyModel, target: float) -> float:
	var e := maxf(m.aabb.size.x, maxf(m.aabb.size.y, m.aabb.size.z))
	return target / maxf(e, 1e-3)


func _settle() -> void:
	for i in 4:
		await process_frame


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_root().get_texture().get_image()


func _save(img: Image, path: String) -> void:
	var p := ProjectSettings.globalize_path(path)
	var dir := p.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	img.save_png(p)
	print("saved ", p, " ", img.get_size())
