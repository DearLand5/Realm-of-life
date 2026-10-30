class_name PoolDynamics
extends RefCounted
## One sub-step of the population dynamics of every pool in a sector.
## All rates come from the same PhysiologyProfile functions individuals use:
##   * energy: income (food via a Holling type-II functional response on the
##     sector's EcoGrid plants/plankton/detritus/carcasses, predation, light)
##     − demand (maintenance at body temperature, activity, thermoregulation,
##     juvenile growth, embryos); hunger sets foraging effort (satiation);
##   * mortality: starvation (empty reserve), heat/cold stress, habitat or
##     respiration mismatch, dehydration without drinking water, density-
##     dependent disease, background accidents, senescence (Gompertz), and
##     predation between pools (weapons, bulk, armour, speed, vigilance,
##     size window, pack hunting; type-II with handling time);
##   * births: breeding share × clutch × fertility / breeding interval ×
##     condition × season × mate availability (Allee), paid from the reserve.
## Every genotype sample has its own energy and mortality → its weight
## changes by its own fitness (selection). Formulas are exponential/clamped
## so any sub-step up to an hour is stable.

const DAY := Units.SECONDS_PER_DAY
const FORAGE_TIME := 0.5
const BASE_ACTIVITY := 0.1
const FORAGE_ACTIVITY := 0.35
const BG_MORTALITY := 0.004 / DAY
const HABITAT_MORTALITY := 1.5 / DAY
const DISEASE_POOL := 0.01 / DAY          # per (individual per 100 m²)
const HUNT_SEARCH := 0.05
const CHASE_TIME := 1800.0
const NEWBORN_ENERGY := Reproduction.OFFSPRING_START_ENERGY
## Prey density (per m²) at which half of the prey can be found by predators.
const REFUGE_DENSITY := 0.3 / 1024.0
const MAX_HARVEST := 0.5                  # of the available food per sub-step
const MIN_COUNT := 0.02
const MATE_SEARCH_S := 3.0 * 86400.0

var eco: EcoGrid
var climate: ClimateState
## Dead mass (kg) per species produced during the last call, added as carcasses.
var _h := EcoGrid.Harvest.new()
var _prefs := PackedFloat32Array()
var _st: Array[_St] = []
var _x := PackedFloat32Array()     # predation scratch: attack rate × density × success
var _hd := PackedFloat32Array()    # handling time
var _kill := PackedFloat32Array()  # unconstrained kills per prey class
var _eat := PackedFloat32Array()   # kg eaten per kill
var _carcass_kg: float = 0.0
# Per-update scratch buffers (no allocations in the hot loop).
var _wants := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _dens := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _avail := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _desired := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _ratio := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _epk := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _intake := PackedFloat32Array()
var _land_share := PackedFloat32Array()
var _surv := PackedFloat32Array()
var _rec := PackedFloat32Array()
var _n_new := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


class _St:
	var pool: SpeciesPool
	var m75: float = 1.0
	var m1: float = 1.0
	var m23: float = 1.0
	var mf_juv: float = 0.2
	var mf_ado: float = 0.6
	var habitat: float = 1.0
	var e_mean: float = 0.5
	var effort: float = 0.5
	var attack: float = 0.0
	var defense: float = 0.0
	var speed: float = 1.0
	var mass: float = 1.0
	var detection: float = 10.0
	var vigilance: float = 0.5
	var sociality: float = 0.5
	var land_ok: float = 0.0
	var water_ok: float = 0.0
	var gut_meat: float = 1.0
	var intake_meat: float = 1e-4
	var eff_meat: float = 0.0
	var pred_w: float = 0.0
	var juvenile_s: float = 1.0
	var maturity: float = 2.0
	var elder_age: float = 3.0
	var kills := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var meat_gain: float = 0.0       # W per capita from predation
	var max_energy_pc: float = 1.0   # J reserve per capita (class-mass weighted)
	var demand_pc: float = 0.0       # W per capita (last step)
	var meat_share: float = 0.0      # share of meat in the diet weights


