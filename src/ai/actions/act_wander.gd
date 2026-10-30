class_name ActWander
extends AiAction
## Wander / explore: ambles between random goals chosen on terrain the body can
## use (water for fish, dry ground for walkers), biased toward home and away from
## remembered danger, with pauses; social animals drift with their group.

var goal := Vector3.INF
var pause: float = 0.0


func _init() -> void:
	id = &"wander"
	label = "Бродит"
	min_commit = 2.5


func score() -> float:
	var s := 0.16 + 0.12 * a.personality.curiosity
	return s * (0.5 + 0.5 * needs.awake) * (1.0 - needs.fear)


func start() -> void:
	super.start()
	goal = Vector3.INF
	pause = a.rng.range_f(0.0, 1.5)


func activity() -> float:
	return 0.25 if pause <= 0.0 else 0.08


func update(dt: float) -> void:
	if pause > 0.0:
		pause -= dt
		a.stop_moving()
		a.intent.group_pull = Vector3.ZERO
		if pause <= 0.0:
			goal = Vector3.INF
		return
	if goal == Vector3.INF:
		goal = a.pick_wander_goal(18.0 + 40.0 * a.personality.curiosity)
		if goal == Vector3.INF:
			pause = 2.0
			return
	var d := Vector2(goal.x - a.mover.pos.x, goal.z - a.mover.pos.z).length()
	if d < 1.5 or a.mover.stuck > 1.0 or t_active > 40.0:
		pause = a.rng.range_f(1.0, 6.0) * (1.4 - a.personality.curiosity)
		goal = Vector3.INF
		a.mover.stuck = 0.0
		t_active = 0.0
		return
	a.go(goal, a.cruise_speed() * 0.6, 1.0)
	a.intent.group_pull = Flocking.pull(a) * 0.6
	target_text = ""
