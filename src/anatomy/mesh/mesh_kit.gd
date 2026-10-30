class_name MeshKit
extends RefCounted
## Low-level procedural geometry helpers writing into MeshBuffer:
## swept tubes with elliptical sections and per-ring skinning, ellipsoids,
## and the vertex "style" that decides how attributes are filled.


## How a builder fills the non-geometric attributes (see MeshBuffer).
class Style:
	var color := Color(1, 0, 0, 0)  # COLOR (slot weights, iris colour, ...)
	var w: float = 0.0              # CUSTOM0.w
	var part: float = -1.0          # CUSTOM1.x (BodyPart id)
	var code: float = 0.0           # CUSTOM1.y (detail code)
	var ao: float = 1.0             # UV2.x
	var local := false              # CUSTOM0.xyz = local coordinates instead of rest position
	var uv_param := false           # UV = surface parameters instead of (along, ventral)
	var along: float = 0.0          # UV.x offset for body-like parts

	func copy() -> Style:
		var s := Style.new()
		s.color = color
		s.w = w
		s.part = part
		s.code = code
		s.ao = ao
		s.local = local
		s.uv_param = uv_param
		s.along = along
		return s


## Body-format style: one-hot covering slot.
static func body_style(slot: int, part_id: int, along: float = 0.0, ao: float = 1.0) -> Style:
	var s := Style.new()
	var sl := clampi(slot, 0, 3)
	var c := Color(0, 0, 0, 0)
	c[sl] = 1.0
	s.color = c
	s.w = float(sl)
	s.part = float(part_id)
	s.along = along
	s.ao = ao
	return s


## Parametric style (hard parts, membranes, eyes...): UV = surface parameters.
static func param_style(color: Color, w: float, part_id: int, code: float = 0.0, local: bool = true) -> Style:
	var s := Style.new()
	s.color = color
	s.w = w
	s.part = float(part_id)
	s.code = code
	s.local = local
	s.uv_param = true
	return s


static func slot_color(slot: int) -> Color:
	var c := Color(0, 0, 0, 0)
	c[clampi(slot, 0, 3)] = 1.0
	return c


static func one_bone(b: int) -> PackedInt32Array:
	return PackedInt32Array([maxi(b, 0), 0, 0, 0])


const W1 := Vector4(1, 0, 0, 0)


## Writes one vertex. `param` = surface parameters (UV in param mode, UV.x
## offset in body mode), `t` = UV2.y, `local` = CUSTOM0.xyz in local mode.
static func put(buf: MeshBuffer, p: Vector3, n: Vector3, st: Style, param: Vector2, t: float, local: Vector3,
		bi: PackedInt32Array, bw: Vector4) -> int:
	var uvv := param if st.uv_param else Vector2(st.along + param.x, clampf(0.5 - 0.5 * n.y, 0.0, 1.0))
	var c0 := Vector4(local.x, local.y, local.z, st.w) if st.local else Vector4(p.x, p.y, p.z, st.w)
	return buf.add(p, n, st.color, uvv, Vector2(st.ao, t), c0, Vector2(st.part, st.code), bi, bw)


## Ring data for sweep(): centre line, radii, cross-section and skinning per ring.
class Sweep:
	var centers := PackedVector3Array()
	var radii := PackedFloat32Array()
	var flats := PackedFloat32Array()     # section height/width ratio
	var xref := PackedVector3Array()      # reference width axis per ring
	var bones := PackedInt32Array()       # 4 per ring
	var weights := PackedFloat32Array()   # 4 per ring
	var ts := PackedFloat32Array()        # 0..1 along the sweep (UV2.y / UV.x)
	var alongs := PackedFloat32Array()    # along-body coordinate (body style)
	var aos := PackedFloat32Array()       # per-ring AO (optional, empty = style.ao)

	func add_ring(c: Vector3, r: float, fl: float, x: Vector3, bi: PackedInt32Array, bw: Vector4, t: float, along: float = 0.0, ao: float = -1.0) -> void:
		centers.append(c)
		radii.append(maxf(r, 0.0))
		flats.append(fl)
		xref.append(x)
		bones.append_array(bi)
		weights.append_array([bw.x, bw.y, bw.z, bw.w])
		ts.append(t)
		alongs.append(along)
		if ao >= 0.0:
			aos.append(ao)

	func size() -> int:
		return centers.size()


