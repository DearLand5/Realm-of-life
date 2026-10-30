class_name SpeciesPool
extends RefCounted
## Population of one species in one sector (tiers C/D): a (fractional)
## head count, an age structure and ≤ MAX_SAMPLES weighted genotype samples
## each with its own condition. Selection acts on sample weights
## (replicator dynamics); recombination/mutation create new samples.

const MAX_SAMPLES := 8
## Age classes.
enum { JUV, ADO, ADULT, ELDER, CLASSES }

var species_id: int = -1
var sector: int = -1
var count: float = 0.0
var classes := PackedFloat32Array([0.3, 0.15, 0.45, 0.1])   # fractions, sum 1
var samples: Array[PoolSample] = []
var births_since_resample: float = 0.0
var resample_queued := false
var last_net: float = 0.0            # last per-capita growth rate (1/s)
var last_kills: float = 0.0          # prey killed by this pool last step
var migrated_in: float = 0.0         # recent immigrants (gene flow indicator)


func mean_energy() -> float:
	var e := 0.0
	var w := 0.0
	for s in samples:
		e += s.energy * s.weight
		w += s.weight
	return e / w if w > 0.0 else 0.0


func normalize_weights() -> void:
	var t := 0.0
	for s in samples:
		t += s.weight
	if t <= 0.0:
		for s in samples:
			s.weight = 1.0 / float(maxi(samples.size(), 1))
		return
	for s in samples:
		s.weight /= t


func normalize_classes() -> void:
	var t := 0.0
	for c in CLASSES:
		classes[c] = maxf(classes[c], 0.0)
		t += classes[c]
	if t <= 0.0:
		classes = PackedFloat32Array([0.0, 0.0, 1.0, 0.0])
		return
	for c in CLASSES:
		classes[c] /= t


## Weighted mean of a trait (normalized 0..1 expression).
func trait_mean(trait_index: int) -> float:
	var t := 0.0
	var w := 0.0
	for s in samples:
		t += s.genome.norm_at(trait_index) * s.weight
		w += s.weight
	return t / w if w > 0.0 else 0.0


## Adds samples (with total share `share` of the merged pool) and keeps at
## most MAX_SAMPLES by merging the lightest sample into its closest relative.
func merge_samples(incoming: Array[PoolSample], share: float) -> void:
	share = clampf(share, 0.0, 1.0)
	for s in samples:
		s.weight *= (1.0 - share)
	var tin := 0.0
	for s in incoming:
		tin += s.weight
	for s in incoming:
		var w := s.weight / tin * share if tin > 0.0 else share / float(incoming.size())
		var same: PoolSample = null
		for o in samples:
			if o.genome == s.genome:
				same = o
				break
		if same != null:
			same.energy = (same.energy * same.weight + s.energy * w) / maxf(same.weight + w, 1e-12)
			same.weight += w
		else:
			var c := s.clone()
			c.weight = w
			samples.append(c)
	compact()


func compact() -> void:
	while samples.size() > MAX_SAMPLES:
		var li := 0
		for i in samples.size():
			if samples[i].weight < samples[li].weight:
				li = i
		var light := samples[li]
		samples.remove_at(li)
		var best: PoolSample = samples[0]
		var best_d := INF
		for o in samples:
			var d := Genetics.distance(light.genome, o.genome)
			if d < best_d:
				best_d = d
				best = o
		best.energy = (best.energy * best.weight + light.energy * light.weight) / maxf(best.weight + light.weight, 1e-12)
		best.weight += light.weight
	normalize_weights()


func to_dict(genome_ids: Dictionary, genomes: Array) -> Dictionary:
	var sd := []
	for s in samples:
		var gi: int = genome_ids.get(s.genome, -1)
		if gi < 0:
			gi = genomes.size()
			genome_ids[s.genome] = gi
			genomes.append(s.genome)
		sd.append(s.to_dict(gi))
	return {
		"species": species_id, "sector": sector, "count": count, "classes": Array(classes), "samples": sd,
		"births": births_since_resample, "net": last_net,
	}
