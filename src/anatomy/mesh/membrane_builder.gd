class_name MembraneBuilder
extends RefCounted
## Wings and fins from "membrane" accessories (params: bones, chord, trail,
## normal, fan, subtype) and tail flukes. The leading edge follows the bone
## chain; every vertex is skinned to the chain bones at its span position
## (and to the parent bone near the root) so membranes flap with the bones.
## Feathered wings / tails are delegated to FeatherBuilder.
##   kinds (CUSTOM1.y): 0 skin membrane, 1 fin with rays, 2 insect wing, 3 web

const KIND_SKIN := 0
const KIND_FIN := 1
const KIND_INSECT := 2


static func build(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	var chain := CreatureMeshBuilder._bones_param(a.params.get("bones"))
	if chain.is_empty():
		return
	for bi in chain:
		if bi <= 0 or bi >= ctx.model.bones.size():
			return
	var subtype := str(a.params.get("subtype", "membrane"))
	var fan := bool(a.params.get("fan", false))
	var slot := ctx.slot(a.covering)
	var feathered := ctx.covering_type(slot) == &"feathers"
	if subtype == "feather" or (fan and feathered):
		if fan:
			FeatherBuilder.tail(ctx, a, chain)
		else:
			FeatherBuilder.wing(ctx, a, chain)
	elif fan:
		_caudal(ctx, a, chain, slot)
	elif subtype == "insect":
		_planform(ctx, a, chain, slot, KIND_INSECT)
	elif subtype == "membrane":
		_planform(ctx, a, chain, slot, KIND_SKIN)
	else:
		_planform(ctx, a, chain, slot, KIND_FIN)


## Leading-edge samples: position, trail and normal per span parameter
## s in [0, 1] (linear along the chain, continuous at joints).
class Edge:
	var chain: PackedInt32Array
	var model: AnatomyModel
	var trail_sign := 1.0
	var normal_sign := 1.0
	var total := 0.0

	func _init(m: AnatomyModel, c: PackedInt32Array, trail: Vector3, normal: Vector3) -> void:
		model = m
		chain = c
		var b0 := m.bones[c[0]]
		trail_sign = 1.0 if trail.dot(b0.basis.x) >= 0.0 else -1.0
		normal_sign = 1.0 if normal.dot(b0.basis.z) >= 0.0 else -1.0
		for bi in c:
			total += m.bones[bi].length

	## Chain parameter (0 .. bone count) of normalised span s.
	func chain_s(s: float) -> float:
		var target := clampf(s, 0.0, 1.0) * total
		var acc := 0.0
		for k in chain.size():
			var l := model.bones[chain[k]].length
			if acc + l >= target or k == chain.size() - 1:
				return float(k) + clampf((target - acc) / maxf(l, 1e-6), 0.0, 1.0)
			acc += l
		return float(chain.size())

	func point(s: float) -> Vector3:
		var cs := chain_s(s)
		var k := mini(int(floorf(cs)), chain.size() - 1)
		var b := model.bones[chain[k]]
		return b.start.lerp(b.end, cs - float(k))

	## Blended bone frame vector (x = trail, z = normal) at s.
	func frame_vec(s: float, axis: int) -> Vector3:
		var cs := chain_s(s)
		var k := mini(int(floorf(cs)), chain.size() - 1)
		var u := cs - float(k)
		var b := model.bones[chain[k]]
		var v := (b.basis.x * trail_sign) if axis == 0 else (b.basis.z * normal_sign)
		if u > 0.7 and k < chain.size() - 1:
			var nb := model.bones[chain[k + 1]]
			var nv := (nb.basis.x * trail_sign) if axis == 0 else (nb.basis.z * normal_sign)
			v = v.lerp(nv, (u - 0.7) / 0.3 * 0.5)
		elif u < 0.3 and k > 0:
			var pb := model.bones[chain[k - 1]]
			var pv := (pb.basis.x * trail_sign) if axis == 0 else (pb.basis.z * normal_sign)
			v = v.lerp(pv, (0.3 - u) / 0.3 * 0.5)
		return v.normalized()


static func _chord_shape(kind: int, s: float, n_bones: int) -> float:
	match kind:
		KIND_INSECT:
			return (0.18 + 0.82 * sin(PI * pow(clampf(s, 0.0, 1.0), 0.75))) * (1.0 - 0.15 * s)
		KIND_SKIN:
			# Bat-like: wide at the body, scalloped between "fingers".
			var sc := 1.0 - 0.16 * sin(PI * fposmod(s * float(maxi(n_bones, 1)), 1.0))
			return pow(1.0 - clampf(s, 0.0, 1.0), 0.65) * sc
		_:
			# Fin: rounded triangle.
			return sqrt(maxf(0.0, 1.0 - s * s)) * (1.0 - 0.25 * s) + 0.02
	return 1.0


static func _planform(ctx: CreatureBuildContext, a: AnatomyModel.Accessory, chain: PackedInt32Array, slot: int, kind: int) -> void:
	var m := ctx.model
	var edge := Edge.new(m, chain, a.params.get("trail", Vector3.BACK), a.params.get("normal", Vector3.UP))
	var chord := maxf(float(a.params.get("chord", a.size)), 1e-4)
	var parent := m.bones[chain[0]].parent
	var buf := ctx.buffer(CreatureBuildContext.KIND_MEMBRANE)
	var st := MeshKit.param_style(MeshKit.slot_color(slot), float(slot), a.part_id, float(kind), false)
	var ns := MeshLod.seg(ctx.lod, 12, 3)
	var nc := MeshLod.seg(ctx.lod, 6, 2)
	var camber := 0.0 if kind == KIND_INSECT else (0.06 if kind == KIND_SKIN else 0.04)
	var base := buf.vertex_count()
	for i in ns + 1:
		var s := float(i) / float(ns)
		var lead := edge.point(s)
		var tr := edge.frame_vec(s, 0)
		var nr := edge.frame_vec(s, 2)
		var c := chord * _chord_shape(kind, s, chain.size())
		if i == ns:
			c = chord * 0.015
		var cs := edge.chain_s(s)
		for j in nc + 1:
			var u := float(j) / float(nc)
			var p := lead + tr * (c * u) + nr * (c * camber * sin(PI * u))
			# The fin/wing root sits on the body surface.
			if i == 0 and ctx.has_surface() and u > 0.0:
				var sn: Array = ctx.snap(p, -ctx.cell * 0.25, nr, chord)
				if sn[2]:
					p = sn[0]
			var pw := 0.0
			if parent > 0:
				var root_k := 0.65 if kind == KIND_SKIN else 0.4
				pw = root_k * pow(1.0 - s, 4.0) * smoothstep(0.0, 0.6, u) if kind != KIND_INSECT else 0.0
			var w: Array = CreatureRig.chain_weights(chain, cs, 0.3, parent, pw)
			MeshKit.put(buf, p, nr, st, Vector2(s, u), s, Vector3.ZERO, w[0], w[1])
	for i in ns:
		for j in nc:
			var a0 := base + i * (nc + 1) + j
			buf.quad(a0, a0 + 1, a0 + nc + 2, a0 + nc + 1)
	MeshKit.recompute_normals(buf, base, buf.indices.size() - ns * nc * 6)


## Fish caudal fin: forked fan in the plane of the chain axis and the
## body's vertical, rays radiating from the root.
static func _caudal(ctx: CreatureBuildContext, a: AnatomyModel.Accessory, chain: PackedInt32Array, slot: int) -> void:
	var m := ctx.model
	var b0 := m.bones[chain[0]]
	var root := b0.start
	var axis := (m.bones[chain[chain.size() - 1]].end - root)
	var length := axis.length()
	axis = axis.normalized() if length > 1e-6 else b0.basis.y
	var nrm: Vector3 = a.params.get("normal", Vector3.UP)
	var vert := nrm - axis * nrm.dot(axis)
	vert = vert.normalized() if vert.length_squared() > 1e-6 else Vector3.UP
	var chord := maxf(float(a.params.get("chord", a.size)), 1e-4)
	var reach := length * 0.6 + chord * 0.75
	var spread := deg_to_rad(48.0)
	var buf := ctx.buffer(CreatureBuildContext.KIND_MEMBRANE)
	var st := MeshKit.param_style(MeshKit.slot_color(slot), float(slot), a.part_id, float(KIND_FIN), false)
	var nr := MeshLod.seg(ctx.lod, 12, 4)
	var nt := MeshLod.seg(ctx.lod, 5, 2)
	var parent := b0.parent
	var side := axis.cross(vert).normalized()
	var start := root + axis * length * 0.25
	var base := buf.vertex_count()
	for i in nr + 1:
		var q := float(i) / float(nr) * 2.0 - 1.0
		var th := q * spread
		var dir := (axis * cos(th) + vert * sin(th)).normalized()
		var fork := 1.0 + 0.55 * pow(absf(q), 1.6) - 0.3 * pow(1.0 - absf(q), 2.0)
		var lr := reach * fork
		for j in nt + 1:
			var t := float(j) / float(nt)
			var p := start + dir * (lr * t) + side * (sin(t * PI) * chord * 0.015)
			var cs := clampf(t * float(chain.size()), 0.0, float(chain.size()))
			var pw := 0.5 * pow(1.0 - t, 3.0) if parent > 0 else 0.0
			var w: Array = CreatureRig.chain_weights(chain, cs, 0.3, parent, pw)
			MeshKit.put(buf, p, side, st, Vector2(t, (q + 1.0) * 0.5), t, Vector3.ZERO, w[0], w[1])
	for i in nr:
		for j in nt:
			var a0 := base + i * (nt + 1) + j
			buf.quad(a0, a0 + 1, a0 + nt + 2, a0 + nt + 1)


## Whale-like horizontal tail flukes (body material) at the tail tip.
static func fluke(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	var bone := ctx.bone_or_root(a.bone)
	var size := maxf(a.size, 1e-4)
	var axis := a.transform.basis.y.normalized()
	var flat_side := axis.cross(Vector3.UP)
	if flat_side.length_squared() < 1e-6:
		flat_side = a.transform.basis.x
	flat_side = flat_side.normalized()
	var tip := a.transform.origin
	var span := size * 1.1
	var sw := MeshKit.Sweep.new()
	var bi := MeshKit.one_bone(bone)
	var rings := MeshLod.seg(ctx.lod, 14, 5)
	var along := ctx.rig.along_on_bone(bone, tip) if bone > 0 else 0.0
	for i in rings + 1:
		var u := float(i) / float(rings) * 2.0 - 1.0
		var au := absf(u)
		var c := tip + flat_side * (u * span) + axis * (pow(au, 1.5) * span * 0.45 + size * 0.1)
		var width := size * 0.45 * sqrt(maxf(0.0, 1.0 - au * au)) + size * 0.04
		sw.add_ring(c, width, 0.22, axis, bi, MeshKit.W1, (u + 1.0) * 0.5, along + au * span)
	var st := MeshKit.body_style(ctx.slot(a.covering), a.part_id, 0.0, 0.95)
	MeshKit.sweep(ctx.buffer(CreatureBuildContext.KIND_BODY), sw, st, MeshLod.seg(ctx.lod, 10, 5), 2, true)
