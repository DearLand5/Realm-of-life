extends TestCase
## Creature runtime: perception, needs-driven AI, movement limits, combat,
## reproduction, animation (IK) and persistence — headless, on ArenaWorld.

var _dummy := RefCounted.new()   # stands in for a controller: keeps the AI away from an agent


func _sim(seed_value: int = 5) -> ArenaSim:
	var s := ArenaSim.new(true, seed_value)
	s.clear_plants()
	return s


## Holds a creature still without the AI (it "is possessed" by a dummy).
func _hold(a: CreatureAgent) -> void:
	a.possess(_dummy)
	a.intent.stop()


# --- Feeding / drinking ----------------------------------------------------------------------------

func test_hungry_herbivore_finds_and_eats_plants() -> void:
	var s := _sim()
	s.plant_patch(Vector3(-22, 0, 8), 10.0, 0.8)
	var before := s.eco.total_biomass()
	var g := s.spawn_preset(&"grazer", Vector3(0, 0, 0), &"adult", 0.35)
	s.run(100.0)
	check(g.individual.stomach_total() > 0.3, "stomach filled (%.2f kg)" % g.individual.stomach_total())
	check(s.eco.total_biomass() < before, "plants were removed from the ecosystem")
	check(g.mover.pos.distance_to(Vector3(-22, 0, 8)) < 20.0, "went to the patch")
	s.free()


func test_thirsty_creature_reaches_water() -> void:
	var s := _sim()
	var g := s.spawn_preset(&"grazer", Vector3(-10, 0, 10), &"adult", 0.9)
	g.individual.hydration = 0.72
	s.run(40.0)
	check(g.individual.hydration > 0.95, "hydration restored (%.2f)" % g.individual.hydration)
	s.free()


# --- Predator and prey -----------------------------------------------------------------------------

func test_prey_flees_perceived_predator() -> void:
	var s := _sim()
	var pred := s.spawn_preset(&"predator", Vector3(-20, 0, -10), &"adult", 0.3)
	var prey := s.spawn_preset(&"grazer", Vector3(-8, 0, -10), &"adult", 0.9)
	var d0 := pred.position.distance_to(prey.position)
	var fled := false
	var t := 0.0
	while t < 6.0:
		s.step(1.0 / 30.0)
		t += 1.0 / 30.0
		if prey.brain.current != null and prey.brain.current.id == &"flee":
			fled = true
	check(fled, "prey switched to the flee action")
	check(prey.brain.needs.fear > 0.3, "prey is afraid")
	check(prey.position.x > -8.0 + 2.0, "prey ran away from the predator")
	check(d0 > 0.0, "setup")
	s.free()


func test_predator_kills_prey_and_carcass_appears() -> void:
	var s := _sim()
	var pred := s.spawn_preset(&"predator", Vector3(-20, 0, -10), &"adult", 0.3)
	var prey := s.spawn_preset(&"turtle", Vector3(-8, 0, -10), &"adult", 0.9)
	s.run(40.0)
	check(s.deaths.size() >= 1 and s.deaths[0]["cause"] == &"predation", "agent_died callback fired with predation")
	check(not prey.is_alive(), "prey is dead")
	check(s.eco.carcasses.count() >= 1 or pred.individual.stomach_total() > 0.0, "carcass created by the world callback")
	check(pred.individual.stomach_total() > 0.5, "predator ate the carcass (%.2f kg)" % pred.individual.stomach_total())
	s.free()


