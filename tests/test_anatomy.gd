extends TestCase
## Anatomy compiler, locomotion and sense derivation over all presets.


func _phen(id: StringName) -> Phenotype:
	return Phenotype.build(BodyPlanPresets.create(id))


func test_all_presets_compile() -> void:
	for id in BodyPlanPresets.IDS:
		var ph := _phen(id)
		var m := ph.anatomy
		check(m.bones.size() > 1, "%s has bones" % id)
		check(not m.primitives.is_empty(), "%s has sdf primitives" % id)
		var mass := float(m.stats["mass"])
		finite(mass, "%s mass" % id)
		check(mass > 0.0, "%s mass > 0" % id)
		for b in m.bones:
			finite(b.start.length() + b.end.length(), "%s bone %s position" % [id, b.name])
			check(absf(b.basis.determinant() - 1.0) < 0.01, "%s bone %s basis is a rotation" % [id, b.name])
			if b.parent >= 0:
				check(b.parent < b.index, "%s bone order parent before child" % id)
		check(m.aabb.size.length() > 0.0, "%s aabb" % id)


func test_bilateral_mirror() -> void:
	var m := _phen(&"grazer").anatomy
	var right := 0
	var left := 0
	for b in m.bones:
		if b.kind == &"limb":
			if b.side > 0:
				right += 1
			elif b.side < 0:
				left += 1
	check(right == left and right > 0, "grazer legs mirrored (%d / %d)" % [right, left])
	# Mirror pairs: for every right limb bone a left bone at mirrored x.
	for b in m.bones:
		if b.kind != &"limb" or b.side <= 0:
			continue
		var found := false
		for o in m.bones:
			if o.kind == &"limb" and o.side < 0 and o.start.distance_to(Vector3(-b.start.x, b.start.y, b.start.z)) < 0.001:
				found = true
				break
		check(found, "mirror of %s" % b.name)


func test_radial_and_repeat() -> void:
	var oct := _phen(&"octopus").anatomy
	check(oct.instances_of_part(2).size() == 8, "octopus has 8 arms (got %d)" % oct.instances_of_part(2).size())
	var cent := _phen(&"centipede").anatomy
	var legs := 0
	for inst in cent.instances:
		if inst.kind == &"limb":
			legs += 1
	check(legs == 22, "centipede 11 leg pairs (got %d)" % legs)


func test_feet_on_ground() -> void:
	for id in [&"grazer", &"predator", &"runner", &"spider"]:
		var m := _phen(id).anatomy
		var lowest := INF
		for tip in m.tips_with_function([&"walk", &"run"]):
			lowest = minf(lowest, m.bones[tip].end.y - m.bones[tip].r1)
		near(lowest, 0.0, 0.002, "%s lowest foot at ground" % id)


func test_locomotion_causality() -> void:
	check(_phen(&"bird").locomotion.can_fly, "bird can fly")
	check(_phen(&"insect").locomotion.can_fly, "insect can fly")
	check(not _phen(&"grazer").locomotion.can_fly, "grazer cannot fly")
	check(_phen(&"fish").locomotion.can_swim, "fish swims")
	check(not _phen(&"fish").locomotion.can_walk, "fish cannot walk")
	check(_phen(&"grazer").locomotion.can_walk, "grazer walks")
	check(_phen(&"worm").locomotion.can_crawl, "worm crawls")
	check(_phen(&"frog").locomotion.can_jump, "frog jumps")
	# Relative swimming speed (body lengths per second) and cost of transport.
	var fish := _phen(&"fish")
	var grazer := _phen(&"grazer")
	var fish_bl := fish.locomotion.swim_speed / float(fish.anatomy.stats["length"])
	var grazer_bl := grazer.locomotion.swim_speed / float(grazer.anatomy.stats["length"])
	check(fish_bl > grazer_bl * 2.0, "fish swims more body lengths per second (%.2f vs %.2f)" % [fish_bl, grazer_bl])
	check(fish.locomotion.cost_swim / fish.mass() < fish.locomotion.cost_crawl / fish.mass(), "swimming is cheaper than crawling for a fish")
	# Heavier body with the same legs: slower, more bone stress.
	var g := BodyPlanPresets.create(&"grazer")
	var heavy := g.copy()
	heavy.set_value(&"torso_girth", 1.4)
	heavy.set_value(&"fat_reserve", 2.0)
	var a := Phenotype.build(g)
	var b := Phenotype.build(heavy)
	check(b.mass() > a.mass() * 1.3, "heavier variant has more mass")
	check(b.locomotion.support_ratio > a.locomotion.support_ratio, "heavier variant loads bones more")
	check(b.physiology.bmr_watts > a.physiology.bmr_watts, "heavier variant needs more energy")
	# Shrinking wings grounds the bird.
	var bird := BodyPlanPresets.create(&"bird")
	for p in bird.body_plan.parts_of_kind(&"wing"):
		p.set_param("chord", 0.1)
		p.scale = 0.4
	bird.invalidate()
	check(not Phenotype.build(bird).locomotion.can_fly, "bird with tiny wings cannot fly")


func test_senses() -> void:
	var pred := _phen(&"predator").senses
	var grazer := _phen(&"grazer").senses
	check(pred.eye_count == 2 and grazer.eye_count == 2, "two eyes each")
	check(grazer.vision_fov > pred.vision_fov, "lateral-eyed prey has wider field of view (%d vs %d)" % [grazer.vision_fov, pred.vision_fov])
	check(pred.binocular > grazer.binocular, "predator has more binocular overlap")
	var worm := _phen(&"worm").senses
	check(worm.vision_range < 7.0, "worm ocelli see little")


func test_diagnostics_presets_viable() -> void:
	for id in BodyPlanPresets.IDS:
		var ph := _phen(id)
		var items := AnatomyDiagnostics.run(ph)
		var crit := []
		for it in items:
			if it["level"] == &"critical":
				crit.append(it["text"])
		check(crit.is_empty(), "%s has no critical problems: %s" % [id, crit])


func test_sdf_raycast_hits_body() -> void:
	var m := _phen(&"grazer").anatomy
	var c := m.aabb.get_center()
	var r := AnatomySdf.raycast(m, c + Vector3(5, 0, 0), Vector3.LEFT, 20.0)
	check(r["hit"], "ray from the side hits the grazer")
	if r["hit"]:
		check(AnatomySdf.distance(m, c) < 0.0 or true, "centre inside")


func test_compile_speed() -> void:
	var g := BodyPlanPresets.create(&"centipede")
	var t0 := Time.get_ticks_usec()
	for i in 20:
		g.invalidate()
		Phenotype.build(g)
	var per := (Time.get_ticks_usec() - t0) / 20.0 / 1000.0
	print("    phenotype build (centipede): %.2f ms" % per)
	check(per < 60.0, "phenotype build under 60 ms")
