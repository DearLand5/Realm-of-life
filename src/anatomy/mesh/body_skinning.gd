class_name BodySkinning
extends RefCounted
## Turns a polygonized SDF surface into a skinned creature MeshBuffer.
##
## Per vertex, the unblended distance d_j of every nearby primitive j is
## compared with the closest one: influence = smoothstep(1 - (d_j - d_min) / σ_j).
## On a joint between two chain segments d_j - d_min grows ~x²/2r with the
## distance x from the joint, so σ ≈ 0.6·r blends parent and child over about
## ±r — wide enough to bend without collapsing, narrow enough to keep segments
## rigid. Influences are limited to bones related to the dominant one (graph
## distance ≤ 2). Covering slots use the same kernel with a narrower σ.
## Also fills the along-body coordinate, ventral factor, part position, part id
## and an SDF ambient-occlusion term (samples along the normal).

const COVER_SIGMA := 0.3
const AO_STEPS: Array[float] = [0.35, 0.9]   # sample distances in units of the local radius
const AO_STRENGTH := 0.85


## Skin / covering kernel at one point (reused for surface decorations).
class Kernel:
	var field: SdfField
	var grid: SdfGrid
	var rig: CreatureRig
	var sig_skin := PackedFloat32Array()
	var sig_cov := PackedFloat32Array()
	var rad := PackedFloat32Array()
	var b_start := PackedVector3Array()
	var b_axis := PackedVector3Array()   # end - start
	var b_len := PackedFloat32Array()
	var b_part := PackedInt32Array()
	# Results of the last eval().
	var bi := PackedInt32Array([0, 0, 0, 0])
	var bw := Vector4(1, 0, 0, 0)
	var cw := Vector4(1, 0, 0, 0)
	var dom: int = 0
	var dom_slot: int = 0
	var dom_prim: int = -1
	var along: float = 0.0
	var part_t: float = 0.0
	var _dist := PackedFloat32Array()
	var _wb := PackedInt32Array()
	var _ww := PackedFloat32Array()

	func _init(r: CreatureRig, g: SdfGrid) -> void:
		rig = r
		grid = g
		field = g.field if g != null else null
		if field != null:
			for j in field.count:
				var rr := field.mean_radius(j)
				var k := field.data[j * SdfField.STRIDE + 6]
				rad.append(rr)
				sig_skin.append(maxf(field.reach[j] * 0.98, g.cell * 0.5))
				sig_cov.append(maxf(COVER_SIGMA * rr + 0.35 * k, g.cell * 0.35))
		for b in r.model.bones:
			b_start.append(b.start)
			b_axis.append(b.end - b.start)
			b_len.append(b.length)
			b_part.append(b.part_id)

	## Evaluates weights at p. Returns false when no primitive is near.
	func eval(p: Vector3) -> bool:
		bi = PackedInt32Array([0, 0, 0, 0])
		bw = Vector4(1, 0, 0, 0)
		cw = Vector4(1, 0, 0, 0)
		dom = 0
		dom_slot = 0
		dom_prim = -1
		along = 0.0
		part_t = 0.0
		if field == null:
			return false
		var cand := grid.cand_at(p)
		var nc := cand.size()
		if nc == 0:
			return false
		field.distances(p, cand, _dist)
		var imin := 0
		var dmin := _dist[0]
		for c in range(1, nc):
			if _dist[c] < dmin:
				dmin = _dist[c]
				imin = c
		dom_prim = cand[imin]
		dom = field.bone[dom_prim]
		if dom < 0 or dom >= b_len.size():
			dom = 0
		var rel: PackedInt32Array = rig.related[dom]
		_wb.resize(0)
		_ww.resize(0)
		var cv := Vector4.ZERO
		for c in nc:
			var j := cand[c]
			var delta := _dist[c] - dmin
			var ss := sig_skin[j]
			if delta < ss:
				var b := field.bone[j]
				if rel.has(b):
					var x := 1.0 - delta / ss
					var w := x * x * (3.0 - 2.0 * x)
					var at := _wb.find(b)
					if at >= 0:
						_ww[at] = maxf(_ww[at], w)
					else:
						_wb.append(b)
						_ww.append(w)
			var sc := sig_cov[j]
			if delta < sc:
				var x2 := 1.0 - delta / sc
				var slot := clampi(field.covering[j], 0, 3)
				cv[slot] = maxf(cv[slot], x2 * x2 * (3.0 - 2.0 * x2))
		bi[0] = dom
		if _wb.size() > 0:
			var tot := 0.0
			for s in 4:
				var best := -1
				var bv := 0.0
				for q in _wb.size():
					if _ww[q] > bv:
						bv = _ww[q]
						best = q
				if best < 0:
					break
				bi[s] = _wb[best]
				bw[s] = bv
				tot += bv
				_ww[best] = -2.0
			if tot > 0.0:
				bw /= tot
		for s in 4:
			var w := bw[s]
			if w <= 0.0:
				continue
			var b := bi[s]
			var ax := b_axis[b]
			var l2 := ax.length_squared()
			var t := clampf((p - b_start[b]).dot(ax) / l2, 0.0, 1.0) if l2 > 1e-12 else 0.0
			along += w * (rig.along_start[b] + t * b_len[b])
			part_t += w * clampf((rig.part_offset[b] + t * b_len[b]) / rig.part_total[b], 0.0, 1.0)
		var cs := cv.x + cv.y + cv.z + cv.w
		if cs > 0.0:
			cw = cv / cs
		dom_slot = 0
		for s in range(1, 4):
			if cw[s] > cw[dom_slot]:
				dom_slot = s
		return true

	## Ambient occlusion from the SDF along the normal.
	func ao(p: Vector3, n: Vector3) -> float:
		if dom_prim < 0:
			return 1.0
		var r := rad[dom_prim]
		var occl := 0.0
		for step in AO_STEPS:
			var dlt := step * r
			var sp := p + n * dlt
			var f := field.value(sp, grid.cand_at(sp))
			occl += clampf((dlt - f) / dlt, 0.0, 1.0) * 0.5
		return clampf(1.0 - occl * AO_STRENGTH, 0.0, 1.0)