func test_roles_by_size_weapons_and_diet() -> void:
	var s := _sim()
	var pred := s.spawn_preset(&"predator", Vector3(0, 0, 0))
	var graz := s.spawn_preset(&"grazer", Vector3(5, 0, 0))
	var frog := s.spawn_preset(&"frog", Vector3(10, 0, 0))
	var role_a := Relations.classify(graz.phys, graz.phenotype.anatomy.stats, graz.individual.mass(), pred.phys, pred.phenotype.anatomy.stats, pred.individual.mass(), false)
	var role_b := Relations.classify(pred.phys, pred.phenotype.anatomy.stats, pred.individual.mass(), graz.phys, graz.phenotype.anatomy.stats, graz.individual.mass(), false)
	var role_c := Relations.classify(graz.phys, graz.phenotype.anatomy.stats, graz.individual.mass(), frog.phys, frog.phenotype.anatomy.stats, frog.individual.mass(), false)
	check(role_a == Percept.ROLE_PREDATOR, "grazer sees the predator as a predator")
	check(role_b == Percept.ROLE_PREY, "predator sees the grazer as prey")
	check(role_c == Percept.ROLE_NEUTRAL, "grazer ignores a frog")
	var dmg_p := Relations.attack_damage(pred.phys, pred.phenotype.anatomy.stats, pred.individual.mass(), graz.phys, graz.individual.mass(), 0.5)
	var dmg_g := Relations.attack_damage(graz.phys, graz.phenotype.anatomy.stats, graz.individual.mass(), frog.phys, frog.individual.mass(), 0.5)
	check(dmg_p > 0.05 and dmg_p < 0.6, "bite damage in a sane range (%.2f)" % dmg_p)
	check(dmg_g >= 0.0, "damage is finite")
	s.free()


# --- Perception: no omniscience ----------------------------------------------------------------------

func _blind_observer(s: ArenaSim, pos: Vector3, heading: float) -> CreatureAgent:
	var o := s.spawn_preset(&"grazer", pos, &"adult", 0.9)
	_hold(o)
	o.mover.heading = heading
	var sp := o.phenotype.senses
	sp.smell_range = 0.0
	sp.hearing_range = 0.0
	sp.vibration_range = 0.0
	sp.touch_range = 0.0
	return o


func _knows(o: CreatureAgent, other: CreatureAgent) -> bool:
	return o.perception.memory.short.has(Percept.make_key(Percept.Kind.AGENT, other.individual.id))


func test_vision_cone_hides_targets_behind() -> void:
	var s := _sim()
	s.climate.daylight = 1.0
	var o := _blind_observer(s, Vector3(0, 0, 0), 0.0)   # faces -Z
	var front := s.spawn_preset(&"grazer", Vector3(0, 0, -15))
	var back := s.spawn_preset(&"grazer", Vector3(0, 0, 15))
	_hold(front)
	_hold(back)
	o.perception.update(1.0)
	check(_knows(o, front), "target in front is seen")
	check(not _knows(o, back), "target in the blind cone behind is not perceived")
	s.free()


func test_night_and_range_limit_vision() -> void:
	var s := _sim()
	var o := _blind_observer(s, Vector3(0, 0, 0), 0.0)
	var far := s.spawn_preset(&"grazer", Vector3(0, 0, -28))
	_hold(far)
	s.climate.daylight = 1.0
	o.perception.update(1.0)
	check(_knows(o, far), "seen by day at 28 m")
	o.memory.clear_short()
	s.climate.daylight = 0.0
	o.perception.update(2.0)
	check(not _knows(o, far), "not seen at night at 28 m")
	var beyond := s.spawn_preset(&"grazer", Vector3(0, 0, -80))
	_hold(beyond)
	s.climate.daylight = 1.0
	o.perception.update(3.0)
	check(not _knows(o, beyond), "beyond the vision range nothing is known")
	s.free()


