extends TestCase
## EcoGrid, population pools (stability, rates, selection, migration,
## predation), fold/unfold and save/load roundtrips.

const DAY := Units.SECONDS_PER_DAY


## A small world with its ecosystem and population manager.
class Sim:
	var world: WorldData
	var climate: ClimateState
	var eco: EcoGrid
	var pop: PopulationManager

	func _init(w: WorldData, plants: Array[PlantSpecies], seed_value: int = 5, settings: Dictionary = {}, resource: float = 1.0) -> void:
		world = w
		climate = TestWorlds.climate_for(w, 0.05)
		climate.sandbox_resource_mult = resource
		eco = EcoGrid.new()
		eco.setup(w, plants, climate)
		pop = PopulationManager.new()
		pop.setup(w, eco, climate, seed_value, settings if not settings.is_empty() else Genetics.settings_with_defaults())

	func step(dt: float, pools: bool = true) -> void:
		TestWorlds.advance(climate, dt)
		eco.step_all(dt)
		if pools:
			pop.step(dt)

	func run_days(days: int, dt: float = DAY) -> void:
		for d in days:
			for k in maxi(1, int(round(DAY / dt))):
				step(dt)


func _grass_plants() -> Array[PlantSpecies]:
	return EcoDefaults.plants([&"grass", &"shrub"])


func _founders(sim: Sim, ids: Array, counts: Array) -> void:
	for i in ids.size():
		sim.pop.seed_species(i + 1, BodyPlanPresets.create(ids[i]), float(counts[i]))


# --- EcoGrid ------------------------------------------------------------------------

func test_eco_grid_grows_and_is_grazed() -> void:
	var w := TestWorlds.flat(16.0, 0.5, 64.0, 9)
	var sim := Sim.new(w, _grass_plants())
	var eco := sim.eco
	check(eco.total_biomass(0) > 0.0, "initial grass exists")
	# Grazing removes biomass and yields energy.
	var cells := eco.cells_in_rect(-32.0, -32.0, 32.0, 32.0)
	var prefs := PackedFloat32Array([1.0, 0.0])
	var avail := eco.plant_available(cells, prefs)
	var h := EcoGrid.Harvest.new()
	eco.harvest_plants(cells, avail * 0.8, prefs, h)
	near(h.kg, avail * 0.8, avail * 0.01, "harvest returns the requested kg")
	check(h.energy > h.kg * 1.0e6, "harvest carries energy")
	near(eco.plant_available(cells, prefs), avail * 0.2, avail * 0.02, "available biomass drops accordingly")
	check(eco.total_biomass(1) > 0.0, "unpreferred plants are untouched")
	# Regrowth after grazing.
	var after := eco.plant_available(cells, prefs)
	for i in 6:
		sim.step(DAY)
	check(eco.plant_available(cells, prefs) > after * 1.3, "grazed grass regrows (%.0f -> %.0f kg)" % [after, eco.plant_available(cells, prefs)])
	# A year later the grass has a seasonal cycle but never dies out.
	var lo := INF
	for i in 80:
		sim.step(DAY)
		lo = minf(lo, eco.total_biomass(0))
	check(lo > 20.0, "grass persists through the seasons (min %.0f kg)" % lo)


func test_eco_grid_carcass_becomes_detritus() -> void:
	var w := TestWorlds.flat(16.0, 0.5, 64.0, 9)
	var sim := Sim.new(w, _grass_plants())
	var det0 := 0.0
	for d in sim.eco.detritus:
		det0 += d
	sim.eco.add_carcass(Vector3(5, 0, 5), 200.0, 3)
	check(sim.eco.carcasses.count() == 1, "carcass added")
	check(not sim.eco.nearest_carcass(Vector3(5, 0, 5), 3.0).is_empty(), "carcass found nearby")
	for i in 120:
		sim.step(DAY)
	var det1 := 0.0
	for d in sim.eco.detritus:
		det1 += d
	check(sim.eco.carcasses.total_kg() < 5.0, "carcass decays (%.1f kg left)" % sim.eco.carcasses.total_kg())
	check(det1 > det0, "decayed mass enters the detritus pool")


