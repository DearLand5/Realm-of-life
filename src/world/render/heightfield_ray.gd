class_name HeightfieldRay
extends RefCounted
## Ray vs. WorldData height field (tap-to-select on terrain). Marches in
## half-cell steps inside the world box, then refines by bisection.


## Returns the hit point or Vector3.INF. include_water: stop at water surfaces.
static func cast(w: WorldData, origin: Vector3, dir: Vector3, max_dist: float = 3000.0, include_water: bool = false) -> Vector3:
	if w == null or dir.length_squared() < 1e-12:
		return Vector3.INF
	var d := dir.normalized()
	var half := w.size * 0.5
	# Clip the ray to the world's XZ box and height range.
	var t0 := 0.0
	var t1 := max_dist
	for axis in [0, 2]:
		var o: float = origin[axis]
		var v: float = d[axis]
		if absf(v) < 1e-9:
			if o < -half or o > half:
				return Vector3.INF
			continue
		var ta := (-half - o) / v
		var tb := (half - o) / v
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t0 > t1:
		return Vector3.INF
	var step := w.cell * 0.5
	var t := t0
	var prev_t := t
	if _above(w, origin + d * t, include_water) <= 0.0:
		return origin + d * t
	while prev_t < t1:
		var above := _above(w, origin + d * t, include_water)
		if above <= 0.0:
			var lo := prev_t
			var hi := t
			for k in 14:
				var mid := (lo + hi) * 0.5
				if _above(w, origin + d * mid, include_water) > 0.0:
					lo = mid
				else:
					hi = mid
			var hit := origin + d * hi
			if not include_water:
				hit.y = w.height_at(hit.x, hit.z)
			return hit
		prev_t = t
		# Big strides high above the ground (safe for slopes up to ~1.5).
		t = minf(t + maxf(step, minf(above * 0.4, 20.0)), t1)
		if t == prev_t:
			break
	return Vector3.INF


static func _above(w: WorldData, p: Vector3, include_water: bool) -> float:
	var g := w.height_at(p.x, p.z)
	if include_water and w.water_type_at(p.x, p.z) != WorldData.Water.LAND:
		g = maxf(g, w.water_surface_at(p.x, p.z))
	return p.y - g
