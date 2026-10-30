class_name PlayerActions
extends RefCounted
## Context actions the player can trigger on a possessed creature (eat, drink,
## attack, mate, call, rest ...) and which of them are available right now.
## Uses the same mechanics as the AI (Feeding, attack(), Reproduction).

const REACH_EXTRA := 0.6


## {eat, drink, attack, jump, sprint, call, mate, rest, fly, dive, ascend, descend} -> bool
static func available(a: CreatureAgent) -> Dictionary:
	var m := a.mover
	var lp := m.lp
	var out := {
		"eat": false, "drink": false, "attack": false, "jump": false, "sprint": false, "call": true,
		"mate": false, "rest": true, "fly": false, "dive": false, "ascend": false, "descend": false,
	}
	if not a.is_alive() or a.is_egg():
		return out
	out["eat"] = eat_kind(a) != -2
	out["drink"] = a.individual.hydration < 0.995 and (a.water_in_reach() or m.water_depth > 0.05)
	out["attack"] = attack_target(a) != null
	out["jump"] = lp.can_jump and m.on_ground and m.medium == &"land"
	out["sprint"] = m.medium == &"land" and lp.can_walk
	out["mate"] = mate_partner(a) != null
	out["fly"] = lp.can_fly
	out["dive"] = lp.can_swim and (m.medium == &"water" or a.water_in_reach())
	out["ascend"] = m.flying or (m.medium == &"water" and lp.can_swim)
	out["descend"] = out["ascend"]
	return out


## Food kind that can be eaten at the current spot: Food.* index, -1 = carcass/prey body, -2 = none.
static func eat_kind(a: CreatureAgent) -> int:
	var eco := a.ctx.eco as EcoGrid
	var ind := a.individual
	if ind.stomach_fullness() > 0.97:
		return -2
	if eco != null:
		var i := eco.carcasses.nearest(a.mover.pos, a.body_length() * 0.6 + 1.0)
		if i >= 0 and (Relations.eats_carrion(a.phys) or Relations.eats_meat(a.phys)):
			return Food.CARRION
		var cells := PackedInt32Array([eco.cell_index(a.mover.pos)])
		var w := a.food_weights
		if w[Food.PLANT] > 0.08 and eco.plant_available(cells, a.plant_prefs(eco)) > 0.05:
			return Food.PLANT
		if w[Food.DETRITUS] > 0.15 and eco.detritus_available(cells) > 0.05:
			return Food.DETRITUS
		if w[Food.PLANKTON] > 0.15 and a.mover.medium == &"water" and eco.plankton_available(cells) > 0.003:
			return Food.PLANKTON
	return -2


static func eat(a: CreatureAgent, dt: float) -> float:
	var kind := eat_kind(a)
	if kind == -2:
		return 0.0
	var cid := -1
	if kind == Food.CARRION:
		var eco := a.ctx.eco as EcoGrid
		var i := eco.carcasses.nearest(a.mover.pos, a.body_length() * 0.6 + 1.0)
		cid = eco.carcasses.ids[i]
	a.player_pose = &"eat"
	return Feeding.eat(a, kind, dt, cid)


static func drink(a: CreatureAgent, dt: float) -> float:
	a.player_pose = &"drink"
	return Feeding.drink(a, dt)


## Nearest other creature (or egg) in front of the mouth.
static func attack_target(a: CreatureAgent) -> CreatureAgent:
	var m := a.mover
	var best: CreatureAgent = null
	var best_d := INF
	var fwd := m.forward()
	var reach := m.length * 0.55 + REACH_EXTRA + 1.0
	for o in a.ctx.agents.query(m.pos, reach + 1.5, a, 12):
		var oa := o as CreatureAgent
		if oa == null or not oa.is_alive():
			continue
		var d := oa.position - m.pos
		var flat := Vector3(d.x, 0.0, d.z)
		var dist := flat.length()
		if dist > reach + oa.mover.radius:
			continue
		if dist > 0.3 and flat.normalized().dot(fwd) < 0.2:
			continue
		if dist < best_d:
			best_d = dist
			best = oa
	return best


static func attack(a: CreatureAgent) -> Dictionary:
	var t := attack_target(a)
	if t == null:
		return {}
	a.player_pose = &"attack"
	return a.attack(t)


static func mate_partner(a: CreatureAgent) -> CreatureAgent:
	if not a.individual.is_mature():
		return null
	for o in a.ctx.agents.query(a.mover.pos, a.body_length() * 3.0 + 3.0, a, 8):
		var oa := o as CreatureAgent
		if oa != null and oa.is_alive() and not oa.is_egg() and Reproduction.can_mate(a.individual, oa.individual, a.ctx.climate):
			return oa
	return null


static func mate(a: CreatureAgent) -> bool:
	var p := mate_partner(a)
	if p == null:
		return false
	var mother := p.individual if a.individual.sex == Individual.Sex.MALE else a.individual
	var father := a.individual if a.individual.sex == Individual.Sex.MALE else p.individual
	var ok := Reproduction.conceive(mother, father, a.bio.rng, a.ctx.mutation_settings, a.ctx.climate)
	a.mating_done = true
	a.individual.repro_cooldown = maxf(a.individual.repro_cooldown, 60.0)
	p.individual.repro_cooldown = maxf(p.individual.repro_cooldown, 60.0)
	return ok


static func call_out(a: CreatureAgent) -> void:
	a.player_pose = &"call"
	a.emit_call(&"sound", 1.4)
