extends TestCase
## Procedural creature meshes: every preset × LOD builds valid, skinned,
## budget-conforming geometry; cache, skeleton, visual node and degenerate
## inputs.

## Total vertex budgets per LOD (all material kinds of one creature).
const VERTEX_BUDGET: Array[int] = [16000, 6000, 2500]
## Grazer build-time budgets (ms, desktop GDScript) with slack for loaded CI machines.
const GRAZER_MS: Array[float] = [400.0, 120.0, 40.0]
const TIME_SLACK := 1.5


func _model(id: StringName) -> AnatomyModel:
	return AnatomyCompiler.compile(BodyPlanPresets.create(id))


func test_all_presets_all_lods_build_valid_meshes() -> void:
	var times := {}
	for id in BodyPlanPresets.IDS:
		var m := _model(id)
		var row := PackedStringArray()
		for lod in MeshLod.COUNT:
			var t0 := Time.get_ticks_usec()
			var d := CreatureMeshBuilder.build_data(m, lod)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			row.append("L%d %.0f ms/%d v" % [lod, ms, d.vertex_count()])
			check(d.body_vertex_count() > 0, "%s L%d has a body" % [id, lod])
			check(d.vertex_count() <= VERTEX_BUDGET[lod], "%s L%d vertex budget (%d > %d)" % [id, lod, d.vertex_count(), VERTEX_BUDGET[lod]])
			for kind in d.buffers:
				_check_buffer(d.buffers[kind], m.bones.size(), "%s L%d %s" % [id, lod, kind])
			check((d.stats["warnings"] as Array).is_empty(), "%s L%d warnings %s" % [id, lod, d.stats["warnings"]])
		times[id] = ", ".join(row)
	for id in times:
		print("    mesh %-10s %s" % [id, times[id]])


func _check_buffer(b: MeshBuffer, bone_count: int, label: String) -> void:
	var n := b.vertex_count()
	if n == 0:
		return
	check(b.indices.size() % 3 == 0, "%s index count multiple of 3" % label)
	check(b.normals.size() == n and b.colors.size() == n and b.uv.size() == n and b.uv2.size() == n, "%s attribute sizes" % label)
	check(b.custom0.size() == n * 4 and b.custom1.size() == n * 2, "%s custom sizes" % label)
	check(b.bones.size() == n * 4 and b.weights.size() == n * 4, "%s skin sizes" % label)
	var bad_idx := 0
	for i in b.indices:
		if i < 0 or i >= n:
			bad_idx += 1
	check(bad_idx == 0, "%s %d indices out of range" % [label, bad_idx])
	var bad_pos := 0
	var bad_w := 0
	var bad_b := 0
	for v in n:
		if not b.verts[v].is_finite() or not b.normals[v].is_finite() or not b.uv[v].is_finite() or not b.uv2[v].is_finite():
			bad_pos += 1
		var s := 0.0
		for k in 4:
			var w := b.weights[v * 4 + k]
			if not is_finite(w) or w < -1e-5:
				bad_w += 1
			s += w
			var bi := b.bones[v * 4 + k]
			if bi < 0 or bi >= bone_count:
				bad_b += 1
		if absf(s - 1.0) > 1e-3:
			bad_w += 1
	for c in b.custom0:
		if not is_finite(c):
			bad_pos += 1
	check(bad_pos == 0, "%s %d non-finite values" % [label, bad_pos])
	check(bad_w == 0, "%s %d bad weights (sum must be 1)" % [label, bad_w])
	check(bad_b == 0, "%s %d bone indices out of range" % [label, bad_b])


