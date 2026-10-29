class_name ClimateGen
extends RefCounted
## Annual climate grids: moisture (noise + orographic rain shadow + water
## proximity), temperature (latitude band + altitude lapse + noise), then
## biome classification and soil fertility.


## Moisture before rivers exist (used to choose river sources).
static func base_moisture(w: WorldData, c: Dictionary, seed_value: int) -> void:
	var res := w.res
	var size := w.size
	var div: float = c["biome_diversity"]
	var n_m := FastNoiseLite.new()
	n_m.seed = seed_value + 71
	n_m.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_m.frequency = 1.0 / (size * lerpf(0.42, 0.18, div))
	n_m.fractal_octaves = 4
	n_m.domain_warp_enabled = true
	n_m.domain_warp_amplitude = size * 0.08
	n_m.domain_warp_frequency = 1.0 / (size * 0.3)
	var amp := 0.16 + 0.34 * div
	var east := (seed_value & 1) == 0   # prevailing wind blows towards +x when true
	var half := size * 0.5
	var k_base := 0.0012 * w.cell
	var k_lift := 0.16
	var recharge := 0.0006 * w.cell
	var m := w.moisture
	for iz in res:
		var row := iz * res
		var z := -half + float(iz) * w.cell
		var air := 1.0
		var prev_h := w.sea_level
		for step in res:
			var ix := step if east else res - 1 - step
			var i := row + ix
			var hh := maxf(w.heights[i], w.sea_level)
			var orog := 0.0
			if w.water[i] != WorldData.Water.LAND:
				air = minf(1.0, air + 0.03 * w.cell)
			else:
				var lift := clampf((hh - prev_h) / w.cell, 0.0, 1.5)
				var rain := air * (k_base + k_lift * lift)
				air = clampf(air - rain + recharge, 0.1, 1.0)
				orog = minf(1.0, lift * 1.4) * air
			prev_h = hh
			var x := -half + float(ix) * w.cell
			var base := 0.5 + n_m.get_noise_2d(x, z) * amp * 2.0
			m[i] = base * 0.6 + air * 0.4 + orog * 0.2 - 0.03
	GridOps.box_blur(m, res, maxi(1, int(round(4.0 / w.cell))))


## Final moisture (water proximity), temperature, biomes, fertility.
static func finish(w: WorldData, c: Dictionary, seed_value: int) -> void:
	var res := w.res
	var n := res * res
	var size := w.size
	var div: float = c["biome_diversity"]
	var sea := w.sea_level
	# Distances to any water and to fresh water.
	var any_mask := PackedByteArray()
	any_mask.resize(n)
	var fresh_mask := PackedByteArray()
	fresh_mask.resize(n)
	var ocean_mask := PackedByteArray()
	ocean_mask.resize(n)
	for i in n:
		var wt := w.water[i]
		any_mask[i] = 1 if wt != WorldData.Water.LAND else 0
		fresh_mask[i] = 1 if (wt == WorldData.Water.LAKE or wt == WorldData.Water.RIVER) else 0
		ocean_mask[i] = 1 if wt == WorldData.Water.OCEAN else 0
	var dw := GridOps.distance_from(any_mask, res, w.cell, w.water_surface)
	w.water_dist = dw["dist"]
	w.shore_level = dw["level"]
	var d_fresh: PackedFloat32Array = GridOps.distance_from(fresh_mask, res, w.cell, w.water_surface)["dist"]
	var d_ocean: PackedFloat32Array = GridOps.distance_from(ocean_mask, res, w.cell, w.water_surface)["dist"]
	var m_off: float = c["moisture_offset"]
	for i in n:
		if any_mask[i] != 0:
			w.moisture[i] = 1.0
			continue
		var v := w.moisture[i]
		v += 0.34 * exp(-d_fresh[i] / 20.0) + 0.14 * exp(-d_ocean[i] / 45.0)
		w.moisture[i] = clampf(v + m_off, 0.0, 1.0)
	_temperature(w, c, seed_value)
	var slope := GridOps.slopes(w.heights, res, w.cell)
	_biomes(w, slope, d_ocean)
	_fertility(w, slope, d_fresh, seed_value, div)


static func _temperature(w: WorldData, c: Dictionary, seed_value: int) -> void:
	var res := w.res
	var size := w.size
	var div: float = c["biome_diversity"]
	var n_t := FastNoiseLite.new()
	n_t.seed = seed_value + 83
	n_t.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_t.frequency = 1.0 / (size * 0.28)
	n_t.fractal_octaves = 3
	var t_amp := 1.2 + 3.5 * div
	var warm: float = c["warm_edge_temp"]
	var cold: float = c["cold_edge_temp"]
	var offset: float = c["temperature_offset"]
	var lapse: float = c["lapse_rate"]
	var south := str(c["warm_side"]) != "north"
	var half := size * 0.5
	for iz in res:
		var z := -half + float(iz) * w.cell
		var lat := z / size + 0.5
		if not south:
			lat = 1.0 - lat
		var t_lat := lerpf(cold, warm, lat)
		for ix in res:
			var i := iz * res + ix
			var x := -half + float(ix) * w.cell
			var surface := w.heights[i]
			if w.water[i] != WorldData.Water.LAND:
				surface = w.water_surface[i]
			var t := t_lat + n_t.get_noise_2d(x, z) * t_amp + offset
			t -= maxf(0.0, surface - w.sea_level) * lapse
			w.temperature[i] = t


static func _biomes(w: WorldData, slope: PackedFloat32Array, d_ocean: PackedFloat32Array) -> void:
	var beach_reach := 10.0 + 2.0 * w.cell
	for i in w.res * w.res:
		match w.water[i]:
			WorldData.Water.OCEAN:
				w.biome[i] = Biomes.OCEAN
			WorldData.Water.LAKE:
				w.biome[i] = Biomes.LAKE
			WorldData.Water.RIVER:
				w.biome[i] = Biomes.RIVER
			_:
				var hs := w.heights[i] - w.sea_level
				var b := Biomes.classify(w.temperature[i], w.moisture[i], hs, slope[i])
				if b == Biomes.BEACH and d_ocean[i] > beach_reach:
					b = Biomes.classify(w.temperature[i], w.moisture[i], maxf(hs, 1.25), slope[i])
				w.biome[i] = b


static func _fertility(w: WorldData, slope: PackedFloat32Array, d_fresh: PackedFloat32Array, seed_value: int, div: float) -> void:
	var n_f := FastNoiseLite.new()
	n_f.seed = seed_value + 97
	n_f.frequency = 1.0 / 40.0
	n_f.fractal_octaves = 2
	var half := w.size * 0.5
	for iz in w.res:
		for ix in w.res:
			var i := iz * w.res + ix
			var b := w.biome[i]
			if Biomes.is_water(b):
				w.fertility[i] = 0.5 if b != Biomes.OCEAN else 0.35
				continue
			var s := minf(slope[i], 1.0)
			var mf := MathUtil.tolerance(w.moisture[i], 0.62, 0.3)
			var tf := MathUtil.tolerance(w.temperature[i], 19.0, 13.0)
			var flood := exp(-d_fresh[i] / 16.0) * (1.0 - s)
			var f := 0.12 + 0.58 * mf * tf + 0.3 * flood - 0.35 * s
			f += n_f.get_noise_2d(-half + ix * w.cell, -half + iz * w.cell) * (0.06 + 0.08 * div)
			f *= 0.35 + 0.65 * Biomes.vegetation(b) if b != Biomes.BEACH else 0.4
			w.fertility[i] = clampf(f, 0.0, 1.0)
