extends TestCase
## Creature editor logic: history, attachment mapping, subtree commands,
## panel specs and the save → library → load round trip (all headless).


func _doc(preset: StringName = &"grazer") -> EditorDocument:
	return EditorDocument.new(BodyPlanPresets.create(preset))


func _first_of(plan: BodyPlan, kind: StringName) -> BodyPart:
	var l := plan.parts_of_kind(kind)
	return l[0] if not l.is_empty() else null


func test_undo_redo_add_modify_remove() -> void:
	var doc := _doc(&"predator")
	var plan := doc.plan()
	var base := plan.to_dict()
	var n0 := plan.parts.size()
	var root_id := plan.root_id
	var holder := {"id": -1}
	doc.modify("add", func(g: Genome) -> void:
		var src := _first_of(g.body_plan, &"claw")
		var sub := EditorCommands.subtree_dict(g.body_plan, src.id if src != null else root_id)
		holder["id"] = EditorCommands.graft(g.body_plan, sub, root_id, {"attach_t": 0.5}), &"part_added")
	var new_id: int = holder["id"]
	check(new_id > 0 and doc.plan().get_part(new_id) != null, "part added")
	var after_add := doc.plan().to_dict()
	var torso := doc.plan().get_part(root_id)
	var l0 := torso.segments[0].length
	doc.modify("len", func(g: Genome) -> void: g.body_plan.get_part(root_id).segments[0].length = l0 * 1.5, &"shape")
	var after_mod := doc.plan().to_dict()
	check(not (after_mod == after_add), "modify changed plan")
	doc.modify("rm", func(g: Genome) -> void: EditorCommands.delete_parts(g.body_plan, [new_id]), &"edit")
	check(doc.plan().get_part(new_id) == null, "part removed")
	var after_rm := doc.plan().to_dict()
	check(doc.undo(), "undo 1")
	check(doc.plan().to_dict() == after_mod, "undo restores modify state")
	check(doc.undo(), "undo 2")
	check(doc.plan().to_dict() == after_add, "undo restores add state")
	check(doc.undo(), "undo 3")
	check(doc.plan().to_dict() == base and doc.plan().parts.size() == n0, "undo restores base")
	check(not doc.can_undo(), "nothing more to undo")
	check(doc.redo() and doc.redo() and doc.redo(), "redo x3")
	check(doc.plan().to_dict() == after_rm, "redo reaches final state")
	check(not doc.can_redo(), "nothing more to redo")


func test_history_depth_and_live_edit() -> void:
	var doc := _doc(&"fish")
	var root_id := doc.plan().root_id
	for i in 130:
		doc.modify("step", func(g: Genome) -> void: g.body_plan.get_part(root_id).scale = 1.0 + 0.001 * float(i + 1))
	var undone := 0
	while doc.undo():
		undone += 1
	check(undone >= 100, "at least 100 undo steps (got %d)" % undone)
	# Live edits collapse into a single history step.
	var doc2 := _doc(&"fish")
	var r2 := doc2.plan().root_id
	var size0 := doc2.history.size()
	for i in 20:
		doc2.live_edit(func(g: Genome) -> void: g.body_plan.get_part(r2).scale = 1.0 + 0.01 * float(i))
	check(doc2.history.size() == size0, "live edits do not record")
	doc2.commit("drag")
	check(doc2.history.size() == size0 + 1, "commit records one step")
	check(doc2.undo() and absf(doc2.plan().get_part(r2).scale - 1.0) < 1e-6, "undo of a drag restores scale")