## Sweeps a closed elliptical section along the rings.
##   cap_end: 0 open, 1 pointed apex, 2 rounded (hemisphere)
##   cap_start: closes the first ring with an apex (hidden bases stay open)
static func sweep(buf: MeshBuffer, sw: Sweep, st: Style, sides: int, cap_end: int = 2, cap_start: bool = false, apex_len: float = 0.8) -> void:
	var n := sw.size()
	if n < 2:
		return
	sides = maxi(sides, 3)
	var tang := PackedVector3Array()
	tang.resize(n)
	for i in n:
		var a := sw.centers[maxi(i - 1, 0)]
		var b := sw.centers[mini(i + 1, n - 1)]
		var t := b - a
		tang[i] = t.normalized() if t.length_squared() > 1e-16 else (tang[i - 1] if i > 0 else Vector3.UP)
	var prev_x := Vector3.ZERO
	var frames_x := PackedVector3Array()
	frames_x.resize(n)
	for i in n:
		var t := tang[i]
		var x := sw.xref[i]
		x = x - t * x.dot(t)
		if x.length_squared() < 1e-10:
			x = prev_x - t * prev_x.dot(t) if prev_x != Vector3.ZERO else MathUtil.basis_from_y(t).x
		x = x.normalized()
		# Keep vertex j of consecutive rings on the same side (no twisting).
		if prev_x != Vector3.ZERO and x.dot(prev_x) < 0.0:
			x = -x
		frames_x[i] = x
		prev_x = x
	var base := buf.vertex_count()
	var cs := PackedFloat32Array()
	var sn := PackedFloat32Array()
	for j in sides:
		var a := TAU * float(j) / float(sides)
		cs.append(cos(a))
		sn.append(sin(a))
	for i in n:
		var t := tang[i]
		var x := frames_x[i]
		var z := x.cross(t)
		var r := sw.radii[i]
		var fl := sw.flats[i]
		var bi := sw.bones.slice(i * 4, i * 4 + 4)
		var bw := Vector4(sw.weights[i * 4], sw.weights[i * 4 + 1], sw.weights[i * 4 + 2], sw.weights[i * 4 + 3])
		var s2 := st
		if not sw.aos.is_empty():
			s2 = st.copy()
			s2.ao = sw.aos[i]
		for j in sides:
			var off := x * (cs[j] * r) + z * (sn[j] * r * fl)
			var nn := (x * (cs[j] * fl) + z * sn[j]).normalized()
			var local := Vector3(cs[j], sw.ts[i], sn[j])
			put(buf, sw.centers[i] + off, nn, s2, Vector2(sw.alongs[i] if not st.uv_param else sw.ts[i], float(j) / float(sides)), sw.ts[i], local, bi, bw)
	# Orientation: choose the winding whose face normal agrees with the ring normal.
	var mid := clampi(n / 2, 0, n - 2)
	var a0 := buf.verts[base + mid * sides]
	var b0 := buf.verts[base + mid * sides + 1]
	var c0 := buf.verts[base + (mid + 1) * sides + 1]
	var flip := (c0 - a0).cross(b0 - a0).dot(buf.normals[base + mid * sides]) < 0.0
	for i in n - 1:
		var r0 := base + i * sides
		var r1 := r0 + sides
		for j in sides:
			var j1 := (j + 1) % sides
			if flip:
				buf.quad(r0 + j, r1 + j, r1 + j1, r0 + j1)
			else:
				buf.quad(r0 + j, r0 + j1, r1 + j1, r1 + j)
	if cap_end > 0:
		_cap(buf, sw, st, base + (n - 1) * sides, sides, n - 1, tang[n - 1], frames_x[n - 1], cap_end, flip, false, apex_len)
	if cap_start:
		_cap(buf, sw, st, base, sides, 0, -tang[0], frames_x[0], 1, flip, true, 0.4)


