class_name PhysiologyProfile
extends RefCounted
## Physiological capabilities of a phenotype (rates in REAL units, time in
## BIOLOGICAL seconds — see Units). Everything is derived from anatomy
## (AnatomyModel.stats, organs, coverings) and the genome's physiology traits:
##   metabolism   BMR = Kleiber · M^0.75 · metabolism · [e + (1−e)·ecto·Q10^((Tb−20)/10)]
##   thermal      ThermalModel (insulation, fat, area → conductance, thermogenesis, cooling)
##   respiration  RespirationModel (lungs/gills/trachea/skin capacities vs demand)
##   diet         DietModel (mouth, teeth, gut organs → efficiencies, intake, capacity)
##   water        skin evaporation, respiratory/urinary loss, metabolic water
##   life history LifeHistory (stages, gestation/incubation, clutch, growth, Gompertz)
## Individuals (BiologySystem) and population pools (PopulationManager) use
## the SAME rate methods below, so both tiers obey identical physiology.
##
## CONTRACT (stable API used by other systems):
##   static build(ph: Phenotype) -> PhysiologyProfile
##   bmr_watts, max_energy, respiration, habitat_ok, diet_eff, lifespan,
##   maturity_age, endothermy, diagnose() -> Array[Dictionary]{level, system, text}

const Q10 := 2.5
const REF_TEMP := 20.0
const ACTIVITY_COEF := 3.0           # activity 1 → 4× basal power
const IMMUNE_COST := 0.12            # fraction of BMR at immune trait 1
const REGEN_COST := 0.05             # fraction of BMR at regeneration trait 1
const BRAIN_COST := 0.15             # fraction of BMR for brain index 1
const K_EVAP := 2.3e-4               # kg/(m²·s) skin evaporation at RH 0, 20 °C, no retention
const RESP_WATER := 3.0e-8           # kg water exhaled per J metabolised (dry air)
const METABOLIC_WATER := 2.5e-8      # kg water produced per J metabolised
const URINE_PER_J := 1.5e-8          # kg/J of BMR (kidney baseline)
const SKIN_ABSORB := 2.0e-4          # kg/(m²·s) water uptake through mucous skin
const BODY_WATER_FRACTION := 0.65

# --- Contract fields ---------------------------------------------------------------
var bmr_watts: float = 1.0            # basal metabolic rate (W) at the preferred body temperature
var max_energy: float = 1.0e5         # J of mobilizable reserve (adult)
var respiration: StringName = &"cutaneous"   # lungs | gills | trachea | cutaneous | mixed | none
var habitat_ok := {"land": true, "water": false}
var diet_eff := {"plant": 0.5, "meat": 0.3, "carrion": 0.1, "detritus": 0.1, "filter": 0.0, "photo": 0.0}
var lifespan: float = 20.0 * Units.SECONDS_PER_DAY
var maturity_age: float = 4.0 * Units.SECONDS_PER_DAY
var endothermy: float = 0.5
var notes: Array[Dictionary] = []

# --- Body / metabolism ------------------------------------------------------------
var mass: float = 1.0                 # adult kg
var metabolism: float = 1.0
var bmr_endo_w: float = 0.0           # temperature-independent (endothermic) part
var bmr_ecto20_w: float = 0.0         # ectothermic part at 20 °C body temperature
var upkeep_frac: float = 0.0          # immune + regeneration + brain upkeep (× BMR)
var immune: float = 0.5
var regeneration: float = 0.3
var weapon_score: float = 0.0
var armor: float = 0.0
var free_energy_w: float = 0.0
var photo_w: float = 0.0              # W at light 1 (adult)
var fantasy := false

# --- Thermal ----------------------------------------------------------------------
var thermal_area: float = 0.1
var projected_area: float = 0.03
var insulation: float = 0.1
var fat_fraction: float = 0.07
var conductance_air: float = 1.0      # W/K (adult)
var conductance_water: float = 10.0
var heat_capacity: float = 3500.0     # J/K
var thermal_optimum: float = 20.0
var thermal_tolerance: float = 10.0
var body_temp_set: float = 20.0
var absorptivity: float = 0.6
var max_thermogenesis_w: float = 0.0
var evap_cooling_w: float = 0.0

