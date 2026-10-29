class_name BiologySystem
extends RefCounted
## Integrates the physiology of Individuals (tiers A/B and eggs).
##
##   tick(ind, env, bio_dt, activity) -> Array[Dictionary] events
##     env keys (all optional, defaults in brackets):
##       temperature °C [15], humidity 0..1 [0.5], oxygen 0..1 [1],
##       in_water bool [false] — body immersed (gills work, skin wet, no evaporation),
##       air_access bool [not in_water] — lungs can reach air (surface swimming),
##       light 0..1 [0.5], water_nearby bool [false] — free drinking,
##       wind m/s [1], density conspecifics per 100 m² [1] (disease),
##       move_power W [0] — locomotion power from the mover (cost × speed).
##     activity: 0 rest/sleep … 0.3 foraging … 1 maximal sustained exertion.
##   events: {type: &"died", cause} | &"matured" | {type: &"stage", stage} |
##     &"ready_to_mate" | {type: &"gave_birth", offspring: Array[Individual]} |
##     {type: &"laid_eggs", eggs: Array[Individual]} | &"hatched" |
##     &"metamorphosed" | &"molted" | &"aborted"
##   feed(ind, kind, kg, quality, toxicity) -> float  assimilable J accepted
##   drink(ind, kg) -> float kg absorbed ; damage(ind, amount, cause) ; kill(ind, cause)
## Large bio_dt is sub-stepped (MAX_STEP) so the result does not depend on frame rate.

const DAY := Units.SECONDS_PER_DAY
const MAX_STEP := 600.0
const STARVE_DAMAGE := 1.0 / (1.2 * DAY)   # health/s with an empty reserve
const ASPHYXIA_S := 600.0                 # s from empty O2 store to death
const O2_REFILL_S := 120.0
const HEAT_DAMAGE := 3.0 / DAY            # health/s at full heat stress
const COLD_DAMAGE := 2.0 / DAY
const DEHYDRATION_START := 0.85
const DEHYDRATION_LETHAL := 0.7
const DEHYDRATION_DAMAGE := 2.0 / DAY
const DRINK_TIME := 300.0                 # s to drink up to full with free water access
const FATIGUE_RECOVERY_S := 1800.0
const ENDURANCE_S := 6.0 * 3600.0         # s of maximal sustained activity until exhaustion
const DISEASE_RATE := 0.04 / DAY          # infection chance/s at density 1
const VIRULENCE := 1.2 / DAY
const CLEARANCE := 0.6 / DAY
const DISEASE_DAMAGE := 0.8 / DAY
const HEAL_BASE := 0.15 / DAY
const HEAL_REGEN := 1.2 / DAY
const HEAL_COST := 0.04                   # × max reserve per unit of health
const TOXIN_CLEAR := 1.0 / DAY
const TOXIN_DAMAGE := 2.0 / DAY
const EGG_UPKEEP := 0.3                   # embryo metabolism relative to BMR

var rng: Rng
## Mutation settings for offspring (EvolutionSystem.settings).
var mutation_settings: Dictionary = {}
var climate: ClimateState

var _th := ThermalModel.Result.new()
var _env := _Env.new()


class _Env:
	var temperature: float = 15.0
	var humidity: float = 0.5
	var oxygen: float = 1.0
	var in_water := false
	var air_access := true
	var light: float = 0.5
	var water_nearby := false
	var wind: float = 1.0
	var density: float = 1.0
	var move_power: float = 0.0

	func read(env: Dictionary) -> void:
		temperature = float(env.get("temperature", 15.0))
		humidity = clampf(float(env.get("humidity", 0.5)), 0.0, 1.0)
		oxygen = float(env.get("oxygen", 1.0))
		in_water = bool(env.get("in_water", false))
		air_access = bool(env.get("air_access", not in_water))
		light = clampf(float(env.get("light", 0.5)), 0.0, 1.0)
		water_nearby = bool(env.get("water_nearby", false))
		wind = float(env.get("wind", 1.0))
		density = float(env.get("density", 1.0))
		move_power = float(env.get("move_power", 0.0))


