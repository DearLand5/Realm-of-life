class_name PopulationManager
extends RefCounted
## Population tiers C/D: sectors (default 32 m) × species pools.
##   step(bio_dt)   sub-steps every C sector (≤ MAX_SUBSTEP) and every
##                  D sector each D_INTERVAL calls with its accumulated time;
##                  then migration between neighbour sectors (gene flow) and a
##                  budgeted number of resampling events (recombination +
##                  mutation of fitness-weighted parents → real evolution).
##   fold(individuals, sector) / unfold(sector, max) convert between live
##   Individuals and pools preserving counts, energies, ages and genotypes.
## Dynamics: PoolDynamics (same physiology as BiologySystem).

const DEFAULT_SECTOR := 32.0
const MAX_SUBSTEP := 21600.0
const D_INTERVAL := 5
const RESAMPLE_FRACTION := 0.25        # births / count that trigger a resample
const MIGRATION_RATE := 0.15 / Units.SECONDS_PER_DAY
const MIN_DEME_COUNT := 0.5
const DAY := Units.SECONDS_PER_DAY

var world: WorldData
var eco: EcoGrid
var climate: ClimateState
var sector_size: float = DEFAULT_SECTOR
var sdim: int = 1
var sectors: Array[PopSector] = []
var mutation_settings: Dictionary = {}
var rng: Rng
var dynamics: PoolDynamics
var max_genome_builds_per_step: int = 4
## Tier-C sectors stepped per call (0 = all). Skipped sectors keep their
## accumulated time and are served first next call (time-slicing).
var sector_budget: int = 0
## Target interval between steps of one sector (biological seconds), see step().
var sector_period: float = 300.0
var _sector_credit := 0.0
var _mig_pending := PackedFloat32Array()
var _mig_credit := 0.0
var _mig_cursor := 0
var migration_enabled := true
var time: float = 0.0
var _calls: int = 0
var _cursor: int = 0
var _queue: Array[SpeciesPool] = []


func setup(w: WorldData, grid: EcoGrid, climate_state: ClimateState, seed_value: int = 1,
		settings: Dictionary = {}, sector: float = DEFAULT_SECTOR) -> void:
	world = w
	eco = grid
	climate = climate_state
	mutation_settings = settings
	sector_size = sector
	rng = Rng.new(seed_value)
	dynamics = PoolDynamics.new(grid, climate_state)
	sdim = maxi(1, int(ceil(w.size / sector)))
	sectors.clear()
	var half := w.size * 0.5
	for sz in sdim:
		for sx in sdim:
			var s := PopSector.new()
			s.index = sz * sdim + sx
			s.sx = sx
			s.sz = sz
			s.x0 = -half + float(sx) * sector
			s.z0 = -half + float(sz) * sector
			s.x1 = minf(s.x0 + sector, half)
			s.z1 = minf(s.z0 + sector, half)
			s.center = Vector3((s.x0 + s.x1) * 0.5, 0.0, (s.z0 + s.z1) * 0.5)
			s.center.y = w.height_at(s.center.x, s.center.z)
			s.area = (s.x1 - s.x0) * (s.z1 - s.z0)
			s.cells = grid.cells_in_rect(s.x0, s.z0, s.x1, s.z1)
			var wf := 0.0
			var t := 0.0
			var m := 0.0
			for ci in s.cells:
				wf += grid.cell_water[ci]
				t += grid.cell_temp[ci]
				m += grid.cell_moist[ci]
				if grid.cell_water[ci] > 0.3:
					s.water_cells.append(ci)
			var nc := float(maxi(s.cells.size(), 1))
			s.water_frac = wf / nc
			s.land_frac = 1.0 - s.water_frac
			s.base_temp = t / nc
			s.base_temp_water = s.base_temp
			s.base_moist = m / nc
			s.fresh_water = _has_fresh_water(s)
			sectors.append(s)


