class_name AnatomyCompiler
extends RefCounted
## Morphogenesis: BodyPlan + Genome  ->  AnatomyModel.
##
## Steps:
##  1. Expand the part graph (bilateral mirror, radial copies, metameric
##     repeats) and lay out every spine chain in "raw" (unmirrored) space.
##  2. Emit bones (mirrored where needed), point accessories and organs.
##  3. Classify thin chains (rendered as tubes) and emit SDF primitives.
##  4. Re-centre so the lowest ground contact touches y = 0.
##  5. Compute real-unit statistics (mass, area, volume, support, organs...).
## Pure function of the genome: deterministic and thread-safe (no nodes).

## Chains thinner than (extent / THIN_DIVISOR) become tubes, not SDF body.
const THIN_DIVISOR := 40.0
## Smooth-union radius at part junctions, relative to the junction radius.
const JUNCTION_BLEND := 0.6
## Smooth-union radius between consecutive segments of one chain.
const CHAIN_BLEND := 0.12
const HARD_TISSUE_DENSITY := 1900.0  # horns, claws, spikes (keratin/bone)

const HARD_COVERINGS: Array[StringName] = [&"scales", &"plates", &"shell", &"chitin"]
const INSULATING_COVERINGS: Array[StringName] = [&"fur", &"feathers", &"bristles"]
const SUPPORT_FUNCTIONS: Array[StringName] = [&"walk", &"run", &"climb", &"dig"]
const TEETH_SHARPNESS := {"none": 0.2, "grinding": 0.3, "mixed": 0.6, "cutting": 1.0, "fangs": 1.0}


class _Raw:
	var starts: Array[Vector3] = []
	var ends: Array[Vector3] = []
	var bases: Array[Basis] = []
	var r0s := PackedFloat32Array()
	var r1s := PackedFloat32Array()
	var flats := PackedFloat32Array()
	var lengths := PackedFloat32Array()
	var total: float = 0.0
	var bone_indices := PackedInt32Array()  # emitted bones (same order)
	var point_bone: int = 0                  # for point parts: owning bone


class _Ctx:
	var model: AnatomyModel
	var plan: BodyPlan
	var genome: Genome
	var f: Dictionary          # gene factors
	var raw: Dictionary = {}   # instance index -> _Raw


static func compile(genome: Genome) -> AnatomyModel:
	var plan := genome.body_plan
	var m := AnatomyModel.new()
	m.size_scale = genome.value(&"size")
	m.body_axis = plan.body_axis
	m.morph_key = genome.morph_key()
	m.coverings = express_coverings(plan, genome)
	var ctx := _Ctx.new()
	ctx.model = m
	ctx.plan = plan
	ctx.genome = genome
	ctx.f = gene_factors(genome)

	var rb := AnatomyModel.Bone.new()
	rb.name = "root"
	rb.index = 0
	m.bones.append(rb)

	var root := plan.root()
	if root == null:
		m.warnings.append("План тела без корневой части")
		return m
	var frame: Transform3D
	if plan.body_axis == &"vertical":
		frame = Transform3D(Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK), Vector3.ZERO)
	else:
		frame = Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), Vector3.ZERO)
	_build_part(ctx, root, -1, frame, false, false, 0, 0, 0)
	_classify_thin(m)
	_emit_primitives(ctx)
	_recentre(m)
	_compute_stats(ctx)
	return m


# --- Gene → morphology factors -------------------------------------------------------

static func gene_factors(g: Genome) -> Dictionary:
	var fat := g.value(&"fat_reserve")
	var mus := g.value(&"muscle_mass")
	return {
		"torso_l": g.value(&"torso_length"),
		"torso_r": g.value(&"torso_girth") * (1.0 + 0.12 * (fat - 1.0)),
		"head": g.value(&"head_size"),
		"tail_l": g.value(&"tail_length"),
		"limb_l": g.value(&"limb_length"),
		"limb_r": g.value(&"limb_thickness") * (1.0 + 0.15 * (mus - 1.0)),
		"wing": g.value(&"wing_area"),
		"app": g.value(&"appendage_size"),
		"fat": fat,
		"muscle": mus,
	}


static func _kind_factors(kind: StringName, f: Dictionary) -> Vector2:
	match kind:
		&"torso", &"cell":
			return Vector2(f["torso_l"], f["torso_r"])
		&"neck":
			return Vector2(0.5 + 0.5 * float(f["torso_l"]), sqrt(float(f["torso_r"])))
		&"head":
			return Vector2(f["head"], f["head"])
		&"tail":
			return Vector2(f["tail_l"], sqrt(float(f["torso_r"])))
		&"limb", &"tentacle":
			return Vector2(f["limb_l"], f["limb_r"])
		&"wing", &"fin":
			return Vector2(sqrt(float(f["wing"])) * (0.7 + 0.3 * float(f["limb_l"])), f["limb_r"])
		&"antenna", &"flagellum":
			return Vector2(f["limb_l"], 1.0)
	return Vector2.ONE


