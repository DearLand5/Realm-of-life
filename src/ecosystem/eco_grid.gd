class_name EcoGrid
extends RefCounted
## Ecosystem cells (default 8 m) covering a WorldData: plant biomass per
## PlantSpecies (kg/m²), detritus (kg/m²), soil nutrients (relative units),
## plankton in water (kg/m²) and carcasses (CarcassField).
##
## Plants: logistic growth toward a capacity set by climate suitability
## (ClimateState temperature/humidity incl. season, weather, drought, sandbox
## offsets), site (water/land, biome), soil fertility and
## `sandbox_resource_mult`; competition for space and light (taller plants
## shade shorter ones); growth needs nutrients; senescence and autumn leaf
## fall feed detritus; detritus decomposes (Q10 × moisture) into nutrients;
## seeds diffuse from neighbours plus a small seed bank. Growth uses the
## DAILY MEAN light (not the instantaneous sun), so any step size works.
##
## step(bio_dt) is time-sliced: every call adds dt to all rows and fully
## integrates `rows_per_step` rows (each with its own pending time), so the
## result is deterministic and independent of the slicing.

const DEFAULT_CELL := 8.0
const DAY := Units.SECONDS_PER_DAY
const LUT_T_MIN := -40.0
const LUT_T_STEPS := 201                 # 0.5 °C steps up to +60 °C
const LUT_M_STEPS := 101
const RESIDUAL := 0.05                   # ungrazeable fraction of capacity (roots, stubble)
const SEED_BANK := 0.002                 # per day, × capacity × suitability
const SEED_YIELD := 0.05
const NUTRIENT_PER_KG := 0.05            # nutrient units per kg/m² of plant growth
const NUTRIENT_HALF := 0.15
const NUTRIENT_RELAX := 0.05             # per day toward the soil's fertility
const DECOMPOSITION := 0.08              # per day at 20 °C, moist
const PLANKTON_R := 0.8                  # per day
const PLANKTON_K := 0.06                 # kg/m² in fertile water
const PLANKTON_TURNOVER := 0.1
## Leaf share of biomass: what deciduous plants shed in autumn.
const LEAF_FRACTION := {&"grass": 1.0, &"shrub": 0.3, &"broadleaf_tree": 0.08, &"conifer": 0.05, &"palm": 0.1,
	&"cactus": 0.1, &"fern": 0.8, &"reed": 1.0, &"flower": 1.0, &"mushroom": 1.0, &"kelp": 1.0, &"algae": 1.0}
const TURNOVER := {&"grass": 0.03, &"shrub": 0.012, &"broadleaf_tree": 0.005, &"conifer": 0.004,
	&"palm": 0.006, &"cactus": 0.005, &"fern": 0.02, &"reed": 0.03, &"flower": 0.05, &"mushroom": 0.08,
	&"kelp": 0.05, &"algae": 0.08}

class Harvest:
	var kg: float = 0.0
	var energy: float = 0.0       # gross J (before the consumer's digestion efficiency)
	var toxicity: float = 0.0     # mass-weighted 0..1

	func clear() -> void:
		kg = 0.0
		energy = 0.0
		toxicity = 0.0

	func to_dict() -> Dictionary:
		return {"kg": kg, "energy": energy, "toxicity": toxicity}

var world: WorldData
var climate: ClimateState
var plant_species: Array[PlantSpecies] = []
var cell_size: float = DEFAULT_CELL
var dim: int = 1
var origin := Vector2.ZERO               # world x/z of the grid corner
var rows_per_step: int = 4
## Each row is integrated at most about once per this many biological seconds
## (rows are spread evenly over frames); at high time scales rows_per_step rules.
var row_period: float = 300.0
var _row_credit := 0.0

