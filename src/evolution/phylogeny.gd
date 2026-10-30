class_name Phylogeny
extends RefCounted
## Tree export for the phylogeny UI and lineage comparisons.


## {nodes: [{id, name, latin, parent, origin, niche, color, created_day,
##   extinct, extinct_day, count, depth, order}], edges: [{from, to, day}]}
## `order` is a DFS leaf order (x position), `depth` the speciation depth.
static func export(registry: SpeciesRegistry) -> Dictionary:
	var defs := registry.all()
	var children := {}
	for d in defs:
		var key := d.parent_id if registry.has(d.parent_id) else -1
		if not children.has(key):
			children[key] = []
		(children[key] as Array).append(d.id)
	var depth := {}
	var order := {}
	var counter := [0]
	for root in children.get(-1, []):
		_walk(int(root), 0, children, depth, order, counter)
	var nodes := []
	var edges := []
	for d in defs:
		nodes.append({
			"id": d.id, "name": d.name, "latin": d.latin_name, "parent": d.parent_id, "origin": str(d.origin),
			"niche": str(d.niche), "color": d.ui_color, "created_day": d.created_day, "extinct": d.extinct,
			"extinct_day": d.extinct_day, "count": registry.count(d.id), "depth": int(depth.get(d.id, 0)),
			"order": float(order.get(d.id, 0.0)),
		})
		if registry.has(d.parent_id):
			edges.append({"from": d.parent_id, "to": d.id, "day": d.created_day})
	return {"nodes": nodes, "edges": edges}


static func _walk(id: int, dep: int, children: Dictionary, depth: Dictionary, order: Dictionary, counter: Array) -> float:
	depth[id] = dep
	var kids: Array = children.get(id, [])
	if kids.is_empty():
		order[id] = float(counter[0])
		counter[0] = int(counter[0]) + 1
		return order[id]
	var acc := 0.0
	for k in kids:
		acc += _walk(int(k), dep + 1, children, depth, order, counter)
	order[id] = acc / float(kids.size())
	return order[id]


## Weighted centroid of [{genome, weight}] (body plan of the heaviest sample).
static func centroid(samples: Array) -> Genome:
	if samples.is_empty():
		return null
	var best: Genome = samples[0]["genome"]
	var best_w := -1.0
	var wsum := 0.0
	for e in samples:
		var w := float(e["weight"])
		wsum += w
		if w > best_w:
			best_w = w
			best = e["genome"]
	var c := best.copy_shared_plan()
	for i in c.alleles.size():
		var acc := 0.0
		for e in samples:
			acc += (e["genome"] as Genome).alleles[i] * float(e["weight"])
		c.alleles[i] = acc / maxf(wsum, 1e-12)
	c.mutation_log = []
	c.invalidate()
	return c


## Trait-by-trait differences, largest first: [{trait, label, category, a, b, diff}]
## (a/b in real trait units, diff in normalized units), plus a structural entry.
static func compare_genomes(a: Genome, b: Genome, limit: int = 12) -> Array:
	var out := []
	for ti in TraitCatalog.count():
		var d := TraitCatalog.def_at(ti)
		var diff := b.norm_at(ti) - a.norm_at(ti)
		if absf(diff) < 0.005:
			continue
		out.append({"trait": d["id"], "label": d["label"], "category": d["cat"],
			"a": TraitCatalog.denormalize(ti, a.norm_at(ti)), "b": TraitCatalog.denormalize(ti, b.norm_at(ti)), "diff": diff})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return absf(float(x["diff"])) > absf(float(y["diff"])))
	if out.size() > limit:
		out.resize(limit)
	var sd := BodyPlanMutator.structural_distance(a.body_plan, b.body_plan)
	if sd > 0.0:
		out.append({"trait": &"structure", "label": "Строение тела", "category": &"structure",
			"a": float(a.body_plan.parts.size()), "b": float(b.body_plan.parts.size()), "diff": sd})
	return out
