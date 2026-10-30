extends TestCase
## Physiology, individual life cycle and reproduction.

const DAY := Units.SECONDS_PER_DAY
const HOUR := 3600.0


func _ind(id: StringName, seed_value: int = 1) -> Individual:
	return Individual.create(BodyPlanPresets.create(id), 1, &"adult", Rng.new(seed_value))


func _env(temp: float, extra: Dictionary = {}) -> Dictionary:
	var e := {"temperature": temp, "humidity": 0.6, "oxygen": 1.0, "in_water": false, "light": 0.5, "water_nearby": true}
	for k in extra:
		e[k] = extra[k]
	return e


## Runs an individual for `days`, returns the death cause (&"" if alive).
func _run(bio: BiologySystem, ind: Individual, env: Dictionary, seconds: float, activity: float, feed_kind: int = -1, step: float = HOUR) -> StringName:
	var t := 0.0
	while t < seconds and ind.alive:
		if feed_kind >= 0:
			bio.feed(ind, feed_kind, 100.0, 1.0)
		for ev in bio.tick(ind, env, step, activity):
			if ev["type"] == &"died":
				return ev["cause"]
		t += step
	return &"" if ind.alive else ind.cause


func test_fed_vs_starving() -> void:
	var bio := BiologySystem.new(11)
	var fed := _ind(&"grazer")
	var hungry := _ind(&"grazer", 2)
	hungry.disease = 0.0
	var env := _env(12.0)
	var cause := _run(bio, fed, env, 6.0 * DAY, 0.15, Food.PLANT)
	check(cause == &"", "fed grazer survives 6 days (died of %s)" % cause)
	check(fed.energy_fraction() > 0.5, "fed grazer keeps its reserve (%.2f)" % fed.energy_fraction())
	var t := 0.0
	while hungry.alive and t < 60.0 * DAY:
		bio.tick(hungry, env, HOUR, 0.15)
		t += HOUR
	check(not hungry.alive, "unfed grazer dies")
	check(hungry.cause == &"starvation", "unfed grazer dies of starvation (%s)" % hungry.cause)
	var days := t / DAY
	check(days > 3.0 and days < 25.0, "starvation takes a plausible time (%.1f days)" % days)
	# A small endotherm starves faster than a big one (fasting endurance ∝ M^0.25).
	var bird := _ind(&"bird")
	var tb := 0.0
	while bird.alive and tb < 60.0 * DAY:
		bio.tick(bird, env, HOUR, 0.15)
		tb += HOUR
	check(tb < t, "bird starves sooner than the grazer (%.1f vs %.1f days)" % [tb / DAY, days])


func test_insulation_reduces_cold_cost() -> void:
	var thin := BodyPlanPresets.create(&"grazer")
	thin.set_value(&"fur_length", 0.5)
	var thick := BodyPlanPresets.create(&"grazer")
	thick.set_value(&"fur_length", 2.0)
	var pa := Phenotype.build(thin).physiology
	var pb := Phenotype.build(thick).physiology
	check(pb.conductance_air < pa.conductance_air, "thick fur lowers thermal conductance")
	var r := ThermalModel.Result.new()
	ThermalModel.steady(pa, -25.0, false, 0.0, 3.0, pa.maintenance_rate(pa.body_temp_set), 1.0, r)
	var cost_thin := r.extra_w
	ThermalModel.steady(pb, -25.0, false, 0.0, 3.0, pb.maintenance_rate(pb.body_temp_set), 1.0, r)
	var cost_thick := r.extra_w
	check(cost_thin > cost_thick * 1.3, "thin fur costs more heat at -25 °C (%.0f vs %.0f W)" % [cost_thin, cost_thick])
	# The same difference shows up in the energy reserve of living individuals.
	var bio := BiologySystem.new(3)
	var a := Individual.create(thin, 1, &"adult", Rng.new(1))
	var b := Individual.create(thick, 1, &"adult", Rng.new(1))
	a.energy = a.max_energy()
	b.energy = b.max_energy()
	for i in 24:
		bio.tick(a, _env(-25.0), HOUR, 0.1)
		bio.tick(b, _env(-25.0), HOUR, 0.1)
	check(b.energy_fraction() > a.energy_fraction(), "thick fur saves energy in the cold (%.2f vs %.2f)" % [b.energy_fraction(), a.energy_fraction()])
	# Endotherms pay nothing extra inside the thermoneutral zone.
	ThermalModel.steady(pb, 15.0, false, 0.3, 1.0, pb.maintenance_rate(pb.body_temp_set), 1.0, r)
	near(r.extra_w, 0.0, pb.bmr_watts * 0.05, "no thermoregulation cost at 15 °C")


