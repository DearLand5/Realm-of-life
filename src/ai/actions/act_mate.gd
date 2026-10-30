class_name ActMate
extends AiAction
## SeekMate -> Court -> Mate. Males (or any hermaphrodite) look for ready,
## compatible conspecifics (Reproduction.mate_check, mate selectivity included),
## approach, display and call; females wait for a courting male. Conception goes
## through Reproduction.conceive; offspring appear at birth/egg-laying events.

const COURT_DISTANCE := 3.5       # in body lengths
const PAIR_TTL := 25.0

var partner: Percept = null
var phase: StringName = &"seek"
var court_t: float = 0.0
var _pair_cache: Dictionary = {}   # individual id -> [time, ok]
var _search_goal := Vector3.INF
var _find_cache: Percept = null
var _find_t: float = -100.0


func _init() -> void:
	id = &"mate"
	label = "Ищет пару"
	min_commit = 4.0


func _is_chaser() -> bool:
	var ind := a.individual
	return ind.sex != Individual.Sex.FEMALE or a.phys.repro_mode == &"hermaphrodite"


func _compatible(p: Percept) -> bool:
	var o := p.agent as CreatureAgent
	if o == null or not is_instance_valid(o) or not o.is_alive() or o.individual.is_egg():
		return false
	var c: Array = _pair_cache.get(o.individual.id, [-100.0, false])
	if a.now - float(c[0]) < PAIR_TTL:
		return bool(c[1])
	var ok := Reproduction.can_mate(a.individual, o.individual, a.ctx.climate)
	_pair_cache[o.individual.id] = [a.now, ok]
	return ok


func _find() -> Percept:
	if a.now - _find_t < 1.0 and (_find_cache == null or is_instance_valid(_find_cache.agent)):
		return _find_cache
	_find_t = a.now
	_find_cache = _find_uncached()
	return _find_cache


func _find_uncached() -> Percept:
	var best: Percept = null
	var best_s := 0.0
	for k in a.perception.memory.short:
		var p: Percept = a.perception.memory.short[k]
		if p.kind != Percept.Kind.AGENT or p.role != Percept.ROLE_CONSPECIFIC or p.confidence < 0.25:
			continue
		if not _compatible(p):
			continue
		var s := p.confidence / (1.0 + p.dist / 30.0)
		if s > best_s:
			best_s = s
			best = p
	return best


func score() -> float:
	if needs.mate < 0.15 or a.individual.is_egg() or a.individual.pregnant:
		return 0.0
	var p := _find()
	var feas := 0.0
	if p != null:
		feas = 1.0
	elif _is_chaser():
		var call_p := _heard_call()
		feas = 0.55 if call_p != null else 0.22
	else:
		return 0.0   # females wait unless a courting male is around
	if p == null and not _is_chaser():
		return 0.0
	return needs.mate * feas * 0.95 * clampf(1.0 - 1.5 * needs.fear, 0.0, 1.0)


func _heard_call() -> Percept:
	for k in a.perception.memory.short:
		var p: Percept = a.perception.memory.short[k]
		if p.kind == Percept.Kind.SOUND and p.sound_kind == &"mating_call" and p.confidence > 0.3:
			return p
	return null


func start() -> void:
	super.start()
	partner = _find()
	phase = &"seek"
	court_t = 0.0
	_search_goal = Vector3.INF


func activity() -> float:
	return 0.35


func pose() -> StringName:
	return &"court" if phase == &"court" else &""


func update(dt: float) -> void:
	partner = _find() if partner == null or partner.agent == null or not is_instance_valid(partner.agent) or not _compatible(partner) else partner
	if partner == null:
		_seek_without_target()
		return
	var o := partner.agent as CreatureAgent
	var d := a.mover.pos.distance_to(o.position)
	var close := a.body_length() * COURT_DISTANCE + o.body_length() * 0.5
	target_text = "партнёр"
	label = "Ухаживает" if phase != &"seek" else "Ищет пару"
	if not _is_chaser() and d > close * 2.0:
		# Females stay put but turn toward the male and answer.
		a.stop_moving()
		a.face_toward(o.position)
		return
	if d > close:
		phase = &"seek"
		a.go_node(o, a.cruise_speed(), close * 0.6)
		a.intent.group_pull = Vector3.ZERO
		return
	phase = &"court"
	court_t += dt
	a.stop_moving()
	a.face_toward(o.position)
	if int(court_t / 1.2) != int((court_t - dt) / 1.2):
		a.emit_call(&"mating_call", 1.0)
	o.on_courted(a)
	var need_t := lerpf(1.2, 4.5, a.personality.mate_selectivity)
	if court_t >= need_t and d <= a.body_length() * 2.0 + o.body_length():
		_try_mating(o)
	elif court_t > 12.0:
		finished = true
		a.individual.repro_cooldown = maxf(a.individual.repro_cooldown, 120.0)


func _try_mating(o: CreatureAgent) -> void:
	var initiator := a.individual.sex == Individual.Sex.MALE or (a.individual.sex != Individual.Sex.FEMALE and a.individual.id < o.individual.id)
	if not initiator:
		# The female waits for the male to complete the act.
		if court_t > 8.0:
			finished = true
		return
	var mother := o.individual if a.individual.sex == Individual.Sex.MALE else a.individual
	var father := a.individual if a.individual.sex == Individual.Sex.MALE else o.individual
	if a.individual.sex == Individual.Sex.HERMAPHRODITE:
		mother = a.individual
		father = o.individual
	var ok := Reproduction.conceive(mother, father, a.bio.rng, a.ctx.mutation_settings, a.ctx.climate)
	a.ctx.log_event(&"mating", "Спаривание: %s" % [a.species_name()], {"mother": mother.id, "father": father.id, "ok": ok})
	a.mating_done = true
	a.individual.repro_cooldown = maxf(a.individual.repro_cooldown, 60.0)
	o.individual.repro_cooldown = maxf(o.individual.repro_cooldown, 60.0)
	finished = true


func _seek_without_target() -> void:
	var cp := _heard_call()
	if cp != null:
		a.go(cp.pos, a.cruise_speed() * 0.8, 3.0)
		target_text = "зов"
		return
	if not _is_chaser():
		a.stop_moving()
		return
	if _search_goal == Vector3.INF or Vector2(_search_goal.x - a.mover.pos.x, _search_goal.z - a.mover.pos.z).length() < 2.0:
		_search_goal = a.pick_wander_goal(45.0)
		a.emit_call(&"mating_call", 0.8)
	if _search_goal != Vector3.INF:
		a.go(_search_goal, a.cruise_speed() * 0.8, 1.5)
	target_text = "ищет"
