class_name FootBuilder
extends RefCounted
## Limb ends by PartSchema foot type: hoof (keratin cone, cleft when
## digits ≥ 2), pad (soft paw with toe beans), claw (paw + curved claws, or
## paired hooks on thin arthropod legs), web (splayed digits with webbing),
## sucker (adhesive disc), hand (palm, fingers, thumb). Walking feet sit flat
## on the ground plane; other limbs use the bone frame.

const WALKING: Array[String] = ["walk", "run", "climb", "dig"]


static func build(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	var ft := str(a.params.get("foot", "pad"))
	if ft == "none":
		return
	var bone := ctx.bone_or_root(a.bone)
	var b := ctx.model.bones[bone]
	var r := maxf(a.size, 1e-4)
	var e := a.transform.origin
	var axis := a.transform.basis.y.normalized()
	var walking := WALKING.has(str(a.params.get("function", "none")))
	var digits := clampi(int(a.params.get("digits", 4)), 0, 8)
	var f := {}
	if walking:
		var fwd := Vector3(float(a.side) * 0.18, 0.0, -1.0).normalized()
		f = {"up": Vector3.UP, "fwd": fwd, "side": Vector3.UP.cross(fwd).normalized() * -1.0, "ground": e.y - r}
	else:
		var bb := MeshKit.frame(axis, b.basis.z)
		f = {"up": bb.z, "fwd": axis, "side": bb.x, "ground": 0.0}
	if b.thin:
		var leg_cov := ctx.covering_type(b.covering)
		if walking and leg_cov != &"chitin" and leg_cov != &"bristles" and ft != "web":
			_thin_toes(ctx, a, e, r, f, bone)   # birds, small vertebrates
		elif ft == "claw" or ft == "hand" or ft == "pad":
			_hooks(ctx, a, e, axis, r, bone)    # arthropod tarsi
		elif ft == "web":
			_web(ctx, a, e, r * 1.4, f, maxi(digits, 3), bone, walking)
		return
	match ft:
		"hoof":
			_hoof(ctx, a, e, r, f, digits, bone)
		"web":
			_web(ctx, a, e, r, f, maxi(digits, 3), bone, walking)
		"sucker":
			_sucker(ctx, a, e, r, f, bone, walking)
		"hand":
			_hand(ctx, a, e, r, axis, b, maxi(digits, 2), bone)
		_:
			_paw(ctx, a, e, r, f, digits, bone, ft == "claw", walking)


static func _hoof(ctx: CreatureBuildContext, a: AnatomyModel.Accessory, e: Vector3, r: float, f: Dictionary, digits: int, bone: int) -> void:
	var up: Vector3 = f["up"]
	var fwd: Vector3 = f["fwd"]
	var side: Vector3 = f["side"]
	var g: float = f["ground"]
	var sw := MeshKit.Sweep.new()
	var bi := MeshKit.one_bone(bone)
	var heights: Array[float] = [0.04, 0.35, 0.8, 1.25]
	var radii: Array[float] = [1.22, 1.17, 1.07, 0.96]
	var fwd_off: Array[float] = [0.22, 0.16, 0.06, 0.0]
	var base := Vector3(e.x, g, e.z)
	for i in heights.size():
		sw.add_ring(base + up * (heights[i] * r) + fwd * (fwd_off[i] * r), radii[i] * r, 1.12, side, bi, MeshKit.W1, heights[i] / 1.25)
	var st := MeshKit.param_style(MeshKit.slot_color(ctx.slot(a.covering)), float(AppendageBuilder.CODE_HOOF), a.part_id, float(AppendageBuilder.CODE_HOOF))
	MeshKit.sweep(ctx.buffer(CreatureBuildContext.KIND_HARD), sw, st, MeshLod.seg(ctx.lod, 14, 6), 0, true)
	if digits >= 2 and ctx.detail >= 1:
		# Cleft between the two toes at the front.
		var pts := PackedVector3Array()
		var nrm := PackedVector3Array()
		for i in 3:
			var h := float(i) / 2.0 * 0.75
			var rad := lerpf(1.22, 1.1, h / 0.75) * r * 1.12
			pts.append(base + up * (0.05 * r + h * r) + fwd * (rad + lerpf(0.22, 0.1, h / 0.75) * r))
			nrm.append(fwd)
		SurfaceDecal.strip(ctx, pts, nrm, r * 0.07, a.part_id, bone, AppendageBuilder.CODE_DARK, false)


static func _paw(ctx: CreatureBuildContext, a: AnatomyModel.Accessory, e: Vector3, r: float, f: Dictionary, digits: int,
		bone: int, claws: bool, walking: bool) -> void:
	var up: Vector3 = f["up"]
	var fwd: Vector3 = f["fwd"]
	var side: Vector3 = f["side"]
	var g: float = f["ground"]
	var slot := ctx.slot(ctx.model.bones[bone].covering)
	var along := ctx.rig.along_on_bone(bone, e)
	var st := MeshKit.body_style(slot, a.part_id, along, 0.85)
	var bi := MeshKit.one_bone(bone)
	var body := ctx.buffer(CreatureBuildContext.KIND_BODY)
	var b := Basis(side, up, -fwd).orthonormalized()
	var center := (Vector3(e.x, g + r * 0.5, e.z) if walking else e) + fwd * r * 0.3
	MeshKit.ellipsoid(body, Transform3D(b, center), Vector3(r * 1.12, r * 0.55, r * 1.35), MeshLod.seg(ctx.lod, 14, 6), MeshLod.seg(ctx.lod, 8, 4), st, bi, MeshKit.W1)
	if ctx.detail < 1 or digits <= 0:
		return
	var n := clampi(digits, 1, 6)
	var toe_r := r * (0.42 if n <= 4 else 0.34)
	var biped := int(ctx.model.stats.get("support_count", 4)) <= 2
	for k in n:
		var u := (float(k) / float(maxi(n - 1, 1)) - 0.5) if n > 1 else 0.0
		var ang := u * deg_to_rad(95.0 if not claws else 80.0)
		var dir := (fwd * cos(ang) + side * sin(ang)).normalized()
		if claws and biped:
			# Bipeds: long splayed digits ending in curved claws (birds, theropods).
			var len_k := r * (1.9 - 0.6 * absf(u))
			var sw := MeshKit.Sweep.new()
			var rings := 3 if ctx.lod == 0 else 2
			var start := center + dir * r * 0.5 - up * r * 0.1
			for i in rings + 1:
				var t := float(i) / float(rings)
				sw.add_ring(start + dir * (len_k * t) + up * (sin(t * PI) * r * 0.15 - t * r * 0.15), toe_r * lerpf(0.95, 0.7, t), 0.8, dir.cross(up), bi, MeshKit.W1, t)
			MeshKit.sweep(body, sw, st, MeshLod.tube_sides(ctx.lod, 0.4), 2)
			var tip := start + dir * len_k - up * r * 0.12
			AppendageBuilder.cone(ctx, tip, (dir + up * 0.35).normalized(), toe_r * 1.6, toe_r * 0.5, AppendageBuilder.CODE_CLAW, slot, a.part_id, bone, 0.6, -up, 1.0)
		else:
			# Compact toe beans; quadruped claws peek out in front of them.
			var tc := center + dir * r * 1.15 + up * (-r * 0.12)
			var tb := Basis(dir.cross(up).normalized(), up, -dir).orthonormalized()
			MeshKit.ellipsoid(body, Transform3D(tb, tc), Vector3(toe_r, toe_r * 0.8, toe_r * 1.15), MeshLod.seg(ctx.lod, 10, 5), MeshLod.seg(ctx.lod, 6, 3), st, bi, MeshKit.W1)
			if claws:
				var co := tc + dir * toe_r * 0.8 + up * toe_r * 0.1
				AppendageBuilder.cone(ctx, co, (dir + up * 0.2).normalized(), toe_r * 1.3, toe_r * 0.38, AppendageBuilder.CODE_CLAW, slot, a.part_id, bone, 0.6, -up, 0.9)


## Thin bird-like toes: three spread forward, one (hallux) back, each with a claw.
static func _thin_toes(ctx: CreatureBuildContext, a: AnatomyModel.Accessory, e: Vector3, r: float, f: Dictionary, bone: int) -> void:
	var up: Vector3 = f["up"]
	var fwd: Vector3 = f["fwd"]
	var side: Vector3 = f["side"]
	var g: float = f["ground"]
	var slot := ctx.slot(ctx.model.bones[bone].covering)
	var st := MeshKit.body_style(slot, a.part_id, ctx.rig.along_on_bone(bone, e), 0.9)
	var bi := MeshKit.one_bone(bone)
	var body := ctx.buffer(CreatureBuildContext.KIND_BODY)
	var base := Vector3(e.x, g + r * 0.6, e.z)
	var angles: Array[float] = [-32.0, 0.0, 32.0, 180.0]
	for k in angles.size():
		var ang := deg_to_rad(angles[k])
		var dir := (fwd * cos(ang) + side * sin(ang)).normalized()
		var len_k := r * (4.2 if k == 1 else (3.3 if k < 3 else 2.4))
		var sw := MeshKit.Sweep.new()
		for i in 3:
			var t := float(i) / 2.0
			sw.add_ring(base + dir * (len_k * t) - up * (r * 0.45 * t), r * lerpf(0.75, 0.5, t), 0.8, dir.cross(up), bi, MeshKit.W1, t)
		MeshKit.sweep(body, sw, st, MeshLod.tube_sides(ctx.lod, 0.2), 2)
		if ctx.detail >= 1:
			AppendageBuilder.cone(ctx, base + dir * len_k - up * r * 0.45, (dir - up * 0.3).normalized(), r * 1.3, r * 0.4,
				AppendageBuilder.CODE_CLAW, slot, a.part_id, bone, 0.6, -up, 0.8)


## Paired tarsal hooks at the tip of thin arthropod legs.
static func _hooks(ctx: CreatureBuildContext, a: AnatomyModel.Accessory, e: Vector3, axis: Vector3, r: float, bone: int) -> void:
	if ctx.detail < 1:
		return
	var b := MeshKit.frame(axis, Vector3.UP)
	var slot := ctx.slot(ctx.model.bones[bone].covering)
	for sg in [-1.0, 1.0]:
		var dir := (axis + b.x * float(sg) * 0.45).normalized()
		AppendageBuilder.cone(ctx, e, dir, r * 2.6, r * 0.55, AppendageBuilder.CODE_CLAW, slot, a.part_id, bone, 0.7, Vector3.DOWN, 0.8)


static func _web(ctx: CreatureBuildContext, a: AnatomyModel.Accessory, e: Vector3, r: float, f: Dictionary, digits: int, bone: int, walking: bool) -> void:
	var up: Vector3 = f["up"]
	var fwd: Vector3 = f["fwd"]
	var side: Vector3 = f["side"]
	var g: float = f["ground"]
	var slot := ctx.slot(ctx.model.bones[bone].covering)
	var along := ctx.rig.along_on_bone(bone, e)
	var st := MeshKit.body_style(slot, a.part_id, along, 0.9)
	var bi := MeshKit.one_bone(bone)
	var body := ctx.buffer(CreatureBuildContext.KIND_BODY)
	var base := (Vector3(e.x, g + r * 0.45, e.z) if walking else e)
	var n := clampi(digits, 3, 6)
	var length := r * 5.2
	var rays: Array[PackedVector3Array] = []
	var rings := 3 if ctx.lod == 0 else 2
	for k in n:
		var u := float(k) / float(n - 1) - 0.5
		var ang := u * deg_to_rad(110.0)
		var dir := (fwd * cos(ang) + side * sin(ang) * float(signf(e.x) if e.x != 0.0 else 1.0)).normalized()
		var len_k := length * (1.0 - 0.35 * absf(u) * 2.0 * 0.5) * (1.1 if k == n - 2 else 1.0)
		var sw := MeshKit.Sweep.new()
		var pts := PackedVector3Array()
		for i in rings + 1:
			var t := float(i) / float(rings)
			var c := base + dir * (len_k * t) + up * (sin(t * PI) * r * 0.25 - t * r * 0.2)
			pts.append(c)
			sw.add_ring(c, r * lerpf(0.4, 0.22, t), 0.75, dir.cross(up), bi, MeshKit.W1, t)
		rays.append(pts)
		MeshKit.sweep(body, sw, st, MeshLod.tube_sides(ctx.lod, 0.3), 2)
	if ctx.detail < 1:
		return
	var mem := ctx.buffer(CreatureBuildContext.KIND_MEMBRANE)
	var mst := MeshKit.param_style(MeshKit.slot_color(slot), float(slot), a.part_id, 3.0, false)
	for k in n - 1:
		var p0 := rays[k]
		var p1 := rays[k + 1]
		var v0 := mem.vertex_count()
		for i in p0.size():
			var t := float(i) / float(p0.size() - 1)
			var reach := 1.0 - 0.25 * t
			var q0 := p0[i]
			var q1 := p0[i].lerp(p1[i], reach) if i > 0 else p1[i]
			var nn := (q1 - q0).cross(p0[mini(i + 1, p0.size() - 1)] - p0[maxi(i - 1, 0)]).normalized()
			if nn.dot(up) < 0.0:
				nn = -nn
			MeshKit.put(mem, q0, nn, mst, Vector2(t, 0.0), t, Vector3.ZERO, bi, MeshKit.W1)
			MeshKit.put(mem, q0.lerp(q1, 0.5) - up * r * 0.08 * sin(t * PI), nn, mst, Vector2(t, 0.5), t, Vector3.ZERO, bi, MeshKit.W1)
			MeshKit.put(mem, q1, nn, mst, Vector2(t, 1.0), t, Vector3.ZERO, bi, MeshKit.W1)
		for i in p0.size() - 1:
			var a0 := v0 + i * 3
			mem.quad(a0, a0 + 1, a0 + 4, a0 + 3)
			mem.quad(a0 + 1, a0 + 2, a0 + 5, a0 + 4)


static func _sucker(ctx: CreatureBuildContext, a: AnatomyModel.Accessory, e: Vector3, r: float, f: Dictionary, bone: int, walking: bool) -> void:
	var up: Vector3 = f["up"]
	var g: float = f["ground"]
	var slot := ctx.slot(ctx.model.bones[bone].covering)
	var st := MeshKit.body_style(slot, a.part_id, ctx.rig.along_on_bone(bone, e), 0.75)
	var bi := MeshKit.one_bone(bone)
	var c := Vector3(e.x, g + r * 0.2, e.z) if walking else e + (f["fwd"] as Vector3) * r * 0.6
	var n := up if walking else (f["fwd"] as Vector3)
	var seg := MeshLod.seg(ctx.lod, 16, 6)
	MeshKit.torus(ctx.buffer(CreatureBuildContext.KIND_BODY), c, n, MathUtil.basis_from_y(n).x, r * 1.0, r * 0.28, seg, maxi(4, seg / 3), st, bi, MeshKit.W1)
	var dark := MeshKit.param_style(Color(1, 0, 0, 0), float(AppendageBuilder.CODE_DARK), a.part_id, float(AppendageBuilder.CODE_DARK))
	MeshKit.ellipsoid(ctx.buffer(CreatureBuildContext.KIND_HARD), Transform3D(MeshKit.frame(n, Vector3.FORWARD), c - n * r * 0.1),
		Vector3(r * 0.85, r * 0.1, r * 0.85), seg, 3, dark, bi, MeshKit.W1)


static func _hand(ctx: CreatureBuildContext, a: AnatomyModel.Accessory, e: Vector3, r: float, axis: Vector3, b: AnatomyModel.Bone, digits: int, bone: int) -> void:
	var slot := ctx.slot(b.covering)
	var st := MeshKit.body_style(slot, a.part_id, ctx.rig.along_on_bone(bone, e), 0.85)
	var bi := MeshKit.one_bone(bone)
	var body := ctx.buffer(CreatureBuildContext.KIND_BODY)
	var fr := MeshKit.frame(axis, b.basis.z)
	var palm_c := e + axis * r * 0.7
	MeshKit.ellipsoid(body, Transform3D(fr, palm_c), Vector3(r * 1.05, r * 1.0, r * 0.6), MeshLod.seg(ctx.lod, 12, 6), MeshLod.seg(ctx.lod, 8, 4), st, bi, MeshKit.W1)
	if ctx.detail < 1:
		return
	var fingers := clampi(digits - 1, 1, 5)
	var rings := 3 if ctx.lod == 0 else 2
	for k in fingers + 1:
		var thumb := k == fingers
		var u := (float(k) / float(maxi(fingers - 1, 1)) - 0.5) if fingers > 1 else 0.0
		var start := palm_c + axis * r * 0.7 + fr.x * (u * r * 1.2)
		var dir := (axis + fr.x * u * 0.35).normalized()
		var len_k := r * 2.0 * (1.0 - absf(u) * 0.3)
		if thumb:
			start = palm_c + fr.x * r * 0.95 * float(signf(e.x) if e.x != 0.0 else 1.0)
			dir = (fr.x * float(signf(e.x) if e.x != 0.0 else 1.0) + axis * 0.6).normalized()
			len_k = r * 1.4
		var sw := MeshKit.Sweep.new()
		for i in rings + 1:
			var t := float(i) / float(rings)
			var curl := -fr.z * (t * t * len_k * 0.35)
			sw.add_ring(start + dir * (len_k * t) + curl, r * lerpf(0.32, 0.22, t), 0.85, fr.x, bi, MeshKit.W1, t)
		MeshKit.sweep(body, sw, st, MeshLod.tube_sides(ctx.lod, 0.3), 2)