func test_eco_grid_roundtrip() -> void:
	var w := TestWorlds.flat(14.0, 0.5, 64.0, 9)
	var plants := _grass_plants()
	var sim := Sim.new(w, plants)
	for i in 8:
		sim.step(DAY)
	sim.eco.add_carcass(Vector3(3, 0, -4), 80.0, 2)
	var d := sim.eco.to_dict()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(d))
	var eco2 := EcoGrid.restore(w, plants, sim.climate, parsed)
	near(eco2.total_biomass(0), sim.eco.total_biomass(0), 1.0, "grass biomass restored")
	near(eco2.total_biomass(1), sim.eco.total_biomass(1), 1.0, "shrub biomass restored")
	check(eco2.carcasses.count() == 1, "carcass restored")
	near(eco2.carcasses.total_kg(), sim.eco.carcasses.total_kg(), 0.5, "carcass mass restored")
	near(eco2.detritus[10], sim.eco.detritus[10], 1e-3, "detritus restored")
	# Both continue identically.
	sim.eco.step_all(DAY)
	eco2.step_all(DAY)
	near(eco2.total_biomass(0), sim.eco.total_biomass(0), 2.0, "restored grid evolves identically")


# --- Pools: stability and rates -------------------------------------------------------

func test_pools_stable_100_days() -> void:
	var w := TestWorlds.flat(16.0, 0.38, 96.0, 9)
	var sim := Sim.new(w, _grass_plants())
	_founders(sim, [&"grazer", &"predator"], [20.0, 3.0])
	var lo := [INF, INF]
	var hi := [0.0, 0.0]
	for day in 120:
		sim.step(DAY)
		for s in 2:
			var n := sim.pop.total_count(s + 1)
			finite(n, "count finite")
			lo[s] = minf(lo[s], n)
			hi[s] = maxf(hi[s], n)
	check(lo[0] > 1.0, "herbivores never collapse (min %.1f)" % lo[0])
	check(hi[0] < 150.0, "herbivores stay bounded (max %.1f)" % hi[0])
	check(sim.pop.total_count(2) > 0.5, "predators survive 120 days (%.1f)" % sim.pop.total_count(2))
	check(hi[1] < 40.0, "predators stay bounded (max %.1f)" % hi[1])
	check(sim.eco.total_biomass(0) > 0.0, "grass is not wiped out")


func test_pools_stable_at_small_steps_and_huge_steps() -> void:
	for dt in [21600.0, 5.0 * DAY]:
		var w := TestWorlds.flat(16.0, 0.38, 64.0, 9)
		var sim := Sim.new(w, _grass_plants())
		_founders(sim, [&"grazer", &"predator"], [10.0, 1.5])
		var steps := int(round(60.0 * DAY / dt))
		var peak := 0.0
		for i in steps:
			sim.step(dt)
			for sid in [1, 2]:
				var n := sim.pop.total_count(sid)
				finite(n, "count finite at dt=%d" % int(dt))
				peak = maxf(peak, n)
		check(peak < 100.0, "bounded at dt=%d s (peak %.1f)" % [int(dt), peak])
		check(sim.pop.total_count(1) > 0.5, "herbivores persist at dt=%d s (%.1f)" % [int(dt), sim.pop.total_count(1)])
		for sec in sim.pop.sectors:
			for pool in sec.pools.values():
				var p := pool as SpeciesPool
				var tot := 0.0
				for c in p.classes:
					tot += c
				near(tot, 1.0, 1e-3, "class fractions stay normalised")
				var wsum := 0.0
				for s in p.samples:
					wsum += s.weight
					check(s.energy >= 0.0 and s.energy <= 1.0, "sample energy in range")
				near(wsum, 1.0, 1e-3, "sample weights stay normalised")


func test_pool_rate_breakdown() -> void:
	var w := TestWorlds.flat(16.0, 0.4, 64.0, 9)
	var sim := Sim.new(w, _grass_plants())
	_founders(sim, [&"grazer"], [8.0])
	sim.run_days(10)
	var pool: SpeciesPool = sim.pop.pools_of(1)[0]
	var r := pool.rates
	check(r.bmr_w > 10.0, "maintenance power reported (%.0f W)" % r.bmr_w)
	check(r.intake_w[Food.PLANT] > 1.0, "plant intake reported (%.0f W)" % r.intake_w[Food.PLANT])
	check(r.income_total() > 0.0 and r.demand_total() > 0.0, "income and demand reported")
	check(r.births >= 0.0, "births reported")
	for key in ["starvation", "senescence", "juvenile", "predation", "thermal", "habitat", "water", "disease", "background"]:
		check(r.deaths.has(key), "death cause %s present" % key)
	check(r.main_cause() != "", "main cause named")
	check(r.to_dict().has("deaths"), "breakdown serialises")
	# Starvation shows up when the food is gone.
	for i in sim.eco.plant_mass.size():
		sim.eco.plant_mass[i] = 0.0
	for sec in sim.pop.sectors:
		for p in sec.pools.values():
			for s in (p as SpeciesPool).samples:
				s.energy = 0.05
	sim.pop.step(3600.0)
	var starving: SpeciesPool = sim.pop.pools_of(1)[0]
	check(starving.rates.deaths["starvation"] > 0.1, "starvation mortality visible (%.2f/day)" % starving.rates.deaths["starvation"])
	check(starving.rates.main_cause() == "starvation", "main cause is starvation (%s)" % starving.rates.main_cause())


