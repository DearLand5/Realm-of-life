class_name ActHunt
extends AiAction
## Hunt: stalk unsuspecting prey, charge, strike (and kill). Feasibility weighs
## relative speeds, the hunter's stamina (MuscleSystem fatigue) and distance.
## Social carnivores flank prey together (pack hunting). Eggs are taken without
## a chase. After a kill the Scavenge action eats the carcass.

enum Phase { STALK, CHASE, STRIKE }

var phase: int = Phase.STALK
var prey: Percept = null
var chase_t: float = 0.0
var _lost: float = 0.0
var _flank: float = 0.0


func _init() -> void:
	id = &"hunt"
	label = "Охотится"
	min_commit = 4.0


func _pick() -> Percept:
	var best: Percept = null
	var best_s := 0.0
	for k in a.perception.memory.short:
		var p: Percept = a.perception.memory.short[k]
		if p.role != Percept.ROLE_PREY or p.confidence < 0.3 or (p.kind != Percept.Kind.AGENT and p.kind != Percept.Kind.EGG):
			continue
		if p.agent == null or not is_instance_valid(p.agent) or not (p.agent as CreatureAgent).is_alive():
			continue
		var s := _feasibility(p) * p.confidence
		if s > best_s:
			best_s = s
			best = p
	return best


func _feasibility(p: Percept) -> float:
	if not a.can_reach(p.pos):
		return 0.0
	var dist_k := 1.0 / (1.0 + p.dist / 45.0)
	if p.kind == Percept.Kind.EGG:
		return 1.0 * dist_k
	var pa := p.agent as CreatureAgent
	var my_v := a.burst_speed()
	var their_v := pa.mover.max_speed(pa.mover.medium, true) * clampf(1.0 - 0.5 * pa.individual.fatigue, 0.4, 1.0)
	var stamina := a.stamina()
	var edge := clampf(my_v * stamina / maxf(their_v, 0.1), 0.0, 1.6)
	# Ambush bonus: prey that has not noticed me.
	var unaware := 1.0 - pa.alert
	var f := clampf(0.25 + 0.55 * edge * (0.5 + 0.5 * unaware), 0.0, 1.0)
	# Pack hunters feel bolder.
	f *= 1.0 + 0.4 * a.personality.sociality * clampf(float(a.perception.neighbours), 0.0, 3.0) / 3.0
	return clampf(f, 0.0, 1.2) * dist_k


func score() -> float:
	if a.individual.is_egg() or not Relations.eats_meat(a.phys) or a.individual.stage == &"juvenile" and a.phenotype.physiology.diet != &"carnivore":
		return 0.0
	var drive := needs.hunger + 0.12 * a.personality.aggression * (1.0 if needs.hunger > 0.05 else 0.0)
	if drive < 0.15:
		return 0.0
	if a.stamina() < 0.3 and a.brain.current != self:
		return 0.0   # too tired to start a hunt
	var p := _pick()
	if p == null:
		return 0.0
	var s := drive * _feasibility(p) * (0.6 + 0.6 * a.personality.aggression) * 1.35
	s *= clampf(1.0 - 1.4 * needs.fear, 0.0, 1.0) * (0.4 + 0.6 * needs.awake)
	return s


func start() -> void:
	super.start()
	prey = _pick()
	phase = Phase.STALK
	chase_t = 0.0
	_lost = 0.0
	_flank = [-1.0, 1.0][a.rng.range_i(0, 1)] * a.rng.range_f(0.3, 0.9)


func activity() -> float:
	return 0.9 if phase != Phase.STALK else 0.45


func pose() -> StringName:
	match phase:
		Phase.STALK:
			return &"stalk"
		Phase.STRIKE:
			return &"attack"
	return &""


func update(dt: float) -> void:
	if prey == null or prey.agent == null or not is_instance_valid(prey.agent) or not (prey.agent as CreatureAgent).is_alive():
		var kill_pos := prey.pos if prey != null else a.mover.pos
		if prey != null:
			a.memory.note(CreatureMemory.SPOT_FOOD, kill_pos, 0.7, a.now)
		a.request_perception()
		finished = true
		return
	var tgt := prey.agent as CreatureAgent
	if a.stamina() < 0.12 and prey.kind != Percept.Kind.EGG:
		finished = true   # exhausted: break off, recover, try again later
		a.memory.note(CreatureMemory.SPOT_FOOD, prey.pos, 0.3, a.now)
		return
	if prey.confidence < 0.2 or prey.dist > a.perception.vision_now * 1.5 + 25.0:
		_lost += dt
		if _lost > 5.0:
			finished = true
			return
	else:
		_lost = 0.0
	var reach := a.body_length() * 0.55 + tgt.mover.radius + 0.35
	var d_now := a.mover.pos.distance_to(tgt.position)
	target_text = "добыча"
	if phase != Phase.CHASE:
		chase_t = 0.0
	# --- Egg: just walk up and eat it ------------------------------------------------------
	if prey.kind == Percept.Kind.EGG:
		if d_now <= reach + 0.4:
			a.stop_moving()
			var res := a.attack(tgt)
			if res.get("killed", false):
				finished = true
		else:
			a.go(tgt.position, a.cruise_speed(), reach * 0.5)
		return
	var aim := prey.predicted(a.now, 0.8)
	var aware := tgt.alert > 0.25 or (tgt.brain != null and tgt.brain.needs.fear > 0.3)
	var chase_range := clampf(a.burst_speed() * 12.0 * a.stamina(), 14.0, a.perception.vision_now * 1.3 + 10.0)
	match phase:
		Phase.STALK:
			var charge_d := clampf(a.burst_speed() * 1.7, 5.0, 16.0)
			if aware:
				# Spotted: stealth is pointless, run it down if within range.
				if d_now < chase_range:
					phase = Phase.CHASE
				else:
					a.go(aim, a.burst_speed() * 0.8, 0.5)
			else:
				a.go(_flank_point(aim, charge_d), a.cruise_speed() * 0.5, 0.5)
				a.intent.urgency = 0.3
				if d_now < charge_d:
					phase = Phase.CHASE
		Phase.CHASE:
			chase_t += dt
			a.go_node(tgt, a.burst_speed(), reach * 0.6)
			a.intent.sprint = true
			a.intent.urgency = 1.0
			if a.mover.lp.can_fly and a.mover.medium != &"water":
				a.intent.fly = tgt.mover.flying or d_now > 12.0
			if d_now <= reach + 0.2:
				phase = Phase.STRIKE
			elif a.stamina() < 0.2 or chase_t > 28.0:
				finished = true   # out of breath: let it go
				a.memory.note(CreatureMemory.SPOT_FOOD, aim, 0.3, a.now)
		Phase.STRIKE:
			a.go_node(tgt, a.burst_speed() * 0.6, reach * 0.4)
			a.intent.urgency = 1.0
			var res2 := a.attack(tgt)
			if res2.get("killed", false):
				a.request_perception()
				finished = true
			elif d_now > reach * 1.9:
				phase = Phase.CHASE


## Pack hunters approach from the side, lone hunters straight on.
func _flank_point(aim: Vector3, charge_d: float) -> Vector3:
	if a.personality.sociality < 0.5 or a.perception.neighbours < 1:
		return aim
	var to := aim - a.mover.pos
	to.y = 0.0
	if to.length() < charge_d * 1.2:
		return aim
	var side := Vector3(-to.z, 0.0, to.x).normalized() * _flank * to.length() * 0.35
	return aim + side
