class_name Food
extends RefCounted
## Food kinds shared by BiologySystem (stomach contents), EcoGrid (sources)
## and PopulationManager (pool feeding). Energy densities are gross energy of
## WET mass (J/kg); digestion efficiency is applied by the consumer
## (PhysiologyProfile.diet_eff).
##
## GAME COMPRESSION NOTE. Life history is compressed (lifespans last game
## days, not years) while metabolism stays in real watts and food keeps its
## real energy. Building tissue at its full energy content would make growing
## up and breeding cost ~100× maintenance and exceed what any gut can process
## in the compressed time. Development (growth, embryos, eggs) is therefore
## charged at DEVELOPMENT_COST_SCALE of the real construction cost — think of
## it as parental provisioning and compressed development folded together.
## Development times are additionally bounded by the parent's digestive
## assimilation capacity (LifeHistory), so the causal link "better gut →
## faster growth and breeding" is kept.

enum { PLANT, MEAT, CARRION, DETRITUS, PLANKTON, COUNT }

const IDS: Array[StringName] = [&"plant", &"meat", &"carrion", &"detritus", &"plankton"]
const LABELS := ["Растения", "Мясо", "Падаль", "Детрит", "Планктон"]
## Gross energy, J per kg of wet mass.
const ENERGY := [6.0e6, 7.0e6, 6.0e6, 2.5e6, 3.0e6]
## Water content of wet mass (part of the hydration budget).
const WATER := [0.7, 0.6, 0.55, 0.5, 0.8]
## Gut retention time (s) of a 10 kg animal; scales ∝ M^0.25.
const RETENTION := [43200.0, 10800.0, 10800.0, 28800.0, 7200.0]
## Diet-efficiency key in PhysiologyProfile.diet_eff for each kind.
const EFF_KEYS := ["plant", "meat", "carrion", "detritus", "filter"]

## Energy content of animal tissue (J/kg).
const TISSUE_ENERGY := 7.0e6
## Biosynthesis efficiency (fraction of spent energy stored in new tissue).
const SYNTHESIS_EFFICIENCY := 0.7
const DEVELOPMENT_COST_SCALE := 0.2
## Energy charged per kg of new body tissue (growth, embryos, eggs).
const BUILD_COST := TISSUE_ENERGY * DEVELOPMENT_COST_SCALE / SYNTHESIS_EFFICIENCY


static func index_of(kind) -> int:
	if kind is int:
		return clampi(kind, 0, COUNT - 1)
	var sn := StringName(str(kind))
	var i := IDS.find(sn)
	if i >= 0:
		return i
	if sn == &"filter":
		return PLANKTON
	if sn == &"egg":
		return MEAT
	return -1


static func id_of(kind: int) -> StringName:
	return IDS[clampi(kind, 0, COUNT - 1)]