static func _cap(buf: MeshBuffer, sw: Sweep, st: Style, ring: int, sides: int, i: int, t: Vector3, x: Vector3,
		mode: int, flip: bool, at_start: bool, apex_len: float) -> void:
	var c := sw.centers[i]
	var r := sw.radii[i]
	var fl := sw.flats[i]
	var bi := sw.bones.slice(i * 4, i * 4 + 4)
	var bw := Vector4(sw.weights[i * 4], sw.weights[i * 4 + 1], sw.weights[i * 4 + 2], sw.weights[i * 4 + 3])
	# Same section axes as the ring itself (t may be reversed for the start cap).
	var z := x.cross(t) if not at_start else t.cross(x)
	var prev := ring
	var tt := sw.ts[i]
	var al := sw.alongs[i]
	if mode == 2:
		for k in [0.5, 0.82]:
			var phi: float = float(k) * PI * 0.5
			var cr := r * cos(phi)
			var cc := c + t * (r * sin(phi))
			var start := buf.vertex_count()
			for j in sides:
				var a := TAU * float(j) / float(sides)
				var nn := ((x * (cos(a) * fl) + z * sin(a)).normalized() * cos(phi) + t * sin(phi)).normalized()
				var off := x * (cos(a) * cr) + z * (sin(a) * cr * fl)
				put(buf, cc + off, nn, st, Vector2(al if not st.uv_param else tt, float(j) / float(sides)), tt, Vector3(cos(a), tt, sin(a)), bi, bw)
			for j in sides:
				var j1 := (j + 1) % sides
				if flip != at_start:
					buf.quad(prev + j, start + j, start + j1, prev + j1)
				else:
					buf.quad(prev + j, prev + j1, start + j1, start + j)
			prev = start
		apex_len = 1.0
	var tip := c + t * r * apex_len
	var ai := put(buf, tip, t, st, Vector2(al if not st.uv_param else 1.0, 0.0), tt, Vector3(0.0, 1.0, 0.0), bi, bw)
	for j in sides:
		var j1 := (j + 1) % sides
		if flip != at_start:
			buf.tri(prev + j, ai, prev + j1)
		else:
			buf.tri(prev + j, prev + j1, ai)


## UV sphere / ellipsoid in transform `xf` (basis may be non-uniform: radii
## are applied in the local frame). Local unit-sphere coordinates go to
## CUSTOM0.xyz when the style is local. Returns the first vertex index.
static func ellipsoid(buf: MeshBuffer, xf: Transform3D, radii: Vector3, seg_around: int, seg_up: int, st: Style,
		bi: PackedInt32Array, bw: Vector4, uv_scale: Vector2 = Vector2.ONE) -> int:
	seg_around = maxi(seg_around, 3)
	seg_up = maxi(seg_up, 2)
	var base := buf.vertex_count()
	var b := xf.basis.orthonormalized()
	for iy in seg_up + 1:
		var v := float(iy) / float(seg_up)
		var th := v * PI
		var sy := cos(th)
		var ry := sin(th)
		for ix in seg_around:
			var u := float(ix) / float(seg_around)
			var ph := u * TAU
			var lp := Vector3(ry * cos(ph), sy, ry * sin(ph))
			var p := xf.origin + b * (lp * radii)
			var nn := (b * (lp / radii.max(Vector3.ONE * 1e-6))).normalized()
			put(buf, p, nn, st, Vector2(u, v) * uv_scale, v, lp, bi, bw)
	# Rows go from +Y (top) to -Y; columns around +Y.
	var flip := false
	if seg_up >= 2:
		var a0 := buf.verts[base + seg_around]
		var b0 := buf.verts[base + seg_around + 1]
		var c0 := buf.verts[base + 2 * seg_around + 1]
		flip = (c0 - a0).cross(b0 - a0).dot(buf.normals[base + seg_around]) < 0.0
	for iy in seg_up:
		for ix in seg_around:
			var ix1 := (ix + 1) % seg_around
			var a := base + iy * seg_around + ix
			var bb := base + iy * seg_around + ix1
			var c := base + (iy + 1) * seg_around + ix1
			var d := base + (iy + 1) * seg_around + ix
			# Pole rows collapse to triangles (no zero-area faces).
			if iy == 0:
				if flip:
					buf.tri(a, d, c)
				else:
					buf.tri(a, c, d)
			elif iy == seg_up - 1:
				if flip:
					buf.tri(a, c, bb)
				else:
					buf.tri(a, bb, c)
			elif flip:
				buf.quad(a, d, c, bb)
			else:
				buf.quad(a, bb, c, d)
	return base