func _has_fresh_water(s: PopSector) -> bool:
	for k in 9:
		var x := lerpf(s.x0, s.x1, (float(k % 3) + 0.5) / 3.0)
		var z := lerpf(s.z0, s.z1, (float(k / 3) + 0.5) / 3.0)
		var wt := world.water_type_at(x, z)
		if wt == WorldData.Water.LAKE or wt == WorldData.Water.RIVER:
			return true
	return false


# --- Geometry / queries -------------------------------------------------------------

func sector_index(pos: Vector3) -> int:
	var half := world.size * 0.5
	var sx := clampi(int(floor((pos.x + half) / sector_size)), 0, sdim - 1)
	var sz := clampi(int(floor((pos.z + half) / sector_size)), 0, sdim - 1)
	return sz * sdim + sx


func sector_center(i: int) -> Vector3:
	return sectors[i].center


func set_sector_tier(i: int, tier: int) -> void:
	sectors[i].tier = tier


func pool(sector: int, species_id: int) -> SpeciesPool:
	return sectors[sector].pools.get(species_id)


func pools_of(species_id: int) -> Array[SpeciesPool]:
	var out: Array[SpeciesPool] = []
	for s in sectors:
		var p: SpeciesPool = s.pools.get(species_id)
		if p != null:
			out.append(p)
	return out


func total_count(species_id: int) -> float:
	var t := 0.0
	for p in pools_of(species_id):
		t += p.count
	return t


## {species_id: count} over all pools.
func species_counts() -> Dictionary:
	var out := {}
	for s in sectors:
		for sid in s.pools:
			out[sid] = float(out.get(sid, 0.0)) + (s.pools[sid] as SpeciesPool).count
	return out


## [{genome, weight}] — weight = individuals represented (for history/means).
func genome_samples(species_id: int) -> Array:
	var out := []
	for p in pools_of(species_id):
		for s in p.samples:
			out.append({"genome": s.genome, "weight": s.weight * p.count})
	return out


## Count-weighted mean of real trait values.
func trait_means(species_id: int, trait_ids: Array) -> Dictionary:
	var out := {}
	var wsum := 0.0
	for id in trait_ids:
		out[id] = 0.0
	for p in pools_of(species_id):
		for s in p.samples:
			var w := s.weight * p.count
			wsum += w
			for id in trait_ids:
				out[id] = float(out[id]) + s.genome.value(id) * w
	if wsum > 0.0:
		for id in trait_ids:
			out[id] = float(out[id]) / wsum
	return out


# --- Seeding ------------------------------------------------------------------------

## Creates pools of a species: `total` individuals spread over `where` (or
## every sector where the founder can live), `n_samples` founder variants.
func seed_species(species_id: int, founder: Genome, total: float, where: PackedInt32Array = PackedInt32Array(),
		variation: float = 0.04, n_samples: int = 6) -> void:
	var ph := Phenotype.build(founder)
	var proto := PoolSample.create(founder, ph, eco.plant_species)
	var targets := where
	if targets.is_empty():
		for s in sectors:
			if proto.habitat(s.land_frac, s.water_frac) > 0.3:
				targets.append(s.index)
	if targets.is_empty():
		return
	var variants: Array[PoolSample] = []
	for k in maxi(1, n_samples):
		if k == 0 or variation <= 0.0:
			variants.append(proto.clone())
		else:
			var g := founder.copy_shared_plan()
			Genetics.founder_variation(g, rng, variation)
			variants.append(PoolSample.create(g, null, eco.plant_species))
	_seed_variants(species_id, variants, total, targets)


## Seeds pools from explicit genotypes (equal shares): used by experiments
## and the sandbox "release these animals" tool.
func seed_genotypes(species_id: int, genomes: Array, total: float, where: PackedInt32Array = PackedInt32Array()) -> void:
	var variants: Array[PoolSample] = []
	for g in genomes:
		variants.append(PoolSample.create(g as Genome, null, eco.plant_species))
	var targets := where
	if targets.is_empty() and not variants.is_empty():
		for s in sectors:
			if variants[0].habitat(s.land_frac, s.water_frac) > 0.3:
				targets.append(s.index)
	if targets.is_empty() or variants.is_empty():
		return
	_seed_variants(species_id, variants, total, targets)