func test_predation_between_pools() -> void:
	var w := TestWorlds.flat(16.0, 0.5, 32.0, 9)
	var results := []
	for with_predator in [false, true]:
		var sim := Sim.new(w, _grass_plants(), 5, {}, 3.0)
		sim.pop.migration_enabled = false
		_founders(sim, [&"grazer", &"predator"], [4.0, 1.5 if with_predator else 0.0])
		sim.run_days(12)
		results.append(sim.pop.total_count(1))
		if with_predator:
			var pr: SpeciesPool = sim.pop.pools_of(2)[0]
			check(pr.rates.income_total() > 0.0, "predators gain energy")
	check(results[1] < results[0], "predators reduce prey (%.2f vs %.2f)" % [results[1], results[0]])


func test_migration_follows_habitat() -> void:
	var w := TestWorlds.islands(16.0, 128.0, 17)
	var sim := Sim.new(w, _grass_plants())
	var home := sim.pop.sector_index(Vector3(-39.7, 0, -10.0))
	check(sim.pop.sectors[home].land_frac > 0.5, "home sector is land")
	sim.pop.seed_species(1, BodyPlanPresets.create(&"grazer"), 16.0, PackedInt32Array([home]))
	var before := sim.pop.total_count(1)
	for i in 40:
		sim.pop._migrate(DAY)
	near(sim.pop.total_count(1), before, 0.01, "migration conserves individuals")
	var occupied := 0
	var in_ocean := 0.0
	for sec in sim.pop.sectors:
		if sec.pools.has(1):
			occupied += 1
			if sec.water_frac > 0.9:
				in_ocean += (sec.pools[1] as SpeciesPool).count
	check(occupied > 1, "animals spread to neighbour sectors (%d)" % occupied)
	check(in_ocean < 0.02 * before, "a land animal does not settle on open water (%.2f)" % in_ocean)


# --- Selection -----------------------------------------------------------------------

func test_selection_favours_insulation_in_cold() -> void:
	# Two otherwise identical genotypes (poorly vs well insulated) compete
	# for the same food; no mutation. Insulation pays in the cold only.
	var share := {}
	for temp in [-10.0, 12.0]:
		var w := TestWorlds.flat(temp, 0.5, 32.0, 9)
		var plants := EcoDefaults.plants([&"grass"])
		plants.resize(1)
		plants[0].temp_opt = temp
		plants[0].temp_tol = 15.0
		var sim := Sim.new(w, plants, 5, Genetics.settings_with_defaults({"rate": 0.0}), 8.0)
		sim.pop.migration_enabled = false
		var bare := BodyPlanPresets.create(&"grazer")
		bare.set_value(&"fur_length", 0.35)
		bare.set_value(&"fat_reserve", 0.35)
		var furry := BodyPlanPresets.create(&"grazer")
		furry.set_value(&"fur_length", 1.3)
		furry.set_value(&"fat_reserve", 1.3)
		sim.pop.seed_genotypes(1, [bare, furry], 1.5)
		sim.run_days(20)
		var f := 0.0
		var t := 0.0
		for p in sim.pop.pools_of(1):
			for s in p.samples:
				t += s.weight * p.count
				if s.genome.value(&"fur_length") > 1.0:
					f += s.weight * p.count
		share[temp] = f / maxf(t, 1e-9)
		finite(float(share[temp]), "share finite")
	check(float(share[-10.0]) > 0.6, "insulated genotype takes over in the cold (%.2f)" % float(share[-10.0]))
	check(float(share[-10.0]) > float(share[12.0]) + 0.2, "... more than in a mild climate (%.2f vs %.2f)" % [float(share[-10.0]), float(share[12.0])])


