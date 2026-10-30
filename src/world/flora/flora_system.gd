class_name FloraSystem
extends RefCounted
## Generates the plant species of a world from PlantTemplates, matched to the
## biomes that actually occur (climate optima measured from the world grids),
## and provides a default static biomass provider for FloraRenderer.

const MIN_SPECIES := 8
const MAX_SPECIES := 14


## 8–14 species spanning forms and covering every significant biome.
static func generate_species(world: WorldData, rng: Rng) -> Array[PlantSpecies]:
	var stats := _climate_stats(world)
	var div: float = float(world.config.get("biome_diversity", 0.5))
	var present := 0
	for b in stats:
		if int(b) >= 0 and float(stats[b]["frac"]) > 0.015:
			present += 1
	var target := clampi(MIN_SPECIES + int(round(float(present) * 0.35 + div * 2.0)), MIN_SPECIES, MAX_SPECIES)
	# Score templates by how much of the world they fit.
	var scores: Array[float] = []
	for t in PlantTemplates.LIST:
		var s := 0.0
		for b in t["biomes"]:
			if stats.has(b):
				s += float(stats[b]["frac"])
		scores.append(s * rng.range_f(0.85, 1.15))
	var chosen: Array[int] = []
	# 1) Every significant biome (largest first) gets the template it is primary for.
	var biome_ids: Array = stats.keys()
	biome_ids.sort_custom(func(a, b) -> bool: return float(stats[a]["frac"]) > float(stats[b]["frac"]))
	for b in biome_ids:
		if float(stats[b]["frac"]) < 0.012 or chosen.size() >= target:
			continue
		var best := -1
		var best_s := -1.0
		for k in PlantTemplates.LIST.size():
			var t: Dictionary = PlantTemplates.LIST[k]
			if k in chosen or (t["biomes"] as Array).is_empty() or t["biomes"][0] != b:
				continue
			# Canopy species define a biome's look, so they win for their primary biome.
			var s: float = scores[k] + (1.0 if int(t["layer"]) == 0 else 0.0)
			if s > best_s:
				best_s = s
				best = k
		if best >= 0:
			chosen.append(best)
	# 2) Fill by score, preferring forms not yet present.
	while chosen.size() < target:
		var best := -1
		var best_s := 0.0
		for k in PlantTemplates.LIST.size():
			if k in chosen or scores[k] <= 0.0:
				continue
			var s := scores[k]
			if _has_form(chosen, PlantTemplates.LIST[k]["form"]):
				s *= 0.35
			if s > best_s:
				best_s = s
				best = k
		if best < 0:
			break
		chosen.append(best)
	var out: Array[PlantSpecies] = []
	var used_names := {}
	for k in chosen:
		var sp := _instantiate(PlantTemplates.LIST[k], stats, rng, used_names)
		sp.id = out.size()
		out.append(sp)
	return out


static func _has_form(chosen: Array[int], form: StringName) -> bool:
	for k in chosen:
		if PlantTemplates.LIST[k]["form"] == form:
			return true
	return false


static func _instantiate(t: Dictionary, stats: Dictionary, rng: Rng, used_names: Dictionary) -> PlantSpecies:
	var sp := PlantSpecies.new()
	sp.form = t["form"]
	sp.aquatic = bool(t.get("aquatic", false))
	# Climate optimum = fraction-weighted mean of the template's biomes in this world.
	var wsum := 0.0
	var temp := 0.0
	var moist := 0.0
	for b in t["biomes"]:
		if stats.has(b):
			var f: float = stats[b]["frac"]
			wsum += f
			temp += float(stats[b]["temp"]) * f
			moist += float(stats[b]["moist"]) * f
	if wsum > 0.0:
		temp /= wsum
		moist /= wsum
	else:
		temp = 15.0
		moist = 0.5
	sp.temp_opt = temp + rng.gauss(0.0, 0.8)
	sp.temp_tol = float(t["ttol"]) * rng.range_f(0.85, 1.15)
	sp.moist_opt = clampf(moist + rng.gauss(0.0, 0.03), 0.0, 1.0)
	sp.moist_tol = float(t["mtol"]) * rng.range_f(0.85, 1.15)
	var hr: Array = t["h"]
	sp.height = rng.range_f(float(hr[0]), float(hr[1]))
	sp.capacity = float(t["cap"]) * rng.range_f(0.85, 1.15)
	sp.growth_rate = float(t["growth"]) * rng.range_f(0.8, 1.2)
	sp.nutrition = float(t["nut"]) * rng.range_f(0.9, 1.1)
	sp.toughness = clampf(float(t["tough"]) + rng.gauss(0.0, 0.05), 0.0, 1.0)
	var tox: float = t["tox"]
	if sp.form == &"mushroom":
		tox = rng.range_f(0.0, 0.85)   # some mushrooms are deadly
	sp.toxicity = clampf(tox + rng.gauss(0.0, 0.03), 0.0, 1.0)
	sp.seasonal = clampf(float(t["seasonal"]) + rng.gauss(0.0, 0.05), 0.0, 1.0)
	sp.spread = clampf(0.03 + sp.growth_rate * 0.15, 0.01, 0.2)
	# Instance mass scales with the cube of relative height.
	sp.biomass_per_instance = float(t["bpi"]) * pow(sp.height / ((float(hr[0]) + float(hr[1])) * 0.5), 2.0)
	var leaves: Array = t["leaf"]
	sp.color_leaf = _jitter(leaves[rng.range_i(0, leaves.size() - 1)], rng, 0.04)
	var flowers: Array = t.get("flower", [Color(0.95, 0.85, 0.35)])
	sp.color_flower = _jitter(flowers[rng.range_i(0, flowers.size() - 1)], rng, 0.05)
	sp.color_trunk = _jitter(Color(0.47, 0.38, 0.28) if sp.form != &"conifer" else Color(0.44, 0.34, 0.26), rng, 0.04)
	if sp.form == &"broadleaf_tree" and sp.temp_opt < 16.0 and rng.chance(0.35):
		sp.color_trunk = Color(0.82, 0.8, 0.74)   # birch-like pale bark
	sp.seed_value = rng.range_i(1, 0x3FFFFFFF)
	sp.name = _name(t, sp, rng, used_names)
	return sp


