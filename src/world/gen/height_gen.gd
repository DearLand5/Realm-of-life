class_name HeightGen
extends RefCounted
## Terrain height field: warped continents + ocean margin, hills, ridged
## mountain ranges, valleys, sea-level fit to `water_fraction`, coastal
## shaping (beaches and shelves) and light thermal erosion.


static func build(w: WorldData, c: Dictionary, seed_value: int) -> void:
	var res := w.res
	var size := w.size
	var relief: float = c["relief"]
	var mountains: float = c["mountains"]
	var max_h: float = c["max_height"]
	var sea: float = c["sea_level"]

	var n_cont := _noise(seed_value + 11, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / (size * 0.5), 4, FastNoiseLite.FRACTAL_FBM)
	n_cont.domain_warp_enabled = true
	n_cont.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	n_cont.domain_warp_amplitude = size * 0.09
	n_cont.domain_warp_frequency = 1.0 / (size * 0.35)
	n_cont.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_PROGRESSIVE
	n_cont.domain_warp_fractal_octaves = 3
	var hill_oct := 3 + int(round(relief * 2.0))
	var n_hill := _noise(seed_value + 23, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 75.0, hill_oct, FastNoiseLite.FRACTAL_FBM)
	n_hill.fractal_gain = 0.42 + relief * 0.16
	var n_ridge := _noise(seed_value + 37, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / (size * 0.33), 5, FastNoiseLite.FRACTAL_RIDGED)
	n_ridge.fractal_gain = 0.45
	n_ridge.domain_warp_enabled = true
	n_ridge.domain_warp_amplitude = size * 0.05
	n_ridge.domain_warp_frequency = 1.0 / (size * 0.25)
	var n_mask := _noise(seed_value + 41, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / (size * 0.42), 2, FastNoiseLite.FRACTAL_FBM)
	var n_valley := _noise(seed_value + 53, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / (size * 0.32), 2, FastNoiseLite.FRACTAL_FBM)
	n_valley.domain_warp_enabled = true
	n_valley.domain_warp_amplitude = size * 0.06
	n_valley.domain_warp_frequency = 1.0 / (size * 0.3)
	var n_detail := _noise(seed_value + 67, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 16.0, 2, FastNoiseLite.FRACTAL_FBM)
	var n_rdet := _noise(seed_value + 89, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 38.0, 3, FastNoiseLite.FRACTAL_RIDGED)
	var n_edge := _noise(seed_value + 79, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / (size * 0.3), 3, FastNoiseLite.FRACTAL_FBM)

	var hill_amp := 4.0 + 9.0 * relief
	var ridge_amp := max_h * mountains * 0.85
	var valley_amp := 3.0 + 9.0 * relief
	var detail_amp := 0.25 + 0.9 * relief
	var mask_bias := lerpf(-0.5, 0.12, mountains)
	var edge_warp := size * 0.16
	var half := size * 0.5
	var hs := w.heights
	for iz in res:
		var z := -half + float(iz) * w.cell
		for ix in res:
			var x := -half + float(ix) * w.cell
			# Organic coastline: the border falloff is evaluated on warped coordinates.
			var ex := x + n_edge.get_noise_2d(x, z) * edge_warp
			var ez := z + n_edge.get_noise_2d(x + 911.0, z - 457.0) * edge_warp
			var edge := minf(0.5 - absf(ex / size), 0.5 - absf(ez / size)) * 2.0
			var fall := smoothstep(0.0, 0.45, edge)
			var cont := n_cont.get_noise_2d(x, z) * 1.5 + 0.28
			var shape := cont * fall - (1.0 - fall) * 0.9
			var land := smoothstep(-0.1, 0.45, shape)
			var h := shape * 24.0
			h += n_hill.get_noise_2d(x, z) * hill_amp * (0.35 + 0.65 * land)
			var mm := smoothstep(0.0, 0.3, n_mask.get_noise_2d(x, z) + mask_bias) * land
			if mm > 0.0:
				var r := (n_ridge.get_noise_2d(x, z) + 1.0) * 0.5
				h += r * r * mm * ridge_amp
				# Gullies and spurs on mountain flanks.
				h += (n_rdet.get_noise_2d(x, z) + 0.3) * mm * r * (2.0 + 6.0 * relief)
			var v := absf(n_valley.get_noise_2d(x, z))
			h -= (1.0 - smoothstep(0.0, 0.13, v)) * valley_amp * land * (1.0 - 0.6 * mm)
			h += n_detail.get_noise_2d(x, z) * detail_amp
			hs[iz * res + ix] = h

	# Fit sea level so that `water_fraction` of the map lies below it.
	var wf: float = c["water_fraction"]
	var shift := sea - GridOps.percentile(hs, wf) if wf > 0.001 else sea - _min(hs) + 0.5
	for i in hs.size():
		hs[i] = _shape_coast(hs[i] + shift - sea) + sea
	_thermal_erosion(hs, res, w.cell, 10)


## Coastal profile: flat beaches just above the waterline, gentle shelves
## below it, and a bounded ocean floor. Input/output: height above sea.
static func _shape_coast(x: float) -> float:
	if x >= 0.0:
		var b := 3.2
		if x >= b:
			return x
		return b * _hermite(x / b, 0.22, 1.0)
	var s := 7.0
	var d := -x
	var y: float
	if d < s:
		y = s * _hermite(d / s, 0.35, 1.0)
	else:
		y = d
	# Ocean floor flattens out around -26 m.
	y = 26.0 * (1.0 - exp(-y / 26.0)) * 1.15
	return -y


## Cubic Hermite from (0,0) slope k0 to (1,1) slope k1.
static func _hermite(t: float, k0: float, k1: float) -> float:
	var t2 := t * t
	var t3 := t2 * t
	return (t3 - 2.0 * t2 + t) * k0 + (-2.0 * t3 + 3.0 * t2) + (t3 - t2) * k1


## Moves material down slopes steeper than the talus angle. Jacobi-style
## (deltas into a second buffer) so no sweep direction leaves artefacts.
static func _thermal_erosion(hs: PackedFloat32Array, res: int, cell: float, iterations: int) -> void:
	var talus := cell * 0.7
	var delta := PackedFloat32Array()
	delta.resize(hs.size())
	for it in iterations:
		delta.fill(0.0)
		for iz in range(1, res - 1):
			var row := iz * res
			for ix in range(1, res - 1):
				var i := row + ix
				var h := hs[i]
				var d := h - hs[i + 1]
				if d > talus:
					var m := (d - talus) * 0.12
					delta[i] -= m
					delta[i + 1] += m
				d = h - hs[i - 1]
				if d > talus:
					var m := (d - talus) * 0.12
					delta[i] -= m
					delta[i - 1] += m
				d = h - hs[i + res]
				if d > talus:
					var m := (d - talus) * 0.12
					delta[i] -= m
					delta[i + res] += m
				d = h - hs[i - res]
				if d > talus:
					var m := (d - talus) * 0.12
					delta[i] -= m
					delta[i - res] += m
		for i in hs.size():
			hs[i] += delta[i]


static func _noise(s: int, type: int, freq: float, octaves: int, fractal: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = type
	n.frequency = freq
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	return n


static func _min(a: PackedFloat32Array) -> float:
	var m := INF
	for v in a:
		m = minf(m, v)
	return m
