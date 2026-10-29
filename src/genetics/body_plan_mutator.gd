class_name BodyPlanMutator
extends RefCounted
## Structural (body-plan) mutations and structural distance.
## Operates IN PLACE on the given plan; callers pass a copy.

const OPS := [
	["jitter_segment", 5.0], ["jitter_attach", 2.0], ["point_param", 2.0], ["color_shift", 1.2],
	["add_segment", 0.8], ["remove_segment", 0.8], ["repeat_change", 0.6],
	["covering_shift", 0.5], ["duplicate_part", 0.25], ["remove_part", 0.25],
]
const MAX_SEGMENTS := 14
## Parts the mutator will not delete when they are the last of their kind.
const VITAL_KINDS: Array[StringName] = [&"mouth", &"torso", &"cell"]


static func mutate(plan: BodyPlan, rng: Rng, strength: float = 1.0) -> String:
	var weights := []
	for op in OPS:
		weights.append(op[1])
	for _attempt in 4:
		var op: String = OPS[rng.weighted_index(weights)][0]
		var text := _apply(op, plan, rng, strength)
		if text != "":
			plan.repair()
			return text
	return ""


static func _apply(op: String, plan: BodyPlan, rng: Rng, strength: float) -> String:
	match op:
		"jitter_segment":
			var p := _random_spine(plan, rng)
			if p == null or p.segments.is_empty():
				return ""
			var s: BodySegment = rng.pick(p.segments)
			s.length = clampf(s.length * (1.0 + rng.gauss(0.0, 0.08 * strength)), 0.01, 20.0)
			s.radius = clampf(s.radius * (1.0 + rng.gauss(0.0, 0.08 * strength)), 0.003, 10.0)
			s.pitch += rng.gauss(0.0, 4.0 * strength)
			return "Изменились пропорции: %s" % _name(p)
		"jitter_attach":
			var p := _random_nonroot(plan, rng)
			if p == null:
				return ""
			p.attach_t = clampf(p.attach_t + rng.gauss(0.0, 0.04 * strength), 0.0, 1.0)
			p.attach_angle += rng.gauss(0.0, 6.0 * strength)
			return "Сместилось крепление: %s" % _name(p)
		"point_param":
			var candidates: Array[BodyPart] = []
			for p in plan.parts:
				if not p.params.is_empty():
					candidates.append(p)
			if candidates.is_empty():
				return ""
			var p: BodyPart = rng.pick(candidates)
			var specs := PartSchema.param_specs(p.kind)
			var numeric := []
			for k in specs:
				if specs[k].get("type", "float") == "float":
					numeric.append(k)
			if numeric.is_empty():
				return ""
			var key: String = rng.pick(numeric)
			var spec: Dictionary = specs[key]
			var span := float(spec.get("max", 1.0)) - float(spec.get("min", 0.0))
			p.set_param(key, float(p.get_param(key, 0.0)) + rng.gauss(0.0, span * 0.06 * strength))
			return "%s: изменился параметр «%s»" % [_name(p), spec.get("label", key)]
		"color_shift":
			var c: CoveringDef = rng.pick(plan.coverings)
			var which := rng.range_i(0, 1)
			var col := c.color_a if which == 0 else c.color_b
			col = Color.from_hsv(wrapf(col.h + rng.gauss(0.0, 0.03 * strength), 0.0, 1.0),
				clampf(col.s + rng.gauss(0.0, 0.05 * strength), 0.0, 1.0),
				clampf(col.v + rng.gauss(0.0, 0.05 * strength), 0.05, 1.0))
			if which == 0:
				c.color_a = col
			else:
				c.color_b = col
			return "Изменилась окраска покрова «%s»" % c.props()["label"]
		"add_segment":
			var p := _random_spine(plan, rng, [&"tail", &"neck", &"tentacle", &"antenna", &"torso", &"limb", &"flagellum"])
			if p == null or p.segments.size() >= MAX_SEGMENTS:
				return ""
			var last: BodySegment = p.segments[p.segments.size() - 1]
			var ns := last.copy()
			ns.length *= 0.85
			ns.radius *= 0.85
			p.segments.append(ns)
			return "Новый сегмент: %s (%d)" % [_name(p), p.segments.size()]
		"remove_segment":
			var p := _random_spine(plan, rng)
			if p == null or p.segments.size() <= 1:
				return ""
			p.segments.pop_back()
			return "Утрачен сегмент: %s (%d)" % [_name(p), p.segments.size()]
		"repeat_change":
			var p := _random_nonroot(plan, rng, [&"limb", &"spike", &"gill", &"fin", &"eye", &"light_organ", &"tentacle"])
			if p == null:
				return ""
			if p.repeat_count <= 1:
				if not rng.chance(0.3):
					return ""
				p.repeat_count = 2
				p.repeat_span = clampf(0.25 if p.attach_t < 0.6 else -0.25, -1.0, 1.0)
			else:
				p.repeat_count = clampi(p.repeat_count + (1 if rng.chance(0.5) else -1), 1, 16)
			return "Число повторов %s: %d" % [_name(p), p.repeat_count]
		"covering_shift":
			var c: CoveringDef = rng.pick(plan.coverings)
			if rng.chance(0.6):
				c.pattern = rng.pick(CoveringDef.PATTERNS)
				return "Новый узор: %s" % CoveringDef.PATTERN_LABELS.get(c.pattern, str(c.pattern))
			var neighbours := {
				&"skin": [&"scales", &"slime"], &"scales": [&"skin", &"plates"], &"plates": [&"scales", &"shell"],
				&"shell": [&"plates"], &"chitin": [&"plates", &"bristles"], &"fur": [&"bristles", &"feathers"],
				&"feathers": [&"fur"], &"bristles": [&"fur", &"chitin"], &"slime": [&"skin", &"membrane"],
				&"membrane": [&"slime"],
			}
			var opts: Array = neighbours.get(c.type, [])
			if opts.is_empty():
				return ""
			c.type = rng.pick(opts)
			return "Покров сменился на «%s»" % c.props()["label"]
		"duplicate_part":
			var p := _random_nonroot(plan, rng, [&"limb", &"fin", &"wing", &"tentacle", &"antenna", &"horn", &"spike", &"eye", &"gill"])
			if p == null or plan.parts.size() > 60:
				return ""
			var nid := plan.duplicate_subtree(p.id)
			var np := plan.get_part(nid)
			if np == null:
				return ""
			np.attach_t = clampf(p.attach_t + (0.15 if rng.chance(0.5) else -0.15), 0.0, 1.0)
			return "Удвоение: %s" % _name(p)
		"remove_part":
			var p := _random_nonroot(plan, rng)
			if p == null:
				return ""
			if VITAL_KINDS.has(p.kind) and plan.parts_of_kind(p.kind).size() <= 1:
				return ""
			if p.kind == &"organ" and str(p.get_param("organ_type", "")) in ["lungs", "trachea"]:
				return ""
			var n := _name(p)
			plan.remove_part(p.id)
			return "Утрата: %s" % n
	return ""


