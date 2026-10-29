class_name Food
extends RefCounted
## Food kinds shared by BiologySystem (stomach contents), EcoGrid (sources)
## and PopulationManager (pool feeding). Energy densities are gross energy of
## WET mass (J/kg); digestion efficiency is applied by the consumer
## (PhysiologyProfile.diet_eff).
##
## GAME COMPRESSION NOTE. Life history is compressed (lifespans last game
## days) while metabolic power stays in real watts. With real tissue energy
## (~7 MJ/kg) growing up or breeding would cost ~100× more than maintenance
## and trophic transfer would be unrealistically efficient. Animal tissue
## therefore carries an EFFECTIVE energy of ANIMAL_ENERGY_SCALE × real, used
## consistently both when tissue is built (growth, offspring, eggs) and when
## it is eaten (meat, carrion, eggs) — energy is conserved along food chains.
## Plant matter keeps its real energy density.

enum { PLANT, MEAT, CARRION, DETRITUS, PLANKTON, COUNT }

const ANIMAL_ENERGY_SCALE := 0.25
const IDS: Array[StringName] = [&"plant", &"meat", &"carrion", &"detritus", &"plankton"]
const LABELS := ["Растения", "Мясо", "Падаль", "Детрит", "Планктон"]
## Gross (effective) energy, J per kg of wet mass.
const ENERGY := [6.0e6, 7.0e6 * ANIMAL_ENERGY_SCALE, 6.0e6 * ANIMAL_ENERGY_SCALE, 2.5e6, 3.0e6]
## Water content of wet mass (part of the hydration budget).
const WATER := [0.7, 0.6, 0.55, 0.5, 0.8]
## Base gut retention time, biological seconds (scaled by gut size).
const RETENTION := [43200.0, 14400.0, 14400.0, 36000.0, 10800.0]
## Diet-efficiency key in PhysiologyProfile.diet_eff for each kind.
const EFF_KEYS := ["plant", "meat", "carrion", "detritus", "filter"]

## Effective energy content of animal tissue (J/kg), see the note above.
const TISSUE_ENERGY := 7.0e6 * ANIMAL_ENERGY_SCALE
## Biosynthesis efficiency (fraction of spent energy stored in new tissue).
const SYNTHESIS_EFFICIENCY := 0.7


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