# --- Respiration ------------------------------------------------------------------
var ignore_oxygen := false
var lung_volume: float = 0.0
var gill_area: float = 0.0
var body_radius: float = 0.05
var trachea_efficiency: float = 0.0
var lungs_w: float = 0.0
var gills_w: float = 0.0
var trachea_w: float = 0.0
var skin_air_w: float = 0.0
var skin_water_w: float = 0.0
var moist_skin_fraction: float = 0.0
var o2_store_j: float = 0.0
var anaerobic_j: float = 0.0          # anaerobic capacity before exhaustion
var scope_land: float = 0.0           # O2 capacity / BMR in air
var scope_water: float = 0.0          # O2 capacity / BMR submerged

# --- Water ------------------------------------------------------------------------
var body_water_kg: float = 0.65
var skin_evap: float = 0.0            # kg/s at RH 0, 20 °C
var urine_kg_s: float = 0.0
var skin_absorb_kg_s: float = 0.0
var water_retention: float = 0.5      # physiological trait
var needs_moisture := false
var aquatic := false                  # declared water habitat (osmoregulates in water)

# --- Diet -------------------------------------------------------------------------
var diet: StringName = &"herbivore"           # derived
var declared_diet: StringName = &"herbivore"  # from the body plan
var diet_preference: float = 0.1
var mouth_type: StringName = &"none"
var teeth: StringName = &"none"
var gut_capacity_kg: float = 0.05
var gut_retention_factor: float = 1.0
var max_intake_kg_s: float = 1e-4
var max_assimilation_w: float = 1.0   # best sustainable energy intake (W, adult)
var production_w: float = 1.0         # sustainable power for growth/breeding: min(assimilation, spare O2)

# --- Life history -----------------------------------------------------------------
var juvenile_s: float = 1.0
var elder_age: float = 1.0
var repro_mode: StringName = &"sexual"
var repro_method: StringName = &"eggs"
var metamorphosis := false
var molting := false
var fertility: float = 0.7
var breeding_season: float = 0.3
var clutch: float = 1.0
var offspring_fraction: float = 0.1
var birth_growth: float = 0.5
var gestation_s: float = 0.0
var incubation_s: float = 0.0
var egg_formation_s: float = 0.0
var repro_cooldown_s: float = 0.0
var growth_k: float = 1e-5
var molt_interval_s: float = 0.0
var habitat: StringName = &"land"
var can_swim := false
var surface_to_volume: float = 0.0


