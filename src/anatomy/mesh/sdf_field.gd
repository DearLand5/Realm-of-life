class_name SdfField
extends RefCounted
## Evaluation-optimised copy of the body SDF of an AnatomyModel.
##
## Mirrors AnatomySdf (round cones with elliptical cross-section, ellipsoids,
## polynomial smooth union with the blend radius of the primitive being
## merged) but stores primitives in packed arrays and inlines all math:
## GDScript function calls cost ~0.3 µs, a fully inlined round cone ~0.45 µs.
## Every query takes an explicit candidate list (primitive indices in
## ascending order, normally the primitives overlapping one grid brick), so the
## caller controls culling. Thread-safe for concurrent reads.

const STRIDE := 8   # per primitive: h, ra, rb, slope, ca (-1 = degenerate), flatten, blend, dist_scale
const FAR := 1.0e9
## Skin/covering influence width relative to the primitive's mean radius
## (BodySkinning kernels never reach further than `reach`).
const INFLUENCE_SIGMA := 0.62

var count: int = 0
var kind := PackedInt32Array()       # 0 round cone, 1 ellipsoid
var origin := PackedVector3Array()   # cone start / ellipsoid centre
var inv: Array[Basis] = []           # geometry -> primitive local
var fwd: Array[Basis] = []           # primitive local -> geometry (gradients)
var radii := PackedVector3Array()    # ellipsoid radii
var data := PackedFloat32Array()     # STRIDE floats per primitive
var bone := PackedInt32Array()
var covering := PackedInt32Array()
var box: Array[AABB] = []            # conservative bounds incl. flatten and blend
var src := PackedInt32Array()        # index into AnatomyModel.primitives
## Distance from the primitive's own surface beyond which it affects neither
## the blended surface (blend radius) nor skin weights (influence kernel).
var reach := PackedFloat32Array()


## Builds the field from the model's primitives, skipping primitives whose
## bone is listed in `exclude_bones` (chains rendered as tubes at this LOD).
static func from_model(m: AnatomyModel, exclude_bones: Dictionary = {}) -> SdfField:
	var f := SdfField.new()
	for i in m.primitives.size():
		var pr := m.primitives[i]
		if pr == null or exclude_bones.has(pr.bone) or not _valid(pr):
			continue
		f._add(pr, i)
	return f


static func _valid(pr: AnatomyModel.Primitive) -> bool:
	if not (pr.a.is_finite() and pr.b.is_finite() and pr.radii.is_finite() and pr.basis.is_finite()):
		return false
	if not (is_finite(pr.ra) and is_finite(pr.rb) and is_finite(pr.blend) and is_finite(pr.flatten)):
		return false
	if pr.kind == 1:
		return maxf(pr.radii.x, maxf(pr.radii.y, pr.radii.z)) > 1e-6
	return maxf(pr.ra, pr.rb) > 1e-6


func _add(pr: AnatomyModel.Primitive, src_index: int) -> void:
	var b := pr.basis.orthonormalized()
	if not b.is_finite() or absf(b.determinant()) < 0.5:
		b = Basis.IDENTITY
	kind.append(pr.kind)
	origin.append(pr.a)
	inv.append(b.transposed())
	fwd.append(b)
	bone.append(pr.bone)
	covering.append(pr.covering)
	src.append(src_index)
	var blend := maxf(pr.blend, 0.0)
	if pr.kind == 1:
		var r := Vector3(maxf(pr.radii.x, 1e-5), maxf(pr.radii.y, 1e-5), maxf(pr.radii.z, 1e-5))
		radii.append(r)
		data.append_array([0.0, r.x, r.x, 0.0, 0.0, 1.0, blend, 1.0])
		var ext := maxf(r.x, maxf(r.y, r.z)) + blend
		box.append(AABB(pr.a - Vector3.ONE * ext, Vector3.ONE * ext * 2.0))
	else:
		var h := maxf((pr.b - pr.a).length(), 1e-6)
		var ra := maxf(pr.ra, 1e-5)
		var rb := maxf(pr.rb, 1e-5)
		var fl := clampf(pr.flatten, 0.05, 20.0)
		var slope := (ra - rb) / h
		var ca := sqrt(1.0 - slope * slope) if absf(slope) < 0.999 else -1.0
		radii.append(Vector3.ONE * maxf(ra, rb))
		data.append_array([h, ra, rb, slope, ca, fl, blend, minf(1.0, fl)])
		var pad := Vector3.ONE * (maxf(ra, rb) * maxf(1.0, fl) + blend)
		var lo := pr.a.min(pr.b) - pad
		var hi := pr.a.max(pr.b) + pad
		box.append(AABB(lo, hi - lo))
	count += 1
	reach.append(maxf(blend, INFLUENCE_SIGMA * mean_radius(count - 1) + 0.5 * blend))


