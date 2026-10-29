class_name SdfMesher
extends RefCounted
## Surface Nets (dual) polygonizer for an SdfField sampled on an SdfGrid.
##
## Pipeline (all GDScript, tuned for its costs):
##  1. Coarse pass: one field evaluation per brick centre; bricks whose
##     |distance| exceeds the brick half-diagonal (field is 1-Lipschitz) contain
##     no surface and are skipped. Bricks without overlapping primitives are
##     skipped without any evaluation.
##  2. Grid values only for points of active bricks (shared faces computed once).
##  3. One vertex per sign-changing cell at the mean of its edge crossings.
##  4. One quad per sign-changing grid edge, split along the shorter diagonal,
##     oriented outward with Godot's clockwise front-face convention.
##  5. Newton projection of every vertex onto the iso-surface along the analytic
##     gradient; normals = normalised gradient (smooth, exact at fillets).

const SENTINEL := 1.0e20
## Lipschitz safety factor for brick culling (ellipsoid distance is approximate).
const CULL_SAFETY := 1.3


class Result:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var grid: SdfGrid
	var stats := {}


static func polygonize(grid: SdfGrid, newton_steps: int = 2, smooth_passes: int = 0) -> Result:
	var res := Result.new()
	res.grid = grid
	var field := grid.field
	if field == null or field.is_empty():
		return res
	var t0 := Time.get_ticks_usec()
	var B := SdfGrid.BRICK
	var px := grid.points.x
	var py := grid.points.y
	var pxy := px * py
	var cell := grid.cell
	var org := grid.origin
	var vals := PackedFloat32Array()
	vals.resize(px * py * grid.points.z)
	vals.fill(SENTINEL)

	# 1 + 2: classify bricks and fill values of active ones.
	var reach := cell * float(B) * 0.8660254 * CULL_SAFETY + cell * 0.25
	var active := PackedInt32Array()
	var evals := 0
	for bz in grid.bricks.z:
		for by in grid.bricks.y:
			for bx in grid.bricks.x:
				var bi := bx + grid.bricks.x * (by + grid.bricks.y * bz)
				var cand: PackedInt32Array = grid.brick_cand[bi]
				if cand.is_empty():
					continue
				var c := org + Vector3(float(bx * B) + B * 0.5, float(by * B) + B * 0.5, float(bz * B) + B * 0.5) * cell
				var dc := field.value(c, cand)
				evals += 1
				if absf(dc) > reach:
					continue
				active.append(bi)
				for z in range(bz * B, bz * B + B + 1):
					for y in range(by * B, by * B + B + 1):
						var row := px * (y + py * z)
						var pyz := Vector3(0.0, float(y), float(z)) * cell + org
						for x in range(bx * B, bx * B + B + 1):
							var idx := x + row
							if vals[idx] < SENTINEL:
								continue
							vals[idx] = field.value(Vector3(pyz.x + float(x) * cell, pyz.y, pyz.z), cand)
							evals += 1
	var t1 := Time.get_ticks_usec()

	# 3: vertices.
	var cx := grid.cells.x
	var cy := grid.cells.y
	var cxy := cx * cy
	var cell_vert := PackedInt32Array()
	cell_vert.resize(cx * cy * grid.cells.z)
	cell_vert.fill(-1)
	var vcell := PackedInt32Array()
	var vmask := PackedInt32Array()
	var pos := res.positions
	for bi in active:
		var bx := bi % grid.bricks.x
		var by := (bi / grid.bricks.x) % grid.bricks.y
		var bz := bi / (grid.bricks.x * grid.bricks.y)
		for z in range(bz * B, bz * B + B):
			for y in range(by * B, by * B + B):
				for x in range(bx * B, bx * B + B):
					var i0 := x + px * (y + py * z)
					var v0 := vals[i0]
					var v1 := vals[i0 + 1]
					var v2 := vals[i0 + px]
					var v3 := vals[i0 + px + 1]
					var v4 := vals[i0 + pxy]
					var v5 := vals[i0 + pxy + 1]
					var v6 := vals[i0 + pxy + px]
					var v7 := vals[i0 + pxy + px + 1]
					var mask := 0
					if v0 < 0.0: mask |= 1
					if v1 < 0.0: mask |= 2
					if v2 < 0.0: mask |= 4
					if v3 < 0.0: mask |= 8
					if v4 < 0.0: mask |= 16
					if v5 < 0.0: mask |= 32
					if v6 < 0.0: mask |= 64
					if v7 < 0.0: mask |= 128
					if mask == 0 or mask == 255:
						continue
					var s := Vector3.ZERO
					var n := 0
					# X edges.
					if (v0 < 0.0) != (v1 < 0.0):
						s += Vector3(v0 / (v0 - v1), 0.0, 0.0); n += 1
					if (v2 < 0.0) != (v3 < 0.0):
						s += Vector3(v2 / (v2 - v3), 1.0, 0.0); n += 1
					if (v4 < 0.0) != (v5 < 0.0):
						s += Vector3(v4 / (v4 - v5), 0.0, 1.0); n += 1
					if (v6 < 0.0) != (v7 < 0.0):
						s += Vector3(v6 / (v6 - v7), 1.0, 1.0); n += 1
					# Y edges.
					if (v0 < 0.0) != (v2 < 0.0):
						s += Vector3(0.0, v0 / (v0 - v2), 0.0); n += 1
					if (v1 < 0.0) != (v3 < 0.0):
						s += Vector3(1.0, v1 / (v1 - v3), 0.0); n += 1
					if (v4 < 0.0) != (v6 < 0.0):
						s += Vector3(0.0, v4 / (v4 - v6), 1.0); n += 1
					if (v5 < 0.0) != (v7 < 0.0):
						s += Vector3(1.0, v5 / (v5 - v7), 1.0); n += 1
					# Z edges.
					if (v0 < 0.0) != (v4 < 0.0):
						s += Vector3(0.0, 0.0, v0 / (v0 - v4)); n += 1
					if (v1 < 0.0) != (v5 < 0.0):
						s += Vector3(1.0, 0.0, v1 / (v1 - v5)); n += 1
					if (v2 < 0.0) != (v6 < 0.0):
						s += Vector3(0.0, 1.0, v2 / (v2 - v6)); n += 1
					if (v3 < 0.0) != (v7 < 0.0):
						s += Vector3(1.0, 1.0, v3 / (v3 - v7)); n += 1
					var ci := x + cx * (y + cy * z)
					cell_vert[ci] = pos.size()
					pos.append(org + (Vector3(float(x), float(y), float(z)) + s / float(n)) * cell)
					vcell.append(ci)
					vmask.append(mask)
	var t2 := Time.get_ticks_usec()

	# 4: quads.
	var idx_out := res.indices
	for k in vcell.size():
		var ci := vcell[k]
		var m := vmask[k]
		var x := ci % cx
		var y := (ci / cx) % cy
		var z := ci / cxy
		var in0 := m & 1
		if ((m >> 1) & 1) != in0 and y > 0 and z > 0:
			_quad(idx_out, pos, k, cell_vert[ci - cx], cell_vert[ci - cx - cxy], cell_vert[ci - cxy], in0 == 1)
		if ((m >> 2) & 1) != in0 and z > 0 and x > 0:
			_quad(idx_out, pos, k, cell_vert[ci - cxy], cell_vert[ci - cxy - 1], cell_vert[ci - 1], in0 == 1)
		if ((m >> 4) & 1) != in0 and x > 0 and y > 0:
			_quad(idx_out, pos, k, cell_vert[ci - 1], cell_vert[ci - 1 - cx], cell_vert[ci - cx], in0 == 1)
	var t3 := Time.get_ticks_usec()

	if smooth_passes > 0:
		MeshSmoothing.taubin(pos, idx_out, smooth_passes)

	# 5: projection + normals.
	var nrm := res.normals
	nrm.resize(pos.size())
	var tmp := PackedVector3Array()
	var max_disp := cell * 1.0
	for k in pos.size():
		var p0 := pos[k]
		var cand := grid.cand_at(p0)
		var nn := field.project(p0, cand, newton_steps, cell * 0.75, tmp)
		var q := tmp[0]
		var dq := q - p0
		if dq.length() > max_disp:
			q = p0 + dq.normalized() * max_disp
		if not q.is_finite():
			q = p0
		pos[k] = q
		nrm[k] = nn
		evals += newton_steps
	_fix_bad_normals(pos, nrm, idx_out)
	var t4 := Time.get_ticks_usec()
	res.stats = {
		"bricks": grid.bricks.x * grid.bricks.y * grid.bricks.z, "active_bricks": active.size(),
		"evals": evals, "vertices": pos.size(), "triangles": idx_out.size() / 3,
		"t_values_ms": (t1 - t0) / 1000.0, "t_vertices_ms": (t2 - t1) / 1000.0,
		"t_quads_ms": (t3 - t2) / 1000.0, "t_project_ms": (t4 - t3) / 1000.0,
		"cell": cell,
	}
	return res


