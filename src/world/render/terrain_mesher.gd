class_name TerrainMesher
extends RefCounted
## Builds one terrain chunk mesh (world-space vertices) at a LOD step, with
## skirts along its border to hide cracks between chunks of different LOD.
## Vertex layout: COLOR = ground colour + grass, UV = (shore height, annual °C),
## UV2 = (moisture, rock factor).


## x0/z0: first grid sample; cells: chunk width in grid cells; step: LOD stride.
static func build_chunk(w: WorldData, a: TerrainAttributes, x0: int, z0: int, cells: int, step: int, skirt_depth: float) -> ArrayMesh:
	var xs := _samples(x0, mini(x0 + cells, w.res - 1), step)
	var zs := _samples(z0, mini(z0 + cells, w.res - 1), step)
	var nx := xs.size()
	var nz := zs.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var half := w.size * 0.5
	for jz in nz:
		var gz := zs[jz]
		for jx in nx:
			var gx := xs[jx]
			var i := gz * w.res + gx
			verts.append(Vector3(-half + float(gx) * w.cell, w.heights[i], -half + float(gz) * w.cell))
			norms.append(a.normals[i])
			cols.append(a.colors[i])
			uv.append(Vector2(a.shore[i], a.temperature[i]))
			uv2.append(Vector2(a.moisture[i], a.rock[i]))
	# Surface triangles (clockwise seen from above = front face in Godot).
	for jz in nz - 1:
		for jx in nx - 1:
			var p00 := jz * nx + jx
			var p10 := p00 + 1
			var p01 := p00 + nx
			var p11 := p01 + 1
			# Split along the shorter diagonal for a better surface.
			if absf(verts[p00].y - verts[p11].y) < absf(verts[p10].y - verts[p01].y):
				idx.append_array([p00, p10, p11, p00, p11, p01])
			else:
				idx.append_array([p00, p10, p01, p10, p11, p01])
	# Skirts: north (z0), south, west (x0), east edges.
	var edges := [
		[_edge_row(0, nx, 1), Vector3(0, 0, -1)],
		[_edge_row((nz - 1) * nx, nx, 1), Vector3(0, 0, 1)],
		[_edge_row(0, nz, nx), Vector3(-1, 0, 0)],
		[_edge_row(nx - 1, nz, nx), Vector3(1, 0, 0)],
	]
	for e in edges:
		var ids: PackedInt32Array = e[0]
		var outward: Vector3 = e[1]
		var base := verts.size()
		for k in ids.size():
			var src := ids[k]
			verts.append(verts[src] - Vector3(0, skirt_depth, 0))
			norms.append(norms[src])
			cols.append(cols[src])
			uv.append(uv[src])
			uv2.append(uv2[src])
		for k in ids.size() - 1:
			var t0 := ids[k]
			var t1 := ids[k + 1]
			var b0 := base + k
			var b1 := base + k + 1
			_tri(idx, verts, t0, t1, b0, outward)
			_tri(idx, verts, t1, b1, b0, outward)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _samples(a: int, b: int, step: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var v := a
	while v < b:
		out.append(v)
		v += step
	out.append(b)
	return out


static func _edge_row(start: int, count: int, stride: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in count:
		out.append(start + k * stride)
	return out


## Appends a triangle wound so its front face points along `outward`.
static func _tri(idx: PackedInt32Array, v: PackedVector3Array, a: int, b: int, c: int, outward: Vector3) -> void:
	var n := (v[c] - v[a]).cross(v[b] - v[a])
	if n.dot(outward) >= 0.0:
		idx.append_array([a, b, c])
	else:
		idx.append_array([a, c, b])
