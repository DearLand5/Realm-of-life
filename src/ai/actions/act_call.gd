class_name ActCall
extends AiAction
## Call: a lone social animal calls for its group (contact call); also what the
## player's Call button triggers. Alarm and mating calls are emitted by the
## flee/mate actions through CreatureAgent.emit_call.

const COOLDOWN := 12.0

var _last: float = -100.0


func _init() -> void:
	id = &"call"
	label = "Зовёт сородичей"
	min_commit = 1.0


func score() -> float:
	if a.individual.is_egg() or a.now - _last < COOLDOWN or a.personality.sociality < 0.45:
		return 0.0
	if needs.social < 0.6 or a.perception.neighbours > 0:
		return 0.0
	return 0.3 * needs.social * (1.0 - needs.fear)


func start() -> void:
	super.start()
	_last = a.now
	a.emit_call(&"sound", 1.3)
	a.call_time = 0.8


func activity() -> float:
	return 0.1


func pose() -> StringName:
	return &"call"


func update(_dt: float) -> void:
	a.stop_moving()
	if t_active > 0.9:
		finished = true
