class_name ActFlock
extends AiAction
## Flock / Herd / School: social animals that drifted away from the group head
## back to its centre (the last remembered one if it is out of sight).

var centre := Vector3.INF


func _init() -> void:
	id = &"flock"
	label = "Держится стада"
	min_commit = 3.0


func _group_centre() -> Vector3:
	var out: Array = [Vector3.INF]
	var cnt: Array = [0]
	Flocking.pull(a, out, cnt)
	return out[0]


func score() -> float:
	if needs.social < 0.25 or a.individual.is_egg():
		return 0.0
	var c := _group_centre()
	if c == Vector3.INF:
		return 0.0
	var d := a.mover.pos.distance_to(c)
	if d < 12.0:
		return 0.0
	return needs.social * clampf((d - 10.0) / 25.0, 0.0, 1.0) * 0.8 * clampf(1.0 - needs.fear, 0.0, 1.0)


func start() -> void:
	super.start()
	centre = _group_centre()


func activity() -> float:
	return 0.3


func update(_dt: float) -> void:
	centre = _group_centre()
	if centre == Vector3.INF or a.mover.pos.distance_to(centre) < 7.0:
		finished = true
		return
	target_text = "стадо"
	a.go(centre, a.cruise_speed() * 1.1, 4.0)
