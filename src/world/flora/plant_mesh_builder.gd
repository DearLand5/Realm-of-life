class_name PlantMeshBuilder
extends RefCounted
## Low-level geometry accumulator for procedural plants.
## Vertex layout read by shaders/plant.gdshader:
##   COLOR.r = ambient occlusion, COLOR.g = per-card random variant,
##   UV = card/bark coordinates (y up along the part),
##   UV2 = (part kind, wind sway weight 0 at the base .. 1 at the top).

enum Kind { BARK, LEAF, GRASS, NEEDLE, FROND, PETAL, BLADE, RIBBON, CACTUS, CAP, STEM, SILHOUETTE, HEAD }

var height: float = 1.0
var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var uv2s := PackedVector2Array()
var idx := PackedInt32Array()


func _init(plant_height: float = 1.0) -> void:
	height = maxf(plant_height, 0.01)


func sway(y: float) -> float:
	return pow(clampf(y / height, 0.0, 1.0), 1.5)


func _vert(p: Vector3, n: Vector3, uv: Vector2, kind: int, ao: float, variant: float) -> int:
	verts.append(p)
	normals.append(n.normalized() if n.length_squared() > 1e-8 else Vector3.UP)
	colors.append(Color(ao, variant, 0.0, 1.0))
	uvs.append(uv)
	uv2s.append(Vector2(float(kind), sway(p.y)))
	return verts.size() - 1


## Generalised cylinder along `path` (rings use parallel-transport frames).
func tube(path: PackedVector3Array, radii: PackedFloat32Array, sides: int, kind: int = Kind.BARK, ao_base: float = 0.55) -> void:
	var n := path.size()
	if n < 2:
		return
	sides = maxi(sides, 3)
	var t0 := (path[1] - path[0]).normalized()
	var ref := Vector3.RIGHT if absf(t0.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var n1 := t0.cross(ref).normalized()
	var along := 0.0
	var base := verts.size()
	var prev_t := t0
	for k in n:
		var t := (path[mini(k + 1, n - 1)] - path[maxi(k - 1, 0)]).normalized()
		# Parallel transport of the frame.
		var axis := prev_t.cross(t)
		if axis.length_squared() > 1e-10:
			n1 = n1.rotated(axis.normalized(), prev_t.angle_to(t))
		prev_t = t
		var n2 := t.cross(n1).normalized()
		if k > 0:
			along += path[k].distance_to(path[k - 1])
		var ao := lerpf(ao_base, 1.0, clampf(path[k].y / height, 0.0, 1.0))
		for s in sides + 1:
			var a := float(s) / float(sides) * TAU
			var dir := n1 * cos(a) + n2 * sin(a)
			_vert(path[k] + dir * radii[k], dir, Vector2(float(s) / float(sides), along), kind, ao, 0.5)
	var ring := sides + 1
	for k in n - 1:
		for s in sides:
			var a := base + k * ring + s
			var b := a + 1
			var c := a + ring
			var d := c + 1
			_tri_out(a, b, d, normals[a])
			_tri_out(a, d, c, normals[a])


## Flat card from its bottom-centre. right/up are full extents.
func card(base_center: Vector3, right: Vector3, up: Vector3, kind: int, normal: Vector3, ao0: float, ao1: float, variant: float) -> void:
	var a := _vert(base_center - right * 0.5, normal, Vector2(0, 0), kind, ao0, variant)
	var b := _vert(base_center + right * 0.5, normal, Vector2(1, 0), kind, ao0, variant)
	var c := _vert(base_center + right * 0.5 + up, normal, Vector2(1, 1), kind, ao1, variant)
	var d := _vert(base_center - right * 0.5 + up, normal, Vector2(0, 1), kind, ao1, variant)
	idx.append_array([a, b, c, a, c, d])


## Card centred on `center` (leaf clusters).
func card_centered(center: Vector3, right: Vector3, up: Vector3, kind: int, normal: Vector3, ao: float, variant: float) -> void:
	card(center - up * 0.5, right, up, kind, normal, ao * 0.9, ao, variant)


## Ribbon through `points`; `half_widths` are the side vectors per point.
func strip(points: PackedVector3Array, half_widths: PackedVector3Array, kind: int, normal_hint: Vector3, ao0: float, ao1: float, variant: float) -> void:
	var n := points.size()
	if n < 2:
		return
	var base := verts.size()
	for k in n:
		var t := float(k) / float(n - 1)
		var along := (points[mini(k + 1, n - 1)] - points[maxi(k - 1, 0)]).normalized()
		var side := half_widths[k]
		var nrm := side.cross(along).normalized()
		if nrm.dot(normal_hint) < 0.0:
			nrm = -nrm
		nrm = (nrm + normal_hint * 0.8).normalized()
		var ao := lerpf(ao0, ao1, t)
		_vert(points[k] - side, nrm, Vector2(0.0, t), kind, ao, variant)
		_vert(points[k] + side, nrm, Vector2(1.0, t), kind, ao, variant)
	for k in n - 1:
		var a := base + k * 2
		idx.append_array([a, a + 1, a + 3, a, a + 3, a + 2])


## Surface of revolution around +Y: profile = [(radius, y)], from the top down.
func lathe(center: Vector3, profile: PackedVector2Array, sides: int, kind: int, ao: float) -> void:
	var base := verts.size()
	var n := profile.size()
	for k in n:
		var r := profile[k].x
		var y := profile[k].y
		var slope := Vector2(0, 0)
		if n > 1:
			var pa := profile[maxi(k - 1, 0)]
			var pb := profile[mini(k + 1, n - 1)]
			slope = pb - pa
		for s in sides + 1:
			var a := float(s) / float(sides) * TAU
			var dir := Vector3(cos(a), 0.0, sin(a))
			# Normal perpendicular to the profile tangent (dr, dy).
			var nrm := (dir * -slope.y + Vector3.UP * slope.x)
			if nrm.dot(dir * r + Vector3.UP * 0.2) < 0.0:
				nrm = -nrm
			_vert(center + dir * r + Vector3(0, y, 0), nrm, Vector2(float(s) / float(sides), float(k) / float(maxi(n - 1, 1))), kind, ao, 0.5)
	var ring := sides + 1
	for k in n - 1:
		for s in sides:
			var a := base + k * ring + s
			var b := a + 1
			var c := a + ring
			var d := c + 1
			_tri_out(a, b, d, normals[a])
			_tri_out(a, d, c, normals[a])


## Appends a triangle wound so it faces along `outward`.
func _tri_out(a: int, b: int, c: int, outward: Vector3) -> void:
	var nrm := (verts[c] - verts[a]).cross(verts[b] - verts[a])
	if nrm.dot(outward) >= 0.0:
		idx.append_array([a, b, c])
	else:
		idx.append_array([a, c, b])


func triangle_count() -> int:
	return idx.size() / 3


func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if idx.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