func _init(seed_value: int = 1, settings: Dictionary = {}, climate_state: ClimateState = null) -> void:
	rng = Rng.new(seed_value)
	mutation_settings = settings
	climate = climate_state


func setup(seed_value: int, settings: Dictionary = {}, climate_state: ClimateState = null) -> void:
	rng.set_seed(seed_value)
	mutation_settings = settings
	climate = climate_state


# --- Public API ---------------------------------------------------------------------

func tick(ind: Individual, env: Dictionary, bio_dt: float, activity: float = 0.2) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not ind.alive or bio_dt <= 0.0:
		return events
	_env.read(env)
	var steps := maxi(1, int(ceil(bio_dt / MAX_STEP)))
	var dt := bio_dt / float(steps)
	for i in steps:
		if ind.stage == &"egg":
			_step_egg(ind, dt, events)
		else:
			_step(ind, dt, activity, events)
		if not ind.alive:
			break
	if ind.alive and ind.stage != &"egg":
		_reproduction_tick(ind, events)
	return events


## Puts food into the gut. Returns the assimilable energy (J) accepted.
func feed(ind: Individual, kind, kg: float, quality: float = 1.0, toxicity: float = 0.0) -> float:
	if not ind.alive or kg <= 0.0 or ind.stage == &"egg":
		return 0.0
	var k := Food.index_of(kind)
	if k < 0:
		return 0.0
	var p := ind.physiology()
	var free := p.gut_capacity_kg * ind.mass_factor() - ind.stomach_total()
	var taken := clampf(kg, 0.0, maxf(free, 0.0))
	if taken <= 0.0:
		return 0.0
	var j := taken * float(Food.ENERGY[k]) * clampf(quality, 0.0, 2.0) * p.food_efficiency(k)
	ind.stomach_kg[k] += taken
	ind.stomach_j[k] += j
	if toxicity > 0.0:
		var tolerance := float(p.diet_eff["carrion"]) if k == Food.CARRION else float(p.diet_eff["plant"]) * 0.5
		ind.toxin += taken / maxf(ind.mass(), 1e-6) * toxicity * (1.0 - clampf(tolerance, 0.0, 0.9)) * 4.0
	return j


## Drinks water. Returns kg absorbed.
func drink(ind: Individual, kg: float) -> float:
	if not ind.alive:
		return 0.0
	var p := ind.physiology()
	var need := (1.0 - ind.hydration) * p.body_water_kg * ind.mass_factor()
	var taken := clampf(kg, 0.0, maxf(need, 0.0))
	ind.hydration += taken / maxf(p.body_water_kg * ind.mass_factor(), 1e-9)
	return taken


## Mechanical damage (fraction of health, armour already applied by the caller).
func damage(ind: Individual, amount: float, cause: StringName = &"injury") -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not ind.alive:
		return events
	ind.health -= maxf(amount, 0.0)
	ind.last_damage = cause
	if ind.health <= 0.0:
		events.append(kill(ind, cause))
	return events


func kill(ind: Individual, cause: StringName) -> Dictionary:
	ind.alive = false
	ind.health = 0.0
	ind.cause = cause
	ind.pregnant = false
	ind.embryos.clear()
	return {"type": &"died", "cause": cause}


## Speed/activity multiplier for movement: thermal performance × condition.
func speed_factor(ind: Individual) -> float:
	if not ind.alive or ind.stage == &"egg":
		return 0.0
	var p := ind.physiology()
	var frail := 1.0
	if ind.age > p.elder_age:
		frail = clampf(1.0 - 0.6 * (ind.age - p.elder_age) / maxf(p.lifespan - p.elder_age, 1.0), 0.3, 1.0)
	return clampf(ind.performance * (1.0 - 0.6 * ind.fatigue) * sqrt(maxf(ind.health, 0.0)) * frail, 0.0, 1.0)


## 0 sated .. 1 starving — for AI motivation.
func hunger(ind: Individual) -> float:
	return clampf(1.0 - ind.energy_fraction() * 0.7 - ind.stomach_fullness() * 0.3, 0.0, 1.0)


func thirst(ind: Individual) -> float:
	return clampf((1.0 - ind.hydration) / (1.0 - DEHYDRATION_LETHAL), 0.0, 1.0)


# --- Integration ----------------------------------------------------------------------