func _seed_variants(species_id: int, variants: Array[PoolSample], total: float, targets: PackedInt32Array) -> void:
	var per := total / float(targets.size())
	for si in targets:
		var p := _get_or_create(sectors[si], species_id)
		var incoming: Array[PoolSample] = []
		for v in variants:
			var c := v.clone()
			c.weight = 1.0
			c.energy = 0.7
			incoming.append(c)
		var share := per / maxf(p.count + per, 1e-9)
		p.merge_samples(incoming, share)
		p.count += per


func _get_or_create(sec: PopSector, species_id: int) -> SpeciesPool:
	var p: SpeciesPool = sec.pools.get(species_id)
	if p == null:
		p = SpeciesPool.new()
		p.species_id = species_id
		p.sector = sec.index
		sec.pools[species_id] = p
	return p


# --- Simulation ---------------------------------------------------------------------

func step(bio_dt: float) -> void:
	if bio_dt <= 0.0:
		return
	time += bio_dt
	_calls += 1
	var n := sectors.size()
	# Sectors are stepped about once per sector_period biological seconds (spread
	# evenly over frames); at high time scales sector_budget limits instead.
	_sector_credit = minf(_sector_credit + float(n) * bio_dt / maxf(sector_period, 1.0), float(n))
	var allowed := int(_sector_credit)
	if sector_budget > 0:
		allowed = mini(allowed, sector_budget)
	var processed := 0
	var next_cursor := -1
	for k in n:
		var idx := (_cursor + k) % n
		var s := sectors[idx]
		if s.pools.is_empty():
			s.pending_dt = 0.0
			continue
		s.pending_dt += bio_dt
		if s.tier >= PopSector.Tier.D and (_calls + idx) % D_INTERVAL != 0:
			continue
		if processed >= allowed:
			if next_cursor < 0:
				next_cursor = idx
			continue
		processed += 1
		var dt := s.pending_dt
		s.pending_dt = 0.0
		_step_sector(s, dt)
	_cursor = next_cursor if next_cursor >= 0 else 0
	_sector_credit -= float(processed)
	if migration_enabled:
		_migrate_sliced(bio_dt)
	_resample_budgeted()


func _step_sector(s: PopSector, dt: float) -> void:
	var n := maxi(1, int(ceil(dt / MAX_SUBSTEP)))
	var sub := dt / float(n)
	for k in n:
		_sector_env(s)
		dynamics.step_sector(s, sub)
		if s.pools.is_empty():
			return
	for p in s.pools.values():
		var pool := p as SpeciesPool
		if not pool.resample_queued and pool.births_since_resample >= RESAMPLE_FRACTION * maxf(pool.count, 1.0):
			pool.resample_queued = true
			_queue.append(pool)


## Daily-mean environment of a sector (same offsets as ClimateState sampling).
func _sector_env(s: PopSector) -> void:
	var so := 0.0
	var wo := 0.0
	var so_s := 0.0
	var moist := 0.0
	var light := 0.5
	if climate != null:
		so = climate.seasonal_offset()
		wo = climate.weather_temp_offset
		so_s = climate.sandbox_temp_offset
		moist = climate.precipitation * 0.3 - climate.drought * 0.35 + climate.sandbox_moisture_offset
		light = (0.45 + 0.15 * cos((climate.year_phase - 0.375) * TAU)) * (1.0 - 0.4 * climate.cloud_cover)
	s.t_air = s.base_temp + so + wo + so_s
	s.t_water = maxf(-1.8, s.base_temp_water + so * 0.5 + so_s)
	s.humidity = clampf(s.base_moist + moist, 0.0, 1.0)
	s.light = light
	s.oxygen_water = clampf(1.0 - maxf(0.0, s.t_water - 4.0) * 0.018, 0.25, 1.0)


func _neighbours(i: int) -> PackedInt32Array:
	var s := sectors[i]
	var out := PackedInt32Array()
	if s.sx > 0:
		out.append(i - 1)
	if s.sx < sdim - 1:
		out.append(i + 1)
	if s.sz > 0:
		out.append(i - sdim)
	if s.sz < sdim - 1:
		out.append(i + sdim)
	return out