## Emits the quad (c00, c10, c11, c01) — c10/c01 are the neighbours along the
## two other axes — with outward (clockwise) winding.
static func _quad(out: PackedInt32Array, pos: PackedVector3Array, c00: int, c10: int, c11: int, c01: int, inside_first: bool) -> void:
	if c10 < 0 or c11 < 0 or c01 < 0:
		return
	var q0 := c00
	var q1 := c01 if inside_first else c10
	var q2 := c11
	var q3 := c10 if inside_first else c01
	if pos[q0].distance_squared_to(pos[q2]) <= pos[q1].distance_squared_to(pos[q3]):
		out.append_array(PackedInt32Array([q0, q1, q2, q0, q2, q3]))
	else:
		out.append_array(PackedInt32Array([q0, q1, q3, q1, q2, q3]))


## Replaces degenerate gradient normals with area-weighted face normals.
static func _fix_bad_normals(pos: PackedVector3Array, nrm: PackedVector3Array, idx: PackedInt32Array) -> void:
	var bad := false
	for n in nrm:
		if not n.is_finite() or n.length_squared() < 0.5:
			bad = true
			break
	if not bad:
		return
	var acc := PackedVector3Array()
	acc.resize(pos.size())
	for t in range(0, idx.size(), 3):
		var a := idx[t]
		var b := idx[t + 1]
		var c := idx[t + 2]
		# Clockwise front faces: (c - a) x (b - a) points outward.
		var fn := (pos[c] - pos[a]).cross(pos[b] - pos[a])
		acc[a] += fn
		acc[b] += fn
		acc[c] += fn
	for k in nrm.size():
		var n := nrm[k]
		if not n.is_finite() or n.length_squared() < 0.5:
			var f := acc[k]
			nrm[k] = f.normalized() if f.length_squared() > 1e-20 else Vector3.UP