func test_attach_mapper_roundtrip() -> void:
	var doc := _doc(&"predator")
	var plan := doc.plan()
	var m := doc.phenotype.anatomy
	var torso := plan.root()
	var inst := PartPicker.first_instance(m, torso.id)
	check(inst >= 0, "torso instance")
	for t in [0.25, 0.5, 0.7]:
		for ang in [0.0, 45.0, 90.0, 200.0, 270.0]:
			for depth in [0.6, 1.0]:
				var tf := AttachMapper.frame(m, inst, t, ang, depth)
				var r := AttachMapper.params_on_instance(m, inst, tf.origin)
				check(r["ok"], "mapped")
				near(float(r["t"]), t, 0.01, "t roundtrip")
				near(float(r["depth"]), depth, 0.03, "depth roundtrip")
				var da := absf(wrapf(float(r["angle"]) - ang, -180.0, 180.0))
				check(da < 1.5, "angle roundtrip %s vs %s" % [r["angle"], ang])
	# Surface hit → attach params → compiled anchor near the hit.
	var origin := Vector3(m.aabb.get_center().x + 2.0, m.aabb.get_center().y + 0.2, m.aabb.get_center().z)
	var hit := PartPicker.pick(m, origin, Vector3.LEFT)
	check(hit["hit"], "ray hits the body")
	var p: Vector3 = hit["position"]
	var a := AttachMapper.params_on_instance(m, int(hit["instance"]), p)
	check(a["ok"], "hit mapped")
	var spike := BodyPlanPresets.point(&"spike", {})
	var parent_part := plan.get_part(int(hit["part_id"]))
	var sid := plan.add_part(spike, parent_part.id)
	spike.attach_t = float(a["t"])
	spike.attach_angle = float(a["angle"])
	spike.attach_depth = float(a["depth"])
	spike.symmetry = 0
	var g2 := doc.genome
	g2.invalidate()
	var m2 := AnatomyCompiler.compile(g2)
	var si := PartPicker.first_instance(m2, sid)
	check(si >= 0, "spike compiled")
	var inst_anchor := m2.instances[si].anchor
	# Recentring may shift the whole model vertically: compare relative to the torso.
	var shift := m2.instances[PartPicker.first_instance(m2, torso.id)].anchor - m.instances[inst].anchor
	check(inst_anchor.distance_to(p + shift) < 0.02 * maxf(m.aabb.size.length(), 0.1), "anchor near hit (%s vs %s)" % [inst_anchor, p + shift])
	# Snapping keeps parameters valid.
	var sn := AttachMapper.snap(a, parent_part)
	check(float(sn["angle"]) >= 0.0 and float(sn["angle"]) <= 360.0 and float(sn["t"]) > 0.0 and float(sn["t"]) < 1.0, "snap in range")


func test_duplicate_delete_subtree_ids() -> void:
	var doc := _doc(&"grazer")
	var plan := doc.plan()
	var leg := _first_of(plan, &"limb")
	check(leg != null, "has a leg")
	var sub := plan.descendants_of(leg.id)
	var n0 := plan.parts.size()
	var nid := EditorCommands.duplicate_part(plan, leg.id)
	check(nid > 0 and plan.parts.size() == n0 + 1 + sub.size(), "duplicate adds subtree")
	var ids := {}
	for p in plan.parts:
		check(not ids.has(p.id), "unique id %d" % p.id)
		ids[p.id] = true
	var copy_desc := plan.descendants_of(nid)
	check(copy_desc.size() == sub.size(), "descendant count equal")
	for d in copy_desc:
		check(plan.get_part(d.parent_id) != null, "copy child has parent")
	var removed := EditorCommands.delete_parts(plan, [nid])
	check(removed == 1 + sub.size() and plan.parts.size() == n0, "delete removes the copy and its children")
	check(EditorCommands.delete_parts(plan, [plan.root_id]) == 0, "root cannot be deleted")
	leg.locked = true
	check(EditorCommands.delete_parts(plan, [leg.id]) == 0, "locked part is kept")
	# Copy / paste.
	var clip := EditorCommands.subtree_dict(plan, leg.id)
	var pid := EditorCommands.graft(plan, clip, plan.root_id, {"attach_t": 0.3})
	check(pid > 0 and plan.get_part(pid).kind == leg.kind and absf(plan.get_part(pid).attach_t - 0.3) < 1e-6, "paste with override")
	plan.repair()
	check(plan.repair().is_empty(), "plan stays valid")


