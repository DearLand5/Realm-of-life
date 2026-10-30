class_name Feeding
extends RefCounted
## Eating and drinking mechanics shared by the AI and the player: intake is
## limited by the mouth/gut (PhysiologyProfile.intake_limit, free stomach space);
## food is removed from the EcoGrid and handed to BiologySystem.feed().
## Intake rates are per BIOLOGICAL second, `phys_dt` is physical seconds.

const FRESH_CARCASS_AGE := 0.15 * Units.SECONDS_PER_DAY   # bio s; fresher kills count as meat
const MAX_TOXICITY_ACCEPTED := 0.55


## Preference weight (0..1) per plant species for this creature.
static func plant_prefs(a: CreatureAgent, eco: EcoGrid) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var reach := a.mover.height * 1.3 + 0.3
	var aquatic := a.phys.habitat == &"water" or a.mover.aquatic_only
	for sp in eco.plant_species:
		var w := 1.0 - sp.toxicity * 0.9 - sp.toughness * 0.25
		if sp.aquatic != aquatic and not (sp.aquatic and a.phys.habitat == &"amphibious"):
			w = 0.0
		if not sp.aquatic:
			w *= clampf(reach / maxf(sp.height * 0.5, 0.05), 0.12, 1.0)
		out.append(clampf(w, 0.0, 1.0))
	return out


## Eats `kind` for `phys_dt` seconds at the creature's position. Returns wet kg eaten.
static func eat(a: CreatureAgent, kind: int, phys_dt: float, carcass_id: int = -1) -> float:
	var ind := a.individual
	var p := a.phys
	var eco := a.ctx.eco as EcoGrid
	if eco == null or not ind.alive:
		return 0.0
	var mf := ind.mass_factor()
	var free := p.gut_capacity_kg * mf - ind.stomach_total()
	var want := minf(p.intake_limit(kind, mf) * phys_dt * Units.BIO_TIME_RATIO, free)
	if want <= 1e-7:
		return 0.0
	var h := {}
	match kind:
		Food.PLANT:
			h = eco.consume_plants(a.mover.pos, want, a.plant_prefs(eco))
		Food.DETRITUS:
			h = eco.consume_detritus(a.mover.pos, want)
		Food.PLANKTON:
			h = eco.consume_plankton(a.mover.pos, want)
		Food.CARRION:
			var i := eco.carcasses.index_of(carcass_id)
			if i < 0:
				return 0.0
			var age := eco.carcasses.ages[i]
			h = eco.consume_carcass(carcass_id, want)
			if age < FRESH_CARCASS_AGE and Relations.eats_meat(p):
				kind = Food.MEAT
	var kg := float(h.get("kg", 0.0))
	if kg <= 0.0:
		return 0.0
	var tox := float(h.get("toxicity", 0.0))
	var quality := float(h.get("energy", 0.0)) / (kg * float(Food.ENERGY[kind]))
	a.bio.feed(ind, kind, kg, quality, tox)
	return kg


## Eats part of a freshly killed animal / egg directly (no ecosystem or no carcass yet).
static func eat_body(a: CreatureAgent, mass_kg: float) -> float:
	var ind := a.individual
	var p := a.phys
	var mf := ind.mass_factor()
	var free := p.gut_capacity_kg * mf - ind.stomach_total()
	var kg := minf(mass_kg * 0.7, maxf(free, 0.0))
	if kg <= 0.0:
		return 0.0
	a.bio.feed(ind, Food.MEAT, kg, 1.0, 0.0)
	return kg


## Drinks for `phys_dt` seconds (needs water in reach, checked by the caller).
static func drink(a: CreatureAgent, phys_dt: float) -> float:
	var ind := a.individual
	var p := a.phys
	var mf := ind.mass_factor()
	var max_kg := p.body_water_kg * mf * 0.6 * phys_dt   # a thirsty animal drinks its fill in seconds
	return a.bio.drink(ind, max_kg)
