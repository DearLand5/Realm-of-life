class_name ActDrink
extends AiAction
## Drink: find water (seen, smelled, or remembered), go to the bank, drink until
## hydration is restored. Unreachable water is forgotten after a while.

var phase: StringName = &"search"
var goal := Vector3.INF
var _search_goal := Vector3.INF
var _giveup: float = 0.0


func _init() -> void:
	id = &"drink"
	label = "Пьёт"
	min_commit = 3.0


func score() -> float:
	if needs.thirst < 0.12 or a.individual.is_egg():
		return 0.0
	var per := a.perception
	var feas := 0.3
	if a.mover.water_depth > 0.05 or a.water_in_reach():
		feas = 1.2
	elif per.water_pos != Vector3.INF and a.now - per.water_t < 40.0:
		feas = 1.0
	elif a.memory.recall(CreatureMemory.SPOT_WATER, a.mover.pos) != Vector3.INF:
		feas = 0.75
	return needs.thirst * feas * 1.15 * clampf(1.0 - 1.4 * needs.fear, 0.0, 1.0)


func start() -> void:
	super.start()
	phase = &"search"
	goal = Vector3.INF
	_search_goal = Vector3.INF
	_giveup = 0.0


func activity() -> float:
	return 0.1 if phase == &"drink" else 0.3


func pose() -> StringName:
	return &"drink" if phase == &"drink" else &""


func update(dt: float) -> void:
	var per := a.perception
	if a.water_in_reach() and (a.mover.speed < 1.5 or phase == &"drink"):
		phase = &"drink"
	if phase == &"drink":
		a.stop_moving()
		if per.water_pos != Vector3.INF:
			a.face_toward(per.water_pos)
		var kg := Feeding.drink(a, dt)
		a.memory.note(CreatureMemory.SPOT_WATER, a.mover.pos, 0.8, a.now)
		if a.individual.hydration >= 0.985 or (kg <= 0.0 and a.individual.hydration > 0.9):
			finished = true
		return
	goal = Vector3.INF
	if per.water_pos != Vector3.INF and a.now - per.water_t < 40.0:
		goal = per.water_pos
	else:
		goal = a.memory.recall(CreatureMemory.SPOT_WATER, a.mover.pos)
	if goal != Vector3.INF:
		phase = &"approach"
		target_text = "водоём"
		_giveup += dt
		if _giveup > 45.0 or a.mover.stuck > 2.5:
			# Standing at the closest point we can reach: drink if the bank is near, else forget.
			if a.distance_to_water() < a.body_length() + 2.5:
				phase = &"drink"
			else:
				a.memory.penalize(CreatureMemory.SPOT_WATER, goal, 0.6)
				per.water_pos = Vector3.INF
				_giveup = 0.0
				a.mover.stuck = 0.0
		else:
			a.go(goal, a.cruise_speed() * (0.8 + 0.4 * needs.thirst), 0.8)
	else:
		phase = &"search"
		if _search_goal == Vector3.INF or Vector2(_search_goal.x - a.mover.pos.x, _search_goal.z - a.mover.pos.z).length() < 2.0:
			_search_goal = a.pick_wander_goal(45.0)
		if _search_goal != Vector3.INF:
			a.go(_search_goal, a.cruise_speed() * 0.8, 1.5)
		target_text = "ищет воду"