func test_ectotherm_temperature_dependence() -> void:
	var p := Phenotype.build(BodyPlanPresets.create(&"turtle")).physiology
	check(p.basal_rate(30.0) > p.basal_rate(10.0) * 3.0, "Q10: ectotherm metabolism rises with temperature")
	var r := ThermalModel.Result.new()
	ThermalModel.steady(p, 5.0, false, 0.0, 1.0, p.basal_rate(5.0), 1.0, r)
	var cold_perf := r.performance
	ThermalModel.steady(p, 24.0, false, 0.5, 1.0, p.basal_rate(24.0), 1.0, r)
	check(r.performance > cold_perf + 0.3, "ectotherm is sluggish in the cold (%.2f vs %.2f)" % [cold_perf, r.performance])
	# Endotherm keeps its body temperature.
	var g := Phenotype.build(BodyPlanPresets.create(&"grazer")).physiology
	ThermalModel.steady(g, 0.0, false, 0.0, 1.0, g.basal_rate(g.body_temp_set), 1.0, r)
	near(r.body_temp, g.body_temp_set, 1.0, "endotherm regulates body temperature at 0 °C")


func test_respiration_media() -> void:
	var bio := BiologySystem.new(5)
	# Fish on land suffocates.
	var fish := _ind(&"fish")
	var cause := _run(bio, fish, _env(18.0, {"humidity": 0.7}), DAY, 0.1, -1, 600.0)
	check(cause == &"suffocation", "fish dies on land of suffocation (%s)" % cause)
	# Fish in water is fine.
	var fish2 := _ind(&"fish")
	cause = _run(bio, fish2, _env(14.0, {"in_water": true, "oxygen": 0.8}), DAY, 0.1, Food.MEAT, 600.0)
	check(cause == &"", "fish lives in water (%s)" % cause)
	# Land mammal held under water drowns quickly.
	var grazer := _ind(&"grazer")
	cause = _run(bio, grazer, _env(15.0, {"in_water": true, "air_access": false, "oxygen": 0.8}), 2.0 * HOUR, 0.3, -1, 60.0)
	check(cause == &"drowning", "grazer drowns under water (%s)" % cause)
	# ... but swimming at the surface it breathes.
	var swimmer := _ind(&"grazer")
	cause = _run(bio, swimmer, _env(15.0, {"in_water": true, "air_access": true, "oxygen": 0.8}), 2.0 * HOUR, 0.3, -1, 60.0)
	check(cause == &"", "grazer swimming at the surface survives (%s)" % cause)
	# Amphibian: lungs on land, skin under water.
	var frog := _ind(&"frog")
	cause = _run(bio, frog, _env(18.0, {"humidity": 0.75}), 0.5 * DAY, 0.15, Food.MEAT, 600.0)
	check(cause == &"", "frog survives on land near water (%s)" % cause)
	var frog2 := _ind(&"frog")
	cause = _run(bio, frog2, _env(14.0, {"in_water": true, "air_access": false, "oxygen": 0.85}), 0.5 * DAY, 0.05, Food.MEAT, 600.0)
	check(cause == &"", "frog survives submerged at rest through its skin (%s)" % cause)
	# Limits: a frog far from water in dry air dries out.
	var frog3 := _ind(&"frog")
	cause = _run(bio, frog3, _env(26.0, {"humidity": 0.25, "water_nearby": false}), 3.0 * DAY, 0.15, Food.MEAT, 600.0)
	check(cause == &"dehydration", "frog in dry air dies of dehydration (%s)" % cause)


func test_trachea_limits_size() -> void:
	var small := Phenotype.build(BodyPlanPresets.create(&"insect")).physiology
	var g := BodyPlanPresets.create(&"insect")
	g.set_value(&"size", 2.0)
	var big := Phenotype.build(g).physiology
	check(big.trachea_efficiency < small.trachea_efficiency, "tracheal efficiency falls with body size")
	check(big.scope_land < small.scope_land, "bigger insect has less aerobic scope")
	var texts := ""
	for n in big.diagnose():
		texts += str(n["text"]) + "\n"
	check(texts.contains("Трахейное дыхание неэффективно для такой массы"), "diagnostics explain the tracheal limit")


