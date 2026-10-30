class_name Individual
extends RefCounted
## State of one organism (tiers A/B; eggs too). Pure data: BiologySystem
## integrates it, Reproduction creates offspring, PopulationManager folds
## individuals into pools and unfolds them back.
## Units: energy J, masses kg, temperatures °C, times biological seconds.
## `phenotype` is not saved — rebuilt lazily from the genome.

enum Sex { FEMALE = 0, MALE = 1, HERMAPHRODITE = 2, ASEXUAL = 3 }

static var _next_id: int = 1

var id: int = 0
var species_id: int = -1
var genome: Genome
var sex: int = Sex.FEMALE
var generation: int = 0
var mother_id: int = -1
var father_id: int = -1
var seed: int = 0                    # per-individual visual/behaviour seed

# --- Life cycle -----------------------------------------------------------------
var age: float = 0.0                 # s since birth / hatching (eggs: since laying)
var stage: StringName = &"adult"     # egg | juvenile | adolescent | adult | elder
var growth: float = 1.0              # linear size fraction of the adult (mass ∝ growth³)
var larval := false                  # metamorphosing species before metamorphosis
var dormant := false                 # spores waiting for good conditions
var incubation_left: float = 0.0     # eggs/spores
var molt_timer: float = 0.0
var molt_pending: float = 0.0        # growth accumulated until the next moult
var soft_shell: float = 0.0          # s of vulnerability after a moult

# --- Physiological state ------------------------------------------------------------
var energy: float = 0.0              # J of reserve
var stomach_kg := PackedFloat32Array()   # wet kg per Food kind
var stomach_j := PackedFloat32Array()    # assimilable J still in the gut per Food kind
var hydration: float = 1.0           # fraction of normal body water
var body_temp: float = 20.0
var fatigue: float = 0.0             # 0 fresh .. 1 exhausted
var health: float = 1.0              # 0 dead .. 1 intact
var disease: float = 0.0             # infection load 0..1
var immunity: float = 0.0            # acquired immunity 0..1
var oxygen: float = 1.0              # O2 store fraction
var toxin: float = 0.0               # toxin load (fraction of body mass equivalent)
var performance: float = 1.0         # last thermal performance (ectotherm speed factor)
var heat_stress: float = 0.0
var cold_stress: float = 0.0

# --- Reproduction ---------------------------------------------------------------------
var repro_cooldown: float = 0.0
var pregnant := false                # carrying embryos / forming eggs / preparing division
var gestation_left: float = 0.0
var repro_cost_rate: float = 0.0     # W paid while pregnant
var embryos: Array[Genome] = []
var embryo_father: int = -1
var ready_to_mate := false           # last evaluated readiness (edge-triggered event)
var offspring_count: int = 0

# --- Placement / status -----------------------------------------------------------
var position := Vector3.ZERO
var heading: float = 0.0             # yaw, rad
var alive := true
var cause: StringName = &""          # death cause
var last_damage: StringName = &""
var tags: Dictionary = {}            # free-form, saved (AI/world annotations)

var _phenotype: Phenotype


func _init(g: Genome = null) -> void:
	genome = g
	stomach_kg.resize(Food.COUNT)
	stomach_j.resize(Food.COUNT)
	id = _next_id
	_next_id += 1


static func id_counter() -> int:
	return _next_id


static func ensure_id_counter(min_next: int) -> void:
	_next_id = maxi(_next_id, min_next)


## Founder/test helper: an individual at a stage with a full reserve.
static func create(g: Genome, species: int, at_stage: StringName = &"adult", rng: Rng = null) -> Individual:
	var ind := Individual.new(g)
	ind.species_id = species
	ind.generation = g.generation
	ind.seed = rng.range_i(1, 1 << 30) if rng != null else ind.id * 7919
	var p := ind.physiology()
	ind.sex = Individual.sex_for(p, rng)
	ind.set_stage_age(at_stage)
	ind.body_temp = p.body_temp_set
	ind.energy = ind.max_energy() * 0.8
	return ind


static func sex_for(p: PhysiologyProfile, rng: Rng) -> int:
	match p.repro_mode:
		&"hermaphrodite":
			return Sex.HERMAPHRODITE
		&"asexual":
			return Sex.ASEXUAL
	if rng == null:
		return Sex.FEMALE
	return Sex.FEMALE if rng.chance(0.5) else Sex.MALE


## Places the individual at a typical age/size of a stage.
func set_stage_age(at_stage: StringName) -> void:
	var p := physiology()
	stage = at_stage
	match at_stage:
		&"egg":
			age = 0.0
			growth = p.birth_growth
			incubation_left = p.incubation_s
		&"juvenile":
			age = p.juvenile_s * 0.3
		&"adolescent":
			age = (p.juvenile_s + p.maturity_age) * 0.5
		&"elder":
			age = p.elder_age * 1.05
		_:
			age = lerpf(p.maturity_age, p.elder_age, 0.3)
	if at_stage != &"egg":
		growth = LifeHistory.expected_growth(p, age)
		if at_stage == &"adult" or at_stage == &"elder":
			growth = maxf(growth, 0.97)
	larval = p.metamorphosis and at_stage in [&"egg", &"juvenile"]


func get_phenotype() -> Phenotype:
	if _phenotype == null and genome != null:
		_phenotype = Phenotype.build(genome)
	return _phenotype


## Shares an already-built phenotype of the SAME genome (pool samples).
func set_phenotype(ph: Phenotype) -> void:
	_phenotype = ph