func _step(ind: Individual, dt: float, activity: float, events: Array[Dictionary]) -> void:
	var p := ind.physiology()
	var e := _env
	var mf := ind.mass_factor()
	var basal := p.maintenance_rate(ind.body_temp, mf)
	var act_w := p.activity_power(activity, ind.body_temp, mf) * ind.performance + e.move_power
	var fever := basal * 0.4 * ind.disease
	# --- Thermal balance -----------------------------------------------------
	ThermalModel.steady(p, e.temperature, e.in_water, e.light, e.wind, basal + act_w + fever, mf, _th)
	var thermo_w := _th.extra_w
	var cooling_water := _th.cooling_water
	var tau := ThermalModel.time_constant(p, _th.conductance, mf)
	ind.body_temp = _th.target_temp + (ind.body_temp - _th.target_temp) * exp(-dt / maxf(tau, 1.0))
	ThermalModel.evaluate_temp(p, ind.body_temp, _th)
	ind.performance = _th.performance
	ind.heat_stress = _th.heat_stress
	ind.cold_stress = _th.cold_stress
	var worst := 0.0
	var worst_cause: StringName = &""
	# --- Respiration capacity; production (growth, embryos) uses only spare O2 ---
	var cap := p.o2_capacity(e.in_water, e.oxygen, e.air_access, e.humidity, mf)
	if ind.larval and e.in_water:
		cap += p.bmr_watts * 4.0 * pow(mf, 0.75)  # larval gills
	var maint := basal + thermo_w + fever
	var spare := maxf(0.0, cap - maint - act_w * 0.5)
	var repro_req := ind.repro_cost_rate if ind.pregnant else 0.0
	var prod_req := _growth_power(ind, p) + repro_req
	var prod_k := clampf(spare / prod_req, 0.0, 1.0) if prod_req > 0.0 else 1.0
	var growth_w := _growth(ind, p, dt, prod_k, events)
	var repro_w := repro_req * prod_k
	# --- Energy budget ------------------------------------------------------------
	var water_gain := _digest(ind, p, dt)
	var income := p.autotrophic_power(e.light if not e.in_water else e.light * 0.7, mf)
	var demand := maint + act_w + growth_w + repro_w
	ind.energy += (income - demand) * dt
	var max_e := p.max_energy * mf
	if ind.energy > max_e:
		ind.energy = max_e
	if ind.energy <= 0.0:
		ind.energy = 0.0
		var d := STARVE_DAMAGE * dt
		if d > worst:
			worst = d
			worst_cause = &"starvation"
		if ind.pregnant:
			Reproduction.abort(ind)
			events.append({"type": &"aborted"})
	elif ind.pregnant and ind.energy < max_e * Reproduction.ABORT_ENERGY:
		Reproduction.abort(ind)
		events.append({"type": &"aborted"})
	# --- Oxygen balance ---------------------------------------------------------------
	var aerobic := maint + growth_w + repro_w
	var total := aerobic + act_w
	if cap >= total:
		ind.oxygen = minf(1.0, ind.oxygen + dt / O2_REFILL_S)
	elif cap >= aerobic:
		ind.oxygen = minf(1.0, ind.oxygen + dt / O2_REFILL_S)
		ind.fatigue += (total - cap) * dt / maxf(p.anaerobic_j * mf, 1.0)
	else:
		var store := maxf(p.o2_store_j * mf, 1.0)
		var deficit := aerobic - cap
		ind.oxygen -= deficit * dt / store
		ind.fatigue += act_w * dt / maxf(p.anaerobic_j * mf, 1.0)
		if ind.oxygen < 0.0:
			var t_over := -ind.oxygen * store / deficit
			ind.oxygen = 0.0
			var d := t_over / ASPHYXIA_S
			if d > worst:
				worst = d
				worst_cause = &"drowning" if (p.lungs_w > 0.0 and e.in_water and not e.air_access) else &"suffocation"
	# --- Fatigue -----------------------------------------------------------------------
	var scope := clampf(cap / maxf(basal, 1e-9), 1.0, 20.0)
	ind.fatigue += activity * dt / (ENDURANCE_S * sqrt(scope / 5.0))
	if activity < 0.3:
		ind.fatigue -= dt / FATIGUE_RECOVERY_S * (1.0 - activity / 0.3)
	ind.fatigue = clampf(ind.fatigue, 0.0, 1.0)
	# --- Water balance -------------------------------------------------------------------
	_hydrate(ind, p, dt, demand, cooling_water, water_gain)
	if ind.hydration <= DEHYDRATION_LETHAL:
		worst = 2.0
		worst_cause = &"dehydration"
	elif ind.hydration < DEHYDRATION_START:
		var d := (DEHYDRATION_START - ind.hydration) / (DEHYDRATION_START - DEHYDRATION_LETHAL) * DEHYDRATION_DAMAGE * dt
		if d > worst:
			worst = d
			worst_cause = &"dehydration"
	# --- Temperature stress -------------------------------------------------------------
	var heat_d := ind.heat_stress * ind.heat_stress * HEAT_DAMAGE * dt
	var cold_d := ind.cold_stress * ind.cold_stress * COLD_DAMAGE * dt
	var thermal_total := heat_d + cold_d
	# --- Disease & toxins -------------------------------------------------------------------
	var dis_d := _disease(ind, p, dt)
	var tox_d := ind.toxin * TOXIN_DAMAGE * dt
	ind.toxin *= exp(-TOXIN_CLEAR * dt * (0.5 + float(p.diet_eff["carrion"])))
	var damage_total := worst + thermal_total + dis_d + tox_d
	if heat_d > worst and heat_d >= cold_d:
		worst_cause = &"overheating"
	elif cold_d > worst:
		worst_cause = &"hypothermia"
	if dis_d > maxf(worst, thermal_total):
		worst_cause = &"disease"
	if tox_d > maxf(worst, maxf(thermal_total, dis_d)):
		worst_cause = &"poisoning"
	if damage_total > 0.0:
		ind.health -= damage_total
		ind.last_damage = worst_cause
	elif ind.health < 1.0 and ind.energy > max_e * 0.2:
		_heal(ind, p, dt, max_e)
	# --- Aging ---------------------------------------------------------------------------------
	ind.age += dt
	if ind.repro_cooldown > 0.0:
		ind.repro_cooldown = maxf(0.0, ind.repro_cooldown - dt)
	_stages(ind, p, events)
	if ind.soft_shell > 0.0:
		ind.soft_shell = maxf(0.0, ind.soft_shell - dt)
	if ind.health <= 0.0:
		events.append(kill(ind, ind.last_damage if ind.last_damage != &"" else &"injury"))
		return
	if rng.chance(1.0 - exp(-LifeHistory.hazard(p, ind.age) * dt)):
		events.append(kill(ind, &"old_age"))
		return
	if ind.pregnant:
		ind.gestation_left -= dt * prod_k
		if ind.gestation_left <= 0.0:
			_deliver(ind, p, events)