## Dispersal to neighbour sectors weighted by habitat quality and crowding.
## Migration of a slice of sectors per call (each about once per
## sector_period), with the time each of them accumulated.
func _migrate_sliced(bio_dt: float) -> void:
	var n := sectors.size()
	if _mig_pending.size() != n:
		_mig_pending.resize(n)
		_mig_cursor = 0
	for i in n:
		_mig_pending[i] += bio_dt
	_mig_credit = minf(_mig_credit + float(n) * bio_dt / maxf(sector_period, 1.0), float(n))
	var count := int(_mig_credit)
	if count <= 0:
		return
	_mig_credit -= float(count)
	var list: Array[PopSector] = []
	var dts := PackedFloat32Array()
	for k in count:
		var idx := (_mig_cursor + k) % n
		list.append(sectors[idx])
		dts.append(_mig_pending[idx])
		_mig_pending[idx] = 0.0
	_mig_cursor = (_mig_cursor + count) % n
	_migrate_sectors(list, dts)


func _migrate(dt: float) -> void:
	var dts := PackedFloat32Array()
	dts.resize(sectors.size())
	dts.fill(dt)
	_migrate_sectors(sectors, dts)


func _migrate_sectors(list: Array[PopSector], dts: PackedFloat32Array) -> void:
	var moves := []
	for si in list.size():
		var s := list[si]
		var dt := dts[si]
		for p in s.pools.values():
			var pool := p as SpeciesPool
			if pool.count < 0.2 or pool.samples.is_empty():
				continue
			var proto := pool.samples[0]
			var mobility := clampf(proto.speed, 0.1, 3.0)
			var pressure := 0.3 + (1.0 - pool.mean_energy())
			var frac := 1.0 - exp(-MIGRATION_RATE * mobility * pressure * dt)
			if frac * pool.count < 0.01:
				continue
			var here := pool.count / maxf(s.area * proto.habitat(s.land_frac, s.water_frac), 1.0)
			var nb := _neighbours(s.index)
			var weights := PackedFloat32Array()
			var wsum := 0.0
			for ni in nb:
				var t := sectors[ni]
				var h := proto.habitat(t.land_frac, t.water_frac)
				var w := 0.0
				if h >= 0.15:
					var other: SpeciesPool = t.pools.get(pool.species_id)
					var dens := (other.count if other != null else 0.0) / maxf(t.area * h, 1.0)
					w = h * exp(-dens / maxf(here, 1e-6))
				weights.append(w)
				wsum += w
			if wsum <= 0.0:
				continue
			for k in nb.size():
				if weights[k] > 0.0:
					moves.append([pool, nb[k], pool.count * frac * weights[k] / wsum])
	for m in moves:
		var src: SpeciesPool = m[0]
		var amount := minf(float(m[2]), src.count)
		if amount <= 0.0:
			continue
		var dst := _get_or_create(sectors[int(m[1])], src.species_id)
		var share := amount / maxf(dst.count + amount, 1e-9)
		dst.merge_samples(src.samples, share)
		if dst.count <= 0.0:
			dst.classes = src.classes.duplicate()
		else:
			for c in SpeciesPool.CLASSES:
				dst.classes[c] = dst.classes[c] * (1.0 - share) + src.classes[c] * share
		dst.count += amount
		dst.migrated_in += amount
		src.count -= amount


## Recombination + mutation of fitness-weighted parents replaces the
## lightest samples (budgeted: Phenotype.build is the expensive part).
func _resample_budgeted() -> void:
	var builds := 0
	while not _queue.is_empty() and builds < max_genome_builds_per_step:
		var pool: SpeciesPool = _queue.pop_front()
		pool.resample_queued = false
		if pool.count < MIN_DEME_COUNT * 0.1 or pool.samples.is_empty():
			continue
		builds += resample(pool)


