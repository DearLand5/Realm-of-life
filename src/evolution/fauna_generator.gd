class_name FaunaGenerator
extends RefCounted
## Procedural founding fauna that is FUNCTIONALLY viable in a given world.
## For every ecological niche the world offers (grazer, browser, small
## herbivore, predator, scavenger, detritivore, aquatic filter feeder, fish,
## flyer/insectivore, amphibian) an archetype from BodyPlanPresets is
## varied by structural and quantitative mutations, scaled, adapted to the
## local climate (thermal optimum, insulation, water retention) and coloured
## after the dominant biome; then validated with AnatomyDiagnostics and a
## habitat test (respiration + thermal stress over the world's cells).

const NICHES := {
	&"grazer": {"preset": &"grazer", "size": [0.75, 1.15], "medium": &"land", "needs": &"grass",
		"label": "Крупный травоед", "traits": {}},
	&"predator": {"preset": &"predator", "size": [0.7, 1.05], "medium": &"land", "needs": &"prey",
		"label": "Хищник", "traits": {}},
	&"small_herbivore": {"preset": &"grazer", "size": [0.5, 0.6], "medium": &"land", "needs": &"plants",
		"label": "Мелкий травоед", "traits": {"appendage_size": 0.5, "clutch_size": 4.0, "offspring_investment": 0.08, "maturity_age": 0.7, "sociality": 0.5}},
	&"detritivore": {"preset": &"worm", "size": [0.8, 1.3], "medium": &"land", "needs": &"plants",
		"label": "Детритофаг", "traits": {}},
	&"browser": {"preset": &"grazer", "size": [0.95, 1.3], "medium": &"land", "needs": &"trees",
		"label": "Листоед-великан", "traits": {"limb_length": 1.35, "torso_length": 1.1, "appendage_size": 0.8}},
	&"flyer": {"preset": &"bird", "size": [0.8, 1.2], "medium": &"land", "needs": &"plants",
		"label": "Летающий насекомоед", "traits": {"diet_preference": 0.55, "digestion_meat": 0.7}},
	&"scavenger": {"preset": &"runner", "size": [0.6, 0.9], "medium": &"land", "needs": &"prey",
		"label": "Падальщик", "traits": {"digestion_carrion": 0.95, "diet_preference": 0.75, "aggression": 0.2}},
	&"fish": {"preset": &"fish", "size": [0.7, 1.2], "medium": &"water", "needs": &"water",
		"label": "Рыба", "traits": {}},
	&"filter": {"preset": &"jellyfish", "size": [0.55, 0.85], "medium": &"water", "needs": &"water",
		"label": "Фильтратор", "traits": {}},
	&"amphibian": {"preset": &"frog", "size": [0.8, 1.2], "medium": &"amphibious", "needs": &"shore",
		"label": "Земноводное", "traits": {}},
}
## Priority order (ecological dependencies: producers' consumers first).
const ORDER: Array[StringName] = [&"grazer", &"small_herbivore", &"predator", &"detritivore", &"fish",
	&"filter", &"amphibian", &"browser", &"flyer", &"scavenger"]
const MAX_ATTEMPTS := 6
const MIN_VIABILITY := 0.6
const MIN_HABITAT := 0.15


static func generate(world: WorldData, plants: Array[PlantSpecies], rng: Rng, count: int) -> Array[SpeciesDef]:
	var info := analyze(world, plants)
	var niches: Array[StringName] = []
	for n in ORDER:
		if _niche_possible(n, info):
			niches.append(n)
	var out: Array[SpeciesDef] = []
	if niches.is_empty():
		return out
	for k in count:
		var niche := niches[k % niches.size()]
		var def := make_species(niche, world, info, rng)
		if def != null:
			out.append(def)
	return out


