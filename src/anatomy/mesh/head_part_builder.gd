class_name HeadPartBuilder
extends RefCounted
## Soft head features: leaf-shaped external ears (cupped thin shell in the body
## material, lighter inner face), tympana, ear pits and noses (wet rhinarium
## with nostrils on furred heads, nostril slits elsewhere).


static func ear(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	var etype := str(a.params.get("ear_type", "external"))
	var bone := ctx.bone_or_root(a.bone)
	var size := maxf(a.size, 1e-4)
	match etype:
		"tympanum":
			var s: Array = ctx.snap(a.transform.origin, 0.0, a.transform.basis.y, size * 4.0)
			var n: Vector3 = s[1]
			var st := MeshKit.body_style(ctx.slot(a.covering), a.part_id, ctx.rig.along_on_bone(bone, s[0]) if bone > 0 else 0.0, 0.6)
			var b := MeshKit.frame(n, Vector3.UP)
			var sk: Array = ctx.skin_at(s[0], bone)
			MeshKit.ellipsoid(ctx.buffer(CreatureBuildContext.KIND_BODY), Transform3D(b, s[0] - n * size * 0.05),
				Vector3(size * 0.75, size * 0.12, size * 0.75), MeshLod.seg(ctx.lod, 14, 6), 4, st, sk[0], sk[1])
		"pit":
			if ctx.detail >= 1:
				SurfaceDecal.dot(ctx, a.transform.origin, size * 0.45, a.part_id, bone)
		_:
			_external_ear(ctx, a, bone, size)


## Leaf ear: closed thin shell, cup facing forward-outward.
static func _external_ear(ctx: CreatureBuildContext, a: AnatomyModel.Accessory, bone: int, size: float) -> void:
	var m := ctx.model
	var buf := ctx.buffer(CreatureBuildContext.KIND_BODY)
	var y := a.transform.basis.y.normalized()
	var fwd := m.bones[bone].basis.y if bone > 0 else Vector3.FORWARD
	var outward := Vector3.RIGHT * float(signf(a.transform.origin.x)) if a.side != 0 else Vector3.ZERO
	var cup_dir := fwd * 0.75 + outward * 0.55
	var b := MeshKit.frame(y, cup_dir)
	var xw := b.x
	var c := b.z
	var height := size * 1.55
	var width := size * 0.62
	var thick := size * 0.07
	var cup := width * 0.45
	var o := a.transform.origin - y * size * 0.25
	var rows := MeshLod.seg(ctx.lod, 9, 3)
	var sides := MeshLod.seg(ctx.lod, 12, 6)
	var slot := ctx.slot(a.covering)
	var skin_slot := ctx.find_slot(&"skin")
	var outer := MeshKit.slot_color(slot)
	var inner := outer
	if skin_slot >= 0 and skin_slot != slot:
		inner = outer.lerp(MeshKit.slot_color(skin_slot), 0.55)
	var along := ctx.rig.along_on_bone(bone, o) if bone > 0 else 0.0
	var bi := MeshKit.one_bone(bone)
	var v_start := buf.vertex_count()
	var i_start := buf.indices.size()
	for iv in rows + 1:
		var v := float(iv) / float(rows)
		var w := width * pow(sin(PI * clampf(pow(v, 0.7), 0.0, 1.0)), 0.8) * (1.0 - 0.25 * v) + width * 0.25 * (1.0 - v)
		if iv == rows:
			w = width * 0.04
		var th := thick * (1.0 - 0.6 * v)
		var cup_v := cup * sin(PI * minf(v * 1.15, 1.0)) * (1.0 - 0.3 * v)
		var center := o + y * (height * v) + c * (cup_v * 0.35)
		for j in sides:
			var ang := TAU * float(j) / float(sides)
			var u := cos(ang)
			var sv := sin(ang)
			var p := center + xw * (u * w) + c * (sv * th - cup_v * (1.0 - u * u))
			var front := sv > 0.0
			var col := inner if front else outer
			var ao := lerpf(0.55, 1.0, absf(u)) if front else 1.0
			buf.add(p, c * signf(sv), col, Vector2(along, 0.85 if front else 0.3), Vector2(ao, v),
				Vector4(p.x, p.y, p.z, float(slot)), Vector2(a.part_id, 0.0), bi, MeshKit.W1)
	for iv in rows:
		for j in sides:
			var j1 := (j + 1) % sides
			var r0 := v_start + iv * sides
			var r1 := r0 + sides
			buf.quad(r0 + j, r0 + j1, r1 + j1, r1 + j)
	# Close the base (hidden in the head) and fix winding/normals from geometry.
	_orient(buf, v_start, i_start, o + y * height * 0.3)
	MeshKit.recompute_normals(buf, v_start, i_start)


## Makes the triangles of a closed shell face away from `inside`.
static func _orient(buf: MeshBuffer, v_start: int, i_start: int, inside: Vector3) -> void:
	var score := 0.0
	for t in range(i_start, buf.indices.size(), 3):
		var a := buf.verts[buf.indices[t]]
		var b := buf.verts[buf.indices[t + 1]]
		var c := buf.verts[buf.indices[t + 2]]
		score += (c - a).cross(b - a).dot((a + b + c) / 3.0 - inside)
	if score < 0.0:
		for t in range(i_start, buf.indices.size(), 3):
			var tmp := buf.indices[t + 1]
			buf.indices[t + 1] = buf.indices[t + 2]
			buf.indices[t + 2] = tmp


static func nose(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	var bone := ctx.bone_or_root(a.bone)
	var size := maxf(a.size, 1e-4)
	var s: Array = ctx.snap(a.transform.origin, 0.0, a.transform.basis.y, size * 4.0)
	if not s[2]:
		return
	var p: Vector3 = s[0]
	var n: Vector3 = s[1]
	var fwd := ctx.model.bones[bone].basis.y if bone > 0 else Vector3.FORWARD
	var b := MeshKit.frame(n, fwd)
	var side := b.x
	var head_cov := ctx.covering_type(ctx.model.bones[bone].covering if bone > 0 else a.covering)
	var r := size * 0.5
	if head_cov == &"fur" or head_cov == &"bristles":
		var sk: Array = ctx.skin_at(p, bone)
		var st := MeshKit.param_style(MeshKit.slot_color(ctx.slot(a.covering)), float(AppendageBuilder.CODE_RHINARIUM), a.part_id, float(AppendageBuilder.CODE_RHINARIUM))
		var pad := p - n * r * 0.18 + b.z * r * 0.15
		MeshKit.ellipsoid(ctx.buffer(CreatureBuildContext.KIND_HARD), Transform3D(b, pad), Vector3(r * 1.05, r * 0.42, r * 0.85),
			MeshLod.seg(ctx.lod, 14, 6), MeshLod.seg(ctx.lod, 8, 4), st, sk[0], sk[1])
		if ctx.detail >= 1:
			for sg in [-1.0, 1.0]:
				var q: Vector3 = pad + side * (float(sg) * r * 0.42) + b.z * r * 0.35 + n * r * 0.3
				SurfaceDecal.dot(ctx, q, r * 0.2, a.part_id, bone, side.rotated(n, float(sg) * 0.6), 0.6, 0.35)
	elif ctx.detail >= 1:
		for sg in [-1.0, 1.0]:
			var q: Vector3 = p + side * (float(sg) * r * 0.5)
			SurfaceDecal.dot(ctx, q, r * 0.16, a.part_id, bone, b.z, 2.2, 0.3)