# Static per cell.
var cell_temp := PackedFloat32Array()
var cell_moist := PackedFloat32Array()
var cell_fert := PackedFloat32Array()
var cell_water := PackedFloat32Array()   # fraction under water 0..1
var cell_site := PackedFloat32Array()    # land site quality (rock, sand, ice)
# Dynamic per cell.
var plant_mass := PackedFloat32Array()      # [p * n + i] kg/m²
var detritus := PackedFloat32Array()     # kg/m²
var nutrients := PackedFloat32Array()
var plankton := PackedFloat32Array()     # kg/m²
var carcasses := CarcassField.new()
var row_pending := PackedFloat32Array()
var cursor: int = 0
var time: float = 0.0

# Per-species constants & lookup tables.
var _n: int = 0
var _p: int = 0
var _rate := PackedFloat32Array()
var _cap := PackedFloat32Array()
var _turn := PackedFloat32Array()
var _seasonal := PackedFloat32Array()
var _spread := PackedFloat32Array()
var _energy := PackedFloat32Array()      # J per kg eaten (gross, incl. toughness)
var _toxic := PackedFloat32Array()
var _leaf := PackedFloat32Array()
var _order := PackedInt32Array()         # species sorted by height (tallest first)
var _shade_len := PackedInt32Array()     # per species: how many of _order are tall enough to shade it
var _turn_k := PackedFloat32Array()      # scratch per row: survival after turnover
var _r_k := PackedFloat32Array()         # scratch per call: seasonal growth rate
var _prefix := PackedFloat32Array()      # scratch per cell: cumulative occupancy in height order
var _site := PackedFloat32Array()        # [p * n + i]
var _temp_lut := PackedFloat32Array()
var _moist_lut := PackedFloat32Array()
var _k := PackedFloat32Array()           # scratch: capacity per species
var _occ := PackedFloat32Array()         # scratch: occupancy per species
var _w := PackedFloat32Array()           # scratch: preference weights
var _h := Harvest.new()
# Climate factors refreshed every step call.
var _t_off: float = 0.0
var _tw_off: float = 0.0
var _m_off: float = 0.0
var _light: float = 0.5
var _mult: float = 1.0
var _winter: float = 0.0
var _autumn: float = 0.0


func setup(w: WorldData, plants: Array[PlantSpecies], climate_state: ClimateState = null, cell: float = DEFAULT_CELL) -> void:
	world = w
	climate = climate_state
	plant_species = plants
	cell_size = cell
	dim = maxi(1, int(ceil(w.size / cell)))
	origin = Vector2(-w.size * 0.5, -w.size * 0.5)
	_n = dim * dim
	_p = plants.size()
	rows_per_step = maxi(1, 128 / dim)
	_build_static()
	_build_species()
	plant_mass.resize(_p * _n)
	detritus.resize(_n)
	nutrients.resize(_n)
	plankton.resize(_n)
	row_pending.resize(dim)
	initialize(0.5)


func _build_static() -> void:
	cell_temp.resize(_n)
	cell_moist.resize(_n)
	cell_fert.resize(_n)
	cell_water.resize(_n)
	cell_site.resize(_n)
	for cz in dim:
		for cx in dim:
			var i := cz * dim + cx
			var c := cell_center(cx, cz)
			cell_temp[i] = world.base_temperature_at(c.x, c.z)
			cell_moist[i] = world.moisture_at(c.x, c.z)
			cell_fert[i] = world.fertility_at(c.x, c.z)
			var wet := 0
			for sz in 3:
				for sx in 3:
					var px := c.x + (float(sx) - 1.0) * cell_size * 0.33
					var pz := c.z + (float(sz) - 1.0) * cell_size * 0.33
					if world.contains(px, pz) and world.water_type_at(px, pz) != WorldData.Water.LAND:
						wet += 1
			cell_water[i] = float(wet) / 9.0
			var site := 1.0
			match world.biome_at(c.x, c.z):
				Biomes.SNOW:
					site = 0.05
				Biomes.MOUNTAIN:
					site = 0.35
				Biomes.BEACH:
					site = 0.4
			cell_site[i] = site


