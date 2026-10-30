class_name Relations
extends RefCounted
## Who is who for a creature: classification of other animals by size, weapons
## and diet (conspecific / predator / prey / neutral) and the combat arithmetic
## shared by AI and player control.

const ROLE_FEARED_MASS_RATIO := 0.16     # a meat eater lighter than this fraction of me is no danger
const ROLE_PREY_MAX_RATIO := 2.0         # I can bring down animals up to this multiple of my mass
const ROLE_PREY_MIN_RATIO := 0.012       # smaller is not worth the chase


## Weighted weapon strength (bite + claws + half horns/spikes + venom).
static func weapon_force(p: PhysiologyProfile, st: Dictionary) -> float:
	var w: Dictionary = st.get("weapons", {})
	return float(w.get("bite", 0.0)) + float(w.get("claw", 0.0)) + 0.5 * float(w.get("horn", 0.0)) \
		+ 0.6 * float(w.get("spike", 0.0)) + 2.0 * float(w.get("venom", 0.0))


static func combat_power(p: PhysiologyProfile, st: Dictionary, mass: float) -> float:
	return pow(maxf(mass, 0.001), 0.75) * (0.4 + 0.25 * weapon_force(p, st))


static func eats_meat(p: PhysiologyProfile) -> bool:
	return (p.diet == &"carnivore" or p.diet == &"omnivore") and float(p.diet_eff["meat"]) > 0.2 and p.mouth_type != &"none"


static func eats_carrion(p: PhysiologyProfile) -> bool:
	return float(p.diet_eff["carrion"]) > 0.15 and p.mouth_type != &"none" and p.diet != &"herbivore" and p.diet != &"filter"


## Role of `other` as seen by `me`. `same_species` is decided by the caller.
static func classify(me: PhysiologyProfile, me_st: Dictionary, me_mass: float,
		other: PhysiologyProfile, other_st: Dictionary, other_mass: float, same_species: bool) -> StringName:
	if same_species:
		return Percept.ROLE_CONSPECIFIC
	var danger := false
	if eats_meat(other) and other.diet != &"scavenger":
		var ratio := other_mass / maxf(me_mass, 1e-6)
		danger = ratio >= ROLE_FEARED_MASS_RATIO or (float(other_st.get("weapons", {}).get("venom", 0.0)) > 0.5 and ratio > 0.02)
		# A much smaller animal cannot kill me however sharp its teeth.
		if combat_power(other, other_st, other_mass) < 0.12 * combat_power(me, me_st, me_mass):
			danger = false
	var prey := false
	if eats_meat(me) and me.diet != &"scavenger":
		var r := other_mass / maxf(me_mass, 1e-6)
		prey = r <= ROLE_PREY_MAX_RATIO and r >= ROLE_PREY_MIN_RATIO
		if prey and combat_power(other, other_st, other_mass) > 1.8 * combat_power(me, me_st, me_mass):
			prey = false   # too dangerous to attack
	if danger and prey:
		return Percept.ROLE_PREDATOR if combat_power(other, other_st, other_mass) > 0.8 * combat_power(me, me_st, me_mass) else Percept.ROLE_PREY
	if danger:
		return Percept.ROLE_PREDATOR
	if prey:
		return Percept.ROLE_PREY
	return Percept.ROLE_NEUTRAL


## 0..1 danger posed by a predator percept to me.
static func threat_level(me_power: float, other_power: float, other_aggression: float) -> float:
	var ratio := other_power / maxf(me_power, 1e-6)
	return clampf(0.25 + 0.5 * sqrt(ratio) * (0.5 + other_aggression), 0.1, 1.0)


## Health damage (fraction of max health) of one successful attack.
static func attack_damage(att_p: PhysiologyProfile, att_st: Dictionary, att_mass: float,
		def_p: PhysiologyProfile, def_mass: float, rng_roll: float = 0.5) -> float:
	var f := weapon_force(att_p, att_st)
	var venom := float(att_st.get("weapons", {}).get("venom", 0.0))
	var base := 0.045 * (0.3 + f) * pow(att_mass / maxf(def_mass, 1e-6), 0.55)
	base *= 1.0 - clampf(def_p.armor, 0.0, 1.0) * 0.6
	base *= 1.0 + venom * 1.0
	return clampf(base * (0.7 + 0.6 * rng_roll), 0.0, 0.6)


## Chance that an attack lands: agility difference and whether the target is still.
static func hit_chance(att_agility: float, def_agility: float, def_speed_frac: float, def_asleep: bool) -> float:
	if def_asleep:
		return 0.95
	return clampf(0.62 + 0.45 * (att_agility - def_agility) - 0.25 * def_speed_frac, 0.12, 0.95)
