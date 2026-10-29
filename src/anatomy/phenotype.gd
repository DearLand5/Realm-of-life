class_name Phenotype
extends RefCounted
## Everything derived from one genome. Built once per individual (cheap: no
## meshes). Meshes are cached separately by Genome.morph_key().
##   anatomy     — AnatomyCompiler (ProceduralAnatomy)
##   locomotion  — LocomotionProfile (CreaturePhysics)
##   senses      — SenseProfile (AIBehaviorSystem)
##   physiology  — PhysiologyProfile (BiologySystem)

var genome: Genome
var anatomy: AnatomyModel
var locomotion: LocomotionProfile
var senses: SenseProfile
var physiology: PhysiologyProfile


static func build(g: Genome) -> Phenotype:
	var ph := Phenotype.new()
	ph.genome = g
	ph.anatomy = AnatomyCompiler.compile(g)
	ph.locomotion = LocomotionProfile.build(ph.anatomy, g)
	ph.senses = SenseProfile.build(ph.anatomy, g)
	ph.physiology = PhysiologyProfile.build(ph)
	return ph


func mass() -> float:
	return float(anatomy.stats.get("mass", 1.0))