func _init(grid: EcoGrid = null, climate_state: ClimateState = null) -> void:
	eco = grid
	climate = climate_state


## Steps every pool of the sector by dt (≤ one hour recommended).
func step_sector(sec: PopSector, dt: float) -> void:
	if sec.pools.is_empty():
		return
	var n := 0
	for pool in sec.pools.values():
		if n >= _st.size():
			_st.append(_St.new())
		_aggregate(_st[n], pool, sec)
		n += 1
	for i in n:
		if _st[i].pred_w > 0.05:
			_predation(sec, i, n, dt)
	var dead: Array[int] = []
	for i in n:
		_carcass_kg = 0.0
		_update(sec, _st[i], dt)
		var pool := _st[i].pool
		if _carcass_kg > 0.05:
			eco.add_carcass(sec.center, _carcass_kg, pool.species_id)
		if pool.count < MIN_COUNT:
			dead.append(pool.species_id)
	for sid in dead:
		sec.pools.erase(sid)


func _aggregate(st: _St, pool: SpeciesPool, sec: PopSector) -> void:
	st.pool = pool
	st.kills.fill(0.0)
	st.meat_gain = 0.0
	var e := 0.0
	st.attack = 0.0
	st.defense = 0.0
	st.speed = 0.0
	st.mass = 0.0
	st.detection = 0.0
	st.vigilance = 0.0
	st.sociality = 0.0
	st.land_ok = 0.0
	st.water_ok = 0.0
	st.gut_meat = 0.0
	st.intake_meat = 0.0
	st.eff_meat = 0.0
	st.pred_w = 0.0
	st.mf_juv = 0.0
	st.mf_ado = 0.0
	st.juvenile_s = 0.0
	st.maturity = 0.0
	st.elder_age = 0.0
	st.max_energy_pc = 0.0
	st.demand_pc = 0.0
	st.meat_share = 0.0
	for s in pool.samples:
		var w := s.weight
		e += s.energy * w
		st.attack += s.attack * w
		st.defense += s.defense * w
		st.speed += s.speed * w
		st.mass += s.mass * w
		st.detection += s.detection * w
		st.vigilance += s.vigilance * w
		st.sociality += s.sociality * w
		st.land_ok += s.land_ok * w
		st.water_ok += s.water_ok * w
		st.gut_meat += s.pp.gut_capacity_kg * w
		st.intake_meat += s.intake[Food.MEAT] * w
		st.eff_meat += s.eff[Food.MEAT] * w
		st.mf_juv += s.mf_juv * w
		st.mf_ado += s.mf_ado * w
		st.juvenile_s += s.pp.juvenile_s * w
		st.maturity += s.pp.maturity_age * w
		st.elder_age += s.pp.elder_age * w
		if s.meat_eater:
			st.pred_w += w
		st.max_energy_pc += s.max_energy * w
		st.demand_pc += (s.last_demand if s.last_demand > 0.0 else s.pp.maintenance_rate(s.pp.body_temp_set)) * w
		var fw := 0.0
		for f in Food.COUNT:
			fw += s.food_w[f]
		st.meat_share += s.food_w[Food.MEAT] / maxf(fw, 1e-6) * w
	st.e_mean = e
	st.effort = effort(e)
	var c := pool.classes
	st.m75 = c[0] * pow(st.mf_juv, 0.75) + c[1] * pow(st.mf_ado, 0.75) + c[2] + c[3]
	st.m1 = c[0] * st.mf_juv + c[1] * st.mf_ado + c[2] + c[3]
	st.m23 = c[0] * pow(st.mf_juv, 2.0 / 3.0) + c[1] * pow(st.mf_ado, 2.0 / 3.0) + c[2] + c[3]
	st.max_energy_pc *= st.m1
	st.habitat = clampf(sec.land_frac * st.land_ok + sec.water_frac * st.water_ok, 0.0, 1.0)


## Foraging/hunting effort from hunger: sated animals rest (satiation).
static func effort(energy_fraction: float) -> float:
	return clampf((1.0 - energy_fraction) * 3.0, 0.05, 1.0)