## Digests gut contents; returns kg of water released by the food.
func _digest(ind: Individual, p: PhysiologyProfile, dt: float) -> float:
	var water := 0.0
	if ind.energy >= p.max_energy * ind.mass_factor():
		return 0.0  # sated: food waits in the gut
	# Cold ectotherms digest slowly.
	var rate_k := lerpf(clampf(ind.performance, 0.15, 1.0), 1.0, p.endothermy)
	for k in Food.COUNT:
		var kg := ind.stomach_kg[k]
		if kg <= 1e-9:
			continue
		var f := 1.0 - exp(-dt * rate_k / p.retention_time(k, ind.mass_factor()))
		var dkg := kg * f
		ind.energy += ind.stomach_j[k] * f
		ind.stomach_j[k] -= ind.stomach_j[k] * f
		ind.stomach_kg[k] = kg - dkg
		water += dkg * float(Food.WATER[k])
	return water


func _hydrate(ind: Individual, p: PhysiologyProfile, dt: float, power: float, cooling: float, food_water: float) -> void:
	var e := _env
	var mf := ind.mass_factor()
	var body_water := maxf(p.body_water_kg * mf, 1e-9)
	var loss := p.water_loss_rate(e.temperature, e.humidity, e.in_water, power, mf) + cooling
	var gain := food_water / dt
	var deficit := (1.0 - ind.hydration) * body_water
	if e.in_water and (p.aquatic or p.moist_skin_fraction > 0.3 or p.habitat == &"amphibious"):
		gain += deficit / 600.0
	elif p.skin_absorb_kg_s > 0.0:
		var wet := 1.0 if (e.water_nearby or e.in_water) else clampf((e.humidity - 0.75) / 0.25, 0.0, 1.0)
		gain += p.skin_absorb_kg_s * pow(mf, 2.0 / 3.0) * wet * (1.0 - ind.hydration) * 10.0
	if e.water_nearby:
		gain += deficit / DRINK_TIME
	ind.hydration = minf(1.0, ind.hydration + (gain - loss) * dt / body_water)


