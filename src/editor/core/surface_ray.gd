class_name SurfaceRay
extends RefCounted
## Ray queries against the body SDF while a part is being dragged: the dragged
## part (and its subtree) is excluded so the ray finds the surface *behind*
## it, i.e. the parent body the part should slide over.


## Model view without the primitives of `excluded` part ids (shares bones).
static func filtered(m: AnatomyModel, excluded: Dictionary) -> AnatomyModel:
	var f := AnatomyModel.new()
	f.bones = m.bones
	f.aabb = m.aabb
	for pr in m.primitives:
		var b := m.bones[pr.bone]
		if not excluded.has(b.part_id):
			f.primitives.append(pr)
	return f


## Ids of a part and all its descendants.
static func subtree_ids(plan: BodyPlan, id: int) -> Dictionary:
	var out := {id: true}
	for d in plan.descendants_of(id):
		out[d.id] = true
	return out


## First surface hit point of the ray on `fm`, or null.
static func surface_point(fm: AnatomyModel, origin: Vector3, dir: Vector3) -> Variant:
	if fm.primitives.is_empty():
		return null
	var r := AnatomySdf.raycast(fm, origin, dir, 1.0e4)
	return r["position"] if r.get("hit", false) else null


## Middle of the body along the ray (inside point) for volume placement of
## organs; null when the ray misses the body.
static func volume_point(fm: AnatomyModel, origin: Vector3, dir: Vector3) -> Variant:
	if fm.primitives.is_empty():
		return null
	var r := AnatomySdf.raycast(fm, origin, dir, 1.0e4)
	if not r.get("hit", false):
		return null
	var t0: float = r["t"]
	var step := maxf(fm.aabb.size.length() / 80.0, 0.001)
	var t := t0 + step
	for _i in 160:
		if AnatomySdf.distance(fm, origin + dir * t) > 0.0:
			break
		t += step
	return origin + dir * ((t0 + t) * 0.5)


## Intersection of the ray with the plane through `point` facing `normal`.
static func plane_point(origin: Vector3, dir: Vector3, point: Vector3, normal: Vector3) -> Vector3:
	var denom := dir.dot(normal)
	if absf(denom) < 1e-6:
		return point
	var t := (point - origin).dot(normal) / denom
	return origin + dir * t