func resample(pool: SpeciesPool) -> int:
	var frac := clampf(pool.births_since_resample / maxf(pool.count, 1.0), 0.0, 0.5)
	pool.births_since_resample = 0.0
	var k := pool.samples.size()
	var r := clampi(int(ceil(float(SpeciesPool.MAX_SAMPLES) * frac)), 1, SpeciesPool.MAX_SAMPLES / 2)
	r = mini(r, maxi(1, int(ceil(pool.count))))
	var parent_w := []
	for s in pool.samples:
		parent_w.append(s.weight * (s.fecundity + 1e-12))
	var mean_e := pool.mean_energy()
	var sexual := pool.samples[0].needs_mate
	var kids: Array[PoolSample] = []
	for j in r:
		var mom := pool.samples[maxi(rng.weighted_index(parent_w), 0)]
		var g: Genome
		if sexual:
			var dad := pool.samples[maxi(rng.weighted_index(parent_w), 0)]
			g = Genetics.sexual(mom.genome, dad.genome, rng, mutation_settings)
		else:
			g = Genetics.asexual(mom.genome, rng, mutation_settings)
		var kid := PoolSample.create(g, null, eco.plant_species)
		kid.energy = mean_e
		kids.append(kid)
	# Make room by merging the rarest genotypes into their closest relatives,
	# then give the new genotypes the share of the pool they were born into.
	pool.compact(SpeciesPool.MAX_SAMPLES - r)
	var kid_share := clampf(frac, 0.04, 0.4)
	for s in pool.samples:
		s.weight *= (1.0 - kid_share)
	for kid in kids:
		kid.weight = kid_share / float(r)
		pool.samples.append(kid)
	pool.normalize_weights()
	return r


# --- Fold / unfold ---------------------------------------------------------------------

const _STAGE_CLASS := {&"egg": 0, &"juvenile": 0, &"adolescent": 1, &"adult": 2, &"elder": 3}


## Turns live individuals into pool members of a sector (counts, energies,
## age classes and genotypes are kept; eggs count as juveniles).
func fold(individuals: Array[Individual], sector: int) -> void:
	var by_species := {}
	for ind in individuals:
		if ind == null or not ind.alive:
			continue
		if not by_species.has(ind.species_id):
			by_species[ind.species_id] = []
		(by_species[ind.species_id] as Array).append(ind)
	for sid in by_species:
		var list: Array = by_species[sid]
		var pool := _get_or_create(sectors[sector], int(sid))
		var n := float(list.size())
		var incoming: Array[PoolSample] = []
		var cls := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
		var by_genome := {}
		for ind in list:
			var individual := ind as Individual
			cls[int(_STAGE_CLASS.get(individual.stage, 2))] += 1.0
			var s: PoolSample = by_genome.get(individual.genome)
			if s == null:
				s = PoolSample.create(individual.genome, individual.get_phenotype(), eco.plant_species)
				s.weight = 0.0
				s.energy = 0.0
				by_genome[individual.genome] = s
				incoming.append(s)
			s.energy = (s.energy * s.weight + individual.energy_fraction()) / (s.weight + 1.0)
			s.weight += 1.0
		var share := n / (pool.count + n)
		pool.merge_samples(incoming, share)
		for c in SpeciesPool.CLASSES:
			pool.classes[c] = pool.classes[c] * (1.0 - share) + cls[c] / n * share
		pool.count += n