func _disease(ind: Individual, p: PhysiologyProfile, dt: float) -> float:
	if ind.disease <= 0.0:
		var chance := DISEASE_RATE * _env.density * (0.5 + _env.humidity) * (1.0 - 0.7 * p.immune) * (1.0 - ind.immunity)
		if rng.chance(1.0 - exp(-chance * dt)):
			ind.disease = 0.05
		ind.immunity = maxf(0.0, ind.immunity - dt / (20.0 * DAY))
		return 0.0
	var growth_r := VIRULENCE * (1.0 - ind.immunity) - CLEARANCE * (0.3 + p.immune) * (1.0 + ind.immunity)
	ind.disease = clampf(ind.disease * exp(growth_r * dt), 0.0, 1.0)
	ind.immunity = minf(1.0, ind.immunity + ind.disease * dt / (1.5 * DAY))
	if ind.disease < 0.01:
		ind.disease = 0.0
	return ind.disease * ind.disease * DISEASE_DAMAGE * dt


func _heal(ind: Individual, p: PhysiologyProfile, dt: float, max_e: float) -> void:
	var size_k := clampf(pow(maxf(ind.mass(), 0.01), -0.1), 0.5, 2.0)
	var rate := (HEAL_BASE + HEAL_REGEN * p.regeneration) * size_k
	if ind.stage == &"elder":
		rate *= 0.5
	var dh := minf(rate * dt, 1.0 - ind.health)
	ind.health += dh
	ind.energy -= dh * HEAL_COST * max_e * (1.0 + p.regeneration)


## Power (W) that full-speed growth would need now (von Bertalanffy, energy-limited).
func _growth_power(ind: Individual, p: PhysiologyProfile) -> float:
	var g := ind.growth + ind.molt_pending
	if g >= 0.999:
		return 0.0
	var condition := clampf((ind.energy_fraction() - 0.2) / 0.3, 0.0, 1.0)
	return 3.0 * p.mass * g * g * p.growth_k * (1.0 - g) * condition * Food.BUILD_COST


## Somatic growth; `throttle` 0..1 from spare O2. Returns the growth power (W).
func _growth(ind: Individual, p: PhysiologyProfile, dt: float, throttle: float, events: Array[Dictionary]) -> float:
	if ind.growth >= 0.999 and ind.molt_pending <= 0.0:
		return 0.0
	var ef := ind.energy_fraction()
	var condition := clampf((ef - 0.2) / 0.3, 0.0, 1.0) * throttle
	var g := ind.growth + ind.molt_pending
	var dg := minf(p.growth_k * (1.0 - g) * dt * condition, 1.0 - g)
	var dm := p.mass * (pow(g + dg, 3.0) - pow(g, 3.0))
	var cost := dm * Food.BUILD_COST
	if p.molting and ind.stage != &"adult" and ind.stage != &"elder":
		ind.molt_pending += dg
		ind.molt_timer += dt
		if ind.molt_timer >= p.molt_interval_s and ind.molt_pending > 0.0:
			ind.growth = minf(1.0, ind.growth + ind.molt_pending)
			ind.molt_pending = 0.0
			ind.molt_timer = 0.0
			ind.soft_shell = 0.1 * DAY
			events.append({"type": &"molted"})
	else:
		ind.growth = minf(1.0, ind.growth + ind.molt_pending + dg)
		ind.molt_pending = 0.0
	return cost / dt


