class_name FeatherBuilder
extends RefCounted
## Individual feathers for feathered wings and tails (feather material):
## primaries fan out from the hand, secondaries trail the forearm, a covert
## row overlaps their bases, tail feathers spread horizontally. Each feather
## is a curved tapered vane with a raised rachis, skinned to the bone at its
## base, so the wing folds and flaps as a whole.


static func wing(ctx: CreatureBuildContext, a: AnatomyModel.Accessory, chain: PackedInt32Array) -> void:
	var m := ctx.model
	var edge := MembraneBuilder.Edge.new(m, chain, a.params.get("trail", Vector3.BACK), a.params.get("normal", Vector3.UP))
	var chord := maxf(float(a.params.get("chord", a.size)), 1e-4)
	var n_b := chain.size()
	var parent := m.bones[chain[0]].parent
	var slot := ctx.slot(a.covering)
	var buf := ctx.buffer(CreatureBuildContext.KIND_FEATHER)
	var up_sign := 1.0
	if edge.frame_vec(0.3, 2).dot(Vector3.UP) < 0.0:
		up_sign = -1.0
	var hand_start := 1.0 - m.bones[chain[n_b - 1]].length / maxf(edge.total, 1e-6) if n_b > 1 else 0.55
	var n_prim := MeshLod.seg(ctx.lod, 10, 4)
	var n_sec := MeshLod.seg(ctx.lod, 11, 4)
	var idx := 0
	# Secondaries along the arm, nearly parallel to the trail direction.
	for i in n_sec:
		var u := float(i) / float(maxi(n_sec - 1, 1))
		var s := lerpf(0.04, hand_start, u)
		var tr := edge.frame_vec(s, 0)
		var sp := (edge.point(minf(s + 0.02, 1.0)) - edge.point(maxf(s - 0.02, 0.0))).normalized()
		var dir := (tr + sp * lerpf(0.0, 0.25, u)).normalized()
		var length := chord * lerpf(0.78, 0.98, u)
		_feather(ctx, buf, edge.point(s), dir, edge.frame_vec(s, 2) * up_sign, length, length * 0.2, slot, a.part_id, idx,
			chain, edge.chain_s(s), parent, 0.45 * pow(1.0 - u, 3.0), s, float(i) * 0.0012 * chord, ctx.lod)
		idx += 1
	# Primaries fanning out from the hand towards the tip.
	for i in n_prim:
		var u := float(i) / float(maxi(n_prim - 1, 1))
		var s := lerpf(hand_start, 0.98, u)
		var tr := edge.frame_vec(s, 0)
		var sp := (edge.point(minf(s + 0.02, 1.0)) - edge.point(maxf(s - 0.02, 0.0))).normalized()
		var ang := lerpf(0.3, 1.25, u)
		var dir := (tr * cos(ang) + sp * sin(ang)).normalized()
		var length := chord * (1.05 + 0.32 * sin(PI * clampf(u * 0.85, 0.0, 1.0)))
		_feather(ctx, buf, edge.point(s), dir, edge.frame_vec(s, 2) * up_sign, length, length * 0.17, slot, a.part_id, idx,
			chain, edge.chain_s(s), parent, 0.0, s, float(n_sec + i) * 0.0012 * chord, ctx.lod)
		idx += 1
	# Coverts: shorter, wider row on top of the flight-feather bases.
	if ctx.detail >= 1:
		var n_cov := MeshLod.seg(ctx.lod, 12, 5)
		for i in n_cov:
			var u := float(i) / float(maxi(n_cov - 1, 1))
			var s := lerpf(0.02, 0.9, u)
			var tr := edge.frame_vec(s, 0)
			var nr := edge.frame_vec(s, 2) * up_sign
			var sp := (edge.point(minf(s + 0.02, 1.0)) - edge.point(maxf(s - 0.02, 0.0))).normalized()
			var dir := (tr + sp * 0.35 * u).normalized()
			var length := chord * lerpf(0.5, 0.36, u)
			_feather(ctx, buf, edge.point(s) - tr * chord * 0.04, dir, nr, length, length * 0.42, slot, a.part_id, idx,
				chain, edge.chain_s(s), parent, 0.5 * pow(1.0 - u, 3.0), s, chord * 0.03, ctx.lod)
			idx += 1


