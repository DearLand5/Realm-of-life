class_name PoolSample
extends RefCounted
## One genotype class of a population pool: a genome with its phenotype,
## its share of the pool (`weight`) and its own condition (`energy`,
## fraction of the reserve). Constants that do not depend on the
## environment are cached once from the phenotype; environment-dependent
## rates are always computed with the PhysiologyProfile methods shared with
## individuals (BiologySystem), so both tiers follow identical physiology.

var genome: Genome
var phenotype: Phenotype
var pp: PhysiologyProfile
var weight: float = 1.0
var energy: float = 0.7
var fecundity: float = 0.0          # last conceptions per capita per s (parent choice)
var fitness: float = 0.0            # last per-capita growth rate (diagnostic)
# Last-step breakdown (W per capita, mortality per s) — diagnostics / UI.
var last_income: float = 0.0
var last_demand: float = 0.0
var mu_starve: float = 0.0
var mu_thermal: float = 0.0
var mu_habitat: float = 0.0
var mu_water: float = 0.0
var mu_disease: float = 0.0
var mu_predation: float = 0.0

# --- Cached constants (adult values) ------------------------------------------------
var mass: float = 1.0
var max_energy: float = 1.0
var land_ok: float = 0.0            # locomotion + breathing ability on land 0..1
var water_ok: float = 0.0           # in water (gills/skin or lung swimmer)
var lung_swimmer := false
var speed: float = 0.5              # typical cruising speed in its habitat (m/s)
var flyer := false
var search_rate: float = 0.1        # m²/s scanned while foraging
var food_w := PackedFloat32Array()  # preference weight per Food kind
var intake := PackedFloat32Array()  # sustainable intake limit per Food kind (kg/s)
var eff := PackedFloat32Array()     # assimilation efficiency per Food kind
var plant_prefs := PackedFloat32Array()
var mouth_rate: float = 1e-4        # handling-limited intake while feeding (kg/s)
var gut_kg: float = 0.1             # gut capacity (kg)
var retention := PackedFloat32Array()  # gut retention per Food kind (s)
var burrower := false               # lives in moist soil (humid microhabitat)
var attack: float = 0.0
var defense: float = 0.0
var detection: float = 10.0
var vigilance: float = 0.5
var sociality: float = 0.5
var mf_juv: float = 0.2             # mass factors of the juvenile / adolescent classes
var mf_ado: float = 0.6
var growth_power: float = 0.0       # W per growing individual at full speed
var breed_rate: float = 0.0         # offspring conceived per breeding individual per s
var offspring_cost: float = 0.0     # J per conceived offspring
var recruit_survival: float = 0.5   # survival from conception to juvenile
var female_share: float = 0.5       # share of adults that give birth
var needs_mate := true
var elder_hazard: float = 0.0
var juv_mortality: float = 0.0
var meat_eater := false

# Thermal cache per medium (temperature changes slowly).
var th_land := ThermalModel.Result.new()
var th_water := ThermalModel.Result.new()
var _t_land: float = 1.0e9
var _t_water: float = 1.0e9

const JUV_MORTALITY := 0.03 / Units.SECONDS_PER_DAY


static func create(g: Genome, ph: Phenotype, plants: Array[PlantSpecies]) -> PoolSample:
	var s := PoolSample.new()
	s.genome = g
	s.phenotype = ph if ph != null else Phenotype.build(g)
	s._cache(plants)
	return s


## Shares genome/phenotype/constants; independent weight and condition.
func clone() -> PoolSample:
	var s := PoolSample.new()
	s.genome = genome
	s.phenotype = phenotype
	s.pp = pp
	s.weight = weight
	s.energy = energy
	for prop in ["mass", "max_energy", "land_ok", "water_ok", "lung_swimmer", "speed", "flyer", "search_rate",
			"attack", "defense", "detection", "vigilance", "sociality", "mf_juv", "mf_ado", "growth_power",
			"breed_rate", "offspring_cost", "recruit_survival", "female_share", "needs_mate", "elder_hazard",
			"juv_mortality", "meat_eater"]:
		s.set(prop, get(prop))
	s.food_w = food_w
	s.intake = intake
	s.eff = eff
	s.plant_prefs = plant_prefs
	s.mouth_rate = mouth_rate
	s.gut_kg = gut_kg
	s.retention = retention
	s.burrower = burrower
	return s


