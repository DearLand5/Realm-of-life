class_name Reproduction
extends RefCounted
## Mating, conception and birth for every reproductive mode/method:
##   modes:   sexual (female × male), hermaphrodite (any two mature
##            conspecifics, selfing allowed at low fertility), asexual
##            (no partner: clones + mutations);
##   methods: eggs (gravid → laid eggs → incubation → hatch), live
##            (gestation → juveniles), fission (parent splits in two),
##            budding (small buds), spores (many dormant propagules).
## Offspring genomes come from Genetics.sexual/asexual with the world's
## mutation settings; the parent pays tissue + starting reserve of every
## offspring (LifeHistory.offspring_cost) during gestation/egg formation.

const READY_ENERGY := 0.45           # energy fraction needed to start breeding
const READY_HEALTH := 0.5
const ABORT_ENERGY := 0.06           # embryos are resorbed below this reserve
const MAX_MATE_DISTANCE := 0.25      # genetic distance beyond which mating fails
const SELFING_FERTILITY := 0.3
const OFFSPRING_START_ENERGY := 0.5  # fraction of the newborn's max reserve
const MATURE_GROWTH := 0.75          # minimum linear size to breed


## 0..1: how favourable the season is for a species. breeding_season 0 =
## year-round, 1 = only in spring/early summer.
static func season_factor(p: PhysiologyProfile, climate: ClimateState) -> float:
	if climate == null or p.breeding_season <= 0.01:
		return 1.0
	# Smooth window peaking in mid-spring (phase 0.12), closed in winter.
	var w := clampf(0.5 + 0.9 * cos((climate.year_phase - 0.12) * TAU), 0.0, 1.0)
	return lerpf(1.0, w, p.breeding_season)


static func is_mature(ind: Individual) -> bool:
	return ind.alive and ind.is_mature() and ind.growth >= MATURE_GROWTH


static func is_ready(ind: Individual, climate: ClimateState = null) -> bool:
	if not is_mature(ind) or ind.pregnant or ind.repro_cooldown > 0.0:
		return false
	if ind.energy_fraction() < READY_ENERGY or ind.health < READY_HEALTH:
		return false
	return season_factor(ind.physiology(), climate) >= 0.5


## {ok: bool, reason: String} — why two individuals can or cannot mate.
static func mate_check(a: Individual, b: Individual, climate: ClimateState = null) -> Dictionary:
	if a == null or b == null or a == b or not a.alive or not b.alive:
		return {"ok": false, "reason": "Нет партнёра"}
	if a.species_id != b.species_id:
		return {"ok": false, "reason": "Разные виды"}
	var pa := a.physiology()
	if pa.repro_mode == &"asexual":
		return {"ok": false, "reason": "Бесполое размножение"}
	if not is_ready(a, climate) or not is_ready(b, climate):
		return {"ok": false, "reason": "Партнёр не готов (возраст, запас энергии, сезон или восстановление)"}
	if pa.repro_mode == &"sexual":
		if not ((a.sex == Individual.Sex.FEMALE and b.sex == Individual.Sex.MALE) or (a.sex == Individual.Sex.MALE and b.sex == Individual.Sex.FEMALE)):
			return {"ok": false, "reason": "Нужны особи разного пола"}
	var dist := Genetics.distance(a.genome, b.genome)
	if dist > MAX_MATE_DISTANCE:
		return {"ok": false, "reason": "Слишком большие генетические различия (%.2f)" % dist}
	# Mate choice: choosy individuals reject partners in poor condition or too different.
	for pair in [[a, b], [b, a]]:
		var chooser: Individual = pair[0]
		var other: Individual = pair[1]
		var sel := chooser.genome.value(&"mate_selectivity")
		var quality := other.health * (0.5 + 0.5 * other.energy_fraction()) * (1.0 - dist * 2.0) * other.growth
		if quality < sel * 0.7:
			return {"ok": false, "reason": "Партнёр отвергнут (избирательность)"}
	return {"ok": true, "reason": ""}


static func can_mate(a: Individual, b: Individual, climate: ClimateState = null) -> bool:
	return bool(mate_check(a, b, climate)["ok"])


## Number of offspring for the next breeding event (condition-dependent).
static func clutch_count(ind: Individual, rng: Rng) -> int:
	var p := ind.physiology()
	var n := p.clutch * (0.5 + 0.5 * ind.energy_fraction())
	var base := int(floor(n))
	if rng.chance(n - float(base)):
		base += 1
	return maxi(1, base)