## Coverings with genome-controlled colour, pattern and thickness applied.
static func express_coverings(plan: BodyPlan, g: Genome) -> Array[CoveringDef]:
	var out: Array[CoveringDef] = []
	var hue := g.value(&"hue_shift")
	var sat := g.value(&"saturation")
	var bri := g.value(&"brightness")
	var mel := g.value(&"melanism")
	var alb := g.norm(&"albinism")
	var pscale := g.value(&"pattern_scale")
	var pcon := g.value(&"pattern_contrast")
	var armor := g.value(&"armor")
	var fur := g.value(&"fur_length")
	for c in plan.coverings:
		var e := c.duplicate_def()
		e.color_a = _express_color(c.color_a, hue, sat, bri, mel, alb)
		e.color_b = _express_color(c.color_b, hue, sat, bri, mel * 0.6, alb)
		e.pattern_scale = c.pattern_scale * pscale
		e.pattern_contrast = clampf(c.pattern_contrast + (pcon - 0.6), 0.0, 1.0)
		if HARD_COVERINGS.has(c.type):
			e.thickness = c.thickness * armor
		elif INSULATING_COVERINGS.has(c.type):
			e.thickness = c.thickness * fur
		out.append(e)
	return out


static func _express_color(c: Color, hue: float, sat: float, bri: float, mel: float, alb: float) -> Color:
	var col := Color.from_hsv(wrapf(c.h + hue, 0.0, 1.0), clampf(c.s * sat, 0.0, 1.0), clampf(c.v * bri, 0.02, 1.0))
	col = col.lerp(col * 0.22, clampf(mel, 0.0, 1.0) * 0.85)
	if alb > 0.5:
		col = col.lerp(Color(0.96, 0.9, 0.88), (alb - 0.5) * 2.0)
	col.a = 1.0
	return col


# --- Graph expansion ----------------------------------------------------------------

static func _build_part(ctx: _Ctx, part: BodyPart, parent_inst: int, frame: Transform3D,
		mirrored: bool, in_bilateral: bool, radial_i: int, repeat_i: int, parent_bone: int, extra_yaw: float = 0.0) -> void:
	var m := ctx.model
	var inst := AnatomyModel.Instance.new()
	inst.part_id = part.id
	inst.kind = part.kind
	inst.parent_instance = parent_inst
	inst.mirrored = mirrored
	inst.radial_index = radial_i
	inst.repeat_index = repeat_i
	inst.anchor = MathUtil.mirror_point_x(frame.origin) if mirrored else frame.origin
	var idx := m.instances.size()
	m.instances.append(inst)

	var oriented := Transform3D(frame.basis * _rot(part.pitch, part.yaw + extra_yaw, part.roll), frame.origin)
	if part.is_spine():
		var raw := _chain(ctx, part, oriented)
		ctx.raw[idx] = raw
		_emit_chain_bones(ctx, part, inst, raw, mirrored, parent_bone)
		_spine_accessories(ctx, part, inst, idx, raw, mirrored, oriented)
	else:
		var raw := _point_raw(ctx, part, inst, idx, oriented, mirrored, parent_bone, parent_inst)
		ctx.raw[idx] = raw
	inst.side = _side_of(inst.anchor)

	for child in ctx.plan.children_of(part.id):
		_attach_child(ctx, child, idx, mirrored, in_bilateral)


static func _attach_child(ctx: _Ctx, child: BodyPart, parent_idx: int, parent_mirrored: bool, parent_in_bilateral: bool) -> void:
	var praw: _Raw = ctx.raw.get(parent_idx)
	if praw == null:
		return
	var thetas: Array[float] = [child.attach_angle]
	var flips: Array[bool] = [false]
	if child.symmetry >= 3:
		thetas.clear()
		flips.clear()
		for k in child.symmetry:
			thetas.append(child.attach_angle + 360.0 * float(k) / float(child.symmetry))
			flips.append(false)
	elif child.symmetry == 1 and not parent_in_bilateral:
		thetas.append(child.attach_angle)
		flips[0] = false
		flips.append(true)
	var reps := maxi(1, child.repeat_count)
	for r in reps:
		var t := child.attach_t
		var fan := 0.0
		if reps > 1:
			var u := float(r) / float(reps - 1)
			t += child.repeat_span * u
			fan = child.repeat_yaw * ((u - 0.5) if child.repeat_span >= 0.0 else (0.5 - u))
		t = clampf(t, 0.0, 1.0)
		for k in thetas.size():
			var fr := attach_frame(praw, t, thetas[k], child.attach_depth)
			var mir := parent_mirrored != flips[k]
			var bil := parent_in_bilateral or child.symmetry == 1
			var pbone := _bone_at(praw, t)
			_build_part(ctx, child, parent_idx, fr, mir, bil, k, r, pbone, fan)


static func _rot(pitch: float, yaw: float, roll: float) -> Basis:
	var b := Basis.IDENTITY
	if pitch != 0.0:
		b = b * Basis(Vector3.RIGHT, deg_to_rad(pitch))
	if yaw != 0.0:
		b = b * Basis(Vector3.BACK, deg_to_rad(yaw))
	if roll != 0.0:
		b = b * Basis(Vector3.UP, deg_to_rad(roll))
	return b