static func success(att: float, def: float, v_pred: float, v_prey: float, vig: float, m_pred: float, m_prey: float, soc: float) -> float:
	var group := 1.0 + 1.5 * soc
	var fight := 1.0 / (1.0 + exp(-(att * group - def) / 2.0))
	var chase := clampf(0.25 + 0.75 * (v_pred / maxf(v_prey * (0.5 + 0.5 * vig), 0.05) - 0.5), 0.05, 1.0)
	var l := log(maxf(m_prey, 1e-6) / maxf(m_pred, 1e-6) / (0.5 * group))
	var size := exp(-l * l / 3.38)
	return fight * chase * size


func _predation(sec: PopSector, pi: int, n: int, dt: float) -> void:
	var P := _st[pi]
	var np := P.pool.count
	if np <= 0.0:
		return
	var slots := n * 4
	if _x.size() < slots:
		_x.resize(slots)
		_hd.resize(slots)
		_kill.resize(slots)
		_eat.resize(slots)
	_x.fill(0.0)
	_kill.fill(0.0)
	var denom := 1.0
	for qi in n:
		if qi == pi:
			continue
		var Q := _st[qi]
		var overlap := sec.land_frac * minf(P.land_ok, Q.land_ok) + sec.water_frac * minf(P.water_ok, Q.water_ok)
		if overlap < 0.01 or Q.pool.count <= 0.0:
			continue
		var a := P.speed * 0.6 * P.detection * HUNT_SEARCH * overlap / maxf(P.habitat, 0.05)
		var area_q := sec.area * maxf(Q.habitat, 0.05)
		var dens_q := Q.pool.count / area_q
		for c in 4:
			var nc := Q.pool.count * Q.pool.classes[c]
			if nc < 1e-4:
				continue
			# Prey refuge: at low density most prey hide (cover, burrows, herds).
			nc *= dens_q / (dens_q + REFUGE_DENSITY)
			var mf := Q.mf_juv if c == 0 else (Q.mf_ado if c == 1 else 1.0)
			var old := 0.8 if c == 3 else 1.0
			var m_c := Q.mass * mf
			var s := success(P.attack, Q.defense * pow(mf, 1.0 / 3.0) * old, P.speed, Q.speed * pow(mf, 1.0 / 6.0) * old,
				Q.vigilance, P.mass, m_c, P.sociality)
			var k := qi * 4 + c
			_x[k] = a * nc / area_q * s
			_eat[k] = minf(m_c, maxf(P.gut_meat, 1e-6))
			_hd[k] = _eat[k] / maxf(P.intake_meat, 1e-9) + CHASE_TIME
			denom += _x[k] * _hd[k]
	var hunters := np * P.effort * P.pred_w
	# Pass 1: kills at the unconstrained rate and the energy they would bring.
	var gain_j := 0.0
	for qi in n:
		if qi == pi:
			continue
		var Q := _st[qi]
		for c in 4:
			var k := qi * 4 + c
			if _x[k] <= 0.0:
				continue
			var kills := minf(_x[k] / denom * hunters * dt, 0.5 * Q.pool.count * Q.pool.classes[c] - Q.kills[c])
			_kill[k] = maxf(kills, 0.0)
			gain_j += _kill[k] * _eat[k] * float(Food.ENERGY[Food.MEAT]) * P.eff_meat
	# Satiation: a predator hunts only for what it can still store plus what
	# it burns meanwhile — no hunting far beyond its needs.
	var appetite := np * (maxf(1.0 - P.e_mean, 0.0) * P.max_energy_pc + P.demand_pc * dt) * P.meat_share
	var scale := minf(1.0, appetite / gain_j) if gain_j > 0.0 else 0.0
	# Pass 2: apply.
	for qi in n:
		if qi == pi:
			continue
		var Q := _st[qi]
		for c in 4:
			var k := qi * 4 + c
			var kills := _kill[k] * scale
			if kills <= 0.0:
				continue
			Q.kills[c] += kills
			var mf := Q.mf_juv if c == 0 else (Q.mf_ado if c == 1 else 1.0)
			P.meat_gain += kills * _eat[k] * float(Food.ENERGY[Food.MEAT]) * P.eff_meat / (np * dt)
			var rest := kills * maxf(Q.mass * mf - _eat[k], 0.0)
			if rest > 0.05:
				eco.add_carcass(sec.center, rest, Q.pool.species_id)


