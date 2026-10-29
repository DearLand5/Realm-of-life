class_name Genome
extends RefCounted
## Heritable material of one organism:
##   * structural genes  — `body_plan` (part graph, coverings, biology choices);
##   * quantitative genes — diploid `alleles` for every locus of TraitCatalog.
## Layout of `alleles`: [locus0_a, locus0_b, locus1_a, locus1_b, ...], values 0..1.

const MAX_LOG := 24
## Traits that change mesh geometry (part of the mesh cache key). `size` is
## excluded on purpose: it is applied as a node scale so meshes are shared.
const MORPH_TRAITS: Array[StringName] = [
	&"limb_length", &"limb_thickness", &"torso_length", &"torso_girth", &"head_size",
	&"tail_length", &"appendage_size", &"wing_area", &"fat_reserve", &"muscle_mass",
]

var body_plan: BodyPlan
var alleles := PackedFloat32Array()
var generation: int = 0
## Notable heritable changes: [{gen:int, kind:String, text:String}]
var mutation_log: Array = []

var _expr := PackedFloat32Array()
var _expr_valid := false
var _morph_key := ""


func _init(plan: BodyPlan = null) -> void:
	body_plan = plan if plan != null else BodyPlan.new()
	reset_to_defaults()


func reset_to_defaults() -> void:
	alleles.resize(TraitCatalog.locus_count() * 2)
	for ti in TraitCatalog.count():
		var d := TraitCatalog.def_at(ti)
		var n := TraitCatalog.normalize(ti, float(d["default"]))
		var ls := TraitCatalog.locus_start(ti)
		for k in int(d["loci"]):
			alleles[(ls + k) * 2] = n
			alleles[(ls + k) * 2 + 1] = n
	invalidate()


func invalidate() -> void:
	_expr_valid = false
	_morph_key = ""


func _ensure_expr() -> void:
	if _expr_valid:
		return
	var n := TraitCatalog.count()
	_expr.resize(n)
	for ti in n:
		var d := TraitCatalog.def_at(ti)
		var h := float(d["h"])
		var ls := TraitCatalog.locus_start(ti)
		var loci := int(d["loci"])
		var acc := 0.0
		for k in loci:
			var a := alleles[(ls + k) * 2]
			var b := alleles[(ls + k) * 2 + 1]
			acc += h * maxf(a, b) + (1.0 - h) * minf(a, b)
		_expr[ti] = acc / float(loci)
	_expr_valid = true


## Expressed normalized value (0..1) of a trait by index.
func norm_at(trait_index: int) -> float:
	_ensure_expr()
	return _expr[trait_index]


## Expressed normalized value (0..1) of a trait by id.
func norm(id: StringName) -> float:
	var ti := TraitCatalog.index_of(id)
	return norm_at(ti) if ti >= 0 else 0.0


## Expressed real value (in trait units) of a trait.
func value(id: StringName) -> float:
	var ti := TraitCatalog.index_of(id)
	if ti < 0:
		push_warning("Genome.value: unknown trait %s" % id)
		return 0.0
	return TraitCatalog.denormalize(ti, norm_at(ti))


## Sets a trait to a real value on all its loci (homozygous). Used by the
## editor to define a founder and by tests.
func set_value(id: StringName, real_value: float) -> void:
	var ti := TraitCatalog.index_of(id)
	if ti < 0:
		return
	var n := TraitCatalog.normalize(ti, real_value)
	var ls := TraitCatalog.locus_start(ti)
	for k in int(TraitCatalog.def_at(ti)["loci"]):
		alleles[(ls + k) * 2] = n
		alleles[(ls + k) * 2 + 1] = n
	invalidate()


## Returns [[a, b], ...] normalized allele pairs of a trait.
func trait_alleles(id: StringName) -> Array:
	var ti := TraitCatalog.index_of(id)
	var out := []
	if ti < 0:
		return out
	var ls := TraitCatalog.locus_start(ti)
	for k in int(TraitCatalog.def_at(ti)["loci"]):
		out.append([alleles[(ls + k) * 2], alleles[(ls + k) * 2 + 1]])
	return out


func is_heterozygous(id: StringName, threshold: float = 0.15) -> bool:
	for pair in trait_alleles(id):
		if absf(float(pair[0]) - float(pair[1])) > threshold:
			return true
	return false


func log_mutation(kind: String, text: String) -> void:
	mutation_log.append({"gen": generation, "kind": kind, "text": text})
	while mutation_log.size() > MAX_LOG:
		mutation_log.pop_front()


## Key identifying the mesh geometry (body plan + quantized morph traits).
func morph_key() -> String:
	if _morph_key != "":
		return _morph_key
	var parts := PackedStringArray([str(body_plan.structural_hash())])
	for id in MORPH_TRAITS:
		parts.append(str(int(round(norm(id) * 20.0))))
	_morph_key = "-".join(parts)
	return _morph_key


func copy() -> Genome:
	var g := Genome.new(body_plan.copy())
	g.alleles = alleles.duplicate()
	g.generation = generation
	g.mutation_log = mutation_log.duplicate(true)
	g.invalidate()
	return g


## Copy sharing the (immutable-by-convention) body plan object. Use only when
## the plan will not be edited afterwards.
func copy_shared_plan() -> Genome:
	var g := Genome.new(body_plan)
	g.alleles = alleles.duplicate()
	g.generation = generation
	g.mutation_log = mutation_log.duplicate(true)
	g.invalidate()
	return g


func to_dict() -> Dictionary:
	var al := {}
	for ti in TraitCatalog.count():
		var d := TraitCatalog.def_at(ti)
		var ls := TraitCatalog.locus_start(ti)
		var pairs := []
		for k in int(d["loci"]):
			pairs.append([snappedf(alleles[(ls + k) * 2], 0.0001), snappedf(alleles[(ls + k) * 2 + 1], 0.0001)])
		al[str(d["id"])] = pairs
	return {"plan": body_plan.to_dict(), "alleles": al, "generation": generation, "mutation_log": mutation_log.duplicate(true)}


## Robust to catalogue changes: unknown traits are ignored, missing traits
## keep catalogue defaults, locus count changes are padded/truncated.
static func from_dict(d: Dictionary) -> Genome:
	var g := Genome.new(BodyPlan.from_dict(Serial.dict(d, "plan")))
	var al := Serial.dict(d, "alleles")
	for key in al:
		var ti := TraitCatalog.index_of(StringName(key))
		if ti < 0:
			continue
		var pairs = al[key]
		if not (pairs is Array):
			continue
		var ls := TraitCatalog.locus_start(ti)
		var loci := int(TraitCatalog.def_at(ti)["loci"])
		for k in loci:
			var pair = pairs[mini(k, pairs.size() - 1)] if pairs.size() > 0 else null
			if pair is Array and pair.size() >= 2:
				g.alleles[(ls + k) * 2] = clampf(float(pair[0]), 0.0, 1.0)
				g.alleles[(ls + k) * 2 + 1] = clampf(float(pair[1]), 0.0, 1.0)
	g.generation = Serial.i(d, "generation", 0)
	g.mutation_log = Serial.arr(d, "mutation_log").duplicate(true)
	g.invalidate()
	return g