func _stages(ind: Individual, p: PhysiologyProfile, events: Array[Dictionary]) -> void:
	var target := LifeHistory.stage_for_age(p, ind.age)
	if target == ind.stage:
		return
	match target:
		&"adolescent":
			if ind.stage == &"juvenile":
				ind.stage = &"adolescent"
				events.append({"type": &"stage", "stage": &"adolescent"})
				if ind.larval:
					ind.larval = false
					events.append({"type": &"metamorphosed"})
		&"adult":
			# Maturity also needs body size: starved juveniles mature late.
			if ind.growth + ind.molt_pending >= Reproduction.MATURE_GROWTH:
				if ind.larval:
					ind.larval = false
					events.append({"type": &"metamorphosed"})
				ind.stage = &"adult"
				events.append({"type": &"matured"})
			elif ind.stage == &"juvenile":
				ind.stage = &"adolescent"
		&"elder":
			if ind.stage == &"adult":
				ind.stage = &"elder"
				events.append({"type": &"stage", "stage": &"elder"})
			elif ind.stage != &"elder" and ind.growth >= Reproduction.MATURE_GROWTH:
				ind.stage = &"adult"
				events.append({"type": &"matured"})


func _deliver(ind: Individual, p: PhysiologyProfile, events: Array[Dictionary]) -> void:
	var kids := Reproduction.offspring(ind, rng)
	if kids.is_empty():
		return
	if p.repro_method in [&"eggs", &"spores"]:
		events.append({"type": &"laid_eggs", "eggs": kids})
	else:
		events.append({"type": &"gave_birth", "offspring": kids})


func _reproduction_tick(ind: Individual, events: Array[Dictionary]) -> void:
	ind.repro_cooldown = maxf(0.0, ind.repro_cooldown)
	var p := ind.physiology()
	if p.repro_mode == &"asexual":
		if not ind.pregnant and Reproduction.is_ready(ind, climate):
			Reproduction.start_asexual(ind, rng, mutation_settings, climate)
		return
	var ready := Reproduction.is_ready(ind, climate)
	if ready and not ind.ready_to_mate:
		events.append({"type": &"ready_to_mate"})
	ind.ready_to_mate = ready


## Eggs and spores: development depends on temperature (ectotherm embryos)
## unless brooded by endothermic parents; yolk pays embryo metabolism.
func _step_egg(ind: Individual, dt: float, events: Array[Dictionary]) -> void:
	var p := ind.physiology()
	var e := _env
	var mf := ind.mass_factor()
	ind.body_temp = e.temperature
	ThermalModel.evaluate_temp(p, e.temperature, _th)
	var brood := p.endothermy * ind.genome.value(&"parental_care")
	var rate := lerpf(_th.performance, 1.0, brood)
	if ind.dormant:
		if _th.performance > 0.5 and (e.humidity > 0.4 or e.in_water):
			ind.dormant = false
		else:
			ind.age += dt
			return
	ind.incubation_left -= dt * rate
	ind.energy -= p.basal_rate(e.temperature, mf) * EGG_UPKEEP * dt
	var dmg := (_th.heat_stress * _th.heat_stress * HEAT_DAMAGE + _th.cold_stress * _th.cold_stress * COLD_DAMAGE * (1.0 - brood)) * dt
	var cause: StringName = &"overheating" if _th.heat_stress > _th.cold_stress else &"hypothermia"
	# Eggs of aquatic/amphibious species dry out on land.
	if (p.habitat == &"water" or (p.habitat == &"amphibious" and p.needs_moisture)) and not e.in_water and e.humidity < 0.85:
		dmg += (0.85 - e.humidity) * 4.0 / DAY * dt
		cause = &"dehydration"
	if ind.energy <= 0.0:
		ind.energy = 0.0
		dmg += STARVE_DAMAGE * dt
		cause = &"starvation"
	ind.age += dt
	if dmg > 0.0:
		ind.health -= dmg
		ind.last_damage = cause
		if ind.health <= 0.0:
			events.append(kill(ind, cause))
			return
	if ind.incubation_left <= 0.0:
		ind.stage = &"juvenile"
		ind.age = 0.0
		ind.larval = p.metamorphosis
		events.append({"type": &"hatched"})