## Heritable variation + selection: a grazer population that starts poorly
## insulated evolves thicker fur, more fat and stronger endothermy in a cold
## world compared with a mild control (3 seeds each; deterministic).
func test_evolution_of_insulation_in_cold_world() -> void:
	var cold := 0.0
	var mild := 0.0
	var start := 0.0
	for seed_value in [3, 4, 5]:
		for temp in [-10.0, 12.0]:
			var w := TestWorlds.flat(temp, 0.5, 32.0, 9)
			var plants := EcoDefaults.plants([&"grass"])
			plants.resize(1)
			plants[0].temp_opt = temp
			plants[0].temp_tol = 15.0
			plants[0].growth_rate = 0.3
			plants[0].capacity = 1.0
			var sim := Sim.new(w, plants, seed_value, Genetics.settings_with_defaults({"rate": 10.0}), 8.0)
			var founder := BodyPlanPresets.create(&"grazer")
			founder.set_value(&"fur_length", 0.4)
			founder.set_value(&"fat_reserve", 0.4)
			founder.set_value(&"endothermy", 0.7)
			sim.pop.seed_species(1, founder, 2.0, PackedInt32Array(), 0.1, 8)
			start += _insulation_index(sim.pop) / 6.0
			sim.run_days(150)
			var idx := _insulation_index(sim.pop)
			if temp < 0.0:
				cold += idx / 3.0
			else:
				mild += idx / 3.0
	start /= 1.0
	check(cold > start + 0.05, "cold-world population insulates (index %.2f vs start %.2f)" % [cold, start])
	check(cold > mild + 0.03, "more than the mild control (%.2f vs %.2f)" % [cold, mild])


## Weighted mean of fur + fat + endothermy (normalised trait values).
func _insulation_index(pop: PopulationManager) -> float:
	var t := 0.0
	var wsum := 0.0
	for e in pop.genome_samples(1):
		var g: Genome = e["genome"]
		var w := float(e["weight"])
		t += (g.norm(&"fur_length") + g.norm(&"fat_reserve") + g.norm(&"endothermy")) * w
		wsum += w
	return t / maxf(wsum, 1e-9)


func test_mutation_setting_controls_variation() -> void:
	var spread := []
	for rate in [0.0, 8.0]:
		var w := TestWorlds.flat(16.0, 0.5, 32.0, 9)
		var sim := Sim.new(w, _grass_plants(), 5, Genetics.settings_with_defaults({"rate": rate}), 3.0)
		sim.pop.migration_enabled = false
		var founder := BodyPlanPresets.create(&"grazer")
		sim.pop.seed_species(1, founder, 6.0, PackedInt32Array(), 0.0, 1)
		sim.run_days(60)
		var d := 0.0
		var n := 0.0
		for p in sim.pop.pools_of(1):
			for s in p.samples:
				d += Genetics.distance(s.genome, founder) * s.weight
				n += s.weight
		spread.append(d / maxf(n, 1e-9))
	check(float(spread[1]) > float(spread[0]) + 0.003, "higher mutation rate -> more divergence (%.4f vs %.4f)" % [float(spread[1]), float(spread[0])])
	check(float(spread[0]) < 0.01, "no mutation -> offspring stay clones/recombinants (%.4f)" % float(spread[0]))


# --- Fold / unfold --------------------------------------------------------------------

func _make_herd(n: int) -> Array[Individual]:
	var rng := Rng.new(11)
	var base := BodyPlanPresets.create(&"grazer")
	var genomes: Array[Genome] = []
	for k in 4:
		var g := base.copy_shared_plan()
		g.set_value(&"fur_length", 0.6 + 0.3 * float(k))
		genomes.append(g)
	var out: Array[Individual] = []
	var stages: Array[StringName] = [&"juvenile", &"adolescent", &"adult", &"adult", &"elder"]
	for i in n:
		var ind := Individual.create(genomes[i % 4], 7, stages[i % stages.size()], rng)
		ind.energy = ind.max_energy() * (0.4 + 0.1 * float(i % 5))
		out.append(ind)
	return out