func is_empty() -> bool:
	return count == 0


## Union of all primitive bounds.
func bounds() -> AABB:
	if count == 0:
		return AABB()
	var bb := box[0]
	for i in range(1, count):
		bb = bb.merge(box[i])
	return bb


## Mean radius of primitive j (used for kernel widths).
func mean_radius(j: int) -> float:
	var o := j * STRIDE
	if kind[j] == 1:
		var r: Vector3 = radii[j]
		return (r.x + r.y + r.z) / 3.0
	return (data[o + 1] + data[o + 2]) * 0.5 * (1.0 + data[o + 5]) * 0.5


## Primitive indices whose bounds overlap `aabb` (ascending order).
func candidates_in(aabb: AABB) -> PackedInt32Array:
	var out := PackedInt32Array()
	for j in count:
		if box[j].intersects(aabb):
			out.append(j)
	return out


## Smooth-union distance at p over the candidate primitives.
func value(p: Vector3, cand: PackedInt32Array) -> float:
	var acc := FAR
	for j in cand:
		var o := j * STRIDE
		var l: Vector3 = inv[j] * (p - origin[j])
		var d: float
		if kind[j] == 1:
			var r: Vector3 = radii[j]
			var k0 := (l / r).length()
			var k1 := (l / (r * r)).length()
			d = k0 * (k0 - 1.0) / k1 if k1 > 1e-12 else -minf(r.x, minf(r.y, r.z))
		else:
			var fl := data[o + 5]
			var lz := l.z / fl
			var qx := sqrt(l.x * l.x + lz * lz)
			var qy := l.y
			var ca := data[o + 4]
			var h := data[o]
			if ca < 0.0:
				var dy0 := qy - h
				d = minf(sqrt(qx * qx + qy * qy) - data[o + 1], sqrt(qx * qx + dy0 * dy0) - data[o + 2])
			else:
				var sb := data[o + 3]
				var kk := ca * qy - sb * qx
				if kk < 0.0:
					d = sqrt(qx * qx + qy * qy) - data[o + 1]
				elif kk > ca * h:
					var dy := qy - h
					d = sqrt(qx * qx + dy * dy) - data[o + 2]
				else:
					d = qx * ca + qy * sb - data[o + 1]
			d *= data[o + 7]
		var k := data[o + 6]
		if k > 0.0:
			var hh := maxf(k - absf(acc - d), 0.0) / k
			acc = minf(acc, d) - hh * hh * k * 0.25
		else:
			acc = minf(acc, d)
	return acc