func _build_species() -> void:
	_rate.resize(_p)
	_cap.resize(_p)
	_turn.resize(_p)
	_seasonal.resize(_p)
	_spread.resize(_p)
	_energy.resize(_p)
	_toxic.resize(_p)
	_k.resize(_p)
	_occ.resize(_p)
	_w.resize(_p)
	_leaf.resize(_p)
	_turn_k.resize(_p)
	_r_k.resize(_p)
	_prefix.resize(_p + 1)
	_shade_len.resize(_p)
	var by_height: Array = []
	for p in _p:
		by_height.append(p)
	by_height.sort_custom(func(a: int, b: int) -> bool: return plant_species[a].height > plant_species[b].height)
	_order = PackedInt32Array(by_height)
	_site.resize(_p * _n)
	_temp_lut.resize(_p * LUT_T_STEPS)
	_moist_lut.resize(_p * LUT_M_STEPS)
	for p in _p:
		var sp := plant_species[p]
		_rate[p] = sp.growth_rate
		_cap[p] = sp.capacity
		_turn[p] = float(TURNOVER.get(sp.form, 0.02))
		_seasonal[p] = sp.seasonal
		_spread[p] = sp.spread
		_energy[p] = float(Food.ENERGY[Food.PLANT]) * sp.nutrition * (1.0 - 0.5 * sp.toughness)
		_toxic[p] = sp.toxicity
		_leaf[p] = float(LEAF_FRACTION.get(sp.form, 0.5))
		var n_tall := 0
		for j in _p:
			if plant_species[_order[j]].height > sp.height * 1.5:
				n_tall = j + 1
		_shade_len[p] = n_tall
		for t in LUT_T_STEPS:
			_temp_lut[p * LUT_T_STEPS + t] = MathUtil.tolerance(LUT_T_MIN + float(t) * 0.5, sp.temp_opt, sp.temp_tol)
		for m in LUT_M_STEPS:
			_moist_lut[p * LUT_M_STEPS + m] = 1.0 if sp.aquatic else MathUtil.tolerance(float(m) / 100.0, sp.moist_opt, sp.moist_tol)
		for i in _n:
			var wf := cell_water[i]
			_site[p * _n + i] = wf if sp.aquatic else (1.0 - wf) * cell_site[i]


## Fills plants at `fill` × local capacity (annual mean climate).
func initialize(fill: float = 0.5) -> void:
	_climate_factors()
	for i in _n:
		var ti := _temp_index(cell_temp[i])
		var mi := clampi(int(cell_moist[i] * 100.0), 0, 100)
		for p in _p:
			var k := _cap[p] * _temp_lut[p * LUT_T_STEPS + ti] * _moist_lut[p * LUT_M_STEPS + mi] * _site[p * _n + i] * (0.5 + 0.5 * cell_fert[i])
			plant_mass[p * _n + i] = k * fill / maxf(1.0, float(_p) * 0.4)
		detritus[i] = 0.05
		nutrients[i] = cell_fert[i]
		plankton[i] = PLANKTON_K * cell_water[i] * (0.5 + cell_fert[i]) * fill
	for r in dim:
		row_pending[r] = 0.0
	cursor = 0


# --- Geometry -------------------------------------------------------------------

func cell_center(cx: int, cz: int) -> Vector3:
	return Vector3(origin.x + (float(cx) + 0.5) * cell_size, 0.0, origin.y + (float(cz) + 0.5) * cell_size)


func cell_coords(pos: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor((pos.x - origin.x) / cell_size)), 0, dim - 1),
		clampi(int(floor((pos.z - origin.y) / cell_size)), 0, dim - 1))


func cell_index(pos: Vector3) -> int:
	var c := cell_coords(pos)
	return c.y * dim + c.x


func cell_area() -> float:
	return cell_size * cell_size


func cell_count() -> int:
	return _n