static func _chain(ctx: _Ctx, part: BodyPart, frame: Transform3D) -> _Raw:
	var raw := _Raw.new()
	var kf := _kind_factors(part.kind, ctx.f)
	var cur := frame.basis
	var pos := frame.origin
	var r_prev := part.base_radius * part.scale * kf.y
	for s in part.segments:
		cur = (cur * _rot(s.pitch, s.yaw, s.roll)).orthonormalized()
		var l := maxf(0.002, s.length * part.scale * kf.x)
		var r1 := maxf(0.001, s.radius * part.scale * kf.y)
		var e := pos + cur.y * l
		raw.starts.append(pos)
		raw.ends.append(e)
		raw.bases.append(cur)
		raw.r0s.append(r_prev)
		raw.r1s.append(r1)
		raw.flats.append(s.flatten)
		raw.lengths.append(l)
		raw.total += l
		pos = e
		r_prev = r1
	return raw


## Attach frame on a raw chain at parameter t / angle theta (deg) / depth.
## Basis: Y = outward direction, X = backward along the parent (mid
## attachments) or parent right (end attachments), Z completes the frame.
static func attach_frame(raw: _Raw, t: float, theta_deg: float, depth: float) -> Transform3D:
	var n := raw.starts.size()
	if n == 0:
		return Transform3D.IDENTITY
	var th := deg_to_rad(theta_deg)
	var c := cos(th)
	var s := sin(th)
	var end_attach := (t >= 0.999 or t <= 0.001) and raw.total > 0.0
	if end_attach:
		var front := t >= 0.999
		var i := n - 1 if front else 0
		var b: Basis = raw.bases[i]
		var tang := b.y if front else -b.y
		var p: Vector3 = raw.ends[i] if front else raw.starts[i]
		var r := raw.r1s[i] if front else raw.r0s[i]
		var fl := raw.flats[i]
		var normal := (b.x * c * fl + b.z * s).normalized()
		var out := tang
		if depth > 0.001:
			out = (tang * (1.0 - depth) + normal * depth * 1.6).normalized()
		var pos := p + out * r * depth
		# Continuations keep the parent's up axis; off-axis cap attachments use
		# the circumferential tangent so radial copies get consistent frames.
		var ref := b.z if depth <= 0.001 else (b.x * -s + b.z * c * fl)
		var z := ref - out * ref.dot(out)
		if z.length_squared() < 1e-6:
			z = b.x - out * b.x.dot(out)
		z = z.normalized()
		var x := out.cross(z).normalized()
		return Transform3D(Basis(x, out, z), pos)
	# Mid attachment.
	var target := clampf(t, 0.0, 1.0) * raw.total
	var acc := 0.0
	var i := 0
	var u := 0.0
	for k in n:
		var l := raw.lengths[k]
		if acc + l >= target or k == n - 1:
			i = k
			u = clampf((target - acc) / maxf(l, 1e-6), 0.0, 1.0)
			break
		acc += l
	var b: Basis = raw.bases[i]
	var r := lerpf(raw.r0s[i], raw.r1s[i], u)
	var fl := raw.flats[i]
	var axis_p: Vector3 = (raw.starts[i] as Vector3).lerp(raw.ends[i], u)
	var pos := axis_p + (b.x * c * r + b.z * s * r * fl) * depth
	var out := (b.x * c * fl + b.z * s).normalized()
	var circ := (b.x * -s + b.z * c * fl)
	var z := circ - out * circ.dot(out)
	if z.length_squared() < 1e-8:
		z = b.z
	z = z.normalized()
	var x := out.cross(z).normalized()
	return Transform3D(Basis(x, out, z), pos)


static func _bone_at(raw: _Raw, t: float) -> int:
	if raw.bone_indices.is_empty():
		return raw.point_bone
	var target := clampf(t, 0.0, 1.0) * raw.total
	var acc := 0.0
	for k in raw.lengths.size():
		acc += raw.lengths[k]
		if acc >= target - 1e-6:
			return raw.bone_indices[k]
	return raw.bone_indices[raw.bone_indices.size() - 1]


## Local radius of a raw chain at parameter t.
static func radius_at(raw: _Raw, t: float) -> float:
	if raw.lengths.is_empty():
		return 0.05
	var target := clampf(t, 0.0, 1.0) * raw.total
	var acc := 0.0
	for k in raw.lengths.size():
		var l := raw.lengths[k]
		if acc + l >= target or k == raw.lengths.size() - 1:
			return lerpf(raw.r0s[k], raw.r1s[k], clampf((target - acc) / maxf(l, 1e-6), 0.0, 1.0))
		acc += l
	return raw.r1s[raw.r1s.size() - 1]


static func _side_of(p: Vector3) -> int:
	if p.x > 0.004:
		return 1
	if p.x < -0.004:
		return -1
	return 0