func test_diagnostics_explain() -> void:
	var grazer := Phenotype.build(BodyPlanPresets.create(&"grazer")).physiology
	var text := ""
	for n in grazer.diagnose():
		text += str(n["text"]) + "\n"
	check(text.contains("Большая масса тела повышает энергетические затраты"), "large mass note")
	# A land animal without lungs or permeable skin cannot breathe.
	var g := BodyPlanPresets.create(&"grazer")
	for p in g.body_plan.parts.duplicate():
		if p.kind == &"organ" and str(p.get_param("organ_type", "")) == "lungs":
			g.body_plan.remove_part(p.id)
	g.invalidate()
	var ph := Phenotype.build(g)
	var crit := false
	for n in ph.physiology.diagnose():
		if n["level"] == &"critical" and str(n["text"]).contains("Отсутствует эффективная система газообмена для выбранной среды"):
			crit = true
	check(crit, "lungless land animal gets a critical gas-exchange note")
	check(AnatomyDiagnostics.viability(AnatomyDiagnostics.run(ph)) < 0.6, "lungless land animal is not viable")


func test_growth_and_maturation() -> void:
	var bio := BiologySystem.new(9)
	var g := BodyPlanPresets.create(&"grazer")
	var fed := Individual.create(g, 1, &"juvenile", Rng.new(1))
	var starved := Individual.create(g, 1, &"juvenile", Rng.new(2))
	var g0 := fed.growth
	var matured := false
	var env := _env(20.0)
	var p := fed.physiology()
	var t := 0.0
	while t < p.maturity_age * 1.6:
		bio.feed(fed, Food.PLANT, 100.0)
		for ev in bio.tick(fed, env, HOUR, 0.15):
			if ev["type"] == &"matured":
				matured = true
		starved.energy = minf(starved.energy, starved.max_energy() * 0.15)
		bio.tick(starved, env, HOUR, 0.15)
		t += HOUR
	check(fed.alive and fed.growth > g0 + 0.2, "fed juvenile grows (%.2f → %.2f)" % [g0, fed.growth])
	check(matured and fed.stage == &"adult", "fed juvenile matures (stage %s)" % fed.stage)
	check(starved.growth < fed.growth - 0.1, "underfed juvenile is stunted (%.2f vs %.2f)" % [starved.growth, fed.growth])


func test_eggs_and_birth() -> void:
	var bio := BiologySystem.new(21)
	var rng := Rng.new(4)
	var settings := {"rate": 0.0, "structural_probability": 0.0}
	bio.mutation_settings = settings
	var env := _env(20.0, {"in_water": true, "air_access": true})
	# Egg layer: frog pair.
	var mom := _ind(&"frog", 1)
	var dad := _ind(&"frog", 2)
	mom.sex = Individual.Sex.FEMALE
	dad.sex = Individual.Sex.MALE
	mom.energy = mom.max_energy()
	dad.energy = dad.max_energy()
	var conceived := false
	for i in 20:
		if Reproduction.conceive(mom, dad, rng, settings):
			conceived = true
			break
		dad.repro_cooldown = 0.0
	check(conceived, "frogs conceive")
	var eggs: Array[Individual] = []
	for i in 24 * 5:
		bio.feed(mom, Food.MEAT, 1.0)
		for ev in bio.tick(mom, env, HOUR, 0.1):
			if ev["type"] == &"laid_eggs":
				eggs.assign(ev["eggs"])
		if not eggs.is_empty():
			break
	check(not eggs.is_empty(), "frog lays eggs")
	if eggs.is_empty():
		return
	check(eggs[0].is_egg() and eggs[0].incubation_left > 0.0, "eggs are Individuals in the egg stage")
	var hatched := 0
	for egg in eggs:
		for i in 48:
			for ev in bio.tick(egg, env, HOUR, 0.0):
				if ev["type"] == &"hatched":
					hatched += 1
			if not egg.is_egg():
				break
	check(hatched == eggs.size(), "all eggs hatch in water (%d/%d)" % [hatched, eggs.size()])
	check(eggs[0].larval, "amphibian hatchlings are larvae")
	# Live bearer.
	var cow := _ind(&"grazer", 5)
	var bull := _ind(&"grazer", 6)
	cow.sex = Individual.Sex.FEMALE
	bull.sex = Individual.Sex.MALE
	cow.energy = cow.max_energy()
	bull.energy = bull.max_energy()
	var ok := false
	for i in 20:
		if Reproduction.conceive(cow, bull, rng, settings):
			ok = true
			break
		bull.repro_cooldown = 0.0
	check(ok and cow.pregnant, "grazers conceive")
	var born: Array[Individual] = []
	for i in 24 * 4:
		bio.feed(cow, Food.PLANT, 50.0)
		for ev in bio.tick(cow, _env(15.0), HOUR, 0.1):
			if ev["type"] == &"gave_birth":
				born.assign(ev["offspring"])
		if not born.is_empty():
			break
	check(not born.is_empty() and born[0].stage == &"juvenile", "grazer gives birth to juveniles")
	if not born.is_empty():
		check(born[0].mother_id == cow.id and born[0].father_id == bull.id, "parents recorded")
		check(born[0].mass() < cow.mass() * 0.3, "newborn is small")


