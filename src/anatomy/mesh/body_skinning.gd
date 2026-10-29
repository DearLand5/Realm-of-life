class_name BodySkinning
extends RefCounted
## Turns a polygonized SDF surface into a skinned creature MeshBuffer.
##
## Per vertex, the unblended distance d_j of every nearby primitive j is
## compared with the closest one: influence = smoothstep(1 - (d_j - d_min) / σ_j).
## On a joint between two chain segments d_j - d_min grows ~x²/2r with the
## distance x from the joint, so σ = SKIN_SIGMA·r blends parent and child over
## about ±r — wide enough to bend without collapsing, narrow enough to keep
## segments rigid. Influences are limited to bones related to the dominant one
## (graph distance ≤ 2). Covering slots use the same kernel with a narrower σ.
## Also fills the along-body coordinate, ventral factor, part position, part id
## and an SDF ambient-occlusion term (two samples along the normal).

const SKIN_SIGMA := 0.62
const COVER_SIGMA := 0.3
const AO_STEPS := [0.35, 0.9]   # sample distances in units of the local radius
const AO_STRENGTH := 0.85


static func build(rig: CreatureRig, grid: SdfGrid, res: SdfMesher.Result, with_ao: bool = true) -> MeshBuffer:
	var out := MeshBuffer.new()
	var field := grid.field
	var m := rig.model
	var n := res.positions.size()
	if n == 0:
		return out
	var sig_skin := PackedFloat32Array()
	var sig_cov := PackedFloat32Array()
	var rad := PackedFloat32Array()
	for j in field.count:
		var r := field.mean_radius(j)
		var k := field.data[j * SdfField.STRIDE + 6]
		rad.append(r)
		sig_skin.append(maxf(SKIN_SIGMA * r + 0.5 * k, grid.cell * 0.5))
		sig_cov.append(maxf(COVER_SIGMA * r + 0.35 * k, grid.cell * 0.35))
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
	var dist := PackedFloat32Array()
	var wb := PackedInt32Array()
	var ww := PackedFloat32Array()
	var bone_count := m.bones.size()
	for i in n:
		var p := res.positions[i]
		var nrm := res.normals[i]
		var cand := grid.cand_at(p)
		var nc := cand.size()
		if nc == 0:
			_write_default(out, i, p, nrm)
			continue
		field.distances(p, cand, dist)
		var imin := 0
		var dmin := dist[0]
		for c in range(1, nc):
			if dist[c] < dmin:
				dmin = dist[c]
				imin = c
		var dom := field.bone[cand[imin]]
		if dom < 0 or dom >= bone_count:
			dom = 0
		var rel: PackedInt32Array = rig.related[dom]
		wb.resize(0)
		ww.resize(0)
		var cw := Vector4.ZERO
		for c in nc:
			var j := cand[c]
			var delta := dist[c] - dmin
			var ss := sig_skin[j]
			if delta < ss:
				var b := field.bone[j]
				if rel.has(b):
					var x := 1.0 - delta / ss
					var w := x * x * (3.0 - 2.0 * x)
					var at := wb.find(b)
					if at >= 0:
						ww[at] = maxf(ww[at], w)
					else:
						wb.append(b)
						ww.append(w)
			var sc := sig_cov[j]
			if delta < sc:
				var x2 := 1.0 - delta / sc
				var slot := clampi(field.covering[j], 0, 3)
				cw[slot] = maxf(cw[slot], x2 * x2 * (3.0 - 2.0 * x2))
		# Top-4 bones.
		var bi := PackedInt32Array([dom, 0, 0, 0])
		var bw := Vector4(1.0, 0.0, 0.0, 0.0)
		if wb.size() > 0:
			var tot := 0.0
			for s in 4:
				var best := -1
				var bv := -1.0
				for q in wb.size():
					if ww[q] > bv:
						bv = ww[q]
						best = q
				if best < 0 or bv <= 0.0:
					break
				bi[s] = wb[best]
				bw[s] = bv
				tot += bv
				ww[best] = -2.0
			if tot > 0.0:
				bw /= tot
		# Along coordinate and part position from the weighted bones.
		var along := 0.0
		var part_t := 0.0
		for s in 4:
			if bw[s] > 0.0:
				along += bw[s] * rig.along_on_bone(bi[s], p)
				part_t += bw[s] * rig.part_t_on_bone(bi[s], p)
		var cs := cw.x + cw.y + cw.z + cw.w
		if cs <= 0.0:
			cw = Vector4(1, 0, 0, 0)
			cs = 1.0
		cw /= cs
		var dom_slot := 0
		for s in range(1, 4):
			if cw[s] > cw[dom_slot]:
				dom_slot = s
		var ao := 1.0
		if with_ao:
			var r := rad[cand[imin]]
			var occl := 0.0
			for step in AO_STEPS:
				var dlt: float = float(step) * r
				var sp := p + nrm * dlt
				var f := field.value(sp, grid.cand_at(sp))
				occl += clampf((dlt - f) / dlt, 0.0, 1.0) * 0.5
			ao = clampf(1.0 - occl * AO_STRENGTH, 0.0, 1.0)
		out.colors[i] = Color(cw.x, cw.y, cw.z, cw.w)
		out.uv[i] = Vector2(along, clampf(0.5 - 0.5 * nrm.y, 0.0, 1.0))
		out.uv2[i] = Vector2(ao, part_t)
		var o4 := i * 4
		out.custom0[o4] = p.x
		out.custom0[o4 + 1] = p.y
		out.custom0[o4 + 2] = p.z
		out.custom0[o4 + 3] = float(dom_slot)
		out.custom1[i * 2] = float(m.bones[dom].part_id)
		out.custom1[i * 2 + 1] = 0.0
		for s in 4:
			out.bones[o4 + s] = bi[s]
			out.weights[o4 + s] = bw[s]
	return out


static func _write_default(out: MeshBuffer, i: int, p: Vector3, nrm: Vector3) -> void:
	out.colors[i] = Color(1, 0, 0, 0)
	out.uv[i] = Vector2(0.0, clampf(0.5 - 0.5 * nrm.y, 0.0, 1.0))
	out.uv2[i] = Vector2(1.0, 0.0)
	var o4 := i * 4
	out.custom0[o4] = p.x
	out.custom0[o4 + 1] = p.y
	out.custom0[o4 + 2] = p.z
	out.custom0[o4 + 3] = 0.0
	out.custom1[i * 2] = -1.0
	out.custom1[i * 2 + 1] = 0.0
	for s in 4:
		out.bones[o4 + s] = 0
		out.weights[o4 + s] = 1.0 if s == 0 else 0.0