## Takes up to `max_count` individuals out of a sector's pools (shared across
## species ∝ counts). Genotypes, condition and ages follow the pool's
## distribution (stratified sampling — no jumps); the remainder stays pooled.
func unfold(sector: int, max_count: int) -> Array[Individual]:
	var out: Array[Individual] = []
	var sec := sectors[sector]
	var total := sec.total_count()
	if total <= 0.0 or max_count <= 0:
		return out
	var ids := sec.pools.keys()
	ids.sort()
	for sid in ids:
		var pool: SpeciesPool = sec.pools[sid]
		# Stochastic rounding keeps sparse pools (count < 1 per sector) visible
		# while preserving the expected number of individuals.
		var whole := int(floor(pool.count))
		if rng.randf() < pool.count - float(whole):
			whole += 1
		var quota := mini(whole, maxi(1, int(round(float(max_count) * pool.count / total))))
		quota = mini(quota, max_count - out.size())
		if quota <= 0:
			continue
		var cum := PackedFloat32Array()
		var acc := 0.0
		for s in pool.samples:
			acc += s.weight
			cum.append(acc)
		var ccum := PackedFloat32Array()
		var cacc := 0.0
		for c in SpeciesPool.CLASSES:
			cacc += pool.classes[c]
			ccum.append(cacc)
		var offset := rng.randf()
		var taken := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
		for k in quota:
			var u := (float(k) + offset) / float(quota)
			var si := 0
			while si < cum.size() - 1 and cum[si] < u * acc:
				si += 1
			var uc := fmod(u * 7.31 + offset, 1.0)
			var ci := 0
			while ci < 3 and ccum[ci] < uc * cacc:
				ci += 1
			taken[ci] += 1.0
			out.append(_make_individual(pool, pool.samples[si], ci, sec))
		var n1 := maxf(0.0, pool.count - float(quota))
		for c in SpeciesPool.CLASSES:
			pool.classes[c] = maxf(0.0, pool.classes[c] * pool.count - taken[c])
		pool.count = n1
		pool.normalize_classes()
		if pool.count < PoolDynamics.MIN_COUNT:
			sec.pools.erase(sid)
	return out


func _make_individual(pool: SpeciesPool, s: PoolSample, cls: int, sec: PopSector) -> Individual:
	var ind := Individual.new(s.genome)
	ind.set_phenotype(s.phenotype)
	ind.species_id = pool.species_id
	ind.generation = s.genome.generation
	ind.seed = rng.range_i(1, 1 << 30)
	var p := s.pp
	ind.sex = Individual.sex_for(p, rng)
	var age := 0.0
	match cls:
		0:
			age = rng.range_f(0.05, 1.0) * p.juvenile_s
			ind.stage = &"juvenile"
		1:
			age = lerpf(p.juvenile_s, p.maturity_age, rng.randf())
			ind.stage = &"adolescent"
		2:
			age = lerpf(p.maturity_age, p.elder_age, rng.randf())
			ind.stage = &"adult"
		_:
			age = p.elder_age * rng.range_f(1.0, 1.25)
			ind.stage = &"elder"
	ind.age = age
	ind.growth = LifeHistory.expected_growth(p, age)
	if cls >= 2:
		ind.growth = maxf(ind.growth, Reproduction.MATURE_GROWTH + 0.05)
	ind.larval = p.metamorphosis and cls == 0
	ind.energy = clampf(s.energy + rng.gauss(0.0, 0.03), 0.0, 1.0) * ind.max_energy()
	ind.body_temp = p.body_temp_set
	ind.position = _random_position(sec, s)
	ind.heading = rng.range_f(-PI, PI)
	return ind


func _random_position(sec: PopSector, s: PoolSample) -> Vector3:
	var want_water := s.water_ok > s.land_ok
	for k in 8:
		var x := rng.range_f(sec.x0, sec.x1)
		var z := rng.range_f(sec.z0, sec.z1)
		var wet := world.is_water(x, z)
		if wet == want_water:
			return Vector3(x, world.height_at(x, z), z)
	return sec.center


# --- Demes / speciation support ---------------------------------------------------

## Connected groups of sectors where the species lives (4-neighbourhood).
## [{sectors: PackedInt32Array, count: float, samples: [{genome, weight}]}]
func demes(species_id: int) -> Array:
	var seen := {}
	var out := []
	for s in sectors:
		var p: SpeciesPool = s.pools.get(species_id)
		if p == null or p.count < MIN_DEME_COUNT or seen.has(s.index):
			continue
		var deme_sectors := PackedInt32Array()
		var count := 0.0
		var samples := []
		var stack: Array[int] = [s.index]
		seen[s.index] = true
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			var cp: SpeciesPool = sectors[cur].pools.get(species_id)
			deme_sectors.append(cur)
			count += cp.count
			for smp in cp.samples:
				samples.append({"genome": smp.genome, "weight": smp.weight * cp.count})
			for ni in _neighbours(cur):
				if seen.has(ni):
					continue
				var np: SpeciesPool = sectors[ni].pools.get(species_id)
				if np != null and np.count >= MIN_DEME_COUNT:
					seen[ni] = true
					stack.append(ni)
		out.append({"sectors": deme_sectors, "count": count, "samples": samples})
	return out


