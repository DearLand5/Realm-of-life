class_name GenomeCodec
extends RefCounted
## Serializes many genomes compactly: identical genome objects are stored
## once and body plans (shared supergenes) are deduplicated by structural
## hash. Alleles keep Genome.to_dict()'s trait-keyed format, so catalogue
## changes stay tolerated. Shared objects stay shared after loading (cheap
## phenotype reuse in population pools).
##   var c := GenomeCodec.new(); var i := c.add(genome) ... c.to_dict()
##   var d := GenomeCodec.from_dict(data); d.genome(i)

var _index := {}          # Genome -> int
var _genomes: Array[Genome] = []
var _plan_index := {}     # structural hash -> int
var _plans: Array = []    # plan dicts (encoding) or BodyPlan (decoding)


func add(g: Genome) -> int:
	if _index.has(g):
		return int(_index[g])
	var i := _genomes.size()
	_index[g] = i
	_genomes.append(g)
	return i


func genome(i: int) -> Genome:
	return _genomes[i] if i >= 0 and i < _genomes.size() else null


func size() -> int:
	return _genomes.size()


func to_dict() -> Dictionary:
	var gl := []
	for g in _genomes:
		var h := g.body_plan.structural_hash()
		var pi: int = _plan_index.get(h, -1)
		if pi < 0:
			pi = _plans.size()
			_plan_index[h] = pi
			_plans.append(g.body_plan.to_dict())
		var d := g.to_dict()
		d.erase("plan")
		d["p"] = pi
		gl.append(d)
	return {"plans": _plans.duplicate(), "genomes": gl}


static func from_dict(d: Dictionary) -> GenomeCodec:
	var c := GenomeCodec.new()
	var plans: Array[BodyPlan] = []
	for pd in Serial.arr(d, "plans"):
		plans.append(BodyPlan.from_dict(pd if pd is Dictionary else {}))
	for gd in Serial.arr(d, "genomes"):
		if not (gd is Dictionary):
			c._genomes.append(Genome.new())
			continue
		var g := Genome.from_dict(gd)
		var pi := Serial.i(gd, "p", -1)
		if pi >= 0 and pi < plans.size():
			g.body_plan = plans[pi]
			g.invalidate()
		c._genomes.append(g)
	return c