func physiology() -> PhysiologyProfile:
	return get_phenotype().physiology


func mass_factor() -> float:
	return growth * growth * growth


func mass() -> float:
	return physiology().mass * mass_factor()


func max_energy() -> float:
	return physiology().max_energy * mass_factor()


func energy_fraction() -> float:
	return clampf(energy / maxf(max_energy(), 1e-9), 0.0, 1.0)


func stomach_total() -> float:
	var t := 0.0
	for v in stomach_kg:
		t += v
	return t


func stomach_fullness() -> float:
	return clampf(stomach_total() / maxf(physiology().gut_capacity_kg * mass_factor(), 1e-9), 0.0, 1.0)


func is_egg() -> bool:
	return stage == &"egg"


func is_mature() -> bool:
	return stage == &"adult" or stage == &"elder"


func to_dict() -> Dictionary:
	var emb := []
	for e in embryos:
		emb.append(e.to_dict())
	return {
		"id": id, "species_id": species_id, "genome": genome.to_dict() if genome != null else {}, "sex": sex,
		"generation": generation, "mother_id": mother_id, "father_id": father_id, "seed": seed,
		"age": age, "stage": str(stage), "growth": growth, "larval": larval, "dormant": dormant,
		"incubation_left": incubation_left, "molt_timer": molt_timer, "molt_pending": molt_pending, "soft_shell": soft_shell,
		"energy": energy, "stomach_kg": Array(stomach_kg), "stomach_j": Array(stomach_j), "hydration": hydration,
		"body_temp": body_temp, "fatigue": fatigue, "health": health, "disease": disease, "immunity": immunity,
		"oxygen": oxygen, "toxin": toxin, "repro_cooldown": repro_cooldown, "pregnant": pregnant,
		"gestation_left": gestation_left, "repro_cost_rate": repro_cost_rate, "embryos": emb,
		"embryo_father": embryo_father, "ready_to_mate": ready_to_mate, "offspring_count": offspring_count,
		"position": Serial.v3(position), "heading": heading, "alive": alive, "cause": str(cause),
		"tags": tags.duplicate(true),
	}


static func from_dict(d: Dictionary) -> Individual:
	var gd := Serial.dict(d, "genome")
	var ind := Individual.new(Genome.from_dict(gd) if not gd.is_empty() else Genome.new())
	ind.id = Serial.i(d, "id", ind.id)
	ensure_id_counter(ind.id + 1)
	ind.species_id = Serial.i(d, "species_id", -1)
	ind.sex = Serial.i(d, "sex", Sex.FEMALE)
	ind.generation = Serial.i(d, "generation", 0)
	ind.mother_id = Serial.i(d, "mother_id", -1)
	ind.father_id = Serial.i(d, "father_id", -1)
	ind.seed = Serial.i(d, "seed", ind.id * 7919)
	ind.age = Serial.f(d, "age", 0.0)
	ind.stage = Serial.sn(d, "stage", &"adult")
	ind.growth = clampf(Serial.f(d, "growth", 1.0), 0.01, 1.0)
	ind.larval = Serial.b(d, "larval", false)
	ind.dormant = Serial.b(d, "dormant", false)
	ind.incubation_left = Serial.f(d, "incubation_left", 0.0)
	ind.molt_timer = Serial.f(d, "molt_timer", 0.0)
	ind.molt_pending = Serial.f(d, "molt_pending", 0.0)
	ind.soft_shell = Serial.f(d, "soft_shell", 0.0)
	ind.energy = Serial.f(d, "energy", 0.0)
	_read_floats(Serial.arr(d, "stomach_kg"), ind.stomach_kg)
	_read_floats(Serial.arr(d, "stomach_j"), ind.stomach_j)
	ind.hydration = Serial.f(d, "hydration", 1.0)
	ind.body_temp = Serial.f(d, "body_temp", 20.0)
	ind.fatigue = Serial.f(d, "fatigue", 0.0)
	ind.health = Serial.f(d, "health", 1.0)
	ind.disease = Serial.f(d, "disease", 0.0)
	ind.immunity = Serial.f(d, "immunity", 0.0)
	ind.oxygen = Serial.f(d, "oxygen", 1.0)
	ind.toxin = Serial.f(d, "toxin", 0.0)
	ind.repro_cooldown = Serial.f(d, "repro_cooldown", 0.0)
	ind.pregnant = Serial.b(d, "pregnant", false)
	ind.gestation_left = Serial.f(d, "gestation_left", 0.0)
	ind.repro_cost_rate = Serial.f(d, "repro_cost_rate", 0.0)
	for ed in Serial.arr(d, "embryos"):
		if ed is Dictionary:
			ind.embryos.append(Genome.from_dict(ed))
	ind.embryo_father = Serial.i(d, "embryo_father", -1)
	ind.ready_to_mate = Serial.b(d, "ready_to_mate", false)
	ind.offspring_count = Serial.i(d, "offspring_count", 0)
	ind.position = Serial.to_v3(d.get("position"))
	ind.heading = Serial.f(d, "heading", 0.0)
	ind.alive = Serial.b(d, "alive", true)
	ind.cause = Serial.sn(d, "cause", &"")
	ind.tags = Serial.dict(d, "tags").duplicate(true)
	return ind


static func _read_floats(src: Array, dst: PackedFloat32Array) -> void:
	for i in mini(src.size(), dst.size()):
		var v = src[i]
		dst[i] = float(v) if (v is float or v is int) else 0.0
