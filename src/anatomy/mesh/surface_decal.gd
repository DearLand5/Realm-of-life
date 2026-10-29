class_name SurfaceDecal
extends RefCounted
## Thin details lying on the body surface — lip lines, gill slits, nostrils,
## pores, lateral lines. Points are projected onto the SDF surface, lifted
## slightly to avoid z-fighting, and skinned with the body's own weights so
## they stay glued to the skin when it deforms. Hard material, dark code.


## Projects a guess polyline onto the surface. Returns [points, normals]
## (only the successfully projected samples).
static func project_polyline(ctx: CreatureBuildContext, guesses: PackedVector3Array, max_dist: float) -> Array:
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	for g in guesses:
		var s: Array = ctx.snap(g, 0.0, Vector3.UP, max_dist)
		if s[2]:
			pts.append(s[0])
			nrm.append(s[1])
	return [pts, nrm]


## Ribbon of half-width `width` along surface points (ends taper).
static func strip(ctx: CreatureBuildContext, pts: PackedVector3Array, nrm: PackedVector3Array, width: float,
		part_id: int, fallback_bone: int, code: int = AppendageBuilder.CODE_DARK, taper: bool = true) -> void:
	var n := pts.size()
	if n < 2 or width <= 0.0:
		return
	var buf := ctx.buffer(CreatureBuildContext.KIND_HARD)
	var st := MeshKit.param_style(Color(1, 0, 0, 0), float(code), part_id, float(code))
	var lift := width * 0.35
	var base := buf.vertex_count()
	for i in n:
		var t := pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
		var nn := nrm[i]
		var side := nn.cross(t)
		side = side.normalized() if side.length_squared() > 1e-16 else MathUtil.basis_from_y(nn).x
		var u := float(i) / float(n - 1)
		var w := width
		if taper:
			w *= clampf(minf(u, 1.0 - u) * 5.0, 0.25, 1.0)
		var sk: Array = ctx.skin_at(pts[i], fallback_bone)
		var p := pts[i] + nn * lift
		MeshKit.put(buf, p - side * w, nn, st, Vector2(u, 0.0), u, Vector3(-1.0, u, 0.0), sk[0], sk[1])
		MeshKit.put(buf, p + side * w, nn, st, Vector2(u, 1.0), u, Vector3(1.0, u, 0.0), sk[0], sk[1])
	var flip := false
	var a0 := buf.verts[base]
	var b0 := buf.verts[base + 1]
	var c0 := buf.verts[base + 3]
	flip = (c0 - a0).cross(b0 - a0).dot(buf.normals[base]) < 0.0
	for i in n - 1:
		var a := base + i * 2
		if flip:
			buf.quad(a, a + 2, a + 3, a + 1)
		else:
			buf.quad(a, a + 1, a + 3, a + 2)


## Small dark oval on the surface at p (nostril, pore, pit), long axis `along`.
static func dot(ctx: CreatureBuildContext, p: Vector3, radius: float, part_id: int, fallback_bone: int,
		along: Vector3 = Vector3.ZERO, elong: float = 1.0, depth: float = 0.25, code: int = AppendageBuilder.CODE_DARK) -> bool:
	var s: Array = ctx.snap(p, 0.0, Vector3.UP, radius * 6.0 + ctx.cell * 2.0)
	if not s[2]:
		return false
	var q: Vector3 = s[0]
	var n: Vector3 = s[1]
	var hint := along if along.length_squared() > 1e-8 else MathUtil.basis_from_y(n).z
	var b := MeshKit.frame(n, hint)
	var sk: Array = ctx.skin_at(q, fallback_bone)
	var st := MeshKit.param_style(Color(1, 0, 0, 0), float(code), part_id, float(code))
	var seg := 8 if ctx.lod == 0 else 6
	MeshKit.ellipsoid(ctx.buffer(CreatureBuildContext.KIND_HARD), Transform3D(b, q - n * radius * (depth - 0.15)),
		Vector3(radius, radius * depth, radius * elong), seg, 3, st, sk[0], sk[1])
	return true
