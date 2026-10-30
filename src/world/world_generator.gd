class_name WorldGenerator
extends RefCounted
## Deterministic procedural world: WorldGenerator.generate(config) -> WorldData.
## Pipeline: heights → ocean/lakes (priority flood) → base moisture → rivers →
## final moisture/temperature → biomes/fertility. Same config ⇒ same world.

## Milliseconds spent in each stage of the last generate() call.
static var last_timings: Dictionary = {}


static func generate(config: Dictionary = {}) -> WorldData:
	var c := WorldConfig.sanitize(config)
	var t0 := Time.get_ticks_usec()
	var timings := {}
	var w := WorldData.new()
	w.config = c
	w.allocate(float(c["size"]), int(c["resolution"]))
	w.sea_level = float(c["sea_level"])
	var seed_value: int = c["seed"]
	var rs := (seed_value * 1103515245 + 12345) & 0x7FFFFFFF
	var rng := Rng.new(rs if rs != 0 else 1)

	HeightGen.build(w, c, seed_value)
	timings["heights"] = _ms(t0)
	var t := Time.get_ticks_usec()
	var hydro := Hydrology.new(w)
	hydro.run(c)
	timings["hydrology"] = _ms(t)
	t = Time.get_ticks_usec()
	ClimateGen.base_moisture(w, c, seed_value)
	timings["moisture"] = _ms(t)
	t = Time.get_ticks_usec()
	RiverTracer.new(w, hydro).run(c, w.moisture, rng)
	timings["rivers"] = _ms(t)
	t = Time.get_ticks_usec()
	ClimateGen.finish(w, c, seed_value)
	timings["climate_biomes"] = _ms(t)
	_finalize(w)
	timings["total"] = _ms(t0)
	last_timings = timings
	return w


static func _finalize(w: WorldData) -> void:
	var lo := INF
	var hi := -INF
	for v in w.heights:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	w.min_height = lo
	w.max_height = hi
	# Water surface never below the ground in water cells.
	for i in w.res * w.res:
		if w.water[i] != WorldData.Water.LAND and w.water_surface[i] < w.heights[i]:
			w.water_surface[i] = w.heights[i]


## Share of cells per biome id: {biome_id: fraction}.
static func biome_histogram(w: WorldData) -> Dictionary:
	var counts := {}
	for b in w.biome:
		counts[b] = int(counts.get(b, 0)) + 1
	var out := {}
	var total := float(w.biome.size())
	for k in counts:
		out[k] = float(counts[k]) / total
	return out


static func _ms(t_start: int) -> float:
	return float(Time.get_ticks_usec() - t_start) / 1000.0
