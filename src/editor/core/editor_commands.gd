class_name EditorCommands
extends RefCounted
## Pure body-plan editing operations used by the editor (no nodes, no
## history — EditorDocument wraps them into undoable edits). All functions
## keep the plan valid: the root is never deleted, ids stay unique and
## parent links are remapped on copies.

const SUBTREE_FORMAT := 1


# --- Subtrees (copy / paste / catalogue presets) ------------------------------------------

## Serializable copy of part `id` with all its descendants. The first entry is
## the subtree top; ids are the plan's ids (remapped when grafted).
static func subtree_dict(plan: BodyPlan, id: int) -> Dictionary:
	var top := plan.get_part(id)
	if top == null:
		return {}
	var parts := [top.to_dict()]
	for d in plan.descendants_of(id):
		parts.append(d.to_dict())
	return {"format": SUBTREE_FORMAT, "kind": str(top.kind), "parts": parts}


## Subtree dict from a standalone BodyPlan (its root becomes the top part).
static func subtree_from_plan(sub: BodyPlan) -> Dictionary:
	return subtree_dict(sub, sub.root_id)


## Adds a copy of `sub` under `parent_id`. `attach` overrides attachment
## fields of the top part ({attach_t, attach_angle, attach_depth, symmetry,
## pitch, yaw, roll}). Returns the new top id (-1 on failure).
static func graft(plan: BodyPlan, sub: Dictionary, parent_id: int, attach: Dictionary = {}) -> int:
	var parts: Array = Serial.arr(sub, "parts")
	if parts.is_empty() or plan.get_part(parent_id) == null:
		return -1
	var id_map := {}
	var top_id := -1
	for i in parts.size():
		var pd = parts[i]
		if not (pd is Dictionary):
			continue
		var part := BodyPart.new().from_dict(pd)
		var old_id := part.id
		var parent := parent_id
		if i > 0:
			parent = int(id_map.get(part.parent_id, top_id))
		if i == 0:
			for key in attach:
				_set_field(part, str(key), attach[key])
		part.group = -1 if i == 0 else part.group
		var nid := plan.add_part(part, parent)
		id_map[old_id] = nid
		if i == 0:
			top_id = nid
	return top_id


static func _set_field(part: BodyPart, key: String, value: Variant) -> void:
	match key:
		"attach_t": part.attach_t = clampf(float(value), 0.0, 1.0)
		"attach_angle": part.attach_angle = wrapf(float(value), 0.0, 360.0)
		"attach_depth": part.attach_depth = clampf(float(value), 0.0, 1.5)
		"symmetry": part.symmetry = clampi(int(value), 0, 12)
		"pitch": part.pitch = float(value)
		"yaw": part.yaw = float(value)
		"roll": part.roll = float(value)
		"scale": part.scale = clampf(float(value), 0.05, 20.0)
		"label": part.label = str(value)
		"covering": part.covering = clampi(int(value), 0, CoveringDef.MAX_SLOTS - 1)


# --- Structural edits --------------------------------------------------------------------

## Deep copy of a part with its children, attached to the same parent and
## nudged along it so the copy is visible. Returns the new id.
static func duplicate_part(plan: BodyPlan, id: int) -> int:
	var src := plan.get_part(id)
	if src == null or id == plan.root_id:
		return -1
	var nid := plan.duplicate_subtree(id)
	var copy := plan.get_part(nid)
	if copy != null:
		copy.group = -1
		var shift := -0.12 if src.attach_t > 0.6 else 0.12
		if src.attach_t >= 0.999 or src.attach_t <= 0.001:
			copy.attach_angle = wrapf(src.attach_angle + 30.0, 0.0, 360.0)
		else:
			copy.attach_t = clampf(src.attach_t + shift, 0.01, 0.99)
	return nid


## Deletes parts (with descendants). Root and locked parts are kept. Returns
## the number of parts actually removed (descendants included).
static func delete_parts(plan: BodyPlan, ids: Array) -> int:
	var before := plan.parts.size()
	for v in ids:
		var id := int(v)
		var p := plan.get_part(id)
		if p == null or id == plan.root_id or p.locked:
			continue
		plan.remove_part(id)
	return before - plan.parts.size()