func test_body_attributes_and_winding() -> void:
	for id in [&"grazer", &"octopus", &"turtle"]:
		var m := _model(id)
		var d := CreatureMeshBuilder.build_data(m, 1)
		var b: MeshBuffer = d.buffers[CreatureBuildContext.KIND_BODY]
		var outward := 0
		var tris := 0
		var degenerate := 0
		for t in range(0, b.indices.size(), 3):
			var i0 := b.indices[t]
			var i1 := b.indices[t + 1]
			var i2 := b.indices[t + 2]
			# Godot front faces are clockwise: (c - a) x (b - a) points outward.
			var fn := (b.verts[i2] - b.verts[i0]).cross(b.verts[i1] - b.verts[i0])
			if fn.length_squared() < 1e-24:
				degenerate += 1
				continue
			tris += 1
			if fn.dot(b.normals[i0] + b.normals[i1] + b.normals[i2]) > 0.0:
				outward += 1
		check(degenerate * 100 < b.indices.size() / 3, "%s few degenerate triangles (%d)" % [id, degenerate])
		check(float(outward) / float(maxi(tris, 1)) > 0.97, "%s outward winding (%d / %d)" % [id, outward, tris])
		var bad_slots := 0
		var bad_rest := 0
		for v in b.vertex_count():
			var c := b.colors[v]
			if absf(c.r + c.g + c.b + c.a - 1.0) > 1e-3:
				bad_slots += 1
			var rest := Vector3(b.custom0[v * 4], b.custom0[v * 4 + 1], b.custom0[v * 4 + 2])
			if rest.distance_to(b.verts[v]) > 1e-5:
				bad_rest += 1
			var slot := int(b.custom0[v * 4 + 3])
			if slot < 0 or slot > 3:
				bad_slots += 1
		check(bad_slots == 0, "%s covering slot weights sum to 1 (%d bad)" % [id, bad_slots])
		check(bad_rest == 0, "%s CUSTOM0.xyz = rest position (%d bad)" % [id, bad_rest])


func test_surface_lies_on_sdf() -> void:
	var m := _model(&"predator")
	var field := SdfField.from_model(m)
	var grid := SdfGrid.create(field, field.bounds(), MeshLod.cells(0))
	var res := SdfMesher.polygonize(grid, 2)
	var max_err := 0.0
	for i in range(0, res.positions.size(), 7):
		max_err = maxf(max_err, absf(AnatomySdf.distance(m, res.positions[i])))
	check(max_err < grid.cell * 0.35, "vertices projected onto the reference SDF (max error %.4f, cell %.4f)" % [max_err, grid.cell])


func test_grazer_timing_budget() -> void:
	var m := _model(&"grazer")
	for lod in MeshLod.COUNT:
		var best := INF
		for rep in 2:
			var t0 := Time.get_ticks_usec()
			CreatureMeshBuilder.build_data(m, lod)
			best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
		print("    grazer LOD%d build: %.1f ms (budget %.0f ms)" % [lod, best, GRAZER_MS[lod]])
		check(best <= GRAZER_MS[lod] * TIME_SLACK, "grazer LOD%d build %.1f ms within budget" % [lod, best])


func test_cache_identity_and_lru() -> void:
	CreatureMeshCache.clear()
	var m := _model(&"worm")
	var a := CreatureMeshCache.build_now(m, 2)
	var b := CreatureMeshCache.build_now(m, 2)
	check(a == b, "cache returns the same set for the same key")
	check(CreatureMeshCache.get_cached(m.morph_key, 2) == a, "get_cached finds the set")
	check(CreatureMeshCache.get_cached(m.morph_key, 1) == null, "other LOD not cached yet")
	var c := CreatureMeshCache.build_now(m, 1)
	check(c != a and c.lod == 1, "different LOD -> different set")
	check(a.body != null and a.body.get_surface_count() == 1, "body mesh has one surface")
	check(a.skin != null and a.skin.get_bind_count() == m.bones.size(), "skin has a bind per bone")
	# LRU: a tiny cap keeps only the most recent entry.
	CreatureMeshCache.set_memory_cap(1)
	CreatureMeshCache.build_now(_model(&"cell"), 2)
	var st := CreatureMeshCache.stats()
	check(int(st["entries"]) == 1, "LRU evicts down to the cap (entries %d)" % int(st["entries"]))
	CreatureMeshCache.set_memory_cap(CreatureMeshCache.DEFAULT_MEMORY_CAP)
	CreatureMeshCache.clear()


func test_async_request_dedup() -> void:
	CreatureMeshCache.clear()
	var m := _model(&"cell")
	var got := []
	var cb := func(s: CreatureMeshSet) -> void: got.append(s)
	CreatureMeshCache.request(m, 2, cb)
	CreatureMeshCache.request(m, 2, cb)
	check(CreatureMeshCache.is_pending(m, 2), "request is pending")
	check(int(CreatureMeshCache.stats()["pending"]) == 1, "concurrent requests share one task")
	var key := CreatureMeshCache.key_for(m, 2)
	var p: Dictionary = CreatureMeshCache._st().pending[key]
	WorkerThreadPool.wait_for_task_completion(int(p["task"]))
	p.erase("task")
	# Worker built the data; deliver runs deferred on the main thread later.
	check(got.is_empty(), "callbacks are not called from the worker thread")


func test_worker_thread_build() -> void:
	var m := _model(&"spider")
	var out := []
	var task := WorkerThreadPool.add_task(func() -> void: out.append(CreatureMeshBuilder.build_data(m, 1)))
	WorkerThreadPool.wait_for_task_completion(task)
	check(out.size() == 1 and (out[0] as CreatureMeshData).vertex_count() > 0, "mesh data builds on a worker thread")


