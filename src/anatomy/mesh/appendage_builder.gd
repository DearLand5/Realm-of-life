class_name AppendageBuilder
extends RefCounted
## Hard pointed appendages in the hard material: curved tapered horns,
## spikes and claws (circular-arc centre lines, laterally compressed
## sections), whiskers, and small cones used for teeth / spinnerets.

const CODE_HORN := 0
const CODE_CLAW := 1
const CODE_HOOF := 2
const CODE_TOOTH := 3
const CODE_BEAK := 4
const CODE_MANDIBLE := 5
const CODE_WHISKER := 6
const CODE_DARK := 7
const CODE_RHINARIUM := 8
const CODE_SPIKE := 9


static func horn(ctx: CreatureBuildContext, a: AnatomyModel.Accessory, code: int) -> void:
	var length := maxf(float(a.params.get("length_m", a.size)), 1e-4)
	var base := maxf(float(a.params.get("base_m", length * 0.2)), length * 0.03)
	var curv := float(a.params.get("curvature", 0.0)) if code != CODE_SPIKE else 0.0
	var y := a.transform.basis.y.normalized()
	var o := a.transform.origin
	# Bend plane: horns sweep back (and slightly outwards), claws curl down.
	var hint := Vector3.BACK
	if code == CODE_HORN and a.side != 0:
		hint = (Vector3.BACK + Vector3.RIGHT * float(a.side) * 0.45).normalized()
	elif code == CODE_CLAW:
		hint = Vector3.DOWN
	var d := hint - y * hint.dot(y)
	if d.length_squared() < 1e-6:
		d = a.transform.basis.x - y * a.transform.basis.x.dot(y)
	d = d.normalized()
	if curv < 0.0:
		d = -d
		curv = -curv
	var max_angle := PI * 0.75 if code == CODE_HORN else PI * 0.55
	var flat := 0.85 if code == CODE_HORN else (0.55 if code == CODE_CLAW else 1.0)
	var taper := 0.85 if code == CODE_HORN else 1.0
	arc_cone(ctx, ctx.buffer(CreatureBuildContext.KIND_HARD), o, y, d, length, base, curv * max_angle, flat, taper,
		code, ctx.slot(a.covering), a.part_id, ctx.bone_or_root(a.bone), MeshLod.seg(ctx.lod, 12, 3))


## Tapered cone along a circular arc starting at `o` in direction `y`, bending
## towards `d` by `angle` radians over `length`.
static func arc_cone(ctx: CreatureBuildContext, buf: MeshBuffer, o: Vector3, y: Vector3, d: Vector3, length: float, base: float,
		angle: float, flat: float, taper: float, code: int, slot: int, part_id: int, bone: int, rings: int, tip_r: float = 0.0) -> void:
	var sw := MeshKit.Sweep.new()
	var bi := MeshKit.one_bone(bone)
	rings = maxi(rings, 2)
	for i in rings + 1:
		var t := float(i) / float(rings)
		var c: Vector3
		if absf(angle) < 1e-3:
			c = o + y * (length * t)
		else:
			var ang := angle * t
			c = o + (y * sin(ang) + d * (1.0 - cos(ang))) * (length / angle)
		var r := lerpf(base, tip_r, pow(t, taper))
		if i == rings:
			r = maxf(tip_r, base * 0.04)
		sw.add_ring(c, r, flat, d, bi, MeshKit.W1, t)
	var st := MeshKit.param_style(MeshKit.slot_color(slot), float(code), part_id, float(code))
	var sides := MeshLod.tube_sides(ctx.lod, base / maxf(ctx.cell, 1e-6))
	MeshKit.sweep(buf, sw, st, sides, 1, false, 0.5)


## Straight cone (teeth, spinnerets, small spines).
static func cone(ctx: CreatureBuildContext, o: Vector3, dir: Vector3, length: float, radius: float, code: int,
		slot: int, part_id: int, bone: int, flat: float = 1.0, bend: Vector3 = Vector3.ZERO, bend_angle: float = 0.0) -> void:
	var y := dir.normalized()
	var d := bend - y * bend.dot(y)
	if d.length_squared() < 1e-8:
		d = MathUtil.basis_from_y(y).x
	arc_cone(ctx, ctx.buffer(CreatureBuildContext.KIND_HARD), o, y, d.normalized(), length, radius, bend_angle, flat, 1.0,
		code, slot, part_id, bone, 2 if ctx.lod > 0 else 3)


## Whiskers: a fan of thin drooping hairs from the muzzle side.
static func whiskers(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	if ctx.detail < 1:
		return
	var count := clampi(int(a.params.get("count", 4)), 1, 12)
	var length := maxf(a.size, 1e-4)
	var bone := ctx.bone_or_root(a.bone)
	var hb := ctx.model.bones[bone]
	var fwd := hb.basis.y if bone > 0 else Vector3.FORWARD
	var y := a.transform.basis.y.normalized()
	var up := Vector3.UP - y * Vector3.UP.dot(y)
	up = up.normalized() if up.length_squared() > 1e-6 else Vector3.UP
	var fw := (fwd - y * fwd.dot(y))
	fw = fw.normalized() if fw.length_squared() > 1e-6 else up.cross(y)
	var o := a.transform.origin
	if ctx.has_surface():
		var s: Array = ctx.snap(o, 0.0, y, length)
		if s[2]:
			o = s[0]
			y = s[1]
	var rings := 4 if ctx.lod == 0 else 3
	var st := MeshKit.param_style(MeshKit.slot_color(ctx.slot(a.covering)), float(CODE_WHISKER), a.part_id, float(CODE_WHISKER))
	var bi := MeshKit.one_bone(bone)
	for k in count:
		var u := float(k) / float(maxi(count - 1, 1)) - 0.5
		var base := o + up * (u * length * 0.12) + fw * (absf(u) * length * 0.05)
		var dir := (y * 1.0 + fw * (0.45 - absf(u) * 0.5) + up * (u * 0.7)).normalized()
		var sw := MeshKit.Sweep.new()
		var len_k := length * (0.85 + 0.3 * Rng.hash01(a.part_id, k, a.side))
		for i in rings + 1:
			var t := float(i) / float(rings)
			var droop := (-up * 0.28 - fw * 0.22) * t * t * len_k
			var c := base + dir * (len_k * t) + droop
			sw.add_ring(c, length * 0.011 * (1.0 - t * 0.9), 1.0, up, bi, MeshKit.W1, t)
		MeshKit.sweep(ctx.buffer(CreatureBuildContext.KIND_HARD), sw, st, 3, 1, false, 0.3)