static func _jitter(c: Color, rng: Rng, amount: float) -> Color:
	return Color(clampf(c.r + rng.gauss(0.0, amount), 0.0, 1.0), clampf(c.g + rng.gauss(0.0, amount), 0.0, 1.0), clampf(c.b + rng.gauss(0.0, amount), 0.0, 1.0))


static func _name(t: Dictionary, sp: PlantSpecies, rng: Rng, used: Dictionary) -> String:
	var nouns: Array = t["names"]
	var pool := "any"
	if sp.moist_opt > 0.78:
		pool = "wet"
	elif sp.temp_opt < 5.0:
		pool = "cold"
	elif sp.temp_opt > 21.0:
		pool = "warm"
	for attempt in 12:
		var noun: Array = nouns[rng.range_i(0, nouns.size() - 1)]
		var eps: Array = PlantTemplates.EPITHETS[pool if attempt < 6 else "any"]
		var ep: Array = eps[rng.range_i(0, eps.size() - 1)]
		var g := {"m": 0, "f": 1, "n": 2}.get(str(noun[1]), 0) as int
		var n := "%s %s" % [noun[0], ep[g]]
		if not used.has(n):
			used[n] = true
			return n
	return "%s №%d" % [nouns[0][0], used.size() + 1]


## Per-biome {frac, temp, moist} (fractions of all cells), plus pseudo-biomes
## for fresh-water shores and water bodies (see PlantTemplates.W_*).
static func _climate_stats(w: WorldData) -> Dictionary:
	var acc := {}
	var n := w.res * w.res
	var step := 2 if w.res > 200 else 1
	var total := 0
	var has_dist := w.water_dist.size() == n
	for iz in range(0, w.res, step):
		for ix in range(0, w.res, step):
			var i := iz * w.res + ix
			total += 1
			var b := int(w.biome[i])
			var wt := w.water[i]
			if wt == WorldData.Water.OCEAN:
				b = PlantTemplates.W_OCEAN
			elif wt != WorldData.Water.LAND:
				b = PlantTemplates.W_FRESHWATER
			_acc(acc, b, w.temperature[i], w.moisture[i])
			if wt == WorldData.Water.LAND and has_dist and w.water_dist[i] < 6.0 and w.shore_level[i] > w.sea_level + 0.2:
				_acc(acc, PlantTemplates.W_FRESH, w.temperature[i], w.moisture[i])
	for b in acc:
		var a: Dictionary = acc[b]
		var c := float(a["n"])
		a["temp"] = float(a["t"]) / c
		a["moist"] = float(a["m"]) / c
		a["frac"] = c / float(total)
	return acc


static func _acc(acc: Dictionary, b: int, t: float, m: float) -> void:
	if not acc.has(b):
		acc[b] = {"n": 0, "t": 0.0, "m": 0.0}
	var a: Dictionary = acc[b]
	a["n"] = int(a["n"]) + 1
	a["t"] = float(a["t"]) + t
	a["m"] = float(a["m"]) + m


## Default biomass provider (no ecosystem yet): Callable(cx, cz, plant) -> kg/m².
static func default_biomass_provider(world: WorldData, species: Array[PlantSpecies], cell_size: float = 8.0) -> Callable:
	var sb := StaticBiomass.new(world, species, cell_size)
	# A lambda keeps `sb` alive (bound method callables do not hold a reference).
	return func(cx: int, cz: int, p: int) -> float: return sb.sample(cx, cz, p)