func test_hearing_louder_when_running_and_smell_downwind() -> void:
	var s := _sim()
	var o := s.spawn_preset(&"grazer", Vector3(0, 0, 0), &"adult", 0.9)
	_hold(o)
	o.phenotype.senses.eye_count = 0
	o.phenotype.senses.smell_range = 0.0
	o.phenotype.senses.vibration_range = 0.0
	o.phenotype.senses.touch_range = 0.0
	o.phenotype.senses.hearing_range = 40.0
	var t := s.spawn_preset(&"grazer", Vector3(30, 0, 0))
	_hold(t)
	o.perception.update(1.0)
	check(not _knows(o, t), "a still animal at 30 m is not heard")
	t.mover.speed = t.mover.max_speed(&"land", true)
	o.perception.update(2.0)
	check(_knows(o, t), "the same animal running is heard")
	# Smell: downwind detection beats upwind.
	var o2 := s.spawn_preset(&"grazer", Vector3(0, 0, 40), &"adult", 0.9)
	_hold(o2)
	o2.phenotype.senses.eye_count = 0
	o2.phenotype.senses.hearing_range = 0.0
	o2.phenotype.senses.vibration_range = 0.0
	o2.phenotype.senses.touch_range = 0.0
	o2.phenotype.senses.smell_range = 5.0
	var src := s.spawn_preset(&"grazer", Vector3(9, 0, 40))
	_hold(src)
	s.climate.wind = Vector2(-6.0, 0.0)   # blows from the source toward the observer
	o2.perception.update(1.0)
	var down := _knows(o2, src)
	o2.memory.clear_short()
	s.climate.wind = Vector2(6.0, 0.0)    # blows away from the observer
	o2.perception.update(2.0)
	var up := _knows(o2, src)
	check(down and not up, "scent is detected downwind but not upwind (down=%s up=%s)" % [down, up])
	s.free()


# --- Media ------------------------------------------------------------------------------------------------

func test_fish_stays_in_water_and_walker_avoids_deep_water() -> void:
	var s := _sim()
	var pc := ArenaWorld.POND_CENTER
	var fish := s.spawn_preset(&"fish", Vector3(pc.x, 0, pc.y), &"adult", 0.9)
	var out_of_water := 0
	var t := 0.0
	while t < 60.0:
		s.step(1.0 / 30.0)
		t += 1.0 / 30.0
		if int(t * 30.0) % 30 == 0 and s.world.water_depth_at(fish.position.x, fish.position.z) < 0.05:
			out_of_water += 1
	check(out_of_water == 0, "the fish never left the water (%d samples out)" % out_of_water)
	# A walker that cannot swim is stopped by deep water.
	var walker := s.spawn_preset(&"grazer", Vector3(0, 0, pc.y), &"adult", 0.9)
	walker.phenotype.locomotion.can_swim = false
	_hold(walker)
	var max_depth := 0.0
	t = 0.0
	while t < 25.0:
		walker.intent.direct(Vector3(1, 0, 0), 2.0)
		walker.intent.avoid_water = true
		s.step(1.0 / 30.0)
		t += 1.0 / 30.0
		max_depth = maxf(max_depth, s.world.water_depth_at(walker.position.x, walker.position.z))
	check(max_depth <= walker.mover.height * 0.55 + 0.1, "non-swimmer stayed out of deep water (max depth %.2f)" % max_depth)
	s.free()