## Removes every pool of a species (extinction clean-up, "remove species" tool).
func remove_species(species_id: int) -> void:
	for sec in sectors:
		sec.pools.erase(species_id)


## Moves the pools of `from_id` in the given sectors to a new species id.
func reassign_species(sector_list: PackedInt32Array, from_id: int, to_id: int) -> void:
	for si in sector_list:
		var sec := sectors[si]
		var p: SpeciesPool = sec.pools.get(from_id)
		if p == null:
			continue
		sec.pools.erase(from_id)
		p.species_id = to_id
		var existing: SpeciesPool = sec.pools.get(to_id)
		if existing == null:
			sec.pools[to_id] = p
		else:
			var share := p.count / maxf(existing.count + p.count, 1e-9)
			existing.merge_samples(p.samples, share)
			existing.count += p.count


# --- Save / load ---------------------------------------------------------------------

func to_dict() -> Dictionary:
	var codec := GenomeCodec.new()
	var ids := {}
	var genomes := []
	var pl := []
	for s in sectors:
		for p in s.pools.values():
			var pd := (p as SpeciesPool).to_dict(ids, genomes)
			pl.append(pd)
	for g in genomes:
		codec.add(g)
	return {
		"sector_size": sector_size, "sdim": sdim, "time": time, "calls": _calls, "pending": sectors.map(func(x: PopSector) -> float: return x.pending_dt), "rng": rng.get_state(),
		"pools": pl, "genomes": codec.to_dict(),
		"tiers": sectors.map(func(x: PopSector) -> int: return x.tier),
	}


## Restores pools onto a manager already set up for the same world.
func from_dict(d: Dictionary) -> void:
	for s in sectors:
		s.pools.clear()
	_queue.clear()
	time = Serial.f(d, "time", 0.0)
	_calls = Serial.i(d, "calls", 0)
	var st = d.get("rng", null)
	if st is float or st is int:
		rng.set_state(int(st))
	var codec := GenomeCodec.from_dict(Serial.dict(d, "genomes"))
	var phenos := {}
	var tiers := Serial.arr(d, "tiers")
	var pend := Serial.arr(d, "pending")
	for i in mini(pend.size(), sectors.size()):
		sectors[i].pending_dt = float(pend[i])
	for i in mini(tiers.size(), sectors.size()):
		sectors[i].tier = int(tiers[i])
	for pd in Serial.arr(d, "pools"):
		if not (pd is Dictionary):
			continue
		var si := Serial.i(pd, "sector", -1)
		if si < 0 or si >= sectors.size():
			continue
		var pool := _get_or_create(sectors[si], Serial.i(pd, "species", -1))
		pool.count = Serial.f(pd, "count", 0.0)
		var cl := Serial.arr(pd, "classes")
		for c in mini(cl.size(), SpeciesPool.CLASSES):
			pool.classes[c] = float(cl[c])
		pool.births_since_resample = Serial.f(pd, "births", 0.0)
		pool.last_net = Serial.f(pd, "net", 0.0)
		for sd in Serial.arr(pd, "samples"):
			if not (sd is Dictionary):
				continue
			var g := codec.genome(Serial.i(sd, "g", -1))
			if g == null:
				continue
			var ph: Phenotype = phenos.get(g)
			if ph == null:
				ph = Phenotype.build(g)
				phenos[g] = ph
			var s := PoolSample.create(g, ph, eco.plant_species)
			s.weight = Serial.f(sd, "w", 1.0)
			s.energy = Serial.f(sd, "e", 0.6)
			pool.samples.append(s)
		if pool.samples.is_empty():
			sectors[si].pools.erase(pool.species_id)
		else:
			pool.normalize_weights()
			pool.normalize_classes()