## Regular grid surface from a callable f(u, v) -> [position, normal],
## u in 0..cols, v in 0..rows. Two-sided materials render it from both sides.
static func grid(buf: MeshBuffer, cols: int, rows: int, pos_fn: Callable, st: Style, skin_fn: Callable) -> int:
	var base := buf.vertex_count()
	for iv in rows + 1:
		for iu in cols + 1:
			var u := float(iu) / float(cols)
			var v := float(iv) / float(rows)
			var pn: Array = pos_fn.call(u, v)
			var sk: Array = skin_fn.call(u, v, pn[0])
			put(buf, pn[0], pn[1], st, Vector2(u, v), u, pn[2] if pn.size() > 2 else Vector3(u, v, 0.0), sk[0], sk[1])
	for iv in rows:
		for iu in cols:
			var a := base + iv * (cols + 1) + iu
			buf.quad(a, a + 1, a + cols + 2, a + cols + 1)
	return base


## Torus around `axis` (unit) at `center`: major radius R, minor radius r.
## `ref` is any direction not parallel to the axis (start of the ring).
static func torus(buf: MeshBuffer, center: Vector3, axis: Vector3, ref: Vector3, R: float, r: float,
		seg_major: int, seg_minor: int, st: Style, bi: PackedInt32Array, bw: Vector4, arc: float = TAU) -> void:
	var y := axis.normalized()
	var x := (ref - y * ref.dot(y)).normalized()
	if x.length_squared() < 0.5:
		x = MathUtil.basis_from_y(y).x
	var z := x.cross(y)
	var closed := is_equal_approx(arc, TAU)
	var nmaj := seg_major if closed else seg_major + 1
	var base := buf.vertex_count()
	for i in nmaj:
		var a := arc * float(i) / float(seg_major)
		var radial := x * cos(a) + z * sin(a)
		var c := center + radial * R
		for j in seg_minor:
			var b := TAU * float(j) / float(seg_minor)
			var nn := radial * cos(b) + y * sin(b)
			put(buf, c + nn * r, nn, st, Vector2(float(i) / float(seg_major), float(j) / float(seg_minor)), float(i) / float(seg_major), Vector3(cos(b), float(i) / float(seg_major), sin(b)), bi, bw)
	var rings := nmaj if closed else nmaj - 1
	var flip := false
	if nmaj > 1:
		var a0 := buf.verts[base]
		var b0 := buf.verts[base + 1]
		var c0 := buf.verts[base + seg_minor + 1]
		flip = (c0 - a0).cross(b0 - a0).dot(buf.normals[base]) < 0.0
	for i in rings:
		var r0 := base + i * seg_minor
		var r1 := base + ((i + 1) % nmaj) * seg_minor
		for j in seg_minor:
			var j1 := (j + 1) % seg_minor
			if flip:
				buf.quad(r0 + j, r1 + j, r1 + j1, r0 + j1)
			else:
				buf.quad(r0 + j, r0 + j1, r1 + j1, r1 + j)


## Recomputes smooth normals of vertices >= v_start from the triangles that
## start at index i_start (area weighted, clockwise front faces).
static func recompute_normals(buf: MeshBuffer, v_start: int, i_start: int) -> void:
	var n := buf.vertex_count() - v_start
	if n <= 0:
		return
	var acc := PackedVector3Array()
	acc.resize(n)
	for t in range(i_start, buf.indices.size(), 3):
		var a := buf.indices[t]
		var b := buf.indices[t + 1]
		var c := buf.indices[t + 2]
		if a < v_start or b < v_start or c < v_start:
			continue
		var fn := (buf.verts[c] - buf.verts[a]).cross(buf.verts[b] - buf.verts[a])
		acc[a - v_start] += fn
		acc[b - v_start] += fn
		acc[c - v_start] += fn
	for k in n:
		var f := acc[k]
		if f.length_squared() > 1e-24:
			buf.normals[v_start + k] = f.normalized()


## Orthonormal frame with Y = `y` and Z as close as possible to `z_hint`.
static func frame(y: Vector3, z_hint: Vector3) -> Basis:
	var yy := y.normalized() if y.length_squared() > 1e-12 else Vector3.UP
	var zz := z_hint - yy * z_hint.dot(yy)
	if zz.length_squared() < 1e-8:
		zz = MathUtil.basis_from_y(yy).z
	zz = zz.normalized()
	return Basis(yy.cross(zz), yy, zz)
