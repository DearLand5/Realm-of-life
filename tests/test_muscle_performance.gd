extends TestCase
## MuscleSystem dynamics and PerformanceManager tiering/sector logic.


func test_muscle_groups_from_anatomy() -> void:
	var ph := Phenotype.build(BodyPlanPresets.create(&"predator"))
	var ms := MuscleSystem.new(ph)
	check(ms.groups.size() >= 6, "predator has muscle groups (%d)" % ms.groups.size())
	var legs := ms.group_indices(&"run")
	check(legs.size() == 4, "four running leg groups (%d)" % legs.size())
	for g in ms.groups:
		check(g.max_force > 0.0 and g.max_power > 0.0, "%s has force and power" % g.name)


func test_fatigue_and_recovery() -> void:
	var ms := MuscleSystem.new(Phenotype.build(BodyPlanPresets.create(&"grazer")))
	ms.set_activation_by_function(&"run", 1.0)
	for i in 600:
		ms.update(0.1)
	var tired := ms.available_force(&"run")
	check(tired < 0.8, "sprinting a minute tires the legs (%.2f)" % tired)
	check(ms.power_watts() > 0.0, "active muscles cost energy")
	ms.relax_all()
	for i in 3000:
		ms.update(0.1)
	check(ms.available_force(&"run") > tired + 0.1, "rest recovers force")
	check(ms.power_watts() == 0.0, "relaxed muscles cost nothing extra")


func test_fast_vs_slow_fibres() -> void:
	var g := BodyPlanPresets.create(&"grazer")
	var fast := g.copy()
	for p in fast.body_plan.parts:
		p.fast_twitch = 1.0
	var slow := g.copy()
	for p in slow.body_plan.parts:
		p.fast_twitch = 0.0
	var mf := MuscleSystem.analyze(AnatomyCompiler.compile(fast), fast)
	var msl := MuscleSystem.analyze(AnatomyCompiler.compile(slow), slow)
	check(mf[0].max_power > msl[0].max_power, "fast fibres more powerful")
	check(mf[0].endurance < msl[0].endurance, "slow fibres more enduring")


class FakeAgent:
	extends Node3D
	var tier := -1
	var lod := -1
	func set_tier(t: int) -> void:
		tier = t
	func set_lod(l: int) -> void:
		lod = l


func test_tier_assignment_budget() -> void:
	var pm := PerformanceManager.new()
	pm.profile.set_level(&"low")
	var agents := []
	var holder := Node3D.new()
	for i in 30:
		var a := FakeAgent.new()
		holder.add_child(a)
		a.position = Vector3(float(i) * 2.0, 0, 0)
		agents.append(a)
	pm.focus = Vector3.ZERO
	# Not in tree: global_position works only in tree; use a temporary root.
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(holder)
	pm.assign_tiers(agents)
	var n_a := 0
	for a in agents:
		if a.tier == 0:
			n_a += 1
	check(n_a == pm.profile.i("max_tier_a"), "tier A capped by budget (%d)" % n_a)
	check(agents[0].tier == 0 and agents[29].tier == 1, "closest get tier A")
	holder.queue_free()
	pm.free()


func test_sector_hysteresis() -> void:
	var pm := PerformanceManager.new()
	pm.profile.set_level(&"medium")
	pm.focus = Vector3.ZERO
	var r := pm.update_active_sectors(256.0)
	check(not r["activate"].is_empty(), "sectors activate around focus")
	var n := pm.active_sector_count()
	pm.focus = Vector3(5, 0, 0)
	r = pm.update_active_sectors(256.0)
	check(r["deactivate"].is_empty(), "small move deactivates nothing (hysteresis)")
	check(pm.update_time_scale(1024.0), "extreme scale → statistical mode")
	r = pm.update_active_sectors(256.0)
	check(r["deactivate"].size() >= n, "statistical mode folds every sector")
	pm.free()
