class_name BodyPlan
extends RefCounted
## The structural blueprint of an organism: a graph of BodyParts plus covering
## slots and species-level biological choices. It is part of the heritable
## Genome (structural genes) and can mutate (see BodyPlanMutator).
##
## No part kind is mandatory: an organism may lack a head, limbs, a spine or
## bilateral symmetry. The only requirement is exactly one root part.

const FORMAT := 1

const BIOLOGY_DEFAULTS := {
	"habitat": "land",                 # land | water | amphibious
	"reproduction_mode": "sexual",     # sexual | asexual | hermaphrodite
	"reproduction_method": "eggs",     # eggs | live | fission | budding | spores
	"diet": "herbivore",               # herbivore | carnivore | omnivore | scavenger | detritivore | filter | parasite | photosynth
	"metamorphosis": false,            # larval stage with different habitat
	"molting": false,                  # exoskeleton growth in discrete moults
	"colonial": false,                 # individuals stay physically clustered
}

const CUSTOM_RULE_DEFAULTS := {
	"fantasy": false,                  # marks the species as using non-terrestrial rules
	"ignore_oxygen": false,            # no gas-exchange requirement
	"ignore_support": false,           # skeleton never overloaded (levitating bodies)
	"free_energy": 0.0,                # W/kg of energy from an unspecified source
}

var name: String = "Новый организм"
var parts: Array[BodyPart] = []
var coverings: Array[CoveringDef] = []
var next_id: int = 1
var root_id: int = -1
## &"horizontal" — spine along -Z (most animals); &"vertical" — spine along +Y
## (radial organisms: jellyfish, starfish, polyps, cells).
var body_axis: StringName = &"horizontal"
var biology: Dictionary = BIOLOGY_DEFAULTS.duplicate()
var custom_rules: Dictionary = CUSTOM_RULE_DEFAULTS.duplicate()


func _init() -> void:
	if coverings.is_empty():
		coverings.append(CoveringDef.new())


# --- Graph queries -------------------------------------------------------------

func get_part(id: int) -> BodyPart:
	for p in parts:
		if p.id == id:
			return p
	return null


func root() -> BodyPart:
	return get_part(root_id)


func children_of(id: int) -> Array[BodyPart]:
	var out: Array[BodyPart] = []
	for p in parts:
		if p.parent_id == id:
			out.append(p)
	return out


func descendants_of(id: int) -> Array[BodyPart]:
	var out: Array[BodyPart] = []
	var stack: Array[int] = [id]
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		for c in children_of(cur):
			out.append(c)
			stack.append(c.id)
	return out


func parts_of_kind(kind: StringName) -> Array[BodyPart]:
	var out: Array[BodyPart] = []
	for p in parts:
		if p.kind == kind:
			out.append(p)
	return out


func bio(key: String):
	return biology.get(key, BIOLOGY_DEFAULTS.get(key))


func rule(key: String):
	return custom_rules.get(key, CUSTOM_RULE_DEFAULTS.get(key))


# --- Editing -------------------------------------------------------------------

## Adds a part; assigns a fresh id. Returns the id.
func add_part(part: BodyPart, parent: int = -1) -> int:
	part.id = next_id
	next_id += 1
	part.parent_id = parent
	if parent == -1:
		if root_id != -1 and get_part(root_id) != null:
			push_warning("BodyPlan.add_part: replacing parentless part with child of root")
			part.parent_id = root_id
		else:
			root_id = part.id
	parts.append(part)
	return part.id


## Removes a part with all its descendants. The root cannot be removed.
func remove_part(id: int) -> bool:
	if id == root_id:
		return false
	var doomed := {id: true}
	for d in descendants_of(id):
		doomed[d.id] = true
	var kept: Array[BodyPart] = []
	for p in parts:
		if not doomed.has(p.id):
			kept.append(p)
	var removed := kept.size() != parts.size()
	parts = kept
	return removed


## Deep-copies a part subtree and attaches the copy to `new_parent`.
## Returns the id of the copied subtree root.
func duplicate_subtree(id: int, new_parent: int = -2) -> int:
	var src := get_part(id)
	if src == null:
		return -1
	var id_map := {}
	var top := src.copy()
	var parent := src.parent_id if new_parent == -2 else new_parent
	var new_top := add_part(top, parent)
	id_map[id] = new_top
	for d in descendants_of(id):
		var c := d.copy()
		var nid := add_part(c, id_map.get(d.parent_id, new_top))
		id_map[d.id] = nid
	return new_top