static func can_delete(plan: BodyPlan, id: int) -> bool:
	var p := plan.get_part(id)
	return p != null and id != plan.root_id and not p.locked


## Assigns a fresh group id to `ids`. Returns the group id.
static func group_parts(plan: BodyPlan, ids: Array) -> int:
	var g := 0
	for p in plan.parts:
		g = maxi(g, p.group + 1)
	for v in ids:
		var p := plan.get_part(int(v))
		if p != null:
			p.group = g
	return g


## Removes the groups of `ids` (every member of those groups is ungrouped).
static func ungroup_parts(plan: BodyPlan, ids: Array) -> void:
	var groups := {}
	for v in ids:
		var p := plan.get_part(int(v))
		if p != null and p.group >= 0:
			groups[p.group] = true
	for p in plan.parts:
		if groups.has(p.group):
			p.group = -1


static func set_locked(plan: BodyPlan, ids: Array, on: bool) -> void:
	for v in ids:
		var p := plan.get_part(int(v))
		if p != null:
			p.locked = on


## Bilateral mirror toggle: single ↔ mirrored pair (radial parts become pairs).
static func toggle_mirror(plan: BodyPlan, id: int) -> void:
	var p := plan.get_part(id)
	if p == null or id == plan.root_id:
		return
	p.symmetry = 0 if p.symmetry == 1 else 1


## Restores schema defaults of params, orientation, scale and muscles; keeps
## the attachment point, segments, covering and label.
static func reset_part(plan: BodyPlan, id: int) -> void:
	var p := plan.get_part(id)
	if p == null:
		return
	p.params = PartSchema.default_params(p.kind)
	p.yaw = 0.0
	p.pitch = 0.0
	p.roll = 0.0
	p.scale = 1.0
	p.muscle_ratio = 0.35
	p.fast_twitch = 0.5
	for s in p.segments:
		s.swing_limit = 40.0
		s.twist_limit = 15.0
		s.stiffness = 0.5
		s.soft = 0.0


# --- Segment chains -------------------------------------------------------------------------

## Inserts a segment after `index` (copy of it, halving its length) or at the
## end (index < 0: copy of the last one, tapering).
static func add_segment(part: BodyPart, index: int = -1) -> void:
	if not part.is_spine():
		return
	if part.segments.is_empty():
		part.segments.append(BodySegment.new(0.2, part.base_radius))
		return
	if part.segments.size() >= 32:
		return
	if index < 0 or index >= part.segments.size():
		var last: BodySegment = part.segments[part.segments.size() - 1]
		var s := last.copy()
		s.pitch = last.pitch if part.segments.size() > 1 else 0.0
		part.segments.append(s)
		return
	var src: BodySegment = part.segments[index]
	var half := src.copy()
	src.length *= 0.5
	half.length = src.length
	half.pitch = 0.0
	half.yaw = 0.0
	half.roll = 0.0
	part.segments.insert(index + 1, half)


## Removes segment `index` (default: last). A chain keeps at least one segment.
static func remove_segment(part: BodyPart, index: int = -1) -> void:
	if part.segments.size() <= 1:
		return
	var i := part.segments.size() - 1 if index < 0 or index >= part.segments.size() else index
	part.segments.remove_at(i)


## Sets the number of segments keeping the total length and taper.
static func set_segment_count(part: BodyPart, count: int) -> void:
	count = clampi(count, 1, 32)
	if not part.is_spine() or part.segments.is_empty() or count == part.segments.size():
		return
	var total := chain_length(part)
	var r_end: float = part.segments[part.segments.size() - 1].radius
	var bend := 0.0
	for s in part.segments:
		bend += s.pitch
	var new_segs: Array[BodySegment] = []
	for i in count:
		var src: BodySegment = part.segments[mini(int(float(i) / count * part.segments.size()), part.segments.size() - 1)]
		var s := src.copy()
		s.length = total / float(count)
		var u := float(i + 1) / float(count)
		s.radius = lerpf(part.base_radius, r_end, u) if count > 1 else r_end
		s.pitch = 0.0 if i == 0 and part.kind in [&"torso", &"cell"] else bend / float(count)
		s.flatten = src.flatten
		new_segs.append(s)
	if part.kind in [&"torso", &"cell"]:
		# Keep the body silhouette: radii follow the old profile.
		for i in count:
			new_segs[i].radius = radius_at(part, float(i + 1) / float(count))
	part.segments = new_segs