func test_skeleton_builder() -> void:
	var m := _model(&"predator")
	var sk := SkeletonBuilder.build(m)
	check(sk.get_bone_count() == m.bones.size(), "skeleton has every model bone")
	var ok_names := true
	var ok_parents := true
	var max_err := 0.0
	for b in m.bones:
		if sk.get_bone_name(b.index) != b.name:
			ok_names = false
		if b.index > 0 and sk.get_bone_parent(b.index) != b.parent:
			ok_parents = false
		var g := sk.get_bone_global_rest(b.index)
		max_err = maxf(max_err, g.origin.distance_to(SkeletonBuilder.global_rest(m, b.index).origin))
	check(ok_names, "bone names match")
	check(ok_parents, "bone parents match")
	check(sk.get_bone_parent(0) == -1, "root bone 0")
	check(max_err < 1e-4, "global rests match model (err %.6f)" % max_err)
	sk.free()


func test_creature_visual_api() -> void:
	var m := _model(&"grazer")
	var v := CreatureVisual.new()
	v.setup(m, 77, 2)
	check(v.get_skeleton() != null and v.get_skeleton().get_bone_count() == m.bones.size(), "visual has the skeleton")
	check(v.get_mesh_set() != null and v.lod == 2, "visual has LOD2 meshes")
	check(v.bone_index(m.bones[3].name) == 3, "bone_index by name")
	v.set_highlight(m.bones[3].part_id, true)
	v.set_condition(0.5, 0.2, 0.1)
	v.set_xray(true)
	check(v.is_xray(), "x-ray on")
	v.set_xray(false)
	var leg := -1
	for b in m.bones:
		if b.kind == &"limb" and b.segment == 0:
			leg = b.index
			break
	v.set_muscle_bulge(leg, 0.3)
	var s := v.get_skeleton().get_bone_pose_scale(leg)
	check(absf(s.x - 1.3) < 1e-4 and absf(s.y - 1.0) < 1e-4, "muscle bulge scales across the bone")
	var child := v.get_skeleton().get_bone_children(leg)
	if child.size() > 0:
		check(v.get_skeleton().get_bone_pose_scale(child[0]).x < 0.99, "child compensates the bulge")
	v.set_lod(1)
	check(v.lod == 1, "set_lod switches synchronously in editor mode")
	v.free()


func test_degenerate_models() -> void:
	var empty := AnatomyModel.new()
	var d := CreatureMeshBuilder.build_data(empty, 0)
	check(d.vertex_count() == 0 and d.bind_poses.size() == 1, "empty model builds nothing")
	var d2 := CreatureMeshBuilder.build_data(null, 1)
	check(d2.vertex_count() == 0, "null model builds nothing")
	# Bones but no SDF primitives: only tubes / accessories.
	var m := _model(&"insect")
	m.primitives.clear()
	var d3 := CreatureMeshBuilder.build_data(m, 1)
	for kind in d3.buffers:
		_check_buffer(d3.buffers[kind], m.bones.size(), "no-primitive insect %s" % kind)
	# Broken primitive data is skipped, not propagated.
	var g := _model(&"grazer")
	g.primitives[1].a = Vector3(NAN, 0, 0)
	g.primitives[2].ra = INF
	var d4 := CreatureMeshBuilder.build_data(g, 2)
	for kind in d4.buffers:
		_check_buffer(d4.buffers[kind], g.bones.size(), "broken grazer %s" % kind)
	check(d4.body_vertex_count() > 0, "broken primitives skipped, body still built")


func test_huge_and_tiny_creatures() -> void:
	for sc in [25.0, 0.04]:
		var gen := BodyPlanPresets.create(&"predator")
		gen.body_plan.root().scale = sc
		gen.invalidate()
		var m := AnatomyCompiler.compile(gen)
		var d := CreatureMeshBuilder.build_data(m, 1)
		check(d.body_vertex_count() > 100, "scale %s builds a body" % sc)
		for kind in d.buffers:
			_check_buffer(d.buffers[kind], m.bones.size(), "scale %s %s" % [sc, kind])
		var bb: AABB = (d.buffers[CreatureBuildContext.KIND_BODY] as MeshBuffer).aabb()
		check(bb.size.length() > m.aabb.size.length() * 0.3 and bb.size.length() < m.aabb.size.length() * 3.0, "scale %s mesh matches model extent" % sc)