static func build(ph: Phenotype) -> PhysiologyProfile:
	var p := PhysiologyProfile.new()
	var g := ph.genome
	var st := ph.anatomy.stats
	var plan := g.body_plan
	p.mass = maxf(float(st.get("mass", 1.0)), 1e-4)
	p.endothermy = g.value(&"endothermy")
	p.metabolism = g.value(&"metabolism")
	p.immune = g.value(&"immune")
	p.regeneration = g.value(&"regeneration")
	p.fantasy = bool(plan.rule("fantasy"))
	p.habitat = StringName(str(plan.bio("habitat")))
	p.aquatic = p.habitat == &"water"
	var kleiber := Units.KLEIBER_COEF * pow(p.mass, 0.75) * p.metabolism
	p.bmr_endo_w = kleiber * p.endothermy
	p.bmr_ecto20_w = kleiber * (1.0 - p.endothermy) * Units.ECTOTHERM_FACTOR
	p.upkeep_frac = IMMUNE_COST * p.immune + REGEN_COST * p.regeneration + BRAIN_COST * float(st.get("brain", 0.3)) * 0.3
	var weapons: Dictionary = st.get("weapons", {})
	p.weapon_score = float(weapons.get("bite", 0.0)) + float(weapons.get("claw", 0.0)) + float(weapons.get("horn", 0.0)) \
		+ float(weapons.get("spike", 0.0)) + float(weapons.get("venom", 0.0)) * 5.0
	p.armor = float(st.get("armor", 0.0))
	# Thermal first (sets optimum used by BMR), then BMR at the preferred body temperature.
	p.bmr_watts = kleiber * lerpf(Units.ECTOTHERM_FACTOR, 1.0, p.endothermy)
	ThermalModel.build(p, ph)
	p.bmr_watts = p.basal_rate(p.body_temp_set)
	ThermalModel.build(p, ph)  # thermogenic capacity depends on the final BMR
	RespirationModel.build(p, ph)
	DietModel.build(p, ph)
	p.max_assimilation_w = 0.0
	for k in Food.COUNT:
		p.max_assimilation_w = maxf(p.max_assimilation_w, p.intake_limit(k) * float(Food.ENERGY[k]) * p.food_efficiency(k))
	p.max_assimilation_w = maxf(p.max_assimilation_w, p.autotrophic_power(0.5))
	var o2_best := maxf(RespirationModel.capacity(p, false, 1.0, true, 0.6), RespirationModel.capacity(p, true, 0.8, false, 1.0))
	p.production_w = maxf(minf(p.max_assimilation_w, o2_best - p.bmr_watts * (1.0 + p.upkeep_frac)), p.bmr_watts * 0.2)
	LifeHistory.build(p, ph)
	p.anaerobic_j = float(st.get("muscle_mass", p.mass * 0.3)) * 300.0
	_build_water(p, ph)
	var cap_air := RespirationModel.capacity(p, false, 1.0, true, 0.6)
	var cap_water := RespirationModel.capacity(p, true, 0.8, false, 1.0)
	p.scope_land = cap_air / maxf(p.bmr_watts, 1e-9)
	p.scope_water = cap_water / maxf(p.bmr_watts, 1e-9)
	var lung_swimmer := p.lungs_w > 0.0 and ph.locomotion.can_swim
	p.habitat_ok = {
		"land": p.scope_land >= 1.2 and (ph.locomotion.best_land_speed() > 0.01 or ph.locomotion.can_fly),
		"water": (p.scope_water >= 1.2 or lung_swimmer) and (ph.locomotion.can_swim or ph.locomotion.can_crawl),
	}
	p.can_swim = ph.locomotion.can_swim
	p.surface_to_volume = float(st.get("surface_to_volume", 0.0))
	return p


static func _build_water(p: PhysiologyProfile, ph: Phenotype) -> void:
	var st := ph.anatomy.stats
	var g := ph.genome
	var organs: Dictionary = st.get("organ_volume", {})
	p.water_retention = g.value(&"water_retention")
	p.body_water_kg = p.mass * BODY_WATER_FRACTION
	var cov_ret := clampf(float(st.get("water_retention", 0.5)), 0.0, 1.0)
	p.skin_evap = p.thermal_area * pow(1.0 - cov_ret, 2.0) * K_EVAP * (1.0 - 0.35 * p.water_retention)
	var kidney := 0.8 if organs.has("kidney") else 1.0
	p.urine_kg_s = p.bmr_watts * URINE_PER_J * (1.3 - p.water_retention) * kidney
	p.needs_moisture = bool(st.get("needs_moisture", false))
	p.skin_absorb_kg_s = p.thermal_area * SKIN_ABSORB * p.moist_skin_fraction


## Area (m², real) covered by each covering slot.
static func covering_areas(m: AnatomyModel) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(m.coverings.size())
	var s2 := m.size_scale * m.size_scale
	for b in m.bones:
		if b.part_id < 0 or out.is_empty():
			continue
		var ci := clampi(b.covering, 0, out.size() - 1)
		out[ci] += PI * (b.r0 + b.r1) * sqrt((b.r0 - b.r1) * (b.r0 - b.r1) + b.length * b.length) * (1.0 + b.flatten) * 0.5 * s2
	return out


# --- Shared rate functions (individuals AND pools) ------------------------------------