func test_mendelian_ratio_through_reproduction() -> void:
	var rng := Rng.new(77)
	var settings := {"rate": 0.0, "structural_probability": 0.0}
	var g := BodyPlanPresets.create(&"insect")
	var li := TraitCatalog.locus_start(TraitCatalog.index_of(&"albinism"))
	g.alleles[li * 2] = 1.0
	g.alleles[li * 2 + 1] = 0.0
	g.invalidate()
	var ph := Phenotype.build(g)
	var affected := 0
	var total := 0
	for i in 200:
		var mom := Individual.new(g)
		mom.set_phenotype(ph)
		mom.species_id = 1
		mom.sex = Individual.Sex.FEMALE
		mom.set_stage_age(&"adult")
		mom.energy = mom.max_energy()
		var dad := Individual.new(g)
		dad.set_phenotype(ph)
		dad.species_id = 1
		dad.sex = Individual.Sex.MALE
		dad.set_stage_age(&"adult")
		dad.energy = dad.max_energy()
		if not Reproduction.conceive(mom, dad, rng, settings):
			continue
		for child in Reproduction.offspring(mom, rng):
			total += 1
			if child.genome.norm(&"albinism") > 0.5:
				affected += 1
	check(total > 500, "enough offspring (%d)" % total)
	near(float(affected) / maxf(float(total), 1.0), 0.25, 0.04, "Aa × Aa recessive phenotype ratio through Reproduction")


func test_mate_compatibility() -> void:
	var a := _ind(&"predator", 1)
	var b := _ind(&"predator", 2)
	a.sex = Individual.Sex.FEMALE
	b.sex = Individual.Sex.MALE
	a.energy = a.max_energy()
	b.energy = b.max_energy()
	check(Reproduction.can_mate(a, b), "healthy mature pair can mate: %s" % Reproduction.mate_check(a, b)["reason"])
	b.sex = Individual.Sex.FEMALE
	check(not Reproduction.can_mate(a, b), "same sex cannot mate")
	b.sex = Individual.Sex.MALE
	var other := _ind(&"grazer", 3)
	other.species_id = 2
	check(not Reproduction.can_mate(a, other), "different species cannot mate")
	var young := Individual.create(BodyPlanPresets.create(&"predator"), 1, &"juvenile", Rng.new(4))
	young.sex = Individual.Sex.MALE
	check(not Reproduction.can_mate(a, young), "juvenile cannot mate")
	b.energy = b.max_energy() * 0.1
	check(not Reproduction.can_mate(a, b), "starving partner is not ready")
	# Seasonal breeders wait for spring.
	var climate := ClimateState.new()
	climate.year_phase = 0.85  # winter
	b.energy = b.max_energy()
	var seasonal_p := a.physiology()
	if seasonal_p.breeding_season > 0.5:
		check(not Reproduction.can_mate(a, b, climate), "seasonal breeder does not mate in winter")


func test_individual_roundtrip() -> void:
	var bio := BiologySystem.new(1)
	var ind := _ind(&"frog")
	ind.position = Vector3(3, 1, -2)
	bio.feed(ind, Food.MEAT, 0.05)
	bio.tick(ind, _env(20.0), HOUR, 0.2)
	ind.tags["note"] = "тест"
	var json := JSON.stringify(ind.to_dict())
	var back := Individual.from_dict(JSON.parse_string(json))
	check(back.id == ind.id and back.species_id == ind.species_id, "ids survive")
	near(back.energy, ind.energy, ind.energy * 0.001 + 1.0, "energy survives")
	near(back.stomach_kg[Food.MEAT], ind.stomach_kg[Food.MEAT], 1e-5, "stomach survives")
	check(back.stage == ind.stage and back.sex == ind.sex, "stage and sex survive")
	check(back.position.distance_to(ind.position) < 0.001, "position survives")
	check(Genetics.distance(back.genome, ind.genome) < 0.001, "genome survives")
	check(back.get_phenotype() != null, "phenotype rebuilt lazily")
	check(str(back.tags.get("note", "")) == "тест", "tags survive")
	var fresh := Individual.new(ind.genome)
	check(fresh.id > ind.id, "id counter advanced past loaded ids")