static func _emit_chain_bones(ctx: _Ctx, part: BodyPart, inst: AnatomyModel.Instance, raw: _Raw, mirrored: bool, parent_bone: int) -> void:
	var m := ctx.model
	var prev := parent_bone
	var n := raw.starts.size()
	var tag := "R" if not mirrored else "L"
	if inst.radial_index > 0:
		tag += str(inst.radial_index)
	for k in n:
		var b := AnatomyModel.Bone.new()
		b.index = m.bones.size()
		b.name = "%s%d_%s%d_%d" % [part.kind, part.id, tag, inst.repeat_index, k]
		b.parent = prev
		b.part_id = part.id
		b.instance = m.instances.size() - 1
		b.segment = k
		b.kind = part.kind
		b.function = part.function
		var st: Vector3 = raw.starts[k]
		var en: Vector3 = raw.ends[k]
		var bs: Basis = raw.bases[k]
		if mirrored:
			st = MathUtil.mirror_point_x(st)
			en = MathUtil.mirror_point_x(en)
			bs = MathUtil.mirror_basis_x(bs)
		b.start = st
		b.end = en
		b.basis = bs
		b.length = raw.lengths[k]
		b.r0 = raw.r0s[k]
		b.r1 = raw.r1s[k]
		b.flatten = raw.flats[k]
		var seg: BodySegment = part.segments[k]
		b.swing_limit = seg.swing_limit
		b.twist_limit = seg.twist_limit
		b.stiffness = seg.stiffness
		b.soft = seg.soft
		b.fast_twitch = part.fast_twitch
		b.covering = part.covering
		b.depth = k
		b.is_tip = k == n - 1
		b.side = _side_of((st + en) * 0.5)
		m.bones.append(b)
		raw.bone_indices.append(b.index)
		inst.bones.append(b.index)
		prev = b.index


static func _mirror_tf(tf: Transform3D, mirrored: bool) -> Transform3D:
	if not mirrored:
		return tf
	return Transform3D(MathUtil.mirror_basis_x(tf.basis), MathUtil.mirror_point_x(tf.origin))


static func _add_accessory(ctx: _Ctx, type: StringName, part: BodyPart, inst: AnatomyModel.Instance,
		bone: int, tf_raw: Transform3D, size: float, mirrored: bool, params: Dictionary) -> AnatomyModel.Accessory:
	var a := AnatomyModel.Accessory.new()
	a.type = type
	a.bone = bone
	a.part_id = part.id
	a.instance = ctx.model.instances.find(inst)
	a.transform = _mirror_tf(tf_raw, mirrored)
	a.size = size
	a.side = _side_of(a.transform.origin)
	a.covering = part.covering
	a.params = params
	inst.accessories.append(ctx.model.accessories.size())
	ctx.model.accessories.append(a)
	return a


## Accessories generated by spine parts: membranes, flukes, feet, organelles.
static func _spine_accessories(ctx: _Ctx, part: BodyPart, inst: AnatomyModel.Instance, _idx: int, raw: _Raw, mirrored: bool, frame: Transform3D) -> void:
	var n := raw.starts.size()
	if n == 0:
		return
	var last := raw.bone_indices[n - 1]
	match part.kind:
		&"wing", &"fin":
			var area_mult := float(ctx.f["wing"])
			var chord := 0.0
			var subtype := ""
			if part.kind == &"wing":
				chord = float(part.get_param("chord", 0.45)) * raw.total * area_mult
				subtype = str(part.get_param("wing_type", "membrane"))
			else:
				chord = float(part.get_param("fin_area", 1.0)) * 0.5 * raw.total * area_mult
				subtype = str(part.get_param("fin_type", "pectoral"))
			var trail := raw.bases[0].x
			var normal := raw.bases[0].z
			if mirrored:
				trail = MathUtil.mirror_point_x(trail)
				normal = MathUtil.mirror_point_x(normal)
			var fan := part.kind == &"fin" and subtype == "caudal"
			var area := raw.total * chord * (0.75 if not fan else 1.1)
			var p := part.params.duplicate()
			p["bones"] = raw.bone_indices.duplicate()
			p["chord"] = chord
			p["trail"] = trail
			p["normal"] = normal
			p["fan"] = fan
			p["subtype"] = subtype
			p["area"] = area
			p["function"] = str(part.function)
			_add_accessory(ctx, &"membrane", part, inst, raw.bone_indices[0], frame, chord, mirrored, p)
		&"tail":
			var fl := float(part.get_param("fluke", 0.0))
			if fl > 0.01:
				var tf := Transform3D(raw.bases[n - 1], raw.ends[n - 1])
				var sz := fl * maxf(raw.r0s[0], 0.02) * 3.0 * float(ctx.f["wing"])
				_add_accessory(ctx, &"fluke", part, inst, last, tf, sz, mirrored, {"area": sz * sz * 1.2})
		&"limb":
			var tf := Transform3D(raw.bases[n - 1], raw.ends[n - 1])
			var p := {"foot": str(part.get_param("foot", "pad")), "digits": int(part.get_param("digits", 4)), "function": str(part.function)}
			_add_accessory(ctx, &"foot", part, inst, last, tf, raw.r1s[n - 1], mirrored, p)
		&"cell":
			var count := int(part.get_param("organelles", 6))
			var rr := Rng.new(part.id * 7919 + 17)
			for k in count:
				var seg := rr.range_i(0, n - 1)
				var u := rr.randf()
				var axis_p: Vector3 = (raw.starts[seg] as Vector3).lerp(raw.ends[seg], u)
				var rad := lerpf(raw.r0s[seg], raw.r1s[seg], u)
				var off := rr.unit_vector3() * rad * rr.range_f(0.1, 0.55)
				var tf := Transform3D(raw.bases[seg], axis_p + off)
				_add_accessory(ctx, &"cell_organelle", part, inst, raw.bone_indices[seg], tf, rad * rr.range_f(0.08, 0.22), mirrored, {"hue": rr.randf()})