## Unscaled length of the chain (sum of segment lengths).
static func chain_length(part: BodyPart) -> float:
	var l := 0.0
	for s in part.segments:
		l += s.length
	return l


## Radius of the (unscaled) chain at 0..1 along its length.
static func radius_at(part: BodyPart, t: float) -> float:
	var total := chain_length(part)
	if total <= 0.0:
		return part.base_radius
	var target := clampf(t, 0.0, 1.0) * total
	var acc := 0.0
	var r_prev := part.base_radius
	for s in part.segments:
		if acc + s.length >= target:
			return lerpf(r_prev, s.radius, (target - acc) / maxf(s.length, 1e-6))
		acc += s.length
		r_prev = s.radius
	return r_prev


## Scales all segment lengths so the chain has total length `l`.
static func set_chain_length(part: BodyPart, l: float) -> void:
	var cur := chain_length(part)
	if cur <= 1e-6:
		return
	var k := clampf(l, 0.002, 40.0) / cur
	for s in part.segments:
		s.length = clampf(s.length * k, 0.005, 20.0)


## Largest radius of the chain (base or any segment end).
static func chain_thickness(part: BodyPart) -> float:
	var r := part.base_radius
	for s in part.segments:
		r = maxf(r, s.radius)
	return r


## Scales the base and all segment radii so the thickest point equals `r`.
static func set_chain_thickness(part: BodyPart, r: float) -> void:
	var cur := chain_thickness(part)
	if cur <= 1e-6:
		return
	var k := clampf(r, 0.001, 10.0) / cur
	part.base_radius = clampf(part.base_radius * k, 0.001, 10.0)
	for s in part.segments:
		s.radius = clampf(s.radius * k, 0.001, 10.0)


## Tip/base radius ratio (taper) of the chain.
static func chain_taper(part: BodyPart) -> float:
	if part.segments.is_empty() or part.base_radius <= 1e-6:
		return 1.0
	return part.segments[part.segments.size() - 1].radius / part.base_radius


## Re-tapers the chain linearly from the base radius to base × `k` at the tip.
static func set_chain_taper(part: BodyPart, k: float) -> void:
	var n := part.segments.size()
	if n == 0:
		return
	k = clampf(k, 0.05, 3.0)
	for i in n:
		var u := float(i + 1) / float(n)
		part.segments[i].radius = clampf(part.base_radius * lerpf(1.0, k, u), 0.001, 10.0)


## Average joint swing range (deg) — the "mobility" of the chain.
static func chain_mobility(part: BodyPart) -> float:
	if part.segments.is_empty():
		return 0.0
	var a := 0.0
	for s in part.segments:
		a += s.swing_limit
	return a / float(part.segments.size())


static func set_chain_mobility(part: BodyPart, swing: float) -> void:
	for s in part.segments:
		s.swing_limit = clampf(swing, 0.0, 180.0)
		s.twist_limit = clampf(swing * 0.4, 0.0, 180.0)


static func chain_stiffness(part: BodyPart) -> float:
	if part.segments.is_empty():
		return 0.5
	var a := 0.0
	for s in part.segments:
		a += s.stiffness
	return a / float(part.segments.size())


static func set_chain_stiffness(part: BodyPart, v: float) -> void:
	for s in part.segments:
		s.stiffness = clampf(v, 0.0, 1.0)


## Total bend (sum of segment pitches after the first) — "curl" of a chain.
static func chain_bend(part: BodyPart) -> float:
	var b := 0.0
	for i in range(1, part.segments.size()):
		b += part.segments[i].pitch
	return b


static func set_chain_bend(part: BodyPart, total: float) -> void:
	var n := part.segments.size()
	if n <= 1:
		return
	var each := clampf(total, -270.0, 270.0) / float(n - 1)
	for i in range(1, n):
		part.segments[i].pitch = each


## Applies a symmetry choice: 0 none, 1 bilateral, N ≥ 3 radial.
static func set_symmetry(part: BodyPart, sym: int) -> void:
	part.symmetry = 0 if sym <= 0 else (1 if sym <= 2 else clampi(sym, 3, 12))