static func tail(ctx: CreatureBuildContext, a: AnatomyModel.Accessory, chain: PackedInt32Array) -> void:
	var m := ctx.model
	var b0 := m.bones[chain[0]]
	var root := b0.start
	var tip := m.bones[chain[chain.size() - 1]].end
	var axis := tip - root
	var length := axis.length()
	axis = axis.normalized() if length > 1e-6 else b0.basis.y
	var side := axis.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = b0.basis.x
	side = side.normalized()
	var up := side.cross(axis).normalized()
	if up.dot(Vector3.UP) < 0.0:
		up = -up
	var chord := maxf(float(a.params.get("chord", a.size)), 1e-4)
	var f_len := length + chord * 0.9
	var n := MeshLod.seg(ctx.lod, 10, 4)
	var spread := deg_to_rad(34.0)
	var slot := ctx.slot(a.covering)
	var buf := ctx.buffer(CreatureBuildContext.KIND_FEATHER)
	for i in n:
		var q := float(i) / float(maxi(n - 1, 1)) * 2.0 - 1.0
		# Central feathers on top, outer ones below (overlap order).
		var lift := (1.0 - absf(q)) * chord * 0.02
		var dir := (axis * cos(q * spread) + side * sin(q * spread)).normalized()
		var l := f_len * (1.0 - 0.12 * absf(q))
		_feather(ctx, buf, root + axis * length * 0.15, dir, up, l, l * 0.15, slot, a.part_id, i,
			chain, 0.3, b0.parent, 0.35, absf(q), lift, ctx.lod)


## One feather vane: rows along the shaft × 3 columns (edge, rachis, edge),
## slightly cupped and drooping. `lift` offsets it along the normal (layering).
static func _feather(ctx: CreatureBuildContext, buf: MeshBuffer, base: Vector3, dir: Vector3, nrm: Vector3, length: float,
		width: float, slot: int, part_id: int, idx: int, chain: PackedInt32Array, chain_s: float, parent: int, parent_w: float,
		along: float, lift: float, lod: int) -> void:
	var y := dir.normalized()
	var n := (nrm - y * nrm.dot(y))
	n = n.normalized() if n.length_squared() > 1e-8 else MathUtil.basis_from_y(y).z
	var x := y.cross(n).normalized()
	var w: Array = CreatureRig.chain_weights(chain, chain_s, 0.3, parent if parent > 0 else -1, parent_w)
	var rows := 4 if lod == 0 else (3 if lod == 1 else 2)
	var st := MeshKit.param_style(MeshKit.slot_color(slot), float(slot), part_id, float(idx), false)
	var v0 := buf.vertex_count()
	var o := base + n * lift
	for r in rows + 1:
		var t := float(r) / float(rows)
		var wt := width * (0.35 + 0.65 * sin(PI * (0.12 + 0.88 * t * 0.82))) * (1.0 - 0.55 * pow(t, 3.0))
		if r == rows:
			wt = width * 0.25
		var c := o + y * (length * t) - n * (length * 0.06 * t * t)
		for col in 3:
			var sx := float(col - 1)
			var p := c + x * (sx * wt) + n * ((1.0 - absf(sx)) * width * 0.08 - absf(sx) * width * 0.03)
			MeshKit.put(buf, p, n, st, Vector2(t, sx), along, Vector3.ZERO, w[0], w[1])
	for r in rows:
		var a0 := v0 + r * 3
		buf.quad(a0, a0 + 1, a0 + 4, a0 + 3)
		buf.quad(a0 + 1, a0 + 2, a0 + 5, a0 + 4)
