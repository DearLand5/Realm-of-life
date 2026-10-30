extends TestCase
## WorldBuilder: new world creation, pool simulation over days, save/restore.


func _small_menu() -> Dictionary:
	return {"seed": 4242, "size": 256.0, "procedural_species": 6, "name": "Тест"}


func test_create_and_run() -> void:
	var t0 := Time.get_ticks_msec()
	var st := WorldBuilder.create(_small_menu())
	var t_create := Time.get_ticks_msec() - t0
	var alive := st.evo.registry.alive()
	check(alive.size() >= 4, "fauna registered (%d)" % alive.size())
	for d in alive:
		check(st.evo.registry.count(d.id) > 0.0, "%s seeded" % d.name)
	t0 = Time.get_ticks_msec()
	st.pop.sector_budget = 0
	var day := 0.0
	for i in 30 * 4:
		st.climate.bio_time += 21600.0
		st.eco.step_all(21600.0)
		st.pop.step(21600.0)
		if i % 4 == 3:
			day += 1.0
			st.climate.day = int(day)
			st.evo.daily(day)
	var t_run := Time.get_ticks_msec() - t0
	var survivors := 0
	for d in st.evo.registry.all():
		if st.evo.registry.count(d.id) > 0.5:
			survivors += 1
	print("    create %d ms, 30 days %d ms, survivors %d/%d, total %.0f" % [t_create, t_run, survivors, alive.size(), st.total_population()])
	check(survivors >= 3, "most species survive 30 days (%d)" % survivors)


func test_save_restore_roundtrip() -> void:
	var st := WorldBuilder.create(_small_menu())
	st.pop.sector_budget = 0
	for i in 8:
		st.eco.step_all(21600.0)
		st.pop.step(21600.0)
	var d := st.to_dict()
	var json := JSON.stringify(d)
	var back: Dictionary = JSON.parse_string(json)
	var st2 := WorldBuilder.restore(back)
	check(st2.evo.registry.alive().size() == st.evo.registry.alive().size(), "species restored")
	near(st2.total_population(), st.total_population(), maxf(1.0, st.total_population() * 0.01), "population restored")
	near(st2.eco.total_biomass(), st.eco.total_biomass(), st.eco.total_biomass() * 0.01 + 0.01, "biomass restored")
	check(st2.world.heights.size() == st.world.heights.size(), "world regenerated")