## Point parts: accessory or organ placed in the parent's attach frame.
static func _point_raw(ctx: _Ctx, part: BodyPart, inst: AnatomyModel.Instance, _idx: int, frame: Transform3D,
		mirrored: bool, parent_bone: int, parent_inst: int) -> _Raw:
	var raw := _Raw.new()
	raw.point_bone = parent_bone
	var praw: _Raw = ctx.raw.get(parent_inst)
	var r_local := 0.05
	var part_volume := 0.0
	if praw != null:
		r_local = radius_at(praw, part.attach_t)
		for k in praw.lengths.size():
			part_volume += _frustum_volume(praw.lengths[k], praw.r0s[k], praw.r1s[k], praw.flats[k])
		if praw.lengths.is_empty():
			r_local = maxf(praw.r1s[0] if praw.r1s.size() > 0 else 0.05, 0.01)
	var app := float(ctx.f["app"])
	var p := part.params.duplicate()
	var size := r_local
	var tf := frame
	var type := part.kind
	match part.kind:
		&"eye":
			size = float(part.get_param("size", 0.35)) * r_local
			tf.origin -= tf.basis.y * size * 0.35
		&"ear", &"nose", &"sensor", &"gland":
			size = float(part.get_param("size", 0.4)) * r_local
		&"light_organ":
			size = float(part.get_param("size", 0.2)) * r_local
			type = &"light"
		&"mouth":
			size = float(part.get_param("size", 0.6)) * r_local
		&"horn", &"spike":
			var length := float(part.get_param("length", 0.6)) * r_local * app
			var base := float(part.get_param("base", 0.2)) * r_local * sqrt(app)
			p["length_m"] = length
			p["base_m"] = base
			size = length
			tf.origin -= tf.basis.y * base * 0.4
		&"claw":
			var length := float(part.get_param("length", 0.6)) * r_local * app
			p["length_m"] = length
			p["base_m"] = r_local * 0.45
			size = length
		&"whisker":
			size = float(part.get_param("length", 1.5)) * r_local
		&"gill":
			size = float(part.get_param("area", 1.0)) * r_local
		&"organ":
			var vol := float(part.get_param("size", 0.15)) * part_volume
			size = pow(maxf(vol, 1e-9) * 3.0 / (4.0 * PI), 1.0 / 3.0)
			p["volume"] = vol
		&"shell":
			type = &"shell"
			size = float(part.get_param("size", 1.15)) * r_local
			p["parent_raw_total"] = praw.total if praw != null else 0.0
	p["radius_local"] = r_local
	var acc := _add_accessory(ctx, type, part, inst, parent_bone, tf, size, mirrored, p)
	raw.starts.append(tf.origin)
	raw.ends.append(tf.origin + tf.basis.y * maxf(size, 0.001))
	raw.bases.append(tf.basis)
	raw.r0s.append(maxf(size * 0.5, 0.001))
	raw.r1s.append(maxf(size * 0.5, 0.001))
	raw.flats.append(1.0)
	raw.lengths.append(maxf(size, 0.001))
	raw.total = maxf(size, 0.001)
	if part.kind == &"shell" and praw != null:
		acc.params["shell_axis_start"] = _mirror_pt(praw.starts[0], mirrored)
		acc.params["shell_axis_end"] = _mirror_pt(praw.ends[praw.ends.size() - 1], mirrored)
	return raw


static func _mirror_pt(p: Vector3, mirrored: bool) -> Vector3:
	return MathUtil.mirror_point_x(p) if mirrored else p


# --- Thin chains & SDF primitives -----------------------------------------------------

static func _extent(m: AnatomyModel) -> float:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for b in m.bones:
		if b.part_id < 0:
			continue
		var r := maxf(b.r0, b.r1)
		lo = lo.min(b.start - Vector3.ONE * r).min(b.end - Vector3.ONE * r)
		hi = hi.max(b.start + Vector3.ONE * r).max(b.end + Vector3.ONE * r)
	if lo.x > hi.x:
		return 0.1
	var e := hi - lo
	return maxf(e.x, maxf(e.y, e.z))


static func _classify_thin(m: AnatomyModel) -> void:
	var threshold := _extent(m) / THIN_DIVISOR
	var root_inst := 0
	for inst in m.instances:
		if inst.bones.is_empty() or m.instances.find(inst) == root_inst:
			continue
		var max_r := 0.0
		for bi in inst.bones:
			max_r = maxf(max_r, maxf(m.bones[bi].r0, m.bones[bi].r1))
		if max_r < threshold:
			for bi in inst.bones:
				m.bones[bi].thin = true
			var a := AnatomyModel.Accessory.new()
			a.type = &"tube"
			a.bone = inst.bones[0]
			a.part_id = inst.part_id
			a.instance = m.instances.find(inst)
			a.transform = m.bones[inst.bones[0]].rest_transform()
			a.size = max_r
			a.side = inst.side
			a.covering = m.bones[inst.bones[0]].covering
			a.params = {"bones": inst.bones.duplicate()}
			inst.accessories.append(m.accessories.size())
			m.accessories.append(a)