static func _name(p: BodyPart) -> String:
	return p.label if p.label != "" else PartSchema.label(p.kind)


static func _random_spine(plan: BodyPlan, rng: Rng, kinds: Array = []) -> BodyPart:
	var c: Array[BodyPart] = []
	for p in plan.parts:
		if p.is_spine() and (kinds.is_empty() or kinds.has(p.kind)):
			c.append(p)
	return rng.pick(c) if not c.is_empty() else null


static func _random_nonroot(plan: BodyPlan, rng: Rng, kinds: Array = []) -> BodyPart:
	var c: Array[BodyPart] = []
	for p in plan.parts:
		if p.id != plan.root_id and (kinds.is_empty() or kinds.has(p.kind)):
			c.append(p)
	return rng.pick(c) if not c.is_empty() else null


## 0 (identical) .. 1 (nothing in common).
static func structural_distance(a: BodyPlan, b: BodyPlan) -> float:
	if a == b:
		return 0.0
	var ids := {}
	for p in a.parts:
		ids[p.id] = true
	for p in b.parts:
		ids[p.id] = true
	if ids.is_empty():
		return 0.0
	var acc := 0.0
	for id in ids:
		var pa := a.get_part(id)
		var pb := b.get_part(id)
		if pa == null or pb == null or pa.kind != pb.kind:
			acc += 1.0
			continue
		var d := 0.0
		d += absf(float(pa.segments.size() - pb.segments.size())) * 0.15
		d += absf(float(pa.repeat_count - pb.repeat_count)) * 0.1
		d += 0.0 if pa.symmetry == pb.symmetry else 0.3
		var n := mini(pa.segments.size(), pb.segments.size())
		for i in n:
			var sa := pa.segments[i]
			var sb := pb.segments[i]
			d += absf(sa.length - sb.length) / maxf(0.01, maxf(sa.length, sb.length)) * 0.3 / float(n)
			d += absf(sa.radius - sb.radius) / maxf(0.005, maxf(sa.radius, sb.radius)) * 0.3 / float(n)
		acc += minf(d, 1.0)
	var cov := 0.0
	var nc := maxi(a.coverings.size(), b.coverings.size())
	for i in nc:
		if i >= a.coverings.size() or i >= b.coverings.size():
			cov += 1.0
		elif a.coverings[i].type != b.coverings[i].type:
			cov += 0.6
		elif a.coverings[i].pattern != b.coverings[i].pattern:
			cov += 0.25
	return clampf((acc + cov * 0.5) / float(ids.size() + nc * 0.5), 0.0, 1.0)
