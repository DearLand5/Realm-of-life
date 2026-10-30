class_name EyeBuilder
extends RefCounted
## Eyes: shaded spheres in the eye material (iris / pupil / facets in the
## shader from eye-local coordinates), plus a soft eyelid rim in body material
## for camera eyes and a recessed cup for pit eyes.

const TYPES := {"camera": 0, "compound": 1, "simple": 2, "pit": 3, "ocellus": 4}
const PUPILS := {"round": 0, "slit": 1, "horizontal": 2}


static func build(ctx: CreatureBuildContext, a: AnatomyModel.Accessory) -> void:
	var etype := str(a.params.get("eye_type", "camera"))
	var type_id: int = int(TYPES.get(etype, 0))
	var pupil_id: int = int(PUPILS.get(str(a.params.get("pupil", "round")), 0))
	var iris_v = a.params.get("iris_color", Color(0.78, 0.63, 0.25))
	var iris: Color = iris_v if iris_v is Color else Color(0.78, 0.63, 0.25)
	var r := maxf(a.size, 1e-4)
	var bone := ctx.bone_or_root(a.bone)
	var bi := MeshKit.one_bone(bone)
	var gaze := a.transform.basis.y.normalized()
	var center := a.transform.origin
	# Eye frame: +Y gaze, +Z as close to "up" as possible (slit pupils stay vertical).
	var basis := MeshKit.frame(gaze, Vector3.UP)
	var st := MeshKit.param_style(iris.srgb_to_linear(), float(type_id * 4 + pupil_id), a.part_id)
	var around := MeshLod.SPHERE_AROUND[ctx.lod]
	var up := MeshLod.SPHERE_UP[ctx.lod]
	var radius_cells := r / maxf(ctx.cell, 1e-6)
	if radius_cells < 0.6:
		around = mini(around, 8)
		up = mini(up, 5)
	match type_id:
		1:  # compound: bulging, slightly elongated
			center += gaze * r * 0.12
			MeshKit.ellipsoid(ctx.buffer(CreatureBuildContext.KIND_EYE), Transform3D(basis, center), Vector3(r, r * 1.05, r * 1.1), around + 4, up + 2, st, bi, MeshKit.W1)
		3:  # pit: dark cup flush with the surface
			var s: Array = ctx.snap(center + gaze * r, -r * 0.05, gaze, r * 3.0)
			var pb := MeshKit.frame(s[1], basis.z)
			MeshKit.ellipsoid(ctx.buffer(CreatureBuildContext.KIND_EYE), Transform3D(pb, s[0]), Vector3(r * 0.9, r * 0.12, r * 0.9), around, maxi(up / 2, 3), st, bi, MeshKit.W1)
		2, 4:  # simple eye / ocellus: small glossy dome
			MeshKit.ellipsoid(ctx.buffer(CreatureBuildContext.KIND_EYE), Transform3D(basis, center + gaze * r * 0.15), Vector3(r, r * 0.85, r), around, up, st, bi, MeshKit.W1)
		_:
			MeshKit.ellipsoid(ctx.buffer(CreatureBuildContext.KIND_EYE), Transform3D(basis, center), Vector3.ONE * r, around, up, st, bi, MeshKit.W1)
			if ctx.detail >= 1:
				_eyelid(ctx, a, center, gaze, basis, r, bone)


## Soft lid rim exactly where the eyeball emerges from the head: the polar
## angle at which the eyeball surface enters the body SDF is found per
## azimuth and averaged; the rim hugs the eyeball along that circle.
static func _eyelid(ctx: CreatureBuildContext, a: AnatomyModel.Accessory, center: Vector3, gaze: Vector3, basis: Basis, r: float, bone: int) -> void:
	var theta := deg_to_rad(80.0)
	if ctx.has_surface():
		var sum := 0.0
		var hits := 0
		for k in 6:
			var phi := TAU * float(k) / 6.0
			var radial := basis.x * cos(phi) + basis.z * sin(phi)
			for step in range(1, 19):
				var th := PI * float(step) / 18.0
				var p := center + (gaze * cos(th) + radial * sin(th)) * r
				if ctx.distance(p) < 0.0:
					sum += th
					hits += 1
					break
		if hits > 0:
			theta = sum / float(hits)
		elif ctx.distance(center) > 0.0:
			return  # eyeball entirely outside the body (e.g. on a stalk): no lid
	theta = clampf(theta, deg_to_rad(25.0), deg_to_rad(150.0))
	var off := r * cos(theta)
	var ring_r := r * sin(theta) * 0.97
	var cov := ctx.slot(ctx.model.bones[bone].covering if bone > 0 else a.covering)
	var st := MeshKit.body_style(cov, a.part_id, ctx.rig.along_on_bone(bone, center) if bone > 0 else 0.0, 0.62)
	var seg := MeshLod.seg(ctx.lod, 20, 8)
	MeshKit.torus(ctx.buffer(CreatureBuildContext.KIND_BODY), center + gaze * off, gaze, basis.z, ring_r, r * 0.13, seg, maxi(4, seg / 3), st, MeshKit.one_bone(bone), MeshKit.W1)