static func _emit_primitives(ctx: _Ctx) -> void:
	var m := ctx.model
	for b in m.bones:
		if b.part_id < 0 or b.thin:
			continue
		var pr := AnatomyModel.Primitive.new()
		pr.bone = b.index
		pr.kind = 0
		pr.a = b.start
		pr.b = b.end
		pr.ra = b.r0
		pr.rb = b.r1
		pr.basis = b.basis
		pr.inv_basis = b.basis.inverse()
		pr.flatten = b.flatten
		var junction_r := minf(b.r0, b.r1)
		pr.blend = junction_r * (JUNCTION_BLEND if b.depth == 0 else CHAIN_BLEND)
		pr.covering = b.covering
		m.primitives.append(pr)
	for a in m.accessories:
		if a.type != &"shell":
			continue
		var st: Vector3 = a.params.get("shell_axis_start", a.transform.origin)
		var en: Vector3 = a.params.get("shell_axis_end", a.transform.origin)
		var cov := float(a.params.get("coverage", 0.7))
		var centre := a.transform.origin
		var axis := en - st
		var axis_len := maxf(axis.length(), 0.01)
		var y_axis := axis / axis_len
		var up := a.transform.basis.y
		var z_axis := (up - y_axis * up.dot(y_axis)).normalized()
		if z_axis.length_squared() < 0.5:
			z_axis = Vector3.UP
		var x_axis := y_axis.cross(z_axis).normalized()
		var pr := AnatomyModel.Primitive.new()
		pr.bone = a.bone
		pr.kind = 1
		pr.a = centre
		pr.basis = Basis(x_axis, y_axis, z_axis)
		pr.inv_basis = pr.basis.inverse()
		var r := a.size
		pr.radii = Vector3(r, axis_len * cov * 0.55, r * float(a.params.get("height", 0.8)))
		pr.ra = maxf(pr.radii.x, maxf(pr.radii.y, pr.radii.z))
		pr.rb = pr.ra
		pr.blend = r * 0.15
		pr.covering = int(a.params.get("shell_covering", 1))
		m.primitives.append(pr)
	for pr in m.primitives:
		var pad := Vector3.ONE * (maxf(pr.ra, pr.rb) * maxf(1.0, pr.flatten) + pr.blend)
		if pr.kind == 0:
			pr.aabb = AABB(pr.a.min(pr.b) - pad, (pr.a.max(pr.b) - pr.a.min(pr.b)) + pad * 2.0)
		else:
			pr.aabb = AABB(pr.a - pad, pad * 2.0)


# --- Recentre --------------------------------------------------------------------------

static func _recentre(m: AnatomyModel) -> void:
	var min_y := INF
	for b in m.bones:
		if b.is_tip and SUPPORT_FUNCTIONS.has(b.function):
			min_y = minf(min_y, b.end.y - b.r1)
	if min_y == INF:
		for b in m.bones:
			if b.part_id < 0:
				continue
			min_y = minf(min_y, minf(b.start.y - b.r0 * b.flatten, b.end.y - b.r1 * b.flatten))
	if min_y == INF:
		min_y = 0.0
	var lo_z := INF
	var hi_z := -INF
	for b in m.bones:
		if b.part_id < 0:
			continue
		lo_z = minf(lo_z, minf(b.start.z, b.end.z))
		hi_z = maxf(hi_z, maxf(b.start.z, b.end.z))
	var cz := 0.0 if lo_z == INF else (lo_z + hi_z) * 0.5
	var off := Vector3(0.0, -min_y, -cz)
	for b in m.bones:
		if b.part_id < 0:
			continue
		b.start += off
		b.end += off
	for pr in m.primitives:
		pr.a += off
		pr.b += off
		pr.aabb.position += off
	for a in m.accessories:
		a.transform.origin += off
		for key in ["shell_axis_start", "shell_axis_end"]:
			if a.params.has(key):
				a.params[key] = (a.params[key] as Vector3) + off
	for inst in m.instances:
		inst.anchor += off
	var box := AABB()
	var first := true
	for b in m.bones:
		if b.part_id < 0:
			continue
		var r := maxf(b.r0, b.r1)
		var bb := AABB(b.start.min(b.end) - Vector3.ONE * r, (b.start.max(b.end) - b.start.min(b.end)) + Vector3.ONE * r * 2.0)
		box = bb if first else box.merge(bb)
		first = false
	for a in m.accessories:
		var ab := AABB(a.transform.origin - Vector3.ONE * a.size, Vector3.ONE * a.size * 2.0)
		box = ab if first else box.merge(ab)
		first = false
	m.aabb = box


# --- Statistics --------------------------------------------------------------------------

static func _frustum_volume(l: float, r0: float, r1: float, fl: float) -> float:
	return PI * l * (r0 * r0 + r0 * r1 + r1 * r1) / 3.0 * fl


static func _frustum_area(l: float, r0: float, r1: float, fl: float) -> float:
	return PI * (r0 + r1) * sqrt((r0 - r1) * (r0 - r1) + l * l) * (1.0 + fl) * 0.5