## Basal metabolic rate (W) at a body temperature and mass factor (current/adult mass).
func basal_rate(body_temp: float, mass_factor: float = 1.0) -> float:
	var q := pow(Q10, clampf(body_temp - REF_TEMP, -40.0, 30.0) / 10.0)
	return (bmr_endo_w + bmr_ecto20_w * q) * pow(maxf(mass_factor, 1e-4), 0.75)


## Maintenance (basal + immune/regeneration/brain upkeep).
func maintenance_rate(body_temp: float, mass_factor: float = 1.0) -> float:
	return basal_rate(body_temp, mass_factor) * (1.0 + upkeep_frac)


## Extra power of an activity level (0 rest .. 1 maximal sustained exertion).
func activity_power(activity: float, body_temp: float, mass_factor: float = 1.0) -> float:
	return maxf(activity, 0.0) * ACTIVITY_COEF * basal_rate(body_temp, mass_factor)


## O2-limited aerobic power in a medium (W).
func o2_capacity(in_water: bool, oxygen: float, air_access: bool, humidity: float, mass_factor: float = 1.0) -> float:
	return RespirationModel.capacity(self, in_water, oxygen, air_access, humidity, mass_factor)


## Breath-hold time (s) at a metabolic power.
func breath_hold_s(power_w: float, mass_factor: float = 1.0) -> float:
	return o2_store_j * mass_factor / maxf(power_w, 1e-9)


## Photosynthetic + free energy income (W).
func autotrophic_power(light: float, mass_factor: float = 1.0) -> float:
	return photo_w * clampf(light, 0.0, 1.0) * pow(maxf(mass_factor, 1e-4), 2.0 / 3.0) + free_energy_w * mass_factor


## Water lost (kg/s) excluding thermoregulatory evaporation.
func water_loss_rate(t_env: float, humidity: float, in_water: bool, metabolic_w: float, mass_factor: float = 1.0) -> float:
	var mf23 := pow(maxf(mass_factor, 1e-4), 2.0 / 3.0)
	var loss := urine_kg_s * pow(maxf(mass_factor, 1e-4), 0.75)
	if not in_water:
		var tf := clampf(pow(2.0, (t_env - 20.0) / 11.0), 0.1, 4.0)
		loss += skin_evap * mf23 * (1.0 - clampf(humidity, 0.0, 1.0)) * tf
		loss += RESP_WATER * metabolic_w * (1.0 - 0.7 * clampf(humidity, 0.0, 1.0))
	return loss - METABOLIC_WATER * metabolic_w


## Assimilation efficiency of a Food kind.
func food_efficiency(kind: int) -> float:
	return float(diet_eff.get(Food.EFF_KEYS[clampi(kind, 0, Food.COUNT - 1)], 0.0))


## Gut retention time (s) of a food kind (allometric ∝ M^0.25; long
## fermenting guts keep plant matter longer).
func retention_time(kind: int, mass_factor: float = 1.0) -> float:
	var base := float(Food.RETENTION[clampi(kind, 0, Food.COUNT - 1)]) * pow(maxf(mass * mass_factor, 1e-4) / 10.0, 0.25)
	return base * (gut_retention_factor if kind == Food.PLANT or kind == Food.DETRITUS else 1.0)


## Sustainable wet intake (kg/s) of a food kind: the smaller of the
## handling limit (mouth) and the digestive throughput (gut capacity / retention).
func intake_limit(kind: int, mass_factor: float = 1.0) -> float:
	var mf := maxf(mass_factor, 1e-4)
	var throughput := gut_capacity_kg * mf / maxf(retention_time(kind, mf), 1.0)
	return minf(max_intake_kg_s * pow(mf, 0.75), throughput)


func stage_for_age(age: float) -> StringName:
	return LifeHistory.stage_for_age(self, age)


func is_aquatic_breather() -> bool:
	return scope_water >= 1.2


## Explanatory notes (built lazily — they are only needed by the editor/UI).
func diagnose() -> Array[Dictionary]:
	if notes.is_empty():
		notes = PhysiologyNotes.build(self)
	return notes.duplicate()