## Smooth-union distance and analytic gradient: Vector4(gx, gy, gz, d).
## The gradient of the polynomial smooth minimum is the convex combination
## (1 - h/2)·∇min + (h/2)·∇other, so it stays well defined at fillets.
func value_grad(p: Vector3, cand: PackedInt32Array) -> Vector4:
	var acc := FAR
	var g_acc := Vector3.UP
	for j in cand:
		var o := j * STRIDE
		var l: Vector3 = inv[j] * (p - origin[j])
		var d: float
		var gl: Vector3
		if kind[j] == 1:
			var r: Vector3 = radii[j]
			var r2 := r * r
			var k0 := (l / r).length()
			var k1 := (l / r2).length()
			if k1 > 1e-12:
				d = k0 * (k0 - 1.0) / k1
				gl = (l / r2) / k1
			else:
				d = -minf(r.x, minf(r.y, r.z))
				gl = Vector3.UP
		else:
			var fl := data[o + 5]
			var lz := l.z / fl
			var qx := sqrt(l.x * l.x + lz * lz)
			var qy := l.y
			var ca := data[o + 4]
			var h := data[o]
			var g2x: float
			var g2y: float
			if ca < 0.0:
				var la := sqrt(qx * qx + qy * qy)
				var dy0 := qy - h
				var lb := sqrt(qx * qx + dy0 * dy0)
				if la - data[o + 1] < lb - data[o + 2]:
					d = la - data[o + 1]
					g2x = qx / maxf(la, 1e-9)
					g2y = qy / maxf(la, 1e-9)
				else:
					d = lb - data[o + 2]
					g2x = qx / maxf(lb, 1e-9)
					g2y = dy0 / maxf(lb, 1e-9)
			else:
				var sb := data[o + 3]
				var kk := ca * qy - sb * qx
				if kk < 0.0:
					var len0 := maxf(sqrt(qx * qx + qy * qy), 1e-9)
					d = len0 - data[o + 1]
					g2x = qx / len0
					g2y = qy / len0
				elif kk > ca * h:
					var dy := qy - h
					var len1 := maxf(sqrt(qx * qx + dy * dy), 1e-9)
					d = len1 - data[o + 2]
					g2x = qx / len1
					g2y = dy / len1
				else:
					d = qx * ca + qy * sb - data[o + 1]
					g2x = ca
					g2y = sb
			var rx := 1.0
			var rz := 0.0
			if qx > 1e-9:
				rx = l.x / qx
				rz = lz / qx
			var s := data[o + 7]
			d *= s
			gl = Vector3(rx * g2x, g2y, rz * g2x / fl) * s
		var g: Vector3 = fwd[j] * gl
		var k := data[o + 6]
		if k > 0.0:
			var hh := maxf(k - absf(acc - d), 0.0) / k
			var corr := hh * hh * k * 0.25
			if acc < d:
				g_acc = g_acc * (1.0 - hh * 0.5) + g * (hh * 0.5)
				acc = acc - corr
			else:
				g_acc = g * (1.0 - hh * 0.5) + g_acc * (hh * 0.5)
				acc = d - corr
		elif d < acc:
			acc = d
			g_acc = g
	return Vector4(g_acc.x, g_acc.y, g_acc.z, acc)


## Unblended distance of every candidate to p, written into `out` (same order).
func distances(p: Vector3, cand: PackedInt32Array, out: PackedFloat32Array) -> PackedFloat32Array:
	out.resize(cand.size())
	var i := 0
	for j in cand:
		var o := j * STRIDE
		var l: Vector3 = inv[j] * (p - origin[j])
		var d: float
		if kind[j] == 1:
			var r: Vector3 = radii[j]
			var k0 := (l / r).length()
			var k1 := (l / (r * r)).length()
			d = k0 * (k0 - 1.0) / k1 if k1 > 1e-12 else -minf(r.x, minf(r.y, r.z))
		else:
			var fl := data[o + 5]
			var lz := l.z / fl
			var qx := sqrt(l.x * l.x + lz * lz)
			var qy := l.y
			var ca := data[o + 4]
			var h := data[o]
			if ca < 0.0:
				var dy0 := qy - h
				d = minf(sqrt(qx * qx + qy * qy) - data[o + 1], sqrt(qx * qx + dy0 * dy0) - data[o + 2])
			else:
				var sb := data[o + 3]
				var kk := ca * qy - sb * qx
				if kk < 0.0:
					d = sqrt(qx * qx + qy * qy) - data[o + 1]
				elif kk > ca * h:
					var dy := qy - h
					d = sqrt(qx * qx + dy * dy) - data[o + 2]
				else:
					d = qx * ca + qy * sb - data[o + 1]
			d *= data[o + 7]
		out[i] = d
		i += 1
	return out


## Moves p onto the iso-surface `iso` with Newton steps along the gradient.
## Returns Vector4(normal.x, normal.y, normal.z, residual); p is passed back
## through `out_p[0]`.
func project(p: Vector3, cand: PackedInt32Array, steps: int, max_step: float, out_p: PackedVector3Array, iso: float = 0.0) -> Vector3:
	var q := p
	var n := Vector3.UP
	for _s in steps:
		var vg := value_grad(q, cand)
		var g := Vector3(vg.x, vg.y, vg.z)
		var gl2 := g.length_squared()
		if gl2 < 1e-10 or vg.w > FAR * 0.5:
			break
		n = g / sqrt(gl2)
		var step := g * ((vg.w - iso) / gl2)
		var sl := step.length()
		if sl > max_step:
			step *= max_step / sl
		q -= step
	out_p.resize(1)
	out_p[0] = q
	return n
