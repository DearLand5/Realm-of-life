class_name WaterMesher
extends RefCounted
## Water surface geometry: ocean/lake chunk grids (flat at the water surface,
## extended one cell under the shore), an outer ocean ring to the horizon and
## river ribbons along WorldData.rivers. UV2.x carries the water depth.

const OUTER_DEPTH := 30.0


## Ocean/lake surface for one chunk; null when the chunk has no such water.
static func build_chunk(w: WorldData, x0: int, z0: int, cells: int) -> ArrayMesh:
	var x1 := mini(x0 + cells, w.res - 1)
	var z1 := mini(z0 + cells, w.res - 1)
	var any := false
	var shore := false
	for iz in range(maxi(z0 - 1, 0), mini(z1 + 2, w.res)):
		for ix in range(maxi(x0 - 1, 0), mini(x1 + 2, w.res)):
			var i := iz * w.res + ix
			if _open(w, i):
				any = true
				if w.water_surface[i] - w.heights[i] < 3.0:
					shore = true
			else:
				shore = true
	if not any:
		return null
	var step := 1 if shore else maxi(1, cells / 4)
	var xs := TerrainMesher._samples(x0, x1, step)
	var zs := TerrainMesher._samples(z0, z1, step)
	var nx := xs.size()
	var nz := zs.size()
	var verts := PackedVector3Array()
	var uv2 := PackedVector2Array()
	var near := PackedByteArray()
	var half := w.size * 0.5
	for jz in nz:
		for jx in nx:
			var i := zs[jz] * w.res + xs[jx]
			var level := w.water_surface[i] if _open(w, i) else _neighbor_level(w, xs[jx], zs[jz])
			verts.append(Vector3(-half + float(xs[jx]) * w.cell, level, -half + float(zs[jz]) * w.cell))
			uv2.append(Vector2(level - w.heights[i], 0.0))
			# Land below the water level (e.g. a carved outflow channel) would get a
			# floating sheet: leave it to the river ribbons.
			var sinks := not _open(w, i) and w.heights[i] < level - 0.05
			near.append(1 if _open_near(w, xs[jx], zs[jz]) and not sinks else 0)
	var idx := PackedInt32Array()
	for jz in nz - 1:
		for jx in nx - 1:
			var p00 := jz * nx + jx
			var p10 := p00 + 1
			var p01 := p00 + nx
			var p11 := p01 + 1
			# Every corner must be open water or (non-sinking) shore next to it.
			if near[p00] + near[p10] + near[p01] + near[p11] < 4:
				continue
			idx.append_array([p00, p10, p11, p00, p11, p01])
	if idx.is_empty():
		return null
	return _mesh(verts, uv2, PackedVector2Array(), idx)


## Large flat ring around the map so the sea reaches the horizon.
static func build_outer_ocean(w: WorldData, radius: float) -> ArrayMesh:
	var h := w.size * 0.5
	var r := maxf(radius, h * 2.0)
	var y := w.sea_level
	var rects := [
		Rect2(-r, -r, 2.0 * r, r - h), Rect2(-r, h, 2.0 * r, r - h),
		Rect2(-r, -h, r - h, 2.0 * h), Rect2(h, -h, r - h, 2.0 * h),
	]
	var verts := PackedVector3Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for rc in rects:
		var rect: Rect2 = rc
		var b := verts.size()
		verts.append(Vector3(rect.position.x, y, rect.position.y))
		verts.append(Vector3(rect.end.x, y, rect.position.y))
		verts.append(Vector3(rect.position.x, y, rect.end.y))
		verts.append(Vector3(rect.end.x, y, rect.end.y))
		for k in 4:
			uv2.append(Vector2(OUTER_DEPTH, 0.0))
		idx.append_array([b, b + 1, b + 3, b, b + 3, b + 2])
	return _mesh(verts, uv2, PackedVector2Array(), idx)


## Ribbons (left, centre, right vertex per polyline point) for all rivers.
static func build_rivers(w: WorldData) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for r in w.rivers:
		var pts: PackedVector3Array = r["points"]
		var wid: PackedFloat32Array = r["widths"]
		var n := pts.size()
		if n < 2:
			continue
		var base := verts.size()
		var along := 0.0
		for k in n:
			var a := pts[maxi(k - 1, 0)]
			var b := pts[mini(k + 1, n - 1)]
			var t := Vector2(b.x - a.x, b.z - a.z)
			if t.length_squared() < 1e-6:
				t = Vector2(1, 0)
			t = t.normalized()
			var side := Vector3(-t.y, 0.0, t.x)
			if k > 0:
				along += Vector2(pts[k].x - pts[k - 1].x, pts[k].z - pts[k - 1].z).length()
			var half_w := wid[k] * 0.5 * 1.3
			var depth := 0.45 + 0.28 * wid[k]
			var c := pts[k] + Vector3(0, 0.03, 0)
			verts.append(c - side * half_w)
			verts.append(c)
			verts.append(c + side * half_w)
			uv.append(Vector2(0.0, along))
			uv.append(Vector2(0.5, along))
			uv.append(Vector2(1.0, along))
			uv2.append(Vector2(0.05, 0.0))
			uv2.append(Vector2(depth, 0.0))
			uv2.append(Vector2(0.05, 0.0))
		for k in n - 1:
			var p := base + k * 3
			var q := p + 3
			for s in 2:
				_quad_up(idx, verts, p + s, p + s + 1, q + s, q + s + 1)
	if idx.is_empty():
		return null
	return _mesh(verts, uv2, uv, idx)


## Appends two triangles facing +Y for the quad (a b / c d).
static func _quad_up(idx: PackedInt32Array, v: PackedVector3Array, a: int, b: int, c: int, d: int) -> void:
	for tri in [[a, b, d], [a, d, c]]:
		var i0: int = tri[0]
		var i1: int = tri[1]
		var i2: int = tri[2]
		var nrm := (v[i2] - v[i0]).cross(v[i1] - v[i0])
		if nrm.y >= 0.0:
			idx.append_array([i0, i1, i2])
		else:
			idx.append_array([i0, i2, i1])


## Surface of the nearest open water (ocean/lake) around a shore sample.
static func _neighbor_level(w: WorldData, ix: int, iz: int) -> float:
	var best := w.sea_level
	var best_d := 99
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var x := ix + dx
			var z := iz + dz
			if x < 0 or z < 0 or x >= w.res or z >= w.res:
				continue
			var j := z * w.res + x
			var d := absi(dx) + absi(dz)
			if _open(w, j) and d < best_d:
				best_d = d
				best = w.water_surface[j]
	return best


static func _open(w: WorldData, i: int) -> bool:
	var t := w.water[i]
	return t == WorldData.Water.OCEAN or t == WorldData.Water.LAKE


## Sample is open water or touches it (surface extends a cell under the shore).
static func _open_near(w: WorldData, ix: int, iz: int) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var x := ix + dx
			var z := iz + dz
			if x < 0 or z < 0 or x >= w.res or z >= w.res:
				continue
			if _open(w, z * w.res + x):
				return true
	return false


static func _mesh(verts: PackedVector3Array, uv2: PackedVector2Array, uv: PackedVector2Array, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	if uv.size() == verts.size():
		arrays[Mesh.ARRAY_TEX_UV] = uv
	else:
		var zero := PackedVector2Array()
		zero.resize(verts.size())
		arrays[Mesh.ARRAY_TEX_UV] = zero
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
