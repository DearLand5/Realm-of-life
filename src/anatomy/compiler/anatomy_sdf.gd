class_name AnatomySdf
extends RefCounted
## Signed distance field of the SDF body of an AnatomyModel (geometry space).
## Reference implementation used by the mesher, editor picking (sphere
## tracing), and anatomical fit checks. Negative = inside the body.


## Round cone (capsule with different end radii) in primitive-local space where
## the axis runs from (0,0,0) to (0,h,0). Exact (Inigo Quilez formulation).
static func sd_round_cone_local(p: Vector3, h: float, r1: float, r2: float) -> float:
	var q := Vector2(Vector2(p.x, p.z).length(), p.y)
	var b := (r1 - r2) / maxf(h, 1e-6)
	if absf(b) >= 0.999:
		return minf(q.length() - r1, (q - Vector2(0.0, h)).length() - r2)
	var a := sqrt(1.0 - b * b)
	var k := q.dot(Vector2(-b, a))
	if k < 0.0:
		return q.length() - r1
	if k > a * h:
		return (q - Vector2(0.0, h)).length() - r2
	return q.dot(Vector2(a, b)) - r1


## Distance to one primitive (approximate for flattened cross-sections).
static func primitive_distance(pr: AnatomyModel.Primitive, p: Vector3) -> float:
	var local := pr.inv_basis * (p - pr.a)
	if pr.kind == 1:
		# Ellipsoid (IQ bound-corrected approximation).
		var r := pr.radii
		var k0 := (local / r).length()
		var k1 := (local / (r * r)).length()
		if k1 < 1e-9:
			return -minf(r.x, minf(r.y, r.z))
		return k0 * (k0 - 1.0) / k1
	var fl := pr.flatten
	if not is_equal_approx(fl, 1.0):
		local.z /= fl
	var d := sd_round_cone_local(local, (pr.b - pr.a).length(), pr.ra, pr.rb)
	return d * minf(1.0, fl)


## Body SDF with smooth unions. `prims` defaults to all primitives.
static func distance(m: AnatomyModel, p: Vector3) -> float:
	var d := 1.0e9
	for pr in m.primitives:
		if not pr.aabb.has_point(p) and d < 1.0e8:
			# Outside the padded box: use a cheap lower bound, no blending.
			var c := pr.aabb.get_center()
			var bound := (p - c).length() - pr.aabb.size.length() * 0.5
			if bound > d:
				continue
		d = MathUtil.smin(d, primitive_distance(pr, p), pr.blend)
	return d


## Index of the primitive (and thus bone) closest to p.
static func nearest_primitive(m: AnatomyModel, p: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in m.primitives.size():
		var d := primitive_distance(m.primitives[i], p)
		if d < bd:
			bd = d
			best = i
	return best


static func gradient(m: AnatomyModel, p: Vector3, eps: float = 0.002) -> Vector3:
	var dx := distance(m, p + Vector3(eps, 0, 0)) - distance(m, p - Vector3(eps, 0, 0))
	var dy := distance(m, p + Vector3(0, eps, 0)) - distance(m, p - Vector3(0, eps, 0))
	var dz := distance(m, p + Vector3(0, 0, eps)) - distance(m, p - Vector3(0, 0, eps))
	var g := Vector3(dx, dy, dz)
	return g.normalized() if g.length_squared() > 1e-12 else Vector3.UP


## Sphere-traces a ray (geometry space). Returns {hit: bool, position, normal,
## primitive, bone, t}.
static func raycast(m: AnatomyModel, origin: Vector3, dir: Vector3, max_dist: float = 100.0) -> Dictionary:
	var d := dir.normalized()
	var box := m.aabb.grow(0.05)
	var t := 0.0
	# Skip to the bounding box.
	var hit_box = box.intersects_ray(origin, d)
	if hit_box == null and not box.has_point(origin):
		return {"hit": false}
	if hit_box != null and not box.has_point(origin):
		t = maxf(0.0, (hit_box - origin).length() - 0.01)
	for _i in 160:
		var p := origin + d * t
		var dist := distance(m, p)
		if dist < 0.0005:
			var pi := nearest_primitive(m, p)
			return {"hit": true, "position": p, "normal": gradient(m, p), "primitive": pi,
				"bone": m.primitives[pi].bone if pi >= 0 else 0, "t": t}
		t += maxf(dist * 0.9, 0.0005)
		if t > max_dist or (not box.has_point(p) and t > 0.05 and dist > box.size.length()):
			break
	return {"hit": false}
