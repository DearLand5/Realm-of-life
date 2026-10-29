extends SceneTree
## Debug view of compiled anatomy as capsules (one per bone) for all presets.
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s tools/preview_bones.gd -- [preset] [out.png]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var only := StringName(args[0]) if args.size() > 0 and args[0] != "all" else &""
	var out := args[1] if args.size() > 1 else "res://screenshots/tmp/bones.png"
	var root := Node3D.new()
	get_root().add_child(root)
	ShotUtil.add_studio(root)
	var ids: Array = [only] if only != &"" else BodyPlanPresets.IDS
	var cols := 5
	var spacing := 2.4
	for i in ids.size():
		var g := BodyPlanPresets.create(ids[i])
		var m := AnatomyCompiler.compile(g)
		var holder := Node3D.new()
		root.add_child(holder)
		var ext := maxf(m.aabb.size.x, maxf(m.aabb.size.y, m.aabb.size.z))
		var k := 1.6 / maxf(ext, 0.01)
		holder.scale = Vector3.ONE * k
		holder.position = Vector3((i % cols - (cols - 1) * 0.5) * spacing, 0, -float(i / cols) * spacing * 1.1) if ids.size() > 1 else Vector3.ZERO
		holder.rotation_degrees.y = -35
		_draw_model(holder, m)
		var lab := Label3D.new()
		lab.text = BodyPlanPresets.label(ids[i])
		lab.font_size = 48
		lab.pixel_size = 0.004
		lab.position = holder.position + Vector3(0, -0.25, 0.6)
		root.add_child(lab)
	var cam := Camera3D.new()
	root.add_child(cam)
	await process_frame
	if ids.size() == 1:
		cam.look_at_from_position(Vector3(2.2, 1.4, 2.6), Vector3(0, 0.5, 0))
	else:
		cam.look_at_from_position(Vector3(0, 5.0, 4.2), Vector3(0, 0, -2.4))
		cam.fov = 62.0
	cam.make_current()
	for f in 3:
		await process_frame
	await ShotUtil.save_viewport(get_root(), ProjectSettings.globalize_path(out))
	quit()


func _draw_model(holder: Node3D, m: AnatomyModel) -> void:
	var colors := [Color(0.85, 0.6, 0.4), Color(0.5, 0.75, 0.9), Color(0.6, 0.85, 0.5), Color(0.9, 0.85, 0.5)]
	for b in m.bones:
		if b.part_id < 0:
			continue
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = b.r1
		cm.bottom_radius = b.r0
		cm.height = b.length
		cm.radial_segments = 12
		mi.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[b.covering % 4] if not b.thin else Color(0.9, 0.3, 0.3)
		mi.material_override = mat
		var basis := b.basis
		mi.transform = Transform3D(basis.scaled_local(Vector3(1, 1, b.flatten)), b.mid())
		holder.add_child(mi)
		var sph := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = b.r1
		sm.height = b.r1 * 2.0
		sph.mesh = sm
		sph.material_override = mat
		sph.position = b.end
		holder.add_child(sph)
	for a in m.accessories:
		var mi := MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		match a.type:
			&"eye":
				var sm := SphereMesh.new()
				sm.radius = a.size
				sm.height = a.size * 2.0
				mi.mesh = sm
				mat.albedo_color = Color(0.05, 0.05, 0.05)
			&"horn", &"spike", &"claw":
				var cm := CylinderMesh.new()
				cm.top_radius = 0.0
				cm.bottom_radius = float(a.params.get("base_m", a.size * 0.2))
				cm.height = a.size
				mi.mesh = cm
				mat.albedo_color = Color(0.95, 0.92, 0.8)
				mi.transform = Transform3D(a.transform.basis, a.transform.origin + a.transform.basis.y * a.size * 0.5)
			&"membrane":
				var bones: PackedInt32Array = a.params["bones"]
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				var trail: Vector3 = a.params["trail"]
				var chord: float = a.params["chord"]
				var pts := [m.bones[bones[0]].start]
				for bi in bones:
					pts.append(m.bones[bi].end)
				for j in pts.size() - 1:
					var p0: Vector3 = pts[j]
					var p1: Vector3 = pts[j + 1]
					var w0 := chord * (1.0 - 0.6 * float(j) / pts.size())
					var w1 := chord * (1.0 - 0.6 * float(j + 1) / pts.size())
					st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p1 + trail * w1)
					st.add_vertex(p0); st.add_vertex(p1 + trail * w1); st.add_vertex(p0 + trail * w0)
				st.generate_normals()
				mi.mesh = st.commit()
				mat.albedo_color = Color(0.7, 0.8, 1.0, 0.7)
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				mi.material_override = mat
				holder.add_child(mi)
				continue
			&"organ":
				continue
			_:
				var sm := SphereMesh.new()
				sm.radius = maxf(a.size * 0.4, 0.004)
				sm.height = sm.radius * 2.0
				mi.mesh = sm
				mat.albedo_color = Color(0.9, 0.4, 0.8)
		mi.material_override = mat
		if a.type != &"horn" and a.type != &"spike" and a.type != &"claw":
			mi.transform = a.transform
		holder.add_child(mi)
