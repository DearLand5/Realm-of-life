class_name PartPicker
extends RefCounted
## Picks the BodyPart under a ray on a compiled AnatomyModel (geometry space).
##   1. sphere-traces the SDF body (AnatomySdf.raycast) → nearest bone → part;
##   2. tests point parts (eyes, horns, mouths... as spheres around their
##      accessory origin), thin tube chains and membranes (capsules along
##      their bones) — these are not part of the SDF;
##   3. returns the closest hit along the ray. Point parts win near ties
##      (they sit on the surface and are small).
## `slop` widens small targets (geometry units ≈ a finger's width).

const SKIP_ACCESSORIES: Array[StringName] = [&"organ", &"foot", &"cell_organelle", &"tube", &"membrane", &"fluke", &"shell"]


## Returns {hit: bool, part_id, instance, position, normal, t}.
static func pick(m: AnatomyModel, origin: Vector3, dir: Vector3, slop: float = 0.0, include_organs: bool = false) -> Dictionary:
	var d := dir.normalized()
	var best := {"hit": false, "t": INF}
	if not m.primitives.is_empty():
		var r := AnatomySdf.raycast(m, origin, d, 1.0e4)
		if r.get("hit", false):
			var bone: AnatomyModel.Bone = m.bones[int(r["bone"])]
			best = {"hit": true, "part_id": bone.part_id, "instance": bone.instance,
				"position": r["position"], "normal": r["normal"], "t": float(r["t"]), "body": true}
	var bias := slop * 1.5
	# Point parts.
	for a in m.accessories:
		if SKIP_ACCESSORIES.has(a.type) and not (include_organs and a.type == &"organ"):
			continue
		var rad := maxf(a.size * 0.6, slop)
		var c := a.transform.origin
		if a.type in [&"horn", &"spike", &"claw", &"whisker"]:
			c = a.transform.origin + a.transform.basis.y.normalized() * a.size * 0.35
		var th := _ray_sphere(origin, d, c, rad)
		if th >= 0.0 and th < float(best["t"]) + bias:
			best = {"hit": true, "part_id": a.part_id, "instance": a.instance, "position": origin + d * th,
				"normal": (origin + d * th - c).normalized(), "t": th, "body": false}
	# Thin chains (tubes) and membranes: capsules along bones.
	for b in m.bones:
		if b.part_id < 0:
			continue
		var rad2 := 0.0
		if b.thin:
			rad2 = maxf(maxf(b.r0, b.r1), slop * 0.8)
		elif b.kind in [&"wing", &"fin"]:
			rad2 = maxf(b.length * 0.35, slop)
		else:
			continue
		var th2 := _ray_capsule(origin, d, b.start, b.end, rad2)
		var allowance := bias * 0.5 if best.get("body", false) else 0.0
		if th2 >= 0.0 and th2 < float(best["t"]) + allowance:
			best = {"hit": true, "part_id": b.part_id, "instance": b.instance, "position": origin + d * th2,
				"normal": -d, "t": th2, "body": false}
	return best


## Distance along the ray to a sphere hit (or the closest approach when the
## ray passes within the radius); -1 when missed.
static func _ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := c - o
	var tc := oc.dot(d)
	if tc < 0.0:
		return -1.0
	var d2 := oc.length_squared() - tc * tc
	if d2 > r * r:
		return -1.0
	return maxf(0.0, tc - sqrt(maxf(r * r - d2, 0.0)))


static func _ray_capsule(o: Vector3, d: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var far := o + d * 1.0e4
	var pts := Geometry3D.get_closest_points_between_segments(o, far, a, b)
	var dist := (pts[0] as Vector3).distance_to(pts[1])
	if dist > r:
		return -1.0
	return maxf(0.0, (pts[0] as Vector3).distance_to(o) - sqrt(maxf(r * r - dist * dist, 0.0)))


## First compiled instance of a part (or -1).
static func first_instance(m: AnatomyModel, part_id: int) -> int:
	for i in m.instances.size():
		if m.instances[i].part_id == part_id:
			return i
	return -1


## Geometry-space centre used for handles and camera focus of a part instance.
static func instance_center(m: AnatomyModel, inst_idx: int) -> Vector3:
	if inst_idx < 0 or inst_idx >= m.instances.size():
		return m.aabb.get_center()
	var inst := m.instances[inst_idx]
	if not inst.bones.is_empty():
		var c := Vector3.ZERO
		for bi in inst.bones:
			c += m.bones[bi].mid()
		return c / float(inst.bones.size())
	if not inst.accessories.is_empty():
		return m.accessories[inst.accessories[0]].transform.origin
	return inst.anchor