func test_mover_respects_locomotion_limits() -> void:
	var s := _sim()
	var ctx := s.ctx
	# Land: grazer pushed at 100 m/s along the meadow.
	var ph := Phenotype.build(BodyPlanPresets.create(&"grazer"))
	var m := CreatureMover.new()
	m.setup(ph, ctx, Vector3(-40, s.world.height_at(-40, -5), -5), -PI * 0.5, 1.0)
	var it := MoveIntent.new()
	it.direct(Vector3(1, 0, 0), 100.0)
	it.sprint = true
	var peak := 0.0
	for i in 150:
		m.step(1.0 / 30.0, it, 1.0)
		peak = maxf(peak, m.speed)
	check(peak <= ph.locomotion.run_speed * 1.02, "land speed capped at run speed (%.2f <= %.2f)" % [peak, ph.locomotion.run_speed])
	check(peak > ph.locomotion.walk_speed, "sprint exceeds walking pace")
	var it2 := MoveIntent.new()
	it2.direct(Vector3(1, 0, 0), 100.0)
	var m2 := CreatureMover.new()
	m2.setup(ph, ctx, Vector3(-40, s.world.height_at(-40, -5), -5), -PI * 0.5, 1.0)
	var peak2 := 0.0
	for i in 150:
		m2.step(1.0 / 30.0, it2, 1.0)
		peak2 = maxf(peak2, m2.speed)
	check(peak2 < peak, "without sprint the sustainable pace is lower")
	# Water.
	var pf := Phenotype.build(BodyPlanPresets.create(&"fish"))
	var pc := ArenaWorld.POND_CENTER
	var mf := CreatureMover.new()
	mf.setup(pf, ctx, Vector3(pc.x - 4, -1.5, pc.y), 0.0, 1.0)
	var itf := MoveIntent.new()
	itf.direct(Vector3(1, 0, 0), 100.0)
	itf.surface = false
	var pk := 0.0
	for i in 60:
		mf.step(1.0 / 30.0, itf, 1.0)
		pk = maxf(pk, mf.speed)
	check(pk <= pf.locomotion.swim_speed * 1.02 and pk > 0.5, "swim speed capped (%.2f <= %.2f)" % [pk, pf.locomotion.swim_speed])
	# Air.
	var pb := Phenotype.build(BodyPlanPresets.create(&"bird"))
	var mb := CreatureMover.new()
	mb.setup(pb, ctx, Vector3(-30, s.world.height_at(-30, 20), 20), 0.0, 1.0)
	var itb := MoveIntent.new()
	itb.direct(Vector3(1, 0, 0), 100.0)
	itb.fly = true
	itb.altitude = 6.0
	var pa := 0.0
	var max_h := 0.0
	for i in 240:
		mb.step(1.0 / 30.0, itb, 1.0)
		pa = maxf(pa, mb.speed)
		max_h = maxf(max_h, mb.height_above_ground())
	check(pa <= pb.locomotion.fly_speed * 1.02, "flight speed capped (%.2f <= %.2f)" % [pa, pb.locomotion.fly_speed])
	check(max_h > 3.0 and mb.flying, "the bird took off and climbed (%.1f m)" % max_h)
	s.free()


# --- Reproduction ---------------------------------------------------------------------------------------------

func test_mating_produces_offspring() -> void:
	var s := _sim()
	var a := s.spawn_preset(&"grazer", Vector3(-3, 0, 0), &"adult", 0.95)
	var b := s.spawn_preset(&"grazer", Vector3(3, 0, 0), &"adult", 0.95)
	a.individual.species_id = 1
	b.individual.species_id = 1
	a.individual.sex = Individual.Sex.FEMALE
	b.individual.sex = Individual.Sex.MALE
	a.individual.hydration = 1.0
	b.individual.hydration = 1.0
	var t := 0.0
	while t < 400.0 and not (a.individual.pregnant or s.births.size() > 0):
		a.individual.energy = a.individual.max_energy() * 0.95
		b.individual.energy = b.individual.max_energy() * 0.95
		s.step(1.0 / 20.0)
		t += 1.0 / 20.0
	check(a.individual.pregnant or s.births.size() > 0, "the pair mated (t=%.0f s)" % t)
	# Fast-forward the gestation: birth goes through ctx.spawn_individual.
	a.individual.gestation_left = 10.0
	for i in 40:
		a.individual.energy = a.individual.max_energy() * 0.95
		s.step_dt(0.5, 600.0)
	check(s.births.size() >= 1, "offspring were created through the spawn callback (%d)" % s.births.size())
	if s.births.size() > 0:
		check(s.births[0].mother_id == a.individual.id, "offspring know their mother")
	s.free()


