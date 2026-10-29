class_name MiscPartBuilder
extends RefCounted
## Gill slits / opercula, sensory pores and lateral lines, glands
## (spinnerets, warts, scent patches), bioluminescent light organs, cell
## organelles and internal organs (x-ray only).

const ORGAN_COLORS := {
	"stomach": Color(0.93, 0.55, 0.45), "gut": Color(0.85, 0.62, 0.5), "gizzard": Color(0.62, 0.32, 0.25),
	"lungs": Color(0.95, 0.6, 0.65), "trachea": Color(0.92, 0.9, 0.85), "swim_bladder": Color(0.85, 0.9, 0.95),
	"heart": Color(0.85, 0.12, 0.15), "brain": Color(0.92, 0.72, 0.75), "gonads": Color(0.95, 0.85, 0.4),
	"fat_body": Color(0.98, 0.92, 0.65), "liver": Color(0.5, 0.15, 0.12), "kidney": Color(0.6, 0.2, 0.25),
	"venom_gland": Color(0.4, 0.85, 0.3), "electric_organ": Color(0.35, 0.6, 1.0), "photo_tissue": Color(0.3, 0.8, 0.35),
	"custom": Color(0.7, 0.5, 0.95),
}


static func gill(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	if ctx.detail < 1 or not ctx.has_surface():
		return
	var bone := ctx.bone_or_root(a.bone)
	var b := ctx.model.bones[bone]
	var slits := clampi(int(a.params.get("slits", 4)), 1, 8)
	var size := maxf(a.size, 1e-4)
	var back := -b.basis.y if bone > 0 else Vector3.BACK
	var out := a.transform.basis.y.normalized()
	var up := (Vector3.UP - out * Vector3.UP.dot(out))
	up = up.normalized() if up.length_squared() > 1e-6 else b.basis.z
	var height := size * 0.75
	var spacing := size * 0.22
	var n := 7 if ctx.lod == 0 else 5
	for k in slits:
		var guesses := PackedVector3Array()
		var c := a.transform.origin + back * (spacing * float(k)) + out * size * 0.4
		var h := height * (1.0 - 0.12 * float(k))
		for i in n:
			var v := float(i) / float(n - 1) * 2.0 - 1.0
			guesses.append(c + up * (v * h * 0.5) - back * ((1.0 - v * v) * h * 0.18))
		var pr: Array = SurfaceDecal.project_polyline(ctx, guesses, size * 3.0)
		SurfaceDecal.strip(ctx, pr[0], pr[1], maxf(size * 0.035, ctx.cell * 0.05), a.part_id, bone)


static func sensor(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	if ctx.detail < 1 or not ctx.has_surface():
		return
	var st_type := str(a.params.get("sensor_type", "electro"))
	var bone := ctx.bone_or_root(a.bone)
	var size := maxf(a.size, 1e-4)
	var r_local := float(a.params.get("radius_local", size * 4.0))
	match st_type:
		"vibration":
			_lateral_line(ctx, a, bone, r_local)
		"thermal":
			var y := a.transform.basis.y
			var side := MeshKit.frame(y, Vector3.UP).x
			for k in 3:
				SurfaceDecal.dot(ctx, a.transform.origin + side * (float(k - 1) * size * 1.4), size * 0.35, a.part_id, bone, side, 1.3, 0.5)
		"polarized":
			var e := AnatomyModel.Accessory.new()
			e.type = &"eye"
			e.bone = a.bone
			e.part_id = a.part_id
			e.transform = a.transform
			e.size = size * 0.6
			e.params = {"eye_type": "ocellus", "iris_color": Color(0.3, 0.6, 0.9)}
			EyeBuilder.build(ctx, e)
		"magnetic":
			SurfaceDecal.dot(ctx, a.transform.origin, size * 0.25, a.part_id, bone)
		_:
			# Electroreceptive ampullae: a cluster of pores.
			var rr := Rng.new(a.part_id * 31 + a.side + 7)
			var count := 9 if ctx.lod == 0 else 5
			var b := MeshKit.frame(a.transform.basis.y, Vector3.UP)
			for k in count:
				var off := (b.x * rr.range_f(-1.0, 1.0) + b.z * rr.range_f(-1.0, 1.0)) * size * 1.6
				SurfaceDecal.dot(ctx, a.transform.origin + off, size * 0.12, a.part_id, bone)


## Lateral line: a thin dark line along the parent chain at the attach angle.
static func _lateral_line(ctx: CreatureBuildContext, a: AnatomyModel.Accessory, bone: int, r_local: float) -> void:
	var chain := ctx.rig.chain_of(bone)
	if chain.is_empty():
		return
	var out := a.transform.basis.y.normalized()
	var guesses := PackedVector3Array()
	var samples := 16 if ctx.lod == 0 else 9
	var first := ctx.model.bones[chain[0]]
	var last := ctx.model.bones[chain[chain.size() - 1]]
	var total := 0.0
	for bi in chain:
		total += ctx.model.bones[bi].length
	for i in samples:
		var t := lerpf(0.06, 0.94, float(i) / float(samples - 1)) * total
		var acc := 0.0
		var p := first.start
		for bi in chain:
			var b := ctx.model.bones[bi]
			if acc + b.length >= t:
				p = b.start.lerp(b.end, (t - acc) / maxf(b.length, 1e-6))
				break
			acc += b.length
			p = last.end
		var rr := ctx.bone_radius_at(bone, p)
		guesses.append(p + out * maxf(rr, r_local) * 1.6)
	var pr: Array = SurfaceDecal.project_polyline(ctx, guesses, r_local * 4.0)
	SurfaceDecal.strip(ctx, pr[0], pr[1], maxf(r_local * 0.03, ctx.cell * 0.05), a.part_id, bone)


static func gland(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	var gt := str(a.params.get("gland_type", "scent"))
	var bone := ctx.bone_or_root(a.bone)
	var size := maxf(a.size, 1e-4)
	var s: Array = ctx.snap(a.transform.origin, 0.0, a.transform.basis.y, size * 4.0)
	var p: Vector3 = s[0]
	var n: Vector3 = s[1] if s[2] else a.transform.basis.y
	match gt:
		"silk":
			# Spinnerets: three short cones pointing out of the abdomen tip.
			var b := MeshKit.frame(n, Vector3.UP)
			for k in 3:
				var ang := TAU * float(k) / 3.0
				var o := p + (b.x * cos(ang) + b.z * sin(ang)) * size * 0.22 - n * size * 0.1
				AppendageBuilder.cone(ctx, o, (n + (b.x * cos(ang) + b.z * sin(ang)) * 0.3).normalized(), size * 0.45, size * 0.12,
					AppendageBuilder.CODE_MANDIBLE, ctx.slot(a.covering), a.part_id, bone)
		"venom", "poison_skin", "slime":
			if ctx.detail < 1:
				return
			var rr := Rng.new(a.part_id * 17 + 3)
			var count := 7 if gt == "poison_skin" else 3
			var b2 := MeshKit.frame(n, Vector3.UP)
			var st := MeshKit.body_style(ctx.slot(a.covering), a.part_id, ctx.rig.along_on_bone(bone, p) if bone > 0 else 0.0, 0.95)
			for k in count:
				var q := p + (b2.x * rr.range_f(-1.0, 1.0) + b2.z * rr.range_f(-1.0, 1.0)) * size * 0.8
				var sq: Array = ctx.snap(q, 0.0, n, size * 3.0)
				if not sq[2]:
					continue
				var wr := size * rr.range_f(0.12, 0.22)
				var sk: Array = ctx.skin_at(sq[0], bone)
				MeshKit.ellipsoid(ctx.buffer(CreatureBuildContext.KIND_BODY), Transform3D(MeshKit.frame(sq[1], Vector3.UP), sq[0] - (sq[1] as Vector3) * wr * 0.4),
					Vector3(wr, wr * 0.8, wr), 8, 4, st, sk[0], sk[1])
		"scent":
			if ctx.detail >= 1:
				SurfaceDecal.dot(ctx, p, size * 0.3, a.part_id, bone, Vector3.ZERO, 1.4, 0.2)
		_:
			pass  # ink and other internal glands are not visible from outside


static func light(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	var bone := ctx.bone_or_root(a.bone)
	var size := maxf(a.size, 1e-4)
	var col_v = a.params.get("color", Color(0.5, 0.95, 1.0))
	var col: Color = col_v if col_v is Color else Color(0.5, 0.95, 1.0)
	var intensity := clampf(float(a.params.get("intensity", 0.6)), 0.0, 1.0)
	var s: Array = ctx.snap(a.transform.origin, -size * 0.15, a.transform.basis.y, size * 4.0)
	var p: Vector3 = s[0]
	var n: Vector3 = s[1] if s[2] else a.transform.basis.y
	var st := MeshKit.param_style(col.srgb_to_linear(), intensity, a.part_id, Rng.hash01(a.part_id, a.instance, a.side))
	var sk: Array = ctx.skin_at(p, bone)
	MeshKit.ellipsoid(ctx.buffer(CreatureBuildContext.KIND_GLOW), Transform3D(MeshKit.frame(n, Vector3.UP), p), Vector3(size, size * 0.75, size) * 0.55,
		MeshLod.seg(ctx.lod, 12, 6), MeshLod.seg(ctx.lod, 8, 4), st, sk[0], sk[1])


static func organelle(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	var size := maxf(a.size, 1e-4)
	var hue := float(a.params.get("hue", 0.3))
	var rr := Rng.new(int(hue * 100000.0) + 11)
	var col := Color.from_hsv(hue, 0.55, 0.75).srgb_to_linear()
	# The largest organelles read as nuclei.
	var big := size > ctx.bone_radius_at(ctx.bone_or_root(a.bone), a.transform.origin) * 0.17
	if big:
		col = Color(0.55, 0.3, 0.6).srgb_to_linear()  # nucleus-like
	var st := MeshKit.param_style(col, 0.0, a.part_id, 0.0)
	var b := Basis.from_euler(Vector3(rr.range_f(0, TAU), rr.range_f(0, TAU), rr.range_f(0, TAU)))
	MeshKit.ellipsoid(ctx.buffer(CreatureBuildContext.KIND_ORGANELLE), Transform3D(b, a.transform.origin),
		Vector3(size, size * rr.range_f(0.55, 0.8), size * rr.range_f(0.7, 0.95)), MeshLod.seg(ctx.lod, 12, 6), MeshLod.seg(ctx.lod, 8, 4),
		st, MeshKit.one_bone(ctx.bone_or_root(a.bone)), MeshKit.W1)


static func organ(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	if ctx.lod >= 2:
		return
	var ot := str(a.params.get("organ_type", "custom"))
	var bone := ctx.bone_or_root(a.bone)
	var size := maxf(a.size, 1e-4)
	var col: Color = ORGAN_COLORS.get(ot, ORGAN_COLORS["custom"])
	var st := MeshKit.param_style(col.srgb_to_linear(), 0.0, a.part_id, float(ORGAN_COLORS.keys().find(ot)))
	var axis := ctx.model.bones[bone].basis.y if bone > 0 else Vector3.FORWARD
	var b := MeshKit.frame(axis, Vector3.UP)
	var bi := MeshKit.one_bone(bone)
	var buf := ctx.buffer(CreatureBuildContext.KIND_ORGAN)
	var seg_a := MeshLod.seg(ctx.lod, 12, 6)
	var seg_u := MeshLod.seg(ctx.lod, 8, 4)
	var o := a.transform.origin
	match ot:
		"lungs":
			for sg in [-1.0, 1.0]:
				MeshKit.ellipsoid(buf, Transform3D(b, o + b.x * (float(sg) * size * 0.55)), Vector3(size * 0.5, size * 1.2, size * 0.7), seg_a, seg_u, st, bi, MeshKit.W1)
		"gut", "trachea":
			MeshKit.ellipsoid(buf, Transform3D(b, o), Vector3(size * 0.6, size * 1.8, size * 0.55), seg_a, seg_u, st, bi, MeshKit.W1)
		"heart":
			MeshKit.ellipsoid(buf, Transform3D(b.rotated(b.x, 0.5), o), Vector3(size * 0.85, size * 1.05, size * 0.8), seg_a, seg_u, st, bi, MeshKit.W1)
		_:
			MeshKit.ellipsoid(buf, Transform3D(b, o), Vector3(size * 0.95, size * 1.1, size * 0.85), seg_a, seg_u, st, bi, MeshKit.W1)