static func _compute_stats(ctx: _Ctx) -> void:
	var m := ctx.model
	var g := ctx.genome
	var plan := ctx.plan
	var s := m.size_scale
	var s2 := s * s
	var s3 := s2 * s
	var mus_trait := float(ctx.f["muscle"])
	var vol := 0.0
	var area := 0.0
	var cov_area := PackedFloat32Array()
	cov_area.resize(m.coverings.size())
	var com := Vector3.ZERO
	var tissue := 0.0
	var muscle := 0.0
	var cavity := 0.0
	var kind_count := {}
	var function_count := {}
	for inst in m.instances:
		kind_count[inst.kind] = int(kind_count.get(inst.kind, 0)) + 1
		if not inst.bones.is_empty():
			var fn: StringName = m.bones[inst.bones[0]].function
			function_count[fn] = int(function_count.get(fn, 0)) + 1
	for b in m.bones:
		if b.part_id < 0:
			continue
		var v := _frustum_volume(b.length, b.r0, b.r1, b.flatten) * s3
		var ar := _frustum_area(b.length, b.r0, b.r1, b.flatten) * s2
		vol += v
		area += ar
		var ci := clampi(b.covering, 0, cov_area.size() - 1)
		cov_area[ci] += ar
		# Gelatinous (membrane-covered) tissue is close to water density.
		var dens := Units.TISSUE_DENSITY
		if ci < m.coverings.size() and m.coverings[ci].type == &"membrane":
			dens = 1015.0
		var bm := v * dens
		var part := plan.get_part(b.part_id)
		var mr := (part.muscle_ratio if part != null else 0.3) * mus_trait
		b.mass = bm
		b.muscle_mass = bm * clampf(mr, 0.0, 0.9)
		tissue += bm
		muscle += b.muscle_mass
		com += b.mid() * bm
		if b.kind == &"torso" or b.kind == &"cell":
			cavity += v
	# Membranes add area (both sides) and a little mass.
	var wing_area := 0.0
	var fin_area := 0.0
	var membrane_mass := 0.0
	var hard_mass := 0.0
	var shell_area := 0.0
	var organ_volume := {}
	for a in m.accessories:
		match a.type:
			&"membrane":
				var ma := float(a.params.get("area", 0.0)) * s2
				area += ma * 2.0
				membrane_mass += ma * 0.6 * s
				var src := plan.get_part(a.part_id)
				if src != null and src.kind == &"wing":
					wing_area += ma
				else:
					fin_area += ma
			&"fluke":
				fin_area += float(a.params.get("area", 0.0)) * s2
			&"horn", &"spike", &"claw":
				var l := float(a.params.get("length_m", a.size)) * s
				var r := float(a.params.get("base_m", a.size * 0.2)) * s
				hard_mass += PI * r * r * l / 3.0 * HARD_TISSUE_DENSITY
			&"shell":
				var r := a.size * s
				var sa := 2.0 * PI * r * r * float(a.params.get("coverage", 0.7)) * 1.6
				shell_area += sa
			&"organ":
				var ot := str(a.params.get("organ_type", "custom"))
				organ_volume[ot] = float(organ_volume.get(ot, 0.0)) + float(a.params.get("volume", 0.0)) * s3
	var covering_mass := 0.0
	var armor := 0.0
	var insulation := 0.0
	var retention := 0.0
	var flex := 0.0
	var total_cov := 0.0
	for i in m.coverings.size():
		var c := m.coverings[i]
		var a_i := cov_area[i]
		covering_mass += a_i * c.mass_per_area()
		armor += c.armor() * a_i
		insulation += c.insulation() * a_i
		retention += c.water_retention() * a_i
		flex += c.flexibility() * a_i
		total_cov += a_i
	var shell_mass := 0.0
	if shell_area > 0.0:
		var shell_slot := 1
		for a in m.accessories:
			if a.type == &"shell":
				shell_slot = clampi(int(a.params.get("shell_covering", 1)), 0, m.coverings.size() - 1)
		var sc := m.coverings[clampi(shell_slot, 0, m.coverings.size() - 1)]
		shell_mass = shell_area * sc.mass_per_area() * 2.0
		armor += sc.armor() * shell_area * 1.5
		insulation += sc.insulation() * shell_area
		retention += sc.water_retention() * shell_area
		flex += sc.flexibility() * shell_area * 0.3
		total_cov += shell_area * 1.5
	total_cov = maxf(total_cov, 1e-6)
	# Air spaces (lungs, swim bladder, tracheae) are part of the volume but weigh nothing.
	var gas := float(organ_volume.get("lungs", 0.0)) + float(organ_volume.get("swim_bladder", 0.0)) + float(organ_volume.get("trachea", 0.0)) * 0.5
	tissue = maxf(tissue * 0.2, tissue - gas * Units.TISSUE_DENSITY)
	var fat := tissue * 0.08 * float(ctx.f["fat"])
	var mass := tissue + fat + covering_mass + shell_mass + hard_mass + membrane_mass
	com = com / maxf(tissue, 1e-9)

	# Support limbs.
	var support := m.tips_with_function(SUPPORT_FUNCTIONS)
	var leg_len := 0.0
	var leg_r := 0.0
	for tip in support:
		var chain := m.chain_to(tip)
		for bi in chain:
			leg_len += m.bones[bi].length
			leg_r += (m.bones[bi].r0 + m.bones[bi].r1) * 0.5 / float(chain.size())
	var n_sup := support.size()
	if n_sup > 0:
		leg_len = leg_len / float(n_sup) * s
		leg_r = leg_r / float(n_sup) * s
	var bone_stress := 0.0
	if n_sup > 0 and leg_r > 0.0:
		# Bone ~45% of limb radius; static load shared by the supporting limbs.
		var bone_r := leg_r * 0.45
		bone_stress = mass * Units.GRAVITY / (float(n_sup) * PI * bone_r * bone_r)

	# Mouth / weapons summary.
	var mouth := {"type": "none", "size": 0.0, "teeth": "none", "bite_force": 0.0, "venom": 0.0, "count": 0}
	var weapons := {"bite": 0.0, "horn": 0.0, "claw": 0.0, "spike": 0.0, "venom": 0.0}
	var brain := 0.0
	var head_found := false
	for inst in m.instances:
		var part := plan.get_part(inst.part_id)
		if part == null:
			continue
		match part.kind:
			&"mouth":
				var acc_i := inst.accessories[0] if not inst.accessories.is_empty() else -1
				var msize := m.accessories[acc_i].size * s if acc_i >= 0 else 0.0
				mouth["count"] = int(mouth["count"]) + 1
				if msize > float(mouth["size"]):
					mouth["type"] = str(part.get_param("mouth_type", "jaws"))
					mouth["size"] = msize
					mouth["teeth"] = str(part.get_param("teeth", "mixed"))
					mouth["bite_force"] = float(part.get_param("bite_force", 0.5))
					mouth["venom"] = float(part.get_param("venom", 0.0))
				var sharp: float = float(TEETH_SHARPNESS.get(str(part.get_param("teeth", "mixed")), 0.5))
				weapons["bite"] = maxf(float(weapons["bite"]), msize * float(part.get_param("bite_force", 0.5)) * sharp * 100.0)
				weapons["venom"] = maxf(float(weapons["venom"]), float(part.get_param("venom", 0.0)))
			&"horn":
				for ai in inst.accessories:
					weapons["horn"] = float(weapons["horn"]) + float(m.accessories[ai].params.get("length_m", 0.0)) * s * float(part.get_param("sharpness", 0.6)) * 40.0
			&"claw":
				for ai in inst.accessories:
					weapons["claw"] = float(weapons["claw"]) + float(m.accessories[ai].params.get("length_m", 0.0)) * s * float(part.get_param("sharpness", 0.7)) * 30.0
			&"spike":
				for ai in inst.accessories:
					weapons["spike"] = float(weapons["spike"]) + float(m.accessories[ai].params.get("length_m", 0.0)) * s * float(part.get_param("sharpness", 0.8)) * 25.0
			&"head":
				head_found = true
				brain = maxf(brain, float(part.get_param("brain_size", 0.4)) * float(ctx.f["head"]))
			&"gland":
				if str(part.get_param("gland_type", "")) in ["venom", "poison_skin"]:
					weapons["venom"] = maxf(float(weapons["venom"]), float(part.get_param("strength", 0.5)) * 0.8)
	if not head_found:
		brain = 0.1
	if organ_volume.has("brain"):
		brain = maxf(brain, clampf(float(organ_volume["brain"]) / maxf(vol, 1e-9) * 40.0, 0.0, 1.0))

	var ext := m.aabb.size * s
	m.stats = {
		"size_scale": s,
		"mass": mass,
		"tissue_mass": tissue,
		"muscle_mass": muscle,
		"fat_mass": fat,
		"covering_mass": covering_mass + shell_mass,
		"hard_mass": hard_mass,
		"volume": vol,
		"surface_area": area,
		"surface_to_volume": area / maxf(vol, 1e-9),
		"length": ext.z,
		"width": ext.x,
		"height": ext.y,
		"streamline": ext.z / maxf(0.01, maxf(ext.x, ext.y)),
		"com": com,
		"cavity_volume": cavity * 0.6,
		"organ_volume": organ_volume,
		"support_count": n_sup,
		"support_tips": support,
		"leg_length": leg_len,
		"leg_radius": leg_r,
		"bone_stress": bone_stress,
		"wing_area": wing_area,
		"fin_area": fin_area,
		"armor": armor / total_cov,
		"insulation": insulation / total_cov,
		"water_retention": retention / total_cov,
		"flexibility": flex / total_cov,
		"needs_moisture": _needs_moisture(m, cov_area),
		"mouth": mouth,
		"weapons": weapons,
		"brain": clampf(brain, 0.0, 1.0),
		"kind_count": kind_count,
		"function_count": function_count,
		"ground_clearance": _ground_clearance(m) * s,
	}


static func _needs_moisture(m: AnatomyModel, cov_area: PackedFloat32Array) -> bool:
	var wet := 0.0
	var total := 0.0
	for i in m.coverings.size():
		total += cov_area[i]
		if bool(m.coverings[i].props()["needs_moisture"]):
			wet += cov_area[i]
	return total > 0.0 and wet / total > 0.4


static func _ground_clearance(m: AnatomyModel) -> float:
	var lowest := INF
	for b in m.bones:
		if b.kind == &"torso" or b.kind == &"cell":
			lowest = minf(lowest, minf(b.start.y - b.r0 * b.flatten, b.end.y - b.r1 * b.flatten))
	return maxf(0.0, lowest) if lowest != INF else 0.0