func _cache(plants: Array[PlantSpecies]) -> void:
	pp = phenotype.physiology
	var lp := phenotype.locomotion
	var st := phenotype.anatomy.stats
	var g := genome
	mass = pp.mass
	max_energy = pp.max_energy
	var land_speed := lp.best_land_speed()
	flyer = lp.can_fly
	lung_swimmer = pp.lungs_w > 0.0 and lp.can_swim
	land_ok = clampf((pp.scope_land - 0.8) / 1.2, 0.0, 1.0) * clampf((land_speed + (2.0 if flyer else 0.0)) / 0.3, 0.0, 1.0)
	var aquatic_breath := clampf((pp.scope_water - 0.8) / 1.2, 0.0, 1.0)
	var water_move := clampf((lp.swim_speed if lp.can_swim else lp.crawl_speed * 0.5) / 0.3, 0.0, 1.0)
	water_ok = maxf(aquatic_breath, 0.6 if lung_swimmer else 0.0) * water_move
	if pp.habitat == &"water":
		land_ok *= 0.3  # aquatic species avoid leaving the water
	speed = maxf(maxf(land_speed if land_ok >= water_ok else lp.swim_speed, lp.fly_speed * 0.5), 0.05)
	var width := maxf(0.3, float(st.get("length", 0.5)) * 0.5)
	search_rate = speed * 0.3 * width
	food_w = PackedFloat32Array()
	DietModel.food_weights(pp, food_w)
	intake = PackedFloat32Array()
	eff = PackedFloat32Array()
	retention = PackedFloat32Array()
	intake.resize(Food.COUNT)
	eff.resize(Food.COUNT)
	retention.resize(Food.COUNT)
	for k in Food.COUNT:
		intake[k] = pp.intake_limit(k)
		eff[k] = pp.food_efficiency(k)
		retention[k] = pp.retention_time(k)
	mouth_rate = pp.max_intake_kg_s
	gut_kg = pp.gut_capacity_kg
	burrower = lp.can_burrow
	meat_eater = food_w[Food.MEAT] > 0.15 and pp.weapon_score > 0.3
	_plant_prefs(plants, st, lp)
	# Combat: weapons (already size-scaled) and bulk.
	var w: Dictionary = st.get("weapons", {})
	sociality = g.value(&"sociality")
	vigilance = g.value(&"vigilance")
	attack = (float(w.get("bite", 0.0)) + float(w.get("claw", 0.0)) + 0.3 * float(w.get("spike", 0.0)) + 0.3 * float(w.get("horn", 0.0)) + 8.0 * float(w.get("venom", 0.0))) \
		* (0.6 + 0.4 * g.value(&"aggression") + 0.5 * g.value(&"muscle_mass") - 0.5)
	defense = 12.0 * pp.armor + 0.6 * (float(w.get("horn", 0.0)) + float(w.get("spike", 0.0))) + 0.3 * float(w.get("claw", 0.0)) + 1.5 * pow(mass, 1.0 / 3.0)
	detection = clampf(phenotype.senses.max_range(), 2.0, 60.0)
	# Life history.
	var gj := LifeHistory.expected_growth(pp, pp.juvenile_s * 0.5)
	var ga := LifeHistory.expected_growth(pp, (pp.juvenile_s + pp.maturity_age) * 0.5)
	mf_juv = gj * gj * gj
	mf_ado = ga * ga * ga
	growth_power = mass * (1.0 - pp.offspring_fraction) * Food.BUILD_COST / maxf(pp.maturity_age, 1.0)
	var interval := (pp.gestation_s if pp.repro_method != &"eggs" and pp.repro_method != &"spores" else pp.egg_formation_s) + pp.repro_cooldown_s
	breed_rate = pp.clutch * pp.fertility / maxf(interval, 600.0)
	offspring_cost = LifeHistory.offspring_cost(pp)
	var care := g.value(&"parental_care")
	var egg_risk := exp(-pp.incubation_s / Units.SECONDS_PER_DAY * 0.15)
	recruit_survival = clampf(0.3 + 0.5 * care + 1.5 * pp.offspring_fraction, 0.15, 0.95) * egg_risk
	needs_mate = pp.repro_mode != &"asexual"
	female_share = 0.5 if pp.repro_mode == &"sexual" else 1.0
	elder_hazard = LifeHistory.elder_hazard(pp)
	juv_mortality = JUV_MORTALITY * (1.0 - 0.5 * care)


func _plant_prefs(plants: Array[PlantSpecies], st: Dictionary, lp: LocomotionProfile) -> void:
	plant_prefs = PackedFloat32Array()
	plant_prefs.resize(plants.size())
	var reach := float(st.get("height", 0.3)) * 1.3
	if lp.can_fly or lp.can_climb:
		reach = maxf(reach, 20.0)
	var grind := 0.6
	match pp.teeth:
		&"grinding":
			grind = 1.0
		&"mixed":
			grind = 0.75
		&"cutting":
			grind = 0.4
		&"fangs":
			grind = 0.3
	if pp.mouth_type == &"beak" or pp.mouth_type == &"mandibles":
		grind = maxf(grind, 0.7)
	var tox_tol := 0.5 * float(pp.diet_eff["plant"])
	for i in plants.size():
		var pl := plants[i]
		var access := clampf(reach / maxf(pl.height, 0.05), 0.15, 1.0)
		if pl.aquatic and water_ok < 0.2:
			access = 0.0
		elif not pl.aquatic and land_ok < 0.05:
			access = 0.0
		var digest := 1.0 - pl.toughness * (1.0 - grind)
		plant_prefs[i] = access * digest * (1.0 - pl.toxicity * (1.0 - tox_tol))


## Habitat suitability in a sector with given land/water fractions.
func habitat(land_frac: float, water_frac: float) -> float:
	return clampf(land_frac * land_ok + water_frac * water_ok, 0.0, 1.0)


## Thermal balance in a medium (cached while the temperature changes < 0.5 °C).
func thermal(t_env: float, in_water: bool, light: float) -> ThermalModel.Result:
	if in_water:
		if absf(t_env - _t_water) > 0.5:
			_t_water = t_env
			ThermalModel.steady(pp, t_env, true, light, 0.5, pp.maintenance_rate(pp.body_temp_set) * 1.6, 1.0, th_water)
		return th_water
	if absf(t_env - _t_land) > 0.5:
		_t_land = t_env
		ThermalModel.steady(pp, t_env, false, light, 1.5, pp.maintenance_rate(pp.body_temp_set) * 1.6, 1.0, th_land)
	return th_land


func to_dict(genome_index: int) -> Dictionary:
	return {"g": genome_index, "w": weight, "e": energy}