func ensure_covering(slot: int) -> CoveringDef:
	slot = clampi(slot, 0, CoveringDef.MAX_SLOTS - 1)
	while coverings.size() <= slot:
		coverings.append(CoveringDef.new())
	return coverings[slot]


# --- Validation ------------------------------------------------------------------

## Repairs structural invariants (single root, valid parents, no cycles).
## Returns a list of human-readable fixes that were applied.
func repair() -> Array[String]:
	var fixes: Array[String] = []
	if parts.is_empty():
		var torso := BodyPart.make_chain(&"torso", 3, 0.3, 0.15, 0.15)
		add_part(torso, -1)
		fixes.append("Добавлено туловище: в плане не было частей")
	if get_part(root_id) == null:
		root_id = parts[0].id
		parts[0].parent_id = -1
		fixes.append("Назначен новый корень тела")
	var ids := {}
	for p in parts:
		ids[p.id] = true
		next_id = maxi(next_id, p.id + 1)
	for p in parts:
		if p.id == root_id:
			p.parent_id = -1
			continue
		if not ids.has(p.parent_id) or p.parent_id == p.id:
			p.parent_id = root_id
			fixes.append("Часть %d прикреплена к корню" % p.id)
	# Break cycles: walk up from each part; if we revisit, reattach to root.
	for p in parts:
		var seen := {}
		var cur := p
		while cur != null and cur.parent_id != -1:
			if seen.has(cur.id):
				p.parent_id = root_id
				fixes.append("Разорван цикл у части %d" % p.id)
				break
			seen[cur.id] = true
			cur = get_part(cur.parent_id)
	for p in parts:
		if p.is_spine() and p.segments.is_empty():
			p.segments.append(BodySegment.new(0.2, p.base_radius))
			fixes.append("Части %d добавлен сегмент" % p.id)
		p.covering = clampi(p.covering, 0, CoveringDef.MAX_SLOTS - 1)
		ensure_covering(p.covering)
	if coverings.is_empty():
		coverings.append(CoveringDef.new())
	return fixes


# --- Hashing / serialization --------------------------------------------------------

## Structural hash used for mesh caching: equal plans → equal hash.
func structural_hash() -> int:
	return MathUtil.fnv1a(JSON.stringify(to_dict()))


func copy() -> BodyPlan:
	return BodyPlan.from_dict(to_dict())


func to_dict() -> Dictionary:
	var pd := []
	for p in parts:
		pd.append(p.to_dict())
	var cd := []
	for c in coverings:
		cd.append(c.to_dict())
	return {
		"format": FORMAT, "name": name, "parts": pd, "coverings": cd, "next_id": next_id,
		"root_id": root_id, "body_axis": str(body_axis), "biology": biology.duplicate(true),
		"custom_rules": custom_rules.duplicate(true),
	}


static func from_dict(d: Dictionary) -> BodyPlan:
	var bp := BodyPlan.new()
	bp.name = Serial.s(d, "name", "Организм")
	bp.parts.clear()
	for pdict in Serial.arr(d, "parts"):
		if pdict is Dictionary:
			bp.parts.append(BodyPart.new().from_dict(pdict))
	bp.coverings.clear()
	for cdict in Serial.arr(d, "coverings"):
		if cdict is Dictionary and bp.coverings.size() < CoveringDef.MAX_SLOTS:
			bp.coverings.append(CoveringDef.new().from_dict(cdict))
	if bp.coverings.is_empty():
		bp.coverings.append(CoveringDef.new())
	bp.next_id = Serial.i(d, "next_id", 1)
	bp.root_id = Serial.i(d, "root_id", -1)
	var axis := Serial.sn(d, "body_axis", &"horizontal")
	bp.body_axis = axis if axis in [&"horizontal", &"vertical"] else &"horizontal"
	bp.biology = BIOLOGY_DEFAULTS.duplicate()
	var bd := Serial.dict(d, "biology")
	for k in bd:
		bp.biology[k] = bd[k]
	bp.custom_rules = CUSTOM_RULE_DEFAULTS.duplicate()
	var cr := Serial.dict(d, "custom_rules")
	for k in cr:
		bp.custom_rules[k] = cr[k]
	bp.repair()
	return bp