func _update(sec: PopSector, st: _St, dt: float) -> void:
	var pool := st.pool
	var n0 := pool.count
	if n0 <= 0.0:
		return
	var land_area := sec.area * maxf(st.habitat, 0.05)
	# --- Food available in the sector ----------------------------------------------
	var np := eco.plant_species.size()
	if _prefs.size() != np:
		_prefs.resize(np)
	_prefs.fill(0.0)
	_wants.fill(0.0)
	_avail.fill(0.0)
	_desired.fill(0.0)
	_ratio.fill(0.0)
	_epk.fill(0.0)
	for s in pool.samples:
		for k in np:
			_prefs[k] += s.plant_prefs[k] * s.weight
		for f in Food.COUNT:
			_wants[f] += s.food_w[f] * s.weight
	if _wants[Food.PLANT] > 0.01:
		_avail[Food.PLANT] = eco.plant_available(sec.cells, _prefs)
	if _wants[Food.DETRITUS] > 0.01:
		_avail[Food.DETRITUS] = eco.detritus_available(sec.cells)
	if _wants[Food.PLANKTON] > 0.01 and not sec.water_cells.is_empty():
		_avail[Food.PLANKTON] = eco.plankton_available(sec.water_cells)
	if _wants[Food.CARRION] > 0.01:
		_avail[Food.CARRION] = eco.carcass_available(sec.x0, sec.z0, sec.x1, sec.z1)
	for f in Food.COUNT:
		_dens[f] = _avail[f] / land_area
	if sec.water_frac > 0.0:
		_dens[Food.PLANKTON] = _avail[Food.PLANKTON] / maxf(sec.area * sec.water_frac, 1.0)
	# --- Per-sample intake → desired harvest ---------------------------------------
	# Type II during foraging time (search rate, mouth handling), capped over
	# the day by the gut volume: Σ intake × retention ≤ gut capacity.
	var ns := pool.samples.size()
	if _intake.size() < ns * Food.COUNT:
		_intake.resize(ns * Food.COUNT)
		_land_share.resize(ns)
		_surv.resize(ns)
		_rec.resize(ns)
	for i in ns:
		var s := pool.samples[i]
		var hl := sec.land_frac * s.land_ok
		var hw := sec.water_frac * s.water_ok
		var ls := hl / (hl + hw) if hl + hw > 1e-6 else 1.0
		_land_share[i] = ls
		var th_l := s.thermal(sec.t_air, false, sec.light)
		var th_w := s.thermal(sec.t_water, true, sec.light)
		var a := s.search_rate * lerpf(th_w.performance, th_l.performance, ls)
		var den := 1.0
		var base := i * Food.COUNT
		for f in Food.COUNT:
			var x := a * s.food_w[f] * _dens[f] * ((1.0 - ls) if f == Food.PLANKTON else 1.0)
			_intake[base + f] = x
			den += x / maxf(s.mouth_rate, 1e-12)
		var k_f := effort(s.energy) * FORAGE_TIME / den
		var load := 0.0
		for f in Food.COUNT:
			var v := _intake[base + f] * k_f
			_intake[base + f] = v
			load += v * s.retention[f]
		var cap := 1.0 if load <= s.gut_kg else s.gut_kg / load
		for f in Food.COUNT:
			var v := _intake[base + f] * cap * st.m75
			_intake[base + f] = v
			_desired[f] += v * n0 * s.weight * dt
	# --- Harvest from the EcoGrid --------------------------------------------------
	for f in Food.COUNT:
		if _desired[f] <= 0.0 or _avail[f] <= 0.0:
			continue
		var want := minf(_desired[f], _avail[f] * MAX_HARVEST)
		match f:
			Food.PLANT:
				eco.harvest_plants(sec.cells, want, _prefs, _h)
			Food.DETRITUS:
				eco.harvest_detritus(sec.cells, want, _h)
			Food.PLANKTON:
				eco.harvest_plankton(sec.water_cells, want, _h)
			Food.CARRION:
				eco.harvest_carcass(sec.x0, sec.z0, sec.x1, sec.z1, want, _h)
			_:
				_h.clear()
		_ratio[f] = _h.kg / _desired[f]
		_epk[f] = _h.energy / maxf(_h.kg, 1e-9) * (1.0 - 0.5 * _h.toxicity)
	# --- Energetics, mortality and births per sample ------------------------------
	var c := pool.classes
	var adults := n0 * (c[2] + c[3])
	var growing := c[0] + c[1]
	var e_pc_scale := st.m1
	var surv_sum := 0.0
	var recruits := 0.0
	var mean_atk := maxf(st.attack, 0.05)
	var mean_def := maxf(st.defense, 0.05)
	var vig_m := 1.2 - st.vigilance
	var v_sum := 0.0
	for s in pool.samples:
		v_sum += s.weight * (mean_def / maxf(s.defense, 0.05)) * sqrt(st.speed / maxf(s.speed, 0.01)) * (1.2 - s.vigilance) / vig_m
	var killed := st.kills[0] + st.kills[1] + st.kills[2] + st.kills[3]
	var pred_rate := killed / (n0 * dt)
	var density := n0 / land_area * 100.0
	for i in ns:
		var s := pool.samples[i]
		var pp := s.pp
		var ls := _land_share[i]
		var th_l := s.thermal(sec.t_air, false, sec.light)
		var th_w := s.thermal(sec.t_water, true, sec.light)
		var t_b := lerpf(th_w.body_temp, th_l.body_temp, ls)
		var perf := lerpf(th_w.performance, th_l.performance, ls)
		var heat := lerpf(th_w.heat_stress, th_l.heat_stress, ls)
		var cold := lerpf(th_w.cold_stress, th_l.cold_stress, ls)
		var eff_now := effort(s.energy)
		# Income.
		var income := pp.autotrophic_power(sec.light * lerpf(0.7, 1.0, ls)) * st.m23
		var water_in := 0.0
		for f in Food.COUNT:
			var kg_s := _intake[i * Food.COUNT + f] * _ratio[f]
			income += kg_s * _epk[f] * s.eff[f]
			water_in += kg_s * float(Food.WATER[f])
		if s.meat_eater and st.pred_w > 0.0:
			var rel := (s.attack + 0.1) / (mean_atk + 0.1) * sqrt(s.speed / maxf(st.speed, 0.01))
			income += st.meat_gain / st.pred_w * rel
		# Demand.
		var gc := smoothstep(0.2, 0.5, s.energy)
		var demand := pp.maintenance_rate(t_b) * st.m75 \
			+ pp.activity_power(BASE_ACTIVITY + FORAGE_ACTIVITY * eff_now, t_b) * st.m75 * perf \
			+ lerpf(th_w.extra_w, th_l.extra_w, ls) * st.m23 \
			+ s.growth_power * growing * gc
		# Births (paid from the reserve).
		var season := Reproduction.season_factor(pp, climate)
		# Mate finding: adults met while searching for ~3 days (Allee effect at low density).
		var mate := 1.0 - exp(-adults / land_area * s.search_rate * MATE_SEARCH_S) if s.needs_mate else 1.0
		var b := (c[2] + 0.5 * c[3]) * s.female_share * s.breed_rate * smoothstep(0.35, 0.7, s.energy) * season * mate
		s.fecundity = b
		var e_pc := s.max_energy * e_pc_scale
		s.energy = clampf(s.energy + ((income - demand) * dt - b * dt * s.offspring_cost) / maxf(e_pc, 1e-9), 0.0, 1.0)
		# Mortality.
		s.last_income = income
		s.last_demand = demand
		s.mu_starve = BiologySystem.STARVE_DAMAGE * (1.0 - smoothstep(0.0, 0.12, s.energy))
		s.mu_thermal = heat * heat * BiologySystem.HEAT_DAMAGE + cold * cold * BiologySystem.COLD_DAMAGE
		var h_i := s.habitat(sec.land_frac, sec.water_frac)
		s.mu_habitat = HABITAT_MORTALITY * (0.3 - h_i) / 0.3 if h_i < 0.3 else 0.0
		s.mu_water = 0.0
		if not sec.fresh_water and ls > 0.5 and not pp.aquatic:
			var hum := maxf(sec.humidity, 0.9) if s.burrower else sec.humidity
			var loss := (pp.water_loss_rate(sec.t_air, hum, false, demand) + th_l.cooling_water) * st.m23 * ls
			var deficit := loss - water_in
			if deficit > 0.0:
				s.mu_water = deficit / maxf(0.3 * pp.body_water_kg * st.m1, 1e-9)
		s.mu_disease = DISEASE_POOL * density * (1.0 - 0.7 * pp.immune) * (0.5 + sec.humidity)
		s.mu_predation = 0.0
		if killed > 0.0 and v_sum > 0.0:
			var v := (mean_def / maxf(s.defense, 0.05)) * sqrt(st.speed / maxf(s.speed, 0.01)) * (1.2 - s.vigilance) / vig_m
			s.mu_predation = pred_rate * v / v_sum
		var mu := BG_MORTALITY + s.mu_starve + s.mu_thermal + s.mu_habitat + s.mu_water + s.mu_disease + s.mu_predation
		var sv := exp(-mu * dt)
		_surv[i] = sv
		surv_sum += s.weight * sv
		_rec[i] = n0 * s.weight * b * dt * s.recruit_survival
		recruits += _rec[i]
		s.fitness = b * s.recruit_survival - mu
	# --- Classes & weights ------------------------------------------------------------
	# Predation removes from classes directly; other mortality is uniform across classes.
	var pred_surv := 1.0 - minf(killed / n0, 0.95)
	var other_surv := clampf(surv_sum / maxf(pred_surv, 1e-6), 0.0, 1.0)
	var n_new := _n_new
	for k in 4:
		n_new[k] = maxf(0.0, n0 * c[k] - st.kills[k]) * other_surv
	var e_mean := pool.mean_energy()
	var gcm := smoothstep(0.2, 0.5, e_mean)
	n_new[0] *= exp(-pool.samples[0].juv_mortality * dt)
	n_new[3] *= exp(-pool.samples[0].elder_hazard * dt)
	var tj := n_new[0] * (1.0 - exp(-dt * gcm / maxf(st.juvenile_s, 1.0)))
	var ta := n_new[1] * (1.0 - exp(-dt * gcm / maxf(st.maturity - st.juvenile_s, 1.0)))
	var te := n_new[2] * (1.0 - exp(-dt / maxf(st.elder_age - st.maturity, 1.0)))
	n_new[0] += recruits - tj
	n_new[1] += tj - ta
	n_new[2] += ta - te
	n_new[3] += te
	var n1 := n_new[0] + n_new[1] + n_new[2] + n_new[3]
	# Dead bodies become carcasses (predation leftovers were added already).
	var died := maxf(0.0, n0 - (n1 - recruits) - killed)
	_carcass_kg += died * st.mass * st.m1
	pool.count = n1
	if n1 > 0.0:
		for k in 4:
			c[k] = n_new[k] / n1
		pool.classes = c
	for i in ns:
		var s := pool.samples[i]
		var kept := n0 * s.weight * _surv[i]
		var tot := kept + _rec[i]
		if tot > 0.0:
			s.energy = (s.energy * kept + NEWBORN_ENERGY * _rec[i]) / tot
		s.weight = tot
	pool.normalize_weights()
	pool.births_since_resample += recruits
	pool.last_net = (n1 - n0) / (n0 * dt)