static func build(rig: CreatureRig, grid: SdfGrid, res: SdfMesher.Result, with_ao: bool = true) -> MeshBuffer:
	var out := MeshBuffer.new()
	var m := rig.model
	var n := res.positions.size()
	if n == 0:
		return out
	var k := Kernel.new(rig, grid)
	out.verts = res.positions
	out.normals = res.normals
	out.indices = res.indices
	out.colors.resize(n)
	out.uv.resize(n)
	out.uv2.resize(n)
	out.custom0.resize(n * 4)
	out.custom1.resize(n * 2)
	out.bones.resize(n * 4)
	out.weights.resize(n * 4)
	for i in n:
		var p := res.positions[i]
		var nrm := res.normals[i]
		var ok := k.eval(p)
		var ao := k.ao(p, nrm) if with_ao and ok else 1.0
		var cw := k.cw
		out.colors[i] = Color(cw.x, cw.y, cw.z, cw.w)
		out.uv[i] = Vector2(k.along, clampf(0.5 - 0.5 * nrm.y, 0.0, 1.0))
		out.uv2[i] = Vector2(ao, k.part_t)
		var o4 := i * 4
		out.custom0[o4] = p.x
		out.custom0[o4 + 1] = p.y
		out.custom0[o4 + 2] = p.z
		out.custom0[o4 + 3] = float(k.dom_slot)
		out.custom1[i * 2] = float(m.bones[k.dom].part_id) if ok else -1.0
		out.custom1[i * 2 + 1] = 0.0
		var bw := k.bw
		var bi := k.bi
		out.bones[o4] = bi[0]
		out.bones[o4 + 1] = bi[1]
		out.bones[o4 + 2] = bi[2]
		out.bones[o4 + 3] = bi[3]
		out.weights[o4] = bw.x
		out.weights[o4 + 1] = bw.y
		out.weights[o4 + 2] = bw.z
		out.weights[o4 + 3] = bw.w
	return out