## Sexual conception (also hermaphrodite pairs and selfing when a == b).
## Returns true when embryos were conceived. `mother` becomes pregnant.
static func conceive(mother: Individual, father: Individual, rng: Rng, settings: Dictionary = {},
		climate: ClimateState = null) -> bool:
	var selfing := mother == father
	if not selfing:
		if not can_mate(mother, father, climate):
			return false
		if mother.sex == Individual.Sex.MALE:
			var t := mother
			mother = father
			father = t
	elif not (is_ready(mother, climate) and mother.physiology().repro_mode == &"hermaphrodite"):
		return false
	var pm := mother.physiology()
	var fert := pm.fertility * sqrt(father.genome.value(&"fertility")) * mother.health
	if selfing:
		fert *= SELFING_FERTILITY
	if not rng.chance(clampf(fert, 0.0, 1.0)):
		father.repro_cooldown = maxf(father.repro_cooldown, pm.repro_cooldown_s * 0.1)
		return false
	var n := clutch_count(mother, rng)
	mother.embryos.clear()
	for i in n:
		mother.embryos.append(Genetics.sexual(mother.genome, father.genome, rng, settings))
	mother.embryo_father = father.id
	_start_pregnancy(mother)
	if not selfing:
		father.repro_cooldown = maxf(father.repro_cooldown, pm.repro_cooldown_s * 0.25)
	return true


## Asexual reproduction (fission, budding, spores, parthenogenetic eggs).
static func start_asexual(parent: Individual, rng: Rng, settings: Dictionary = {}, climate: ClimateState = null) -> bool:
	if not is_ready(parent, climate):
		return false
	var p := parent.physiology()
	if not rng.chance(p.fertility):
		parent.repro_cooldown = p.repro_cooldown_s * 0.2
		return false
	var n := 1 if p.repro_method == &"fission" else clutch_count(parent, rng)
	parent.embryos.clear()
	for i in n:
		parent.embryos.append(Genetics.asexual(parent.genome, rng, settings))
	parent.embryo_father = -1
	_start_pregnancy(parent)
	return true


static func _start_pregnancy(mother: Individual) -> void:
	var p := mother.physiology()
	var dur := p.gestation_s
	if p.repro_method in [&"eggs", &"spores"]:
		dur = p.egg_formation_s
	dur = maxf(dur, 600.0)
	mother.pregnant = true
	mother.gestation_left = dur
	var cost := LifeHistory.offspring_cost(p) * float(mother.embryos.size())
	if p.repro_method == &"fission":
		cost = p.max_energy * 0.1  # the split itself; tissue is shared, not built
	mother.repro_cost_rate = cost / dur


## Resorbs embryos when the mother starves.
static func abort(mother: Individual) -> void:
	mother.pregnant = false
	mother.embryos.clear()
	mother.gestation_left = 0.0
	mother.repro_cost_rate = 0.0
	mother.repro_cooldown = mother.physiology().repro_cooldown_s * 0.5


## Ends pregnancy: returns the new Individuals (eggs or juveniles).
static func offspring(mother: Individual, rng: Rng) -> Array[Individual]:
	var out: Array[Individual] = []
	var p := mother.physiology()
	var as_eggs := p.repro_method in [&"eggs", &"spores"]
	for g in mother.embryos:
		var child := Individual.new(g)
		child.species_id = mother.species_id
		child.generation = g.generation
		child.mother_id = mother.id
		child.father_id = mother.embryo_father
		child.seed = rng.range_i(1, 1 << 30)
		child.sex = _sex_from_mode(p.repro_mode, rng)
		# Size at birth from the mother's investment (child shares her adult size class).
		child.growth = p.birth_growth
		if p.repro_method == &"fission":
			child.growth = mother.growth * 0.7937  # half the mass
		child.energy = p.max_energy * pow(child.growth, 3.0) * OFFSPRING_START_ENERGY
		child.hydration = 1.0
		child.body_temp = mother.body_temp
		child.larval = p.metamorphosis
		child.position = mother.position + Vector3(rng.range_f(-0.5, 0.5), 0.0, rng.range_f(-0.5, 0.5)) * maxf(0.2, pow(p.mass, 1.0 / 3.0) * 0.3)
		child.heading = rng.range_f(-PI, PI)
		if as_eggs:
			child.stage = &"egg"
			child.incubation_left = p.incubation_s
			child.dormant = p.repro_method == &"spores"
		else:
			child.stage = &"juvenile"
		out.append(child)
	if p.repro_method == &"fission":
		mother.growth *= 0.7937
		mother.energy *= 0.5
	mother.offspring_count += out.size()
	mother.pregnant = false
	mother.embryos.clear()
	mother.gestation_left = 0.0
	mother.repro_cost_rate = 0.0
	mother.repro_cooldown = p.repro_cooldown_s
	return out


static func _sex_from_mode(mode: StringName, rng: Rng) -> int:
	match mode:
		&"hermaphrodite":
			return Individual.Sex.HERMAPHRODITE
		&"asexual":
			return Individual.Sex.ASEXUAL
	return Individual.Sex.FEMALE if rng.chance(0.5) else Individual.Sex.MALE