func test_fold_unfold_preserves_counts_and_means() -> void:
	var w := TestWorlds.flat(16.0, 0.5, 64.0, 9)
	var sim := Sim.new(w, _grass_plants())
	var herd := _make_herd(40)
	var mean_fur := 0.0
	var mean_e := 0.0
	for ind in herd:
		mean_fur += ind.genome.value(&"fur_length") / 40.0
		mean_e += ind.energy_fraction() / 40.0
	sim.pop.fold(herd, 1)
	var pool: SpeciesPool = sim.pop.pool(1, 7)
	check(pool != null, "pool created")
	near(pool.count, 40.0, 1e-4, "pool count equals individuals")
	near(pool.mean_energy(), mean_e, 0.02, "mean energy preserved by fold")
	near(sim.pop.trait_means(7, [&"fur_length"])[&"fur_length"], mean_fur, 0.01, "trait mean preserved by fold")
	check(pool.samples.size() <= SpeciesPool.MAX_SAMPLES, "samples capped")
	near(pool.classes[SpeciesPool.JUV], 8.0 / 40.0, 0.01, "juvenile share")
	near(pool.classes[SpeciesPool.ELDER], 8.0 / 40.0, 0.01, "elder share")
	# Partial unfold keeps the rest pooled.
	var part := sim.pop.unfold(1, 12)
	check(part.size() == 12, "unfold returns the requested number (%d)" % part.size())
	near(pool.count, 28.0, 1e-3, "remainder stays in the pool")
	# Full unfold returns everything with the right distribution.
	var rest := sim.pop.unfold(1, 100)
	check(part.size() + rest.size() == 40, "all individuals recovered (%d)" % (part.size() + rest.size()))
	var all: Array[Individual] = []
	all.append_array(part)
	all.append_array(rest)
	var fur := 0.0
	var en := 0.0
	var by_stage := {}
	for ind in all:
		fur += ind.genome.value(&"fur_length") / 40.0
		en += ind.energy_fraction() / 40.0
		by_stage[ind.stage] = int(by_stage.get(ind.stage, 0)) + 1
		check(ind.alive and ind.species_id == 7, "unfolded individuals are alive with the species id")
		check(ind.get_phenotype() != null, "phenotype attached")
	near(fur, mean_fur, 0.12, "trait mean preserved by unfold")
	near(en, mean_e, 0.08, "mean energy preserved by unfold")
	check(int(by_stage.get(&"juvenile", 0)) >= 5 and int(by_stage.get(&"adult", 0)) >= 10, "age structure preserved (%s)" % str(by_stage))
	check(sim.pop.sectors[1].pools.is_empty(), "emptied sector has no pools")
	# Unfolded individuals are alive and can be folded again.
	sim.pop.fold(all, 2)
	near(sim.pop.total_count(7), 40.0, 1e-3, "re-fold restores the count")


func test_fold_merges_into_existing_pool() -> void:
	var w := TestWorlds.flat(16.0, 0.5, 64.0, 9)
	var sim := Sim.new(w, _grass_plants())
	sim.pop.seed_species(7, BodyPlanPresets.create(&"grazer"), 6.0, PackedInt32Array([0]))
	var herd := _make_herd(10)
	sim.pop.fold(herd, 0)
	near(sim.pop.pool(0, 7).count, 16.0, 1e-4, "counts add up")
	var wsum := 0.0
	for s in sim.pop.pool(0, 7).samples:
		wsum += s.weight
	near(wsum, 1.0, 1e-3, "weights normalised after merge")


# --- Save / load -------------------------------------------------------------------------

func test_population_roundtrip() -> void:
	var w := TestWorlds.flat(16.0, 0.5, 64.0, 9)
	var plants := _grass_plants()
	var sim := Sim.new(w, plants)
	_founders(sim, [&"grazer", &"predator"], [10.0, 1.5])
	sim.run_days(15)
	var d := sim.pop.to_dict()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(d))
	var pop2 := PopulationManager.new()
	pop2.setup(w, sim.eco, sim.climate, 5, Genetics.settings_with_defaults())
	pop2.from_dict(parsed)
	for sid in [1, 2]:
		near(pop2.total_count(sid), sim.pop.total_count(sid), 1e-3, "species %d count restored" % sid)
		near(pop2.trait_means(sid, [&"size"])[&"size"], sim.pop.trait_means(sid, [&"size"])[&"size"], 1e-3, "species %d traits restored" % sid)
	for sec in sim.pop.sectors:
		for sid in sec.pools:
			var a: SpeciesPool = sec.pools[sid]
			var b: SpeciesPool = pop2.pool(sec.index, sid)
			check(b != null, "pool restored in sector %d" % sec.index)
			if b != null:
				near(b.count, a.count, 1e-3, "pool count")
				near(b.mean_energy(), a.mean_energy(), 1e-3, "pool energy")
				check(b.samples.size() == a.samples.size(), "sample count restored")
				near(b.classes[SpeciesPool.ADULT], a.classes[SpeciesPool.ADULT], 1e-3, "age structure restored")
