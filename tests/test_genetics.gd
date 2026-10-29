extends TestCase
## Mendelian expression, recombination, mutation, distance, serialization.


func test_dominance_and_recessive() -> void:
	var g := Genome.new()
	var ti := TraitCatalog.index_of(&"albinism")
	var li := TraitCatalog.locus_start(ti)
	g.alleles[li * 2] = 1.0
	g.alleles[li * 2 + 1] = 0.0
	g.invalidate()
	near(g.norm(&"albinism"), 0.0, 0.001, "recessive albinism hidden in heterozygote")
	g.alleles[li * 2 + 1] = 1.0
	g.invalidate()
	near(g.norm(&"albinism"), 1.0, 0.001, "homozygous albinism expressed")
	var mi := TraitCatalog.locus_start(TraitCatalog.index_of(&"melanism"))
	g.alleles[mi * 2] = 1.0
	g.alleles[mi * 2 + 1] = 0.0
	g.invalidate()
	check(g.norm(&"melanism") > 0.85, "dominant melanism expressed in heterozygote")


func test_mendelian_ratio() -> void:
	# Aa x Aa for a recessive single-locus trait -> ~25% affected.
	var rng := Rng.new(1234)
	var parent := Genome.new()
	var li := TraitCatalog.locus_start(TraitCatalog.index_of(&"albinism"))
	parent.alleles[li * 2] = 1.0
	parent.alleles[li * 2 + 1] = 0.0
	parent.invalidate()
	var settings := {"rate": 0.0, "structural_probability": 0.0}
	var affected := 0
	var n := 2000
	for i in n:
		var c := Genetics.sexual(parent, parent, rng, settings)
		if c.norm(&"albinism") > 0.5:
			affected += 1
	near(float(affected) / n, 0.25, 0.04, "recessive phenotype ratio")


func test_mutation_changes_and_bounds() -> void:
	var rng := Rng.new(99)
	var g := BodyPlanPresets.create(&"grazer")
	var settings := Genetics.settings_with_defaults({"rate": 5.0, "structural_probability": 0.5})
	var changed := 0
	var structural := 0
	for i in 200:
		var c := Genetics.asexual(g, rng, settings)
		if Genetics.distance(g, c) > 0.0001:
			changed += 1
		if c.body_plan != g.body_plan:
			structural += 1
		for a in c.alleles:
			check(a >= 0.0 and a <= 1.0, "allele in range")
		Phenotype.build(c)
	check(changed > 100, "high mutation rate changes most offspring (%d)" % changed)
	check(structural > 10, "structural mutations happen (%d)" % structural)


func test_category_lock() -> void:
	var rng := Rng.new(5)
	var g := BodyPlanPresets.create(&"fish")
	var cats := {"anatomy": false, "color": true, "physiology": false, "life": false, "behavior": false, "senses": false, "structure": false}
	var settings := Genetics.settings_with_defaults({"rate": 20.0, "categories": cats})
	var c := g
	for i in 30:
		c = Genetics.asexual(c, rng, settings)
	near(c.value(&"metabolism"), g.value(&"metabolism"), 0.0001, "locked physiology unchanged")
	check(c.body_plan == g.body_plan, "locked structure unchanged")
	check(absf(c.value(&"hue_shift") - g.value(&"hue_shift")) > 0.0 or absf(c.value(&"saturation") - g.value(&"saturation")) > 0.0, "colour evolved")


func test_distance() -> void:
	var a := BodyPlanPresets.create(&"grazer")
	var b := BodyPlanPresets.create(&"fish")
	check(Genetics.distance(a, a.copy()) < 0.001, "self distance ~0")
	check(Genetics.distance(a, b) > 0.2, "grazer vs fish far apart (%.3f)" % Genetics.distance(a, b))


func test_serialization_roundtrip() -> void:
	for id in BodyPlanPresets.IDS:
		var g := BodyPlanPresets.create(id)
		Genetics.founder_variation(g, Rng.new(7), 0.05)
		var json := JSON.stringify(g.to_dict())
		var parsed = JSON.parse_string(json)
		var g2 := Genome.from_dict(parsed)
		check(Genetics.distance(g, g2) < 0.0005, "%s genome roundtrip" % id)
		check(g.body_plan.parts.size() == g2.body_plan.parts.size(), "%s parts roundtrip" % id)
		var m1 := AnatomyCompiler.compile(g)
		var m2 := AnatomyCompiler.compile(g2)
		near(float(m1.stats["mass"]), float(m2.stats["mass"]), float(m1.stats["mass"]) * 0.001 + 1e-6, "%s mass after roundtrip" % id)


func test_unknown_and_missing_keys() -> void:
	var d := BodyPlanPresets.create(&"worm").to_dict()
	d["alleles"].erase("size")
	d["alleles"]["future_trait"] = [[0.1, 0.2]]
	d["plan"]["future_field"] = 42
	var g := Genome.from_dict(d)
	near(g.value(&"size"), 1.0, 0.001, "missing trait falls back to default")