func test_panel_spec_matches_schema() -> void:
	for kind in PartSchema.SPINE_KINDS + PartSchema.POINT_KINDS:
		var keys := PanelSpec.param_keys(kind)
		var want := PackedStringArray()
		for k in PartSchema.param_specs(kind):
			want.append(str(k))
		check(keys == want, "params of %s match PartSchema" % kind)
		var part := BodyPart.new(kind)
		var secs := PanelSpec.sections_for(part, false)
		var has_attach := false
		var other_kind_keys := false
		for s in secs:
			if s["id"] == &"attach":
				has_attach = true
			if s["id"] == &"params":
				for it in s["items"]:
					if it["target"] == &"param" and not want.has(str(it["key"])):
						other_kind_keys = true
		check(has_attach, "%s has attachment section" % kind)
		check(not other_kind_keys, "%s shows only its own params" % kind)
		check(PanelSpec.chain_for(kind).is_empty() == PartSchema.is_point(kind), "chain controls only for spine kinds (%s)" % kind)


func test_save_library_load_roundtrip() -> void:
	var doc := _doc(&"bird")
	doc.set_design_name("Тестовая птица")
	var root_id := doc.plan().root_id
	doc.modify("tweak", func(g: Genome) -> void:
		g.body_plan.get_part(root_id).scale = 1.25
		g.set_value(&"metabolism", 1.3))
	var uid := doc.save_to_library()
	check(uid != "" and not doc.dirty and doc.uid == uid, "saved with uid")
	var back := SpeciesLibrary.load_genome(uid)
	check(back != null, "loaded from library")
	var doc2 := EditorDocument.new()
	doc2.load_genome(back, uid)
	var d1 := JSON.stringify(doc.plan().to_dict(), "\t", true)
	var d2 := JSON.stringify(doc2.plan().to_dict(), "\t", true)
	if d1 != d2:
		var a1 := d1.split("\n")
		var a2 := d2.split("\n")
		for i in mini(a1.size(), a2.size()):
			if a1[i] != a2[i]:
				print("DIFF line ", i, ": ", a1[i], " | ", a2[i])
				break
	check(d1 == d2, "plan identical after roundtrip")
	near(doc2.genome.value(&"metabolism"), doc.genome.value(&"metabolism"), 0.002, "trait identical")
	check(doc2.design_name() == "Тестовая птица", "name kept")
	# Save again keeps the uid (overwrites).
	var uid2 := doc2.save_to_library()
	check(uid2 == uid, "same uid when re-saving")
	var uid3 := doc2.save_to_library("Копия", true)
	check(uid3 != uid, "Save As creates a new entry")
	SpeciesLibrary.delete_species(uid)
	SpeciesLibrary.delete_species(uid3)


func test_invalid_plan_is_repaired_on_load() -> void:
	var g := Genome.new(BodyPlan.new())
	g.body_plan.parts.clear()
	var doc := EditorDocument.new(g)
	check(doc.plan().parts.size() >= 1 and doc.plan().root() != null, "empty plan repaired")
	check(doc.phenotype != null and doc.phenotype.anatomy.bones.size() > 0, "phenotype compiled")


func test_all_presets_compile_and_diagnose() -> void:
	for id in BodyPlanPresets.IDS:
		var doc := EditorDocument.new(BodyPlanPresets.create(id))
		check(doc.phenotype != null and not doc.diagnostics.is_empty(), "preset %s builds" % id)
		var picked := PartPicker.pick(doc.phenotype.anatomy, doc.phenotype.anatomy.aabb.get_center() + Vector3(0, 0, 5), Vector3.FORWARD, 0.02)
		check(picked.has("hit"), "picker runs on %s" % id)
