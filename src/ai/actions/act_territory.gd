class_name ActTerritory
extends AiAction
## DefendTerritory + dominance: territorial adults chase conspecific intruders;
## aggressive rivals of the same sex compete when breeding. Rank = size x
## aggression x health. The weaker yields, the stronger chases; equals spar with
## reduced (ritual) damage until one is hurt.

const SPAR_SCALE := 0.35

var rival: CreatureAgent = null
var phase: StringName = &"approach"
var _t_display: float = 0.0
var _find_cache: CreatureAgent = null
var _find_t: float = -100.0


func _init() -> void:
	id = &"territory"
	label = "Защищает территорию"
	min_commit = 3.0


static func rank_of(c: CreatureAgent) -> float:
	return sqrt(maxf(c.individual.mass(), 0.01)) * (0.4 + c.personality.aggression) * clampf(c.individual.health, 0.1, 1.0)


func _find() -> CreatureAgent:
	if a.now - _find_t < 0.8 and (_find_cache == null or is_instance_valid(_find_cache)):
		return _find_cache
	_find_t = a.now
	_find_cache = _find_uncached()
	return _find_cache


func _find_uncached() -> CreatureAgent:
	var best: CreatureAgent = null
	var best_d := INF
	var home := a.memory.home
	var radius := 22.0 + 30.0 * a.personality.territoriality
	for k in a.perception.memory.short:
		var p: Percept = a.perception.memory.short[k]
		if p.kind != Percept.Kind.AGENT or p.role != Percept.ROLE_CONSPECIFIC or p.confidence < 0.4:
			continue
		var o := p.agent as CreatureAgent
		if o == null or not is_instance_valid(o) or not o.is_alive() or not o.individual.is_mature():
			continue
		var same_sex := o.individual.sex == a.individual.sex
		var territorial := a.personality.territoriality > 0.35 and (home == Vector3.INF or p.pos.distance_to(home) < radius)
		var rival_mate := needs.mate > 0.4 and same_sex and a.personality.aggression > 0.45 and p.dist < 14.0
		if not (territorial and same_sex) and not rival_mate:
			continue
		if p.dist < best_d:
			best_d = p.dist
			best = o
	return best


func score() -> float:
	if a.individual.is_egg() or not a.individual.is_mature() or a.personality.aggression < 0.2:
		return 0.0
	if needs.territory < 0.2 and needs.mate < 0.4:
		return 0.0
	var o := _find()
	if o == null:
		return 0.0
	# Do not pick fights I clearly cannot win.
	if rank_of(o) > rank_of(a) * 1.6:
		return 0.0
	var drive := maxf(needs.territory, 0.5 * needs.mate) * a.personality.aggression
	return drive * 1.1 * clampf(1.0 - 1.5 * needs.fear, 0.0, 1.0) * clampf(1.0 - needs.hunger * 0.7, 0.3, 1.0)


func start() -> void:
	super.start()
	rival = _find()
	phase = &"approach"
	_t_display = 0.0


func activity() -> float:
	return 0.7


func pose() -> StringName:
	return &"display" if phase == &"display" else (&"attack" if phase == &"spar" else &"")


func update(dt: float) -> void:
	if rival == null or not is_instance_valid(rival) or not rival.is_alive():
		finished = true
		return
	var d := a.mover.pos.distance_to(rival.position)
	target_text = "соперник"
	if a.individual.health < 0.65:
		finished = true
		return
	var display_d := a.body_length() * 3.0 + rival.body_length()
	match phase:
		&"approach":
			a.go_node(rival, a.cruise_speed() * 1.2, display_d * 0.8)
			if d < display_d:
				phase = &"display"
				_t_display = 0.0
		&"display":
			a.stop_moving()
			a.face_toward(rival.position)
			_t_display += dt
			if int(_t_display / 1.0) != int((_t_display - dt) / 1.0):
				a.emit_call(&"sound", 1.2)
			if _t_display > 1.5:
				var mine := rank_of(a)
				var theirs := rank_of(rival)
				if theirs > mine * 1.15:
					rival.on_dominated(a, false)
					a.memory.note(CreatureMemory.SPOT_DANGER, rival.position, 0.5, a.now)
					needs.fear = maxf(needs.fear, 0.5)   # yield: back off
					finished = true
				elif mine > theirs * 1.15:
					rival.on_dominated(a, true)
					phase = &"chase"
					_t_display = 0.0
				else:
					phase = &"spar"
		&"chase":
			_t_display += dt
			a.go_node(rival, a.burst_speed() * 0.8, 1.0)
			if _t_display > 4.0 or d > display_d * 4.0:
				finished = true
		&"spar":
			a.go_node(rival, a.cruise_speed(), a.body_length() * 0.4)
			if d < a.body_length() * 0.6 + rival.mover.radius + 0.5:
				a.attack(rival, SPAR_SCALE)
			_t_display += dt
			if _t_display > 14.0 or rival.individual.health < 0.65:
				finished = true