## Cell indices whose centres lie inside a world rectangle.
func cells_in_rect(x0: float, z0: float, x1: float, z1: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var a := cell_coords(Vector3(x0 + 0.01, 0, z0 + 0.01))
	var b := cell_coords(Vector3(x1 - 0.01, 0, z1 - 0.01))
	for cz in range(a.y, b.y + 1):
		for cx in range(a.x, b.x + 1):
			out.append(cz * dim + cx)
	return out


# --- Queries --------------------------------------------------------------------

## Plant biomass (kg/m²) of species p in cell (cx, cz) — FloraRenderer provider.
func biomass(cx: int, cz: int, p: int) -> float:
	if p < 0 or p >= _p or cx < 0 or cz < 0 or cx >= dim or cz >= dim:
		return 0.0
	return plant_mass[p * _n + cz * dim + cx]


func biomass_at(pos: Vector3, p: int) -> float:
	var c := cell_coords(pos)
	return biomass(c.x, c.y, p)


func total_biomass(p: int = -1) -> float:
	var t := 0.0
	for q in _p:
		if p >= 0 and q != p:
			continue
		for i in _n:
			t += plant_mass[q * _n + i]
	return t * cell_area()


func detritus_at(pos: Vector3) -> float:
	return detritus[cell_index(pos)]


func plankton_at(pos: Vector3) -> float:
	return plankton[cell_index(pos)]


func water_fraction_at(pos: Vector3) -> float:
	return cell_water[cell_index(pos)]


## Edible plant kg in the given cells (above the ungrazeable residual),
## weighted by preferences (PackedFloat32Array per species, 0..1).
func plant_available(cells: PackedInt32Array, prefs: PackedFloat32Array) -> float:
	var t := 0.0
	var area := cell_area()
	for p in _p:
		var w := prefs[p] if p < prefs.size() else 1.0
		if w <= 0.0:
			continue
		var res := RESIDUAL * _cap[p]
		for i in cells:
			t += maxf(0.0, plant_mass[p * _n + i] - res * _site[p * _n + i]) * w
	return t * area


## Removes up to `kg` of preferred plants from the cells (proportional to
## weighted availability). Result in `out` (no allocations).
func harvest_plants(cells: PackedInt32Array, kg: float, prefs: PackedFloat32Array, out: Harvest) -> void:
	out.clear()
	var avail := plant_available(cells, prefs)
	if avail <= 0.0 or kg <= 0.0:
		return
	var f := clampf(kg / avail, 0.0, 1.0)
	var area := cell_area()
	var tox := 0.0
	for p in _p:
		var w := prefs[p] if p < prefs.size() else 1.0
		if w <= 0.0:
			continue
		var res := RESIDUAL * _cap[p]
		for i in cells:
			var idx := p * _n + i
			var edible := maxf(0.0, plant_mass[idx] - res * _site[idx])
			var take := edible * w * f
			if take <= 0.0:
				continue
			plant_mass[idx] -= take
			var m := take * area
			out.kg += m
			out.energy += m * _energy[p]
			tox += m * _toxic[p]
	out.toxicity = tox / maxf(out.kg, 1e-9)


## Contract API: grazing at a position. prefs: PackedFloat32Array per plant
## species, Dictionary {plant_id: weight} or empty (everything).
func consume_plants(pos: Vector3, kg: float, prefs = null) -> Dictionary:
	_prefs_to_weights(prefs)
	var cells := PackedInt32Array([cell_index(pos)])
	harvest_plants(cells, kg, _w, _h)
	return _h.to_dict()


func detritus_available(cells: PackedInt32Array) -> float:
	var t := 0.0
	for i in cells:
		t += detritus[i]
	return t * cell_area()


func harvest_detritus(cells: PackedInt32Array, kg: float, out: Harvest) -> void:
	out.clear()
	var avail := detritus_available(cells)
	if avail <= 0.0 or kg <= 0.0:
		return
	var f := clampf(kg / avail, 0.0, 1.0)
	for i in cells:
		var take := detritus[i] * f
		detritus[i] -= take
		out.kg += take * cell_area()
	out.energy = out.kg * float(Food.ENERGY[Food.DETRITUS])
	out.toxicity = 0.05


func consume_detritus(pos: Vector3, kg: float) -> Dictionary:
	harvest_detritus(PackedInt32Array([cell_index(pos)]), kg, _h)
	return _h.to_dict()


func plankton_available(cells: PackedInt32Array) -> float:
	var t := 0.0
	for i in cells:
		t += plankton[i]
	return t * cell_area()


func harvest_plankton(cells: PackedInt32Array, kg: float, out: Harvest) -> void:
	out.clear()
	var avail := plankton_available(cells)
	if avail <= 0.0 or kg <= 0.0:
		return
	# Plankton always keeps a seed population.
	var f := clampf(kg / avail, 0.0, 0.95)
	for i in cells:
		var take := plankton[i] * f
		plankton[i] -= take
		out.kg += take * cell_area()
	out.energy = out.kg * float(Food.ENERGY[Food.PLANKTON])


func consume_plankton(pos: Vector3, kg: float) -> Dictionary:
	harvest_plankton(PackedInt32Array([cell_index(pos)]), kg, _h)
	return _h.to_dict()


# --- Carcasses -------------------------------------------------------------------

func add_carcass(pos: Vector3, kg: float, species_id: int) -> int:
	return carcasses.add(pos, kg, species_id)


## {} when none; else {id, pos, kg, species_id, age, toxicity}.
func nearest_carcass(pos: Vector3, radius: float) -> Dictionary:
	var i := carcasses.nearest(pos, radius)
	return carcasses.info(i) if i >= 0 else {}


func consume_carcass(id: int, kg: float) -> Dictionary:
	var i := carcasses.index_of(id)
	if i < 0:
		return {"kg": 0.0, "energy": 0.0, "toxicity": 0.0}
	var tox := carcasses.toxicity_at(i)
	var t := carcasses.take(i, kg)
	return {"kg": t, "energy": t * float(Food.ENERGY[Food.CARRION]), "toxicity": tox}


func carcass_available(x0: float, z0: float, x1: float, z1: float) -> float:
	return carcasses.kg_in_rect(x0, z0, x1, z1)


func harvest_carcass(x0: float, z0: float, x1: float, z1: float, kg: float, out: Harvest) -> void:
	out.clear()
	var r := carcasses.take_in_rect(x0, z0, x1, z1, kg)
	out.kg = r.x
	out.energy = r.x * float(Food.ENERGY[Food.CARRION])
	out.toxicity = r.y


# --- Simulation ---------------------------------------------------------------------

## Time-sliced update (see class docs).
func step(bio_dt: float) -> void:
	if bio_dt <= 0.0:
		return
	time += bio_dt
	for r in dim:
		row_pending[r] += bio_dt
	_climate_factors()
	_row_credit = minf(_row_credit + float(dim) * bio_dt / maxf(row_period, 1.0), float(rows_per_step) * 2.0)
	var rows := mini(mini(rows_per_step, dim), int(_row_credit))
	_row_credit -= float(rows)
	for k in rows:
		var r := cursor
		_process_row(r, row_pending[r])
		row_pending[r] = 0.0
		cursor = (cursor + 1) % dim
	_step_carcasses(bio_dt)


## Integrates every row now (tests, tier-D catch-up, world load).
func step_all(bio_dt: float) -> void:
	time += bio_dt
	_climate_factors()
	for r in dim:
		_process_row(r, row_pending[r] + bio_dt)
		row_pending[r] = 0.0
	_step_carcasses(bio_dt)


func _step_carcasses(dt: float) -> void:
	if carcasses.count() > 0:
		carcasses.step(dt, _air_temp_at, _carcass_to_detritus)


func _air_temp_at(pos: Vector3) -> float:
	return cell_temp[cell_index(pos)] + _t_off


func _carcass_to_detritus(pos: Vector3, kg: float) -> void:
	if kg > 0.0:
		detritus[cell_index(pos)] += kg / cell_area()


func _climate_factors() -> void:
	if climate == null:
		_t_off = 0.0
		_tw_off = 0.0
		_m_off = 0.0
		_light = 0.5
		_mult = 1.0
		_winter = 0.0
		_autumn = 0.0
		return
	var so := climate.seasonal_offset()
	_t_off = so + climate.weather_temp_offset + climate.sandbox_temp_offset
	_tw_off = so * 0.5 + climate.sandbox_temp_offset
	_m_off = climate.precipitation * 0.3 - climate.drought * 0.35 + climate.sandbox_moisture_offset
	var ph := climate.year_phase
	_light = (0.45 + 0.15 * cos((ph - 0.375) * TAU)) * (1.0 - 0.4 * climate.cloud_cover)
	_mult = maxf(0.0, climate.sandbox_resource_mult)
	_winter = clampf(cos((ph - 0.875) * TAU), 0.0, 1.0)
	var a := (ph - 0.62) / 0.08
	_autumn = exp(-a * a)


func _temp_index(t: float) -> int:
	return clampi(int((t - LUT_T_MIN) * 2.0), 0, LUT_T_STEPS - 1)


func _process_row(r: int, dt: float) -> void:
	if dt <= 0.0:
		return
	var days := dt / DAY
	var light_k := clampf(_light / 0.5, 0.0, 1.5)
	var sq_mult := sqrt(_mult)
	for p in _p:
		_turn_k[p] = exp(-(_turn[p] + _seasonal[p] * _leaf[p] * _autumn) * days)
		_r_k[p] = _rate[p] * light_k * (1.0 - _seasonal[p] * _winter) * sq_mult * days
	var kd0 := DECOMPOSITION * days
	var nut_relax := 1.0 - exp(-NUTRIENT_RELAX * days)
	var lut_t := LUT_T_STEPS
	var lut_m := LUT_M_STEPS
	var n := _n
	for cx in dim:
		var i := r * dim + cx
		var wf := cell_water[i]
		var t := cell_temp[i] + (_tw_off if wf > 0.5 else _t_off)
		var ti := clampi(int((t - LUT_T_MIN) * 2.0), 0, lut_t - 1)
		var moist := clampf(cell_moist[i] + _m_off, 0.0, 1.0)
		var mi := int(moist * 100.0)
		var fert := (0.5 + 0.5 * cell_fert[i]) * _mult
		var nut := nutrients[i]
		var nf := nut / (nut + NUTRIENT_HALF)
		var det := detritus[i]
		var total_occ := 0.0
		for p in _p:
			var k := _cap[p] * _temp_lut[p * lut_t + ti] * _moist_lut[p * lut_m + mi] * _site[p * n + i] * fert
			_k[p] = k
			var b := plant_mass[p * n + i]
			var occ := minf(b / k, 1.5) if k > 1e-5 else (1.0 if b > 1e-5 else 0.0)
			_occ[p] = occ
			total_occ += occ
		_prefix[0] = 0.0
		for j in _p:
			_prefix[j + 1] = _prefix[j] + _occ[_order[j]]
		var uptake := 0.0
		for p in _p:
			var idx := p * n + i
			var b := plant_mass[idx]
			var k := _k[p]
			if k <= 1e-6 and b <= 1e-7:
				continue
			var k_av := k * maxf(0.05, 1.0 - 0.7 * (total_occ - _occ[p]))
			var shade := _prefix[_shade_len[p]]
			var b1 := b
			if k_av > 1e-6 and b > 1e-7:
				var rd := _r_k[p] * maxf(0.15, 1.0 - 0.6 * shade) * nf
				b1 = k_av / (1.0 + (k_av / b - 1.0) * exp(-rd))
			elif k_av <= 1e-6:
				b1 = b * exp(-0.2 * days)
			if b1 > b:
				uptake += (b1 - b) * NUTRIENT_PER_KG
			else:
				det += b - b1  # dieback toward a lower capacity (drought, cold, crowding)
			var survived := b1 * _turn_k[p]
			det += b1 - survived
			b1 = survived
			if k > 1e-4 and b1 < 0.25 * k:
				# Colonisation: seed rain from neighbours + seed bank.
				var nb := _neighbour_mean(p, cx, r)
				b1 = minf(b1 + (_spread[p] * nb * SEED_YIELD + SEED_BANK * k) * days, k)
			plant_mass[idx] = b1
		# Decomposition of litter → nutrients.
		var kd := kd0 * pow(2.0, clampf(t - 20.0, -30.0, 20.0) / 10.0) * moist / (moist + 0.2) * (0.5 if wf > 0.5 else 1.0)
		var decomposed := det * (1.0 - exp(-kd))
		det -= decomposed
		nut += decomposed * NUTRIENT_PER_KG - uptake
		nut += (cell_fert[i] - nut) * nut_relax
		nutrients[i] = maxf(nut, 0.0)
		detritus[i] = det
		# Plankton.
		if wf > 0.05:
			var kp := PLANKTON_K * wf * (0.5 + cell_fert[i]) * _mult
			var rp := PLANKTON_R * light_k * MathUtil.tolerance(t, 18.0, 10.0) * nf
			var pl := maxf(plankton[i], kp * 0.01)
			pl = kp / (1.0 + (kp / pl - 1.0) * exp(-rp * days))
			var pdead := pl * (1.0 - exp(-PLANKTON_TURNOVER * days))
			plankton[i] = pl - pdead
			detritus[i] += pdead * 0.5


func _neighbour_mean(p: int, cx: int, cz: int) -> float:
	var base := p * _n
	var t := 0.0
	var c := 0
	if cx > 0:
		t += plant_mass[base + cz * dim + cx - 1]
		c += 1
	if cx < dim - 1:
		t += plant_mass[base + cz * dim + cx + 1]
		c += 1
	if cz > 0:
		t += plant_mass[base + (cz - 1) * dim + cx]
		c += 1
	if cz < dim - 1:
		t += plant_mass[base + (cz + 1) * dim + cx]
		c += 1
	return t / float(maxi(c, 1))


func _prefs_to_weights(prefs) -> void:
	for p in _p:
		_w[p] = 1.0
	if prefs is PackedFloat32Array:
		for p in mini(_p, (prefs as PackedFloat32Array).size()):
			_w[p] = prefs[p]
	elif prefs is Dictionary and not (prefs as Dictionary).is_empty():
		for p in _p:
			_w[p] = float((prefs as Dictionary).get(plant_species[p].id, 0.0))


# --- Save / load ------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"cell_size": cell_size, "dim": dim, "plants": _p, "time": time, "cursor": cursor,
		"biomass": SaveSystem.pack_f32(plant_mass), "detritus": SaveSystem.pack_f32(detritus),
		"nutrients": SaveSystem.pack_f32(nutrients), "plankton": SaveSystem.pack_f32(plankton),
		"row_pending": SaveSystem.pack_f32(row_pending), "carcasses": carcasses.to_dict(),
	}


