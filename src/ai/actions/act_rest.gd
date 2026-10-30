class_name ActRest
extends AiAction
## Rest / sleep: fatigue and circadian rhythm (diurnal, crepuscular, nocturnal)
## drive it. The animal walks to a remembered shelter or home when close, then
## lies down; deep sleep lowers its vision (eyes closed) and wakes on threats.

var spot := Vector3.INF
var sleeping := false


func _init() -> void:
	id = &"rest"
	label = "Отдыхает"
	min_commit = 8.0


func score() -> float:
	if a.individual.is_egg():
		return 0.0
	var s := needs.sleep * 0.95 * clampf(1.0 - 1.5 * needs.fear, 0.0, 1.0)
	# Hunger and thirst keep an animal awake unless it is truly exhausted.
	s *= clampf(1.0 - 0.8 * maxf(needs.hunger, needs.thirst), 0.25, 1.0)
	# Cold-blooded animals stay still when the temperature does not allow activity.
	if a.individual.performance < 0.35:
		s = maxf(s, 0.5)
	return s


func start() -> void:
	super.start()
	sleeping = false
	spot = Vector3.INF
	var shelter := a.memory.recall(CreatureMemory.SPOT_SHELTER, a.mover.pos)
	if shelter == Vector3.INF:
		shelter = a.memory.home
	if shelter != Vector3.INF and shelter.distance_to(a.mover.pos) < 40.0 and a.can_reach(shelter):
		spot = shelter


func activity() -> float:
	return 0.0 if sleeping else 0.04


func pose() -> StringName:
	return &"sleep" if sleeping else &"rest"


func stop() -> void:
	a.sleeping = false
	sleeping = false


func update(_dt: float) -> void:
	if spot != Vector3.INF and Vector2(spot.x - a.mover.pos.x, spot.z - a.mover.pos.z).length() > 2.5 and a.mover.stuck < 2.0:
		a.go(spot, a.cruise_speed() * 0.6, 1.5)
		target_text = "укрытие"
		a.sleeping = false
		return
	a.stop_moving()
	if spot == Vector3.INF and a.individual.is_mature():
		a.memory.note(CreatureMemory.SPOT_HOME, a.mover.pos, 0.9, a.now)
	var deep := needs.awake < 0.4 or a.individual.fatigue > 0.5
	sleeping = deep
	a.sleeping = deep
	a.intent.urgency = 0.0
	# Done when rested and the rhythm allows activity.
	if needs.sleep < 0.12 and needs.awake > 0.45:
		finished = true
	if a.perception.threat_level > 0.2 and sleeping:
		finished = true