## World summary used for niche choice and climate adaptation.
static func analyze(world: WorldData, plants: Array[PlantSpecies]) -> Dictionary:
	var n := 24
	var land := 0
	var water := 0
	var t_land := 0.0
	var t_water := 0.0
	var m_land := 0.0
	var t_min := INF
	var t_max := -INF
	var land_temps := PackedFloat32Array()
	var water_temps := PackedFloat32Array()
	var biome_count := {}
	var half := world.size * 0.5
	for iz in n:
		for ix in n:
			var x := -half + (float(ix) + 0.5) * world.size / float(n)
			var z := -half + (float(iz) + 0.5) * world.size / float(n)
			var t := world.base_temperature_at(x, z)
			if world.water_type_at(x, z) != WorldData.Water.LAND:
				water += 1
				t_water += t
				water_temps.append(t)
			else:
				land += 1
				t_land += t
				m_land += world.moisture_at(x, z)
				land_temps.append(t)
				var b := world.biome_at(x, z)
				biome_count[b] = int(biome_count.get(b, 0)) + 1
			t_min = minf(t_min, t)
			t_max = maxf(t_max, t)
	var total := float(n * n)
	var dominant := Biomes.GRASSLAND
	var best := -1
	for b in biome_count:
		if int(biome_count[b]) > best:
			best = int(biome_count[b])
			dominant = int(b)
	var info := {
		"land_frac": float(land) / total, "water_frac": float(water) / total,
		"t_land": t_land / maxf(float(land), 1.0), "t_water": t_water / maxf(float(water), 1.0),
		"moist": m_land / maxf(float(land), 1.0), "t_range": t_max - t_min, "biome": dominant,
		"land_temps": land_temps, "water_temps": water_temps,
		"grass": false, "trees": false, "plants": false, "algae": false,
	}
	for p in plants:
		var suit := 0.0
		var temp: float = info["t_water"] if p.aquatic else info["t_land"]
		suit = p.suitability(temp, float(info["moist"]) if not p.aquatic else 1.0, p.aquatic)
		if suit < 0.15:
			continue
		if p.aquatic:
			info["algae"] = info["water_frac"] > 0.05
			continue
		info["plants"] = true
		if p.form in [&"grass", &"reed", &"flower", &"fern"]:
			info["grass"] = true
		if p.form in [&"broadleaf_tree", &"conifer", &"palm", &"shrub"]:
			info["trees"] = true
	return info


static func _niche_possible(niche: StringName, info: Dictionary) -> bool:
	var land: float = info["land_frac"]
	var water: float = info["water_frac"]
	match NICHES[niche]["needs"]:
		&"grass":
			return land > 0.1 and bool(info["grass"])
		&"trees":
			return land > 0.1 and bool(info["trees"])
		&"plants", &"prey":
			return land > 0.1 and bool(info["plants"])
		&"water":
			return water > 0.05
		&"shore":
			return water > 0.03 and land > 0.1
	return true


## One validated species for a niche (falls back to the bare archetype).
static func make_species(niche: StringName, world: WorldData, info: Dictionary, rng: Rng) -> SpeciesDef:
	var spec: Dictionary = NICHES[niche]
	var best_g: Genome = null
	var best_score := -1.0
	for attempt in MAX_ATTEMPTS:
		var mutations := maxi(0, 3 - attempt / 2)
		var g := _variant(spec, info, rng, mutations, attempt == MAX_ATTEMPTS - 1)
		var ph := Phenotype.build(g)
		var score := _score(ph, spec, info)
		if score > best_score:
			best_score = score
			best_g = g
		if score >= 1.0:
			break
	if best_g == null:
		return null
	var ph := Phenotype.build(best_g)
	var names := SpeciesNamer.generate(niche, best_g, rng)
	var d := SpeciesDef.new()
	d.name = names["ru"]
	d.latin_name = names["latin"]
	d.origin = &"procedural"
	d.template = best_g
	d.founder = best_g
	d.niche = niche
	d.description = describe(niche, ph)
	d.ui_color = best_g.body_plan.coverings[0].color_a.lightened(0.2)
	return d


static func _variant(spec: Dictionary, info: Dictionary, rng: Rng, mutations: int, plain: bool) -> Genome:
	var g := BodyPlanPresets.create(spec["preset"])
	var plan := g.body_plan.copy()
	if not plain:
		for k in mutations:
			BodyPlanMutator.mutate(plan, rng, 0.6)
	plan.biology = g.body_plan.biology.duplicate()
	g.body_plan = plan
	if not plain:
		Genetics.founder_variation(g, rng, 0.04)
	var traits: Dictionary = spec["traits"]
	for t in traits:
		g.set_value(StringName(t), float(traits[t]) * (1.0 if plain else rng.range_f(0.92, 1.08)))
	var sr: Array = spec["size"]
	g.set_value(&"size", rng.range_f(float(sr[0]), float(sr[1])) if not plain else (float(sr[0]) + float(sr[1])) * 0.5)
	_adapt_climate(g, spec, info, rng)
	_camouflage(g, info, rng)
	g.invalidate()
	return g


