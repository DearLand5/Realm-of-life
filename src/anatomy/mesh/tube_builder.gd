class_name TubeBuilder
extends RefCounted
## Skinned swept tubes along bone chains (body vertex format): thin parts
## (antennae, insect legs, flagella, tentacles, wing/fin leading edges) and
## SDF chains that are thinner than a grid cell at the current LOD.


## Builds a tube along `chain` (bone indices, root first).
##   flare  — radius boost near the base, imitating the SDF fillet
##   cell   — current grid cell size (side count adapts to the radius)
static func chain_tube(ctx: CreatureBuildContext, buf: MeshBuffer, chain: PackedInt32Array, flare: float = 0.0, radius_scale: float = 1.0) -> void:
	var m := ctx.model
	var rig := ctx.rig
	if chain.is_empty():
		return
	var n := chain.size()
	var pts := PackedVector3Array([m.bones[chain[0]].start])
	var rad := PackedFloat32Array([m.bones[chain[0]].r0])
	for bi in chain:
		pts.append(m.bones[bi].end)
		rad.append(m.bones[bi].r1)
	var rings := MeshLod.rings_per_bone(ctx.lod)
	var b0 := m.bones[chain[0]]
	var parent := b0.parent
	var sw := MeshKit.Sweep.new()
	var total_len := 0.0
	for bi in chain:
		total_len += m.bones[bi].length
	var s_len := 0.0
	for k in n:
		var b := m.bones[chain[k]]
		var steps := maxi(1, rings if b.length > b.r0 * 0.8 else 1)
		var last := k == n - 1
		for q in steps + (1 if last else 0):
			var u := float(q) / float(steps)
			var c := _catmull(_pt(pts, k - 1), pts[k], pts[k + 1], _pt(pts, k + 2), u)
			var r := lerpf(rad[k], rad[k + 1], u) * radius_scale
			var s := float(k) + u
			var sl := s_len + u * b.length
			var fu := clampf(sl / maxf(total_len * 0.3, 1e-6), 0.0, 1.0)
			r *= 1.0 + flare * (1.0 - fu * fu * (3.0 - 2.0 * fu))
			var x := b.basis.x
			if not last and u > 0.6:
				var nx := m.bones[chain[k + 1]].basis.x
				x = x.lerp(nx if nx.dot(x) >= 0.0 else -nx, smoothstep(0.6, 1.0, u) * 0.5)
			var pw := 0.0
			if parent > 0 and flare > 0.0:
				pw = 0.45 * (1.0 - smoothstep(0.0, 0.18, sl / maxf(total_len, 1e-6)))
			var w: Array = CreatureRig.chain_weights(chain, s, 0.3, parent, pw)
			var along := rig.along_start[chain[k]] + u * b.length
			var pt := clampf((rig.part_offset[chain[k]] + u * b.length) / rig.part_total[chain[k]], 0.0, 1.0)
			var ao := lerpf(0.55, 1.0, smoothstep(0.0, 0.15, sl / maxf(total_len, 1e-6))) if parent > 0 else 1.0
			sw.add_ring(c, r, clampf(b.flatten, 0.2, 4.0), x, w[0], w[1], pt, along, ao)
		s_len += b.length
	var st := MeshKit.body_style(b0.covering, b0.part_id)
	var r_cells := rad[0] / maxf(ctx.cell, 1e-6)
	MeshKit.sweep(buf, sw, st, MeshLod.tube_sides(ctx.lod, r_cells), 2, false)


static func _pt(pts: PackedVector3Array, i: int) -> Vector3:
	var n := pts.size()
	if i < 0:
		return pts[0] * 2.0 - pts[1]
	if i >= n:
		return pts[n - 1] * 2.0 - pts[n - 2]
	return pts[i]


## Uniform Catmull-Rom segment p1..p2.
static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * p1) + (p2 - p0) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * u3)
