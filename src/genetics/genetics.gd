class_name Genetics
extends RefCounted
## Stateless genetic operators: meiosis with linkage, fertilisation, mutation,
## genetic distance and founder variation. All randomness comes from the
## caller's Rng so populations are reproducible.

const DEFAULT_SETTINGS := {
	"rate": 1.0,                    # global multiplier on mutation probability
	"strength": 1.0,                # global multiplier on mutation step
	"locus_probability": 0.02,      # base per-allele mutation chance per generation
	"large_effect_chance": 0.06,    # share of mutations with a 4x step
	"structural_probability": 0.05, # base chance of a body-plan mutation per offspring
	"crossover_rate": 0.12,         # crossover chance between neighbouring loci
	"categories": {
		"anatomy": true, "color": true, "physiology": true, "life": true,
		"behavior": true, "senses": true, "structure": true,
	},
}

## Category weights for genetic distance (behaviour diverges more freely).
const DISTANCE_WEIGHTS := {
	&"anatomy": 1.2, &"color": 0.8, &"physiology": 1.0, &"life": 1.0, &"behavior": 0.6, &"senses": 0.8,
}


static func settings_with_defaults(s: Dictionary = {}) -> Dictionary:
	var out := DEFAULT_SETTINGS.duplicate(true)
	for k in s:
		if k == "categories" and s[k] is Dictionary:
			for c in s[k]:
				out["categories"][c] = bool(s[k][c])
		else:
			out[k] = s[k]
	return out


## Haploid gamete: one allele per locus, chromosomes recombine with crossovers.
static func gamete(g: Genome, rng: Rng, crossover_rate: float = 0.12) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(TraitCatalog.locus_count())
	for chr in TraitCatalog.CHROMOSOMES:
		var strand := rng.range_i(0, 1)
		for li in TraitCatalog.chromosome_loci(chr):
			if rng.chance(crossover_rate):
				strand = 1 - strand
			out[li] = g.alleles[li * 2 + strand]
	return out


static func combine(ga: PackedFloat32Array, gb: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(ga.size() * 2)
	for li in ga.size():
		out[li * 2] = ga[li]
		out[li * 2 + 1] = gb[li]
	return out


## Sexual reproduction. The body plan behaves as a supergene inherited from one
## parent, with per-part crossover where both parents share the part id.
static func sexual(mother: Genome, father: Genome, rng: Rng, settings: Dictionary = {}) -> Genome:
	var s := settings_with_defaults(settings)
	var cr := float(s["crossover_rate"])
	var base_plan := mother.body_plan if rng.chance(0.5) else father.body_plan
	var other_plan := father.body_plan if base_plan == mother.body_plan else mother.body_plan
	var plan := _cross_plans(base_plan, other_plan, rng)
	var child := Genome.new(plan)
	child.alleles = combine(gamete(mother, rng, cr), gamete(father, rng, cr))
	child.generation = maxi(mother.generation, father.generation) + 1
	child.invalidate()
	mutate(child, rng, s)
	return child


## Asexual reproduction (fission, budding, spores, parthenogenesis): a clone
## that only differs through new mutations.
static func asexual(parent: Genome, rng: Rng, settings: Dictionary = {}) -> Genome:
	var child := parent.copy_shared_plan()
	child.generation = parent.generation + 1
	child.mutation_log = []
	mutate(child, rng, settings_with_defaults(settings))
	return child


static func _cross_plans(base: BodyPlan, other: BodyPlan, rng: Rng) -> BodyPlan:
	if base == other or base.structural_hash() == other.structural_hash():
		return base  # shared, immutable by convention
	var plan := base.copy()
	var swapped := false
	for i in plan.parts.size():
		var p := plan.parts[i]
		var q := other.get_part(p.id)
		if q == null or q.kind != p.kind or q.segments.size() != p.segments.size():
			continue
		if rng.chance(0.5):
			var np := q.copy()
			np.parent_id = p.parent_id
			plan.parts[i] = np
			swapped = true
	return plan if swapped else base


## Applies mutations in place. Returns the number of mutations.
static func mutate(g: Genome, rng: Rng, settings: Dictionary) -> int:
	var cats: Dictionary = settings.get("categories", {})
	var rate := float(settings.get("rate", 1.0)) * g.value(&"mutation_rate")
	var strength := float(settings.get("strength", 1.0))
	var p := float(settings.get("locus_probability", 0.02)) * rate
	var large := float(settings.get("large_effect_chance", 0.06))
	var count := 0
	if p > 0.0:
		var n_alleles := g.alleles.size()
		# Expected mutations is small; sample the count and positions instead of
		# rolling every allele (cheap for big populations).
		var n_mut := rng.poisson(p * float(n_alleles))
		for _k in n_mut:
			var ai := rng.range_i(0, n_alleles - 1)
			var ti := TraitCatalog.trait_of_locus(ai / 2)
			var d := TraitCatalog.def_at(ti)
			if not bool(cats.get(str(d["cat"]), true)):
				continue
			var is_large := rng.chance(large)
			var step := float(d["sigma"]) * strength * (4.0 if is_large else 1.0)
			var before := g.norm_at(ti)
			g.alleles[ai] = clampf(g.alleles[ai] + rng.gauss(0.0, step), 0.0, 1.0)
			g.invalidate()
			count += 1
			if is_large and absf(g.norm_at(ti) - before) > 0.05:
				var dir := "↑" if g.norm_at(ti) > before else "↓"
				g.log_mutation("trait", "%s %s" % [d["label"], dir])
	if bool(cats.get("structure", true)):
		var ps := float(settings.get("structural_probability", 0.05)) * rate
		if rng.chance(ps):
			var plan := g.body_plan.copy()
			var text := BodyPlanMutator.mutate(plan, rng, strength)
			if text != "":
				g.body_plan = plan
				g.log_mutation("structure", text)
				count += 1
	g.invalidate()
	return count


## Genetic distance 0..~1 combining quantitative and structural divergence.
static func distance(a: Genome, b: Genome) -> float:
	var acc := 0.0
	var wsum := 0.0
	for ti in TraitCatalog.count():
		var w := float(DISTANCE_WEIGHTS.get(TraitCatalog.def_at(ti)["cat"], 1.0))
		acc += absf(a.norm_at(ti) - b.norm_at(ti)) * w
		wsum += w
	var q := acc / maxf(wsum, 0.0001)
	var s := 0.0 if a.body_plan == b.body_plan else BodyPlanMutator.structural_distance(a.body_plan, b.body_plan)
	return q + 0.5 * s


## Adds standing genetic variation around a founder (heterozygosity).
static func founder_variation(g: Genome, rng: Rng, amount: float = 0.04) -> void:
	for i in g.alleles.size():
		g.alleles[i] = clampf(g.alleles[i] + rng.gauss(0.0, amount), 0.0, 1.0)
	g.invalidate()


## Average genome (centroid) of a set — used for species reference genomes.
static func centroid(genomes: Array) -> Genome:
	if genomes.is_empty():
		return null
	var first: Genome = genomes[0]
	var c := first.copy_shared_plan()
	for i in c.alleles.size():
		var acc := 0.0
		for gg in genomes:
			acc += (gg as Genome).alleles[i]
		c.alleles[i] = acc / float(genomes.size())
	c.invalidate()
	return c