func test_egg_incubates_hatches_and_can_be_eaten() -> void:
	var s := _sim()
	var g := BodyPlanPresets.create(&"bird")
	var egg := Individual.create(g, 3, &"egg", s.ctx.rng)
	egg.position = Vector3(-30, s.world.height_at(-30, 20), 20)
	var ea := s.spawn(egg)
	check(ea.is_egg(), "egg agent")
	s.run(2.0)
	check(ea.mover.speed == 0.0 and ea.position.distance_to(egg.position) < 0.01, "eggs are immobile")
	var before := ea.individual.incubation_left
	for i in 20:
		s.step_dt(0.5, 3000.0)
	check(ea.individual.incubation_left < before or not ea.is_egg(), "incubation progresses")
	ea.individual.incubation_left = 1.0
	for i in 20:
		s.step_dt(0.5, 600.0)
	check(not ea.is_egg() and ea.individual.stage != &"egg", "the egg hatched into a juvenile")
	# Predation on an egg.
	var egg2 := Individual.create(BodyPlanPresets.create(&"turtle"), 4, &"egg", s.ctx.rng)
	egg2.position = Vector3(10, s.world.height_at(10, -25), -25)
	var ea2 := s.spawn(egg2)
	var pred := s.spawn_preset(&"predator", Vector3(2, 0, -25), &"adult", 0.3)
	s.run(40.0)
	check(not ea2.is_alive(), "the egg was eaten")
	check(pred.individual.stomach_total() > 0.0, "the predator gained food from the egg")
	s.free()


# --- Animation ------------------------------------------------------------------------------------------------------

func _walk_error(preset: StringName) -> float:
	var ph := Phenotype.build(BodyPlanPresets.create(preset))
	var sk := SkeletonBuilder.build(ph.anatomy)
	var an := ProceduralAnimator.new()
	an.setup_rig(ph, sk)
	var st := AnimState.new()
	st.ground = func(_x: float, _z: float) -> float: return 0.0
	st.max_speed = ph.locomotion.run_speed
	var pos := Vector3.ZERO
	var v := ph.locomotion.walk_speed
	var worst := 0.0
	for f in 300:
		var dt := 1.0 / 60.0
		pos += Vector3(0, 0, -v * dt)
		st.xf = Transform3D(Basis.IDENTITY, pos)
		st.speed = v
		st.vel = Vector3(0, 0, -v)
		st.effort = v / st.max_speed
		an.update_pose(dt, st)
		if f > 90:
			for i in an.rig.legs.size():
				var leg: AnimRig.Leg = an.rig.legs[i]
				if leg.planted:
					worst = maxf(worst, an.foot_tip_world(i, st).distance_to(leg.plant))
	var leg_h := an.rig.leg_height
	sk.free()
	return worst / maxf(leg_h, 0.01)


func test_ik_keeps_planted_feet_fixed_in_world() -> void:
	for preset in [&"predator", &"grazer", &"insect", &"centipede", &"spider", &"bird"]:
		var err := _walk_error(preset)
		check(err < 0.12, "%s: planted foot stays within 12%% of leg length (%.3f)" % [preset, err])


func test_gait_patterns_by_support_count() -> void:
	var quad := Gait.pick(&"quadruped", 4, 0.2)
	var trot := Gait.pick(&"quadruped", 4, 0.5)
	var gal := Gait.pick(&"quadruped", 4, 0.9)
	check(quad.name == &"walk" and trot.name == &"trot" and gal.name == &"gallop", "quadruped walk/trot/gallop")
	check(quad.duty > trot.duty and trot.duty > gal.duty, "duty factor falls with speed")
	var hex := Gait.pick(&"hexapod", 6, 0.3)
	check(hex.name == &"tripod", "hexapods use tripods")
	check(absf(hex.offset(&"hexapod", -1, 0.0, 0, 6) - hex.offset(&"hexapod", 1, 0.5, 1, 6)) < 0.01, "tripod legs move together")
	check(absf(trot.offset(&"quadruped", -1, 0.0, 0, 4) - trot.offset(&"quadruped", 1, 1.0, 3, 4)) < 0.01, "diagonal pairs trot together")
	var wave := Gait.pick(&"multiped", 22, 0.3)
	check(wave.name == &"wave", "many legs use a metachronal wave")


