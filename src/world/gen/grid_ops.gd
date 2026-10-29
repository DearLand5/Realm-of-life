class_name GridOps
extends RefCounted
## Fast whole-grid helpers on square row-major PackedFloat32Array grids
## (res × res). Used by the world generator and the renderers.


## Separable box blur, in place. `radius` in cells.
static func box_blur(a: PackedFloat32Array, res: int, radius: int) -> void:
	if radius <= 0:
		return
	var tmp := PackedFloat32Array()
	tmp.resize(a.size())
	var inv := 1.0 / float(radius * 2 + 1)
	# Horizontal pass (clamped edges) a -> tmp.
	for iz in res:
		var row := iz * res
		var acc := 0.0
		for k in range(-radius, radius + 1):
			acc += a[row + clampi(k, 0, res - 1)]
		for ix in res:
			tmp[row + ix] = acc * inv
			acc += a[row + mini(ix + radius + 1, res - 1)] - a[row + maxi(ix - radius, 0)]
	# Vertical pass tmp -> a.
	for ix in res:
		var acc := 0.0
		for k in range(-radius, radius + 1):
			acc += tmp[clampi(k, 0, res - 1) * res + ix]
		for iz in res:
			a[iz * res + ix] = acc * inv
			acc += tmp[mini(iz + radius + 1, res - 1) * res + ix] - tmp[maxi(iz - radius, 0) * res + ix]


## Chamfer distance transform (metres) from every cell where `mask[i] != 0`.
## Also propagates `level` (e.g. water surface height) of the nearest source.
## Returns {dist: PackedFloat32Array, level: PackedFloat32Array}.
static func distance_from(mask: PackedByteArray, res: int, cell: float, src_level: PackedFloat32Array, far: float = 1.0e6) -> Dictionary:
	var n := res * res
	var dist := PackedFloat32Array()
	dist.resize(n)
	var lvl := PackedFloat32Array()
	lvl.resize(n)
	for i in n:
		if mask[i] != 0:
			dist[i] = 0.0
			lvl[i] = src_level[i]
		else:
			dist[i] = far
			lvl[i] = 0.0
	var d1 := cell
	var d2 := cell * 1.41421356
	# Forward pass.
	for iz in res:
		var row := iz * res
		for ix in res:
			var i := row + ix
			var best := dist[i]
			if best == 0.0:
				continue
			var bl := lvl[i]
			if ix > 0:
				var c := dist[i - 1] + d1
				if c < best:
					best = c
					bl = lvl[i - 1]
			if iz > 0:
				var j := i - res
				var c2 := dist[j] + d1
				if c2 < best:
					best = c2
					bl = lvl[j]
				if ix > 0:
					var c3 := dist[j - 1] + d2
					if c3 < best:
						best = c3
						bl = lvl[j - 1]
				if ix < res - 1:
					var c4 := dist[j + 1] + d2
					if c4 < best:
						best = c4
						bl = lvl[j + 1]
			dist[i] = best
			lvl[i] = bl
	# Backward pass.
	for iz in range(res - 1, -1, -1):
		var row := iz * res
		for ix in range(res - 1, -1, -1):
			var i := row + ix
			var best := dist[i]
			if best == 0.0:
				continue
			var bl := lvl[i]
			if ix < res - 1:
				var c := dist[i + 1] + d1
				if c < best:
					best = c
					bl = lvl[i + 1]
			if iz < res - 1:
				var j := i + res
				var c2 := dist[j] + d1
				if c2 < best:
					best = c2
					bl = lvl[j]
				if ix < res - 1:
					var c3 := dist[j + 1] + d2
					if c3 < best:
						best = c3
						bl = lvl[j + 1]
				if ix > 0:
					var c4 := dist[j - 1] + d2
					if c4 < best:
						best = c4
						bl = lvl[j - 1]
			dist[i] = best
			lvl[i] = bl
	return {"dist": dist, "level": lvl}


## Slope (rise/run) per cell from central differences.
static func slopes(h: PackedFloat32Array, res: int, cell: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(res * res)
	var inv := 1.0 / (2.0 * cell)
	for iz in res:
		var zm := maxi(iz - 1, 0) * res
		var zp := mini(iz + 1, res - 1) * res
		var row := iz * res
		for ix in res:
			var dx := (h[row + mini(ix + 1, res - 1)] - h[row + maxi(ix - 1, 0)]) * inv
			var dz := (h[zp + ix] - h[zm + ix]) * inv
			s[row + ix] = sqrt(dx * dx + dz * dz)
	return s


## Value at a fractional percentile (0..1) of the array.
static func percentile(a: PackedFloat32Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var sorted := a.duplicate()
	sorted.sort()
	return sorted[clampi(int(p * float(sorted.size() - 1)), 0, sorted.size() - 1)]


static func has_nan(a: PackedFloat32Array) -> bool:
	for v in a:
		if is_nan(v) or is_inf(v):
			return true
	return false
