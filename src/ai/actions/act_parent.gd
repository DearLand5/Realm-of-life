class_name ActParent
extends AiAction
## GuardEggs/Young: caring parents stay near their eggs and young and drive off
## predators that come close.

var threat_agent: CreatureAgent = null


func _init() -> void:
	id = &"guard"
	label = "Охраняет потомство"
	min_commit = 4.0


func score() -> float:
	if needs.parental < 0.2 or a.individual.is_egg():
		return 0.0
	var kids := a.dependants()
	if kids.is_empty():
		return 0.0
	var s := needs.parental * 0.62 * clampf(1.0 - 0.8 * maxf(needs.hunger, needs.thirst), 0.2, 1.0)
	if _find_threat(kids) != null:
		s += 0.35 * a.personality.aggression + 0.2
	return s * clampf(1.0 - 1.2 * needs.fear, 0.1, 1.0)


func _find_threat(kids: Array[CreatureAgent]) -> CreatureAgent:
	var centre := _centre(kids)
	for k in a.perception.memory.short:
		var p: Percept = a.perception.memory.short[k]
		if p.kind != Percept.Kind.AGENT or p.role == Percept.ROLE_CONSPECIFIC or p.confidence < 0.3:
			continue
		if p.role != Percept.ROLE_PREDATOR and p.role != Percept.ROLE_COMPETITOR:
			continue
		if p.pos.distance_to(centre) < 22.0 and p.agent is CreatureAgent:
			return p.agent as CreatureAgent
	return null


func _centre(kids: Array[CreatureAgent]) -> Vector3:
	var c := Vector3.ZERO
	for k in kids:
		c += k.position
	return c / float(maxi(kids.size(), 1))


func pose() -> StringName:
	return &"guard"


func activity() -> float:
	return 0.2


func update(_dt: float) -> void:
	var kids := a.dependants()
	if kids.is_empty():
		finished = true
		return
	var centre := _centre(kids)
	threat_agent = _find_threat(kids)
	target_text = "детёныши"
	if threat_agent != null and is_instance_valid(threat_agent) and a.personality.aggression + a.personality.parental_care > 0.7:
		a.go_node(threat_agent, a.burst_speed(), a.body_length() * 0.5)
		a.intent.sprint = true
		if a.mover.pos.distance_to(threat_agent.position) < a.body_length() * 0.7 + threat_agent.mover.radius + 0.3:
			a.attack(threat_agent, 0.8)
		target_text = "угроза детёнышам"
		return
	if a.mover.pos.distance_to(centre) > 7.0:
		a.go(centre, a.cruise_speed() * 0.8, 3.0)
	else:
		a.stop_moving()
		if threat_agent != null:
			a.face_toward(threat_agent.position)