func test_animator_poses_different_anatomies_differently() -> void:
	var changed := {}
	for preset in [&"fish", &"bird", &"octopus", &"worm", &"predator"]:
		var ph := Phenotype.build(BodyPlanPresets.create(preset))
		var sk := SkeletonBuilder.build(ph.anatomy)
		var an := ProceduralAnimator.new()
		an.setup_rig(ph, sk)
		var st := AnimState.new()
		st.ground = func(_x: float, _z: float) -> float: return 0.0
		st.max_speed = 2.0
		st.speed = 1.0
		st.effort = 0.5
		st.on_ground = preset != &"fish"
		st.medium = &"water" if preset == &"fish" else &"land"
		st.flying = preset == &"bird"
		for f in 60:
			st.xf = Transform3D(Basis.IDENTITY, Vector3(0, 0, -float(f) * 0.02))
			st.vel = Vector3(0, 0, -1)
			an.update_pose(1.0 / 60.0, st)
		var moved := 0
		for i in range(1, ph.anatomy.bones.size()):
			var q := sk.get_bone_pose_rotation(i)
			if not q.is_equal_approx(an.rig.rest_q[i]):
				moved += 1
		changed[preset] = moved
		sk.free()
	for preset in changed:
		check(int(changed[preset]) > 0, "%s: bones are animated (%d)" % [preset, changed[preset]])
	check(not (changed[&"fish"] == changed[&"bird"] and changed[&"bird"] == changed[&"octopus"]), "anatomies animate differently")


# --- Persistence, robustness, scheme ---------------------------------------------------------------------------------------

func test_agent_state_roundtrip_through_individual() -> void:
	var s := _sim()
	s.plant_patch(Vector3(-10, 0, 5), 8.0, 0.8)
	var a := s.spawn_preset(&"grazer", Vector3(0, 0, 0), &"adult", 0.4)
	s.run(25.0)
	a.memory.note(CreatureMemory.SPOT_WATER, Vector3(5, 0, 5), 0.9, a.now)
	a.write_state()
	var d := a.individual.to_dict()
	var json := JSON.parse_string(JSON.stringify(d)) as Dictionary
	var restored := Individual.from_dict(json)
	var s2 := _sim(9)
	var b := s2.spawn(restored)
	check(b.position.distance_to(a.position) < 0.01, "position restored")
	near(restored.energy, a.individual.energy, 1.0, "energy restored")
	check(b.memory.spots.size() == a.memory.spots.size() and not b.memory.spots.is_empty(), "spatial memory restored")
	check(b.memory.recall(CreatureMemory.SPOT_WATER, b.position) != Vector3.INF, "water spot remembered")
	s.free()
	s2.free()


func test_invalid_input_does_not_crash() -> void:
	var s := _sim()
	var a := CreatureAgent.new()
	a.setup(Individual.new(null), s.ctx)
	a.sim_update(0.1, 6.0)
	var st := a.get_status()
	for k in ["action", "needs", "energy_frac", "health", "hydration", "body_temp", "age_days", "stage", "sex", "generation", "species_id", "medium", "speed", "target_desc"]:
		check(st.has(k), "status has %s" % k)
	for k in ["hunger", "thirst", "fatigue", "fear", "temperature_discomfort", "mate", "social"]:
		check((st["needs"] as Dictionary).has(k), "needs has %s" % k)
	a.teardown()
	a.free()
	s.free()


func test_tiers_and_possession_contract() -> void:
	var s := _sim()
	var a := s.spawn_preset(&"grazer", Vector3(0, 0, 0))
	check(not a.is_possessed(), "free by default")
	a.set_tier(1)
	s.run(3.0)
	a.set_tier(0)
	a.set_lod(1)
	a.possess(_dummy)
	check(a.is_possessed(), "possess")
	a.release()
	check(not a.is_possessed(), "release")
	a.set_selected(true)
	check(a.species_id() == a.individual.species_id, "species_id")
	s.free()


