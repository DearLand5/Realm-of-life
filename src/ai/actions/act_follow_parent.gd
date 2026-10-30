class_name ActFollowParent
extends AiAction
## FollowParent: juveniles stay close to their mother (or any adult of their
## species) instead of roaming alone.

var guide: CreatureAgent = null


func _init() -> void:
	id = &"follow"
	label = "Следует за родителем"
	min_commit = 3.0


func _find() -> CreatureAgent:
	var ind := a.individual
	var best: CreatureAgent = null
	var best_d := INF
	for k in a.perception.memory.short:
		var p: Percept = a.perception.memory.short[k]
		if p.kind != Percept.Kind.AGENT or p.role != Percept.ROLE_CONSPECIFIC or p.confidence < 0.3:
			continue
		var o := p.agent as CreatureAgent
		if o == null or not is_instance_valid(o) or not o.individual.is_mature():
			continue
		var d := p.dist - (40.0 if o.individual.id == ind.mother_id else 0.0)
		if d < best_d:
			best_d = d
			best = o
	return best


func score() -> float:
	var ind := a.individual
	if ind.is_egg() or ind.is_mature() or ind.growth > 0.8:
		return 0.0
	guide = _find()
	if guide == null:
		return 0.0
	var d := a.mover.pos.distance_to(guide.position)
	if d < 6.0:
		return 0.0
	return clampf((d - 5.0) / 14.0, 0.0, 1.0) * 0.55 + 0.1


func start() -> void:
	super.start()
	guide = _find()


func update(_dt: float) -> void:
	if guide == null or not is_instance_valid(guide):
		finished = true
		return
	var d := a.mover.pos.distance_to(guide.position)
	target_text = "родитель"
	if d < 4.0:
		finished = true
		return
	a.go_node(guide, a.cruise_speed() * clampf(0.6 + d / 20.0, 0.6, 1.4), 3.0)
