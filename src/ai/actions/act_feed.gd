class_name ActFeed
extends AiAction
## Graze/Browse (plants), Forage (detritus), FilterFeed (plankton), Scavenge
## (carcasses) — one state machine parametrised by Food kind:
## search (known patch, remembered food place or roaming) -> approach -> eat.

const REACH_PLANT := 2.4

var kind: int = Food.PLANT
var phase: StringName = &"search"
var goal := Vector3.INF
var carcass_id: int = -1
var _search_goal := Vector3.INF
var _empty: int = 0
var _arrived_check: float = 0.0


func _init(k: int = Food.PLANT) -> void:
	kind = k
	min_commit = 3.0
	match k:
		Food.PLANT:
			id = &"graze"
			label = "Пасётся"
		Food.DETRITUS:
			id = &"forage"
			label = "Собирает детрит"
		Food.PLANKTON:
			id = &"filter"
			label = "Фильтрует планктон"
		_:
			id = &"scavenge"
			label = "Питается падалью"


func score() -> float:
	var w := a.food_weights[kind] if kind < a.food_weights.size() else 0.0
	if w < 0.08 or needs.hunger < 0.1 or a.individual.is_egg():
		return 0.0
	if kind == Food.PLANKTON and a.mover.medium != &"water":
		return 0.0
	var per := a.perception
	var feas := 0.3
	if kind == Food.CARRION:
		var c := per.nearest(Percept.Kind.CARCASS, &"", 0.3)
		if c == null:
			return 0.0
		feas = 1.0 if c.confidence > 0.55 else 0.7
		if not a.can_reach(c.pos):
			return 0.0
	elif per.food_known(kind, a.now):
		feas = 1.0
	elif kind == Food.PLANT and a.memory.recall(CreatureMemory.SPOT_FOOD, a.mover.pos) != Vector3.INF:
		feas = 0.6
	var s := needs.hunger * feas * (0.55 + 0.45 * clampf(w, 0.0, 1.0)) * 1.1
	s *= clampf(1.0 - 1.6 * needs.fear, 0.0, 1.0) * (0.4 + 0.6 * needs.awake)
	return s


func start() -> void:
	super.start()
	phase = &"search"
	goal = Vector3.INF
	_search_goal = Vector3.INF
	carcass_id = -1
	_empty = 0


func activity() -> float:
	return 0.12 if phase == &"eat" else 0.3


func pose() -> StringName:
	return &"eat" if phase == &"eat" else &""


func update(dt: float) -> void:
	var per := a.perception
	match phase:
		&"search":
			_find_target()
			if goal != Vector3.INF:
				phase = &"approach"
			else:
				if _search_goal == Vector3.INF or Vector2(_search_goal.x - a.mover.pos.x, _search_goal.z - a.mover.pos.z).length() < 2.0:
					_search_goal = a.memory.recall(CreatureMemory.SPOT_FOOD, a.mover.pos) if kind == Food.PLANT else Vector3.INF
					if _search_goal != Vector3.INF and Vector2(_search_goal.x - a.mover.pos.x, _search_goal.z - a.mover.pos.z).length() < 6.0:
						a.memory.penalize(CreatureMemory.SPOT_FOOD, _search_goal, 0.5)
						_search_goal = Vector3.INF
					if _search_goal == Vector3.INF:
						_search_goal = a.pick_wander_goal(35.0)
				if _search_goal != Vector3.INF:
					a.go(_search_goal, a.cruise_speed() * 0.8, 1.5)
				else:
					a.stop_moving()
				target_text = "ищет пищу"
		&"approach":
			_find_target()
			if goal == Vector3.INF:
				phase = &"search"
				return
			var d := Vector2(goal.x - a.mover.pos.x, goal.z - a.mover.pos.z).length()
			var reach := _reach()
			if d <= reach:
				phase = &"eat"
				_empty = 0
				a.stop_moving()
			else:
				a.go(goal, a.cruise_speed() * (0.9 + 0.3 * needs.hunger), reach * 0.7)
				a.intent.group_pull = Flocking.pull(a) * 0.35
		&"eat":
			a.stop_moving()
			a.face_toward(goal)
			var kg := Feeding.eat(a, kind, dt, carcass_id)
			if kg <= 1e-6:
				_empty += 1
				if _empty >= 2:
					per.forget_food(kind)
					if kind == Food.PLANT:
						a.memory.penalize(CreatureMemory.SPOT_FOOD, a.mover.pos, 0.6)
					phase = &"search"
					goal = Vector3.INF
					if a.individual.stomach_fullness() > 0.9 or needs.hunger < 0.08:
						finished = true
			else:
				_empty = 0
				if kind == Food.PLANT:
					a.memory.note(CreatureMemory.SPOT_FOOD, a.mover.pos, 0.5, a.now)
			if a.individual.stomach_fullness() > 0.93 or a.individual.energy_fraction() > 0.97:
				finished = true


func _reach() -> float:
	if kind == Food.CARRION:
		return a.body_length() * 0.5 + 0.7
	if kind == Food.PLANT:
		return REACH_PLANT
	return 1.5


func _find_target() -> void:
	var per := a.perception
	if kind == Food.CARRION:
		var c := per.nearest(Percept.Kind.CARCASS, &"", 0.2)
		if c == null:
			goal = Vector3.INF
			carcass_id = -1
			return
		goal = c.pos
		carcass_id = c.id
		target_text = "падаль"
		return
	if per.food_known(kind, a.now):
		goal = per.food_pos[kind]
		target_text = "пища"
	else:
		goal = Vector3.INF