## Restores dynamic state onto a grid already set up with the same world and
## plants. Mismatched layouts keep the freshly initialised state.
func from_dict(d: Dictionary) -> void:
	time = Serial.f(d, "time", 0.0)
	carcasses.from_dict(Serial.dict(d, "carcasses"))
	if Serial.i(d, "dim", -1) != dim or not is_equal_approx(Serial.f(d, "cell_size", -1.0), cell_size):
		push_warning("EcoGrid.from_dict: grid layout changed, plant state reset")
		return
	cursor = clampi(Serial.i(d, "cursor", 0), 0, dim - 1)
	detritus = SaveSystem.unpack_f32(d.get("detritus"), _n)
	nutrients = SaveSystem.unpack_f32(d.get("nutrients"), _n)
	plankton = SaveSystem.unpack_f32(d.get("plankton"), _n)
	row_pending = SaveSystem.unpack_f32(d.get("row_pending"), dim)
	var saved_p := Serial.i(d, "plants", _p)
	var b := SaveSystem.unpack_f32(d.get("biomass"), saved_p * _n)
	for i in mini(b.size(), plant_mass.size()):
		plant_mass[i] = b[i]


static func restore(w: WorldData, plants: Array[PlantSpecies], climate_state: ClimateState, d: Dictionary) -> EcoGrid:
	var g := EcoGrid.new()
	g.setup(w, plants, climate_state, Serial.f(d, "cell_size", DEFAULT_CELL))
	g.from_dict(d)
	return g