static func _adapt_climate(g: Genome, spec: Dictionary, info: Dictionary, rng: Rng) -> void:
	var water := spec["medium"] == &"water"
	var t: float = info["t_water"] if water else info["t_land"]
	g.set_value(&"thermal_optimum", clampf(t + rng.range_f(-2.0, 2.0), -10.0, 40.0))
	g.set_value(&"thermal_tolerance", clampf(6.0 + float(info["t_range"]) * 0.5 + rng.range_f(-1.0, 1.0), 4.0, 25.0))
	var e := g.value(&"endothermy")
	if e > 0.5 and not water:
		# Cold climates: denser fur and more fat; hot climates: thinner coats.
		var cold := clampf((15.0 - t) / 25.0, -0.4, 1.0)
		g.set_value(&"fur_length", clampf(1.0 + cold, 0.5, 2.0))
		g.set_value(&"fat_reserve", clampf(1.0 + cold * 0.7, 0.5, 2.0))
	var dry := clampf((0.45 - float(info["moist"])) / 0.35, 0.0, 1.0)
	g.set_value(&"water_retention", clampf(g.value(&"water_retention") + dry * 0.4, 0.0, 1.0))


static func _camouflage(g: Genome, info: Dictionary, rng: Rng) -> void:
	var target := Biomes.color(int(info["biome"]))
	for c in g.body_plan.coverings:
		c.color_a = c.color_a.lerp(target, rng.range_f(0.3, 0.55))
		c.color_b = c.color_b.lerp(target.lightened(0.3), rng.range_f(0.1, 0.3))


## 0..1 (≥ 1 = fully acceptable): anatomy viability × habitat suitability.
static func _score(ph: Phenotype, spec: Dictionary, info: Dictionary) -> float:
	var items := AnatomyDiagnostics.run(ph)
	for it in items:
		if it["level"] == &"critical":
			return 0.0
	var v := AnatomyDiagnostics.viability(items)
	if v < MIN_VIABILITY:
		return v * 0.5
	var p := ph.physiology
	if p.maturity_age > p.lifespan * 0.5:
		return 0.3
	var h := habitat_suitability(ph, spec["medium"], info)
	if h < MIN_HABITAT:
		return 0.4 * h / MIN_HABITAT
	return minf(1.0, v / 0.85) * minf(1.0, h / 0.5) + 0.0001


## Share of the world's cells (in the species' medium) where it can breathe
## and keep thermal stress low.
static func habitat_suitability(ph: Phenotype, medium: StringName, info: Dictionary) -> float:
	var p := ph.physiology
	var r := ThermalModel.Result.new()
	var heat := p.maintenance_rate(p.body_temp_set) * 1.6
	var ok := 0
	var total := 0
	var media: Array = [[false, info["land_temps"]], [true, info["water_temps"]]]
	for m in media:
		var in_water: bool = m[0]
		if (medium == &"land" and in_water) or (medium == &"water" and not in_water):
			continue
		var temps: PackedFloat32Array = m[1]
		var cap := p.o2_capacity(in_water, 0.8 if in_water else 1.0, not in_water or p.lungs_w > 0.0, 0.6)
		for k in range(0, temps.size(), maxi(1, temps.size() / 32)):
			total += 1
			ThermalModel.steady(p, temps[k], in_water, 0.5, 1.0, heat, 1.0, r)
			if cap >= heat * 1.1 and r.heat_stress < 0.3 and r.cold_stress < 0.3:
				ok += 1
	return float(ok) / float(maxi(total, 1))


static func describe(niche: StringName, ph: Phenotype) -> String:
	var p := ph.physiology
	var lp := ph.locomotion
	var moves := PackedStringArray()
	if lp.can_fly:
		moves.append("летает")
	if lp.can_walk:
		moves.append("бегает до %.1f м/с" % lp.run_speed)
	elif lp.can_crawl:
		moves.append("ползает")
	if lp.can_swim:
		moves.append("плавает")
	var diet := str(PhysiologyNotes.DIET_LABELS.get(p.diet, str(p.diet)))
	var resp := str(PhysiologyNotes.RESP_LABELS.get(p.respiration, str(p.respiration)))
	return "%s: %s, %s; %s; дыхание — %s; оптимум %.0f °C; созревает за %.1f сут." % [
		str(NICHES[niche]["label"]), AnatomyDiagnostics.format_mass(p.mass), diet, ", ".join(moves), resp,
		p.thermal_optimum, p.maturity_age / Units.SECONDS_PER_DAY]
