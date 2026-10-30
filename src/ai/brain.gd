class_name Brain
extends RefCounted
## Utility AI: every AI tick it refreshes the Needs, scores all actions
## (need urgency x feasibility x personality) and runs the best one, with
## commitment/hysteresis so behaviour does not flicker. Emergency actions
## (flee) interrupt anything.

const SWITCH_MARGIN := 1.25      # a rival must beat the running action by this factor...
const SWITCH_ADD := 0.08         # ...plus this much after the commit time

var agent: CreatureAgent
var needs := Needs.new()
var actions: Array[AiAction] = []
var current: AiAction = null
var scores: Dictionary = {}      # id -> last score (debug / HUD)
var forced: AiAction = null      # set while the player triggers an action by hand


func setup(a: CreatureAgent) -> void:
	agent = a
	actions = [
		ActFlee.new(), ActRest.new(), ActDrink.new(), ActHunt.new(),
		ActFeed.new(Food.PLANT), ActFeed.new(Food.DETRITUS), ActFeed.new(Food.PLANKTON), ActFeed.new(Food.CARRION),
		ActThermo.new(), ActMate.new(), ActNest.new(), ActParent.new(), ActFollowParent.new(),
		ActTerritory.new(), ActFlock.new(), ActCall.new(), ActWander.new(),
	]
	for act in actions:
		act.attach(a, needs)


func find(action_id: StringName) -> AiAction:
	for act in actions:
		if act.id == action_id:
			return act
	return null


func think(dt: float) -> void:
	needs.update(agent, dt)
	var best: AiAction = null
	var best_s := 0.0
	var cur_s := 0.0
	for act in actions:
		var s := act.score()
		scores[act.id] = s
		if act == current:
			cur_s = s
		if s > best_s:
			best_s = s
			best = act
	if current != null and not current.finished:
		current.t_active += dt
	var switch := false
	if current == null or current.finished:
		switch = best != null
	elif best != current and best != null:
		if best.emergency and best_s > cur_s + 0.15:
			switch = true
		elif current.t_active >= current.min_commit and best_s > cur_s * SWITCH_MARGIN + SWITCH_ADD:
			switch = true
		elif cur_s <= 0.0 and best_s > 0.0:
			switch = true
	if switch:
		_switch_to(best)
	if current != null:
		current.update(dt)


func _switch_to(act: AiAction) -> void:
	if current != null:
		current.stop()
	current = act
	if current != null:
		current.start()


func stop_all() -> void:
	if current != null:
		current.stop()
	current = null


func activity_level() -> float:
	return current.activity() if current != null else 0.1


func action_label() -> String:
	return current.label if current != null else "Отдыхает"


func target_text() -> String:
	return current.target_text if current != null else ""