func test_control_scheme_by_body_type() -> void:
	var s := _sim()
	var kinds := {&"grazer": &"ground", &"bird": &"flyer", &"fish": &"swimmer", &"octopus": &"tentacle", &"cell": &"cell"}
	for p in kinds:
		var a := s.spawn_preset(p, Vector3(-30, 0, 30) if p != &"fish" and p != &"octopus" and p != &"cell" else Vector3(ArenaWorld.POND_CENTER.x, 0, ArenaWorld.POND_CENTER.y))
		check(ControlScheme.kind_of(a) == kinds[p], "%s -> %s (got %s)" % [p, kinds[p], ControlScheme.kind_of(a)])
	var d := ControlScheme.move_direction(Vector2(0, -1), 0.0, 0.0)
	check(d.z < -0.9, "stick up moves along the view direction")
	var r := ControlScheme.move_direction(Vector2(1, 0), PI * 0.5, 0.0)
	check(r.z < -0.9, "camera-relative strafing")
	s.free()


func test_context_actions_available_only_when_relevant() -> void:
	var s := _sim()
	s.plant_patch(Vector3(0, 0, 0), 12.0, 0.8)
	var g := s.spawn_preset(&"grazer", Vector3(0, 0, 0), &"adult", 0.3)
	_hold(g)
	var av := PlayerActions.available(g)
	check(av["eat"], "can eat where plants grow")
	check(not av["drink"], "no drinking away from water")
	check(not av["attack"], "nobody to attack")
	check(not av["fly"], "grazer cannot fly")
	var other := s.spawn_preset(&"turtle", Vector3(0, 0, -1.2))
	_hold(other)
	g.mover.heading = 0.0
	av = PlayerActions.available(g)
	check(av["attack"], "attack appears with a target in reach")
	var kg := PlayerActions.eat(g, 1.0)
	check(kg > 0.0, "eating through the player action feeds the creature")
	s.free()


func test_arena_scene_builds_and_reports_capabilities() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var arena := TestArena.new()
	arena.auto_start = false
	tree.root.add_child(arena)
	arena.start({"preset": "bird", "return_to": "editor"})
	check(arena.player != null and arena.controller != null, "player and controller exist")
	var txt := arena.capability_text()
	check(txt.contains("летает"), "capability readout mentions flight for a bird")
	check(arena.player.is_possessed(), "third-person control starts possessed")
	arena.controller.set_ai_driven(true)
	check(not arena.player.is_possessed(), "Observe AI hands the creature back to the brain")
	arena.controller.release()
	arena.queue_free()


# --- Performance (reported, loosely bounded) --------------------------------------------------------------------------------

func test_many_agents_cost() -> void:
	var s := _sim(11)
	s.plant_patch(Vector3(-20, 0, 10), 14.0, 0.8)
	var presets := [&"grazer", &"predator", &"runner", &"bird", &"frog", &"spider", &"turtle", &"insect", &"centipede"]
	for i in 100:
		var p: StringName = presets[i % presets.size()]
		var x := -40.0 + float(i % 10) * 8.0
		var z := -40.0 + float(i / 10) * 5.0
		if absf(x - ArenaWorld.POND_CENTER.x) < 14.0 and absf(z - ArenaWorld.POND_CENTER.y) < 14.0:
			x -= 30.0
		var a := s.spawn_preset(p, Vector3(x, 0, z))
		a.set_tier(0 if i < 20 else 1)
	s.run(2.0)   # warm-up
	var t0 := Time.get_ticks_usec()
	var frames := 60
	for f in frames:
		s.step(1.0 / 30.0)
	var per_frame_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(frames)
	var n := s.alive_count()
	print("    perf: %d agents (20 tier A, rest tier B): %.2f ms per frame = %.1f agents per ms" % [n, per_frame_ms, float(n) / maxf(per_frame_ms, 0.001)])
	check(n > 60, "agents survive the warm-up (%d)" % n)
	check(per_frame_ms < 60.0, "100 agents step in a sane time (%.1f ms)" % per_frame_ms)
	s.free()
