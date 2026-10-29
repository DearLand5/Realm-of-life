class_name MouthBuilder
extends RefCounted
## Mouthparts by PartSchema mouth_type: jaws (lip line projected on the head
## surface + teeth by dentition), beak (upper hooked + lower mandible), insect
## mandibles / chelicerae, coiled proboscis, sucker ring, filter fringe,
## radula and cell mouth (cytostome).


static func build(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	var mt := str(a.params.get("mouth_type", "jaws"))
	match mt:
		"beak":
			_beak(ctx, a)
		"mandibles":
			_mandibles(ctx, a)
		"proboscis":
			_proboscis(ctx, a)
		"sucker", "radula":
			_ring_mouth(ctx, a, mt == "radula")
		"filter":
			_filter(ctx, a)
		"cell_mouth":
			_cell_mouth(ctx, a)
		_:
			_jaws(ctx, a)


## Head frame at the mouth: forward, up, side and the head's local radius.
static func _head_frame(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> Dictionary:
	var bone := ctx.bone_or_root(a.bone)
	var m := ctx.model
	var fwd := a.transform.basis.y
	var up := Vector3.UP
	var tip := a.transform.origin
	var r := maxf(float(a.params.get("radius_local", a.size)), 1e-4)
	var chain := PackedInt32Array()
	if bone > 0:
		var hb := m.bones[bone]
		fwd = hb.basis.y
		up = hb.basis.z
		chain = ctx.rig.chain_of(bone)
		tip = hb.end
	var b := MeshKit.frame(fwd, up)
	return {"bone": bone, "fwd": b.y, "up": b.z, "side": b.x, "tip": tip, "r": r, "chain": chain}


## Point on the head axis `dist` behind the tip (walking back along the chain).
static func _axis_back(ctx: CreatureBuildContext, chain: PackedInt32Array, tip: Vector3, fwd: Vector3, dist: float) -> Vector3:
	var left := dist
	for k in range(chain.size() - 1, -1, -1):
		var b := ctx.model.bones[chain[k]]
		if left <= b.length:
			return b.end.lerp(b.start, left / maxf(b.length, 1e-6))
		left -= b.length
	return tip - fwd * dist


static func _jaws(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	if ctx.detail < 1 or not ctx.has_surface():
		return
	var f := _head_frame(ctx, a)
	var chain: PackedInt32Array = f["chain"]
	var fwd: Vector3 = f["fwd"]
	var up: Vector3 = f["up"]
	var side: Vector3 = f["side"]
	var tip: Vector3 = f["tip"]
	var r: float = f["r"]
	var bone: int = f["bone"]
	var head_len := 0.0
	for bi in chain:
		head_len += ctx.model.bones[bi].length
	var gape := minf(maxf(a.size, r) * 1.6, maxf(head_len, r) * 0.85)
	var n := 21 if ctx.lod == 0 else 11
	var guesses := PackedVector3Array()
	for i in n:
		var u := float(i) / float(n - 1) * 2.0 - 1.0     # -1 left corner .. 0 front .. +1 right corner
		var back := absf(u) * gape
		var axis_p := _axis_back(ctx, chain, tip, fwd, back) if not chain.is_empty() else tip - fwd * back
		var rr := ctx.bone_radius_at(bone, axis_p) if bone > 0 else r
		var lateral := smoothstep(0.0, 0.35, absf(u)) * signf(u)
		var g := axis_p + side * (lateral * rr * 1.6) - up * (rr * (0.55 - 0.25 * absf(u))) + fwd * (rr * 1.2 * (1.0 - smoothstep(0.0, 0.3, absf(u))))
		guesses.append(g)
	var pr: Array = SurfaceDecal.project_polyline(ctx, guesses, r * 4.0)
	var pts: PackedVector3Array = pr[0]
	var nrm: PackedVector3Array = pr[1]
	SurfaceDecal.strip(ctx, pts, nrm, maxf(r * 0.045, ctx.cell * 0.06), a.part_id, bone)
	_teeth(ctx, a, pts, nrm, up, r, bone)


static func _teeth(ctx: CreatureBuildContext, a: AnatomyModel.Accessory, pts: PackedVector3Array, nrm: PackedVector3Array, up: Vector3, r: float, bone: int) -> void:
	var teeth := str(a.params.get("teeth", "mixed"))
	if teeth == "none" or teeth == "grinding" or pts.size() < 5 or ctx.detail < 1:
		return
	var n := pts.size()
	var mid := n / 2
	var slot := ctx.slot(a.covering)
	var sk: Array = [MeshKit.one_bone(bone), MeshKit.W1]
	var fang_at := maxi(1, int(round(float(mid) * 0.22)))
	for sgn in [-1, 1]:
		var count := 0
		for k in range(1, mid):
			var i: int = mid + k * int(sgn)
			if i <= 0 or i >= n - 1:
				continue
			var p := pts[i]
			var nn := nrm[i]
			var down := (-up - nn * (-up).dot(nn) * 0.6).normalized()
			var length := 0.0
			var rad := 0.0
			if k == fang_at and (teeth == "fangs" or teeth == "mixed"):
				length = r * (0.5 if teeth == "fangs" else 0.28)
				rad = r * (0.09 if teeth == "fangs" else 0.07)
			elif teeth == "cutting" or (teeth == "mixed" and k < fang_at) or (teeth == "fangs" and k < fang_at):
				if k > mid * 0.75:
					continue
				length = r * (0.13 if teeth == "cutting" else 0.08)
				rad = r * 0.05
			else:
				continue
			if ctx.detail < 2 and length < r * 0.2:
				continue
			var base := p - nn * rad * 0.5 + down * (-length * 0.15)
			AppendageBuilder.cone(ctx, base, down, length, rad, AppendageBuilder.CODE_TOOTH, slot, a.part_id, sk[0][0], 0.8, -nn, 0.35 if length > r * 0.2 else 0.0)
			count += 1


static func _beak(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	var f := _head_frame(ctx, a)
	var bone: int = f["bone"]
	var r: float = f["r"]
	var fwd := a.transform.basis.y.normalized()
	var up_h: Vector3 = f["up"]
	var up := (up_h - fwd * up_h.dot(fwd))
	up = up.normalized() if up.length_squared() > 1e-6 else MeshKit.frame(fwd, Vector3.UP).z
	var length := maxf(a.size, r) * 1.9
	var base_r := r * 0.98
	var slot := ctx.slot(a.covering)
	var o := a.transform.origin - fwd * r * 0.75
	var rings := MeshLod.seg(ctx.lod, 10, 3)
	# Upper mandible: hooked down at the tip.
	AppendageBuilder.arc_cone(ctx, ctx.buffer(CreatureBuildContext.KIND_HARD), o + up * r * 0.12, fwd, -up, length, base_r * 0.92,
		0.55, 0.78, 0.8, AppendageBuilder.CODE_BEAK, slot, a.part_id, bone, rings)
	# Lower mandible: shorter, flatter, straight.
	if ctx.detail >= 1:
		AppendageBuilder.arc_cone(ctx, ctx.buffer(CreatureBuildContext.KIND_HARD), o - up * r * 0.3, fwd, -up, length * 0.8, base_r * 0.72,
			0.12, 0.55, 0.9, AppendageBuilder.CODE_BEAK, slot, a.part_id, bone, maxi(rings - 2, 2))


static func _mandibles(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	var f := _head_frame(ctx, a)
	var bone: int = f["bone"]
	var r: float = f["r"]
	var side: Vector3 = f["side"]
	var fwd := a.transform.basis.y.normalized()
	var length := maxf(a.size, r * 0.3) * 1.1
	var slot := ctx.slot(a.covering)
	for sg in [-1.0, 1.0]:
		var s := float(sg)
		var o := a.transform.origin + side * (s * r * 0.38)
		var dir := (fwd + side * s * 0.35).normalized()
		AppendageBuilder.arc_cone(ctx, ctx.buffer(CreatureBuildContext.KIND_HARD), o, dir, -side * s, length, length * 0.2,
			1.1, 0.6, 0.9, AppendageBuilder.CODE_MANDIBLE, slot, a.part_id, bone, MeshLod.seg(ctx.lod, 8, 3))


static func _proboscis(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	var f := _head_frame(ctx, a)
	var bone: int = f["bone"]
	var fwd := a.transform.basis.y.normalized()
	var up: Vector3 = f["up"]
	var length := maxf(a.size, 1e-4) * 3.0
	var rad := maxf(a.size, 1e-4) * 0.07
	var sw := MeshKit.Sweep.new()
	var rings := MeshLod.seg(ctx.lod, 18, 6)
	var bi := MeshKit.one_bone(bone)
	# Straight then coiling under the head (spiral in the fwd/up plane).
	for i in rings + 1:
		var t := float(i) / float(rings)
		var ang := t * t * PI * 2.2
		var rr := length * 0.35 * (1.0 - t * 0.6)
		var c := a.transform.origin + fwd * (sin(ang) * rr + t * length * 0.15) - up * ((1.0 - cos(ang)) * rr)
		sw.add_ring(c, rad * (1.0 - t * 0.6), 1.0, up, bi, MeshKit.W1, t)
	var st := MeshKit.param_style(MeshKit.slot_color(ctx.slot(a.covering)), float(AppendageBuilder.CODE_MANDIBLE), a.part_id, float(AppendageBuilder.CODE_MANDIBLE))
	MeshKit.sweep(ctx.buffer(CreatureBuildContext.KIND_HARD), sw, st, MeshLod.tube_sides(ctx.lod, 0.2), 2)


## Sucker (worms, starfish) or radula: soft ring around a dark opening.
static func _ring_mouth(ctx: CreatureBuildContext, a: AnatomyModel.Accessory, radula: bool) -> void:
	var bone := ctx.bone_or_root(a.bone)
	var size := maxf(a.size, 1e-4)
	var s: Array = ctx.snap(a.transform.origin, 0.0, a.transform.basis.y, size * 4.0)
	var p: Vector3 = s[0]
	var n: Vector3 = s[1] if s[2] else a.transform.basis.y
	var ring_r := size * 0.45
	var st := MeshKit.body_style(ctx.slot(a.covering), a.part_id, ctx.rig.along_on_bone(bone, p) if bone > 0 else 0.0, 0.7)
	var sk: Array = ctx.skin_at(p, bone)
	var seg := MeshLod.seg(ctx.lod, 18, 6)
	MeshKit.torus(ctx.buffer(CreatureBuildContext.KIND_BODY), p - n * size * 0.04, n, MathUtil.basis_from_y(n).x, ring_r, size * 0.13, seg, maxi(4, seg / 3), st, sk[0], sk[1])
	var dark := MeshKit.param_style(Color(1, 0, 0, 0), float(AppendageBuilder.CODE_DARK), a.part_id, float(AppendageBuilder.CODE_DARK))
	MeshKit.ellipsoid(ctx.buffer(CreatureBuildContext.KIND_HARD), Transform3D(MeshKit.frame(n, Vector3.UP), p - n * size * 0.06),
		Vector3(ring_r * 0.95, size * 0.06, ring_r * 0.95), seg, 3, dark, sk[0], sk[1])
	if radula and ctx.detail >= 2:
		var tooth := MeshKit.param_style(Color(1, 0, 0, 0), float(AppendageBuilder.CODE_TOOTH), a.part_id, float(AppendageBuilder.CODE_TOOTH))
		MeshKit.ellipsoid(ctx.buffer(CreatureBuildContext.KIND_HARD), Transform3D(MeshKit.frame(n, Vector3.UP), p),
			Vector3(ring_r * 0.45, size * 0.05, ring_r * 0.2), 8, 3, tooth, sk[0], sk[1])


## Filter feeders: dark opening with a fringe of short tapering filaments.
static func _filter(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	var bone := ctx.bone_or_root(a.bone)
	var size := maxf(a.size, 1e-4)
	var s: Array = ctx.snap(a.transform.origin, 0.0, a.transform.basis.y, size * 4.0)
	var p: Vector3 = s[0]
	var n: Vector3 = s[1] if s[2] else a.transform.basis.y
	var b := MeshKit.frame(n, Vector3.FORWARD)
	var sk: Array = ctx.skin_at(p, bone)
	var dark := MeshKit.param_style(Color(1, 0, 0, 0), float(AppendageBuilder.CODE_DARK), a.part_id, float(AppendageBuilder.CODE_DARK))
	MeshKit.ellipsoid(ctx.buffer(CreatureBuildContext.KIND_HARD), Transform3D(b, p - n * size * 0.05), Vector3(size * 0.35, size * 0.06, size * 0.35), 12, 3, dark, sk[0], sk[1])
	if ctx.detail < 1:
		return
	var count := 14 if ctx.lod == 0 else 8
	var slot := ctx.slot(a.covering)
	var body := ctx.buffer(CreatureBuildContext.KIND_BODY)
	var st := MeshKit.body_style(slot, a.part_id, 0.0, 0.85)
	for k in count:
		var ang := TAU * float(k) / float(count)
		var radial := b.x * cos(ang) + b.z * sin(ang)
		var base := p + radial * size * 0.38
		var sw := MeshKit.Sweep.new()
		for i in 4:
			var t := float(i) / 3.0
			sw.add_ring(base + n * (t * size * 0.7) + radial * (t * t * size * 0.25), size * 0.05 * (1.0 - t * 0.85), 1.0, radial, sk[0], sk[1], t)
		MeshKit.sweep(body, sw, st, 4, 1, false, 0.4)


static func _cell_mouth(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	var bone := ctx.bone_or_root(a.bone)
	var size := maxf(a.size, 1e-4)
	var s: Array = ctx.snap(a.transform.origin, 0.0, a.transform.basis.y, size * 6.0)
	if not s[2]:
		return
	var p: Vector3 = s[0]
	var n: Vector3 = s[1]
	var sk: Array = ctx.skin_at(p, bone)
	var dark := MeshKit.param_style(Color(1, 0, 0, 0), float(AppendageBuilder.CODE_DARK), a.part_id, float(AppendageBuilder.CODE_DARK))
	var seg := MeshLod.seg(ctx.lod, 16, 6)
	MeshKit.torus(ctx.buffer(CreatureBuildContext.KIND_HARD), p, n, MathUtil.basis_from_y(n).x, size * 0.45, size * 0.06, seg, 4, dark, sk[0], sk[1])
	MeshKit.ellipsoid(ctx.buffer(CreatureBuildContext.KIND_HARD), Transform3D(MeshKit.frame(n, Vector3.UP), p - n * size * 0.08),
		Vector3(size * 0.4, size * 0.05, size * 0.4), seg, 3, dark, sk[0], sk[1])
