class_name AgentManager
extends Node3D
## Bridges statistical populations (tiers C/D) and live creatures (tiers A/B):
##   * sectors near the focus are "active": their pools unfold into
##     CreatureAgent nodes (up to the quality budget);
##   * sectors leaving the active area fold their agents back into pools;
##   * agents wandering into inactive sectors are folded individually;
##   * births spawn new agents, deaths remove them and leave carcasses.
## CreatureAgent is loaded by path so the world still runs (pools only) if
## the creature runtime is missing.

signal agent_spawned(agent: Node)
signal agent_removed(agent: Node)

const AGENT_SCRIPT := "res://src/creature/creature_agent.gd"
const ACTIVATION_INTERVAL := 0.5
const STRAY_CHECK_INTERVAL := 1.0
const SECTOR_HYSTERESIS := 1.3

var state: SimState
var ctx: WorldContext
var perf: PerformanceManager
var biology: BiologySystem
var focus := Vector3.ZERO
var enabled := true
var agents: Array[Node] = []

var _agent_script: Script
var _active: Dictionary = {}       # sector index -> true
var _activation_timer := 0.0
var _stray_timer := 0.0


func setup(sim_state: SimState, world_ctx: WorldContext, performance: PerformanceManager) -> void:
	state = sim_state
	ctx = world_ctx
	perf = performance
	if ResourceLoader.exists(AGENT_SCRIPT):
		_agent_script = load(AGENT_SCRIPT)
	ctx.spawn_individual = _on_spawn_individual
	ctx.agent_died = _on_agent_died
	state.evo.live_provider = _live_individuals


func has_runtime() -> bool:
	return _agent_script != null


func live_count() -> int:
	return agents.size()


func _live_individuals(species_id: int) -> Array[Individual]:
	var out: Array[Individual] = []
	for a in agents:
		var ind: Individual = a.get("individual")
		if ind != null and ind.alive and ind.species_id == species_id:
			out.append(ind)
	return out


func all_individuals() -> Array:
	var out := []
	for a in agents:
		var ind: Individual = a.get("individual")
		if ind != null and ind.alive:
			out.append(ind)
	return out


# --- Per-frame -------------------------------------------------------------------

func sim_update(phys_dt: float, bio_dt: float, real_dt: float) -> void:
	ctx.phys_time += phys_dt
	if not enabled or not has_runtime():
		return
	_activation_timer -= real_dt
	if _activation_timer <= 0.0:
		_activation_timer = ACTIVATION_INTERVAL
		_update_sectors()
		if perf != null:
			perf.focus = focus
			perf.assign_tiers(agents)
	_stray_timer -= real_dt
	if _stray_timer <= 0.0:
		_stray_timer = STRAY_CHECK_INTERVAL
		_fold_strays()
		ctx.prune_stimuli(3.0)
	for i in range(agents.size() - 1, -1, -1):
		var a := agents[i]
		if is_instance_valid(a):
			a.sim_update(phys_dt, bio_dt)


func _radius() -> float:
	return perf.profile.f("active_radius") if perf != null else 110.0


func _update_sectors() -> void:
	var statistical := perf != null and perf.statistical_mode
	var r := _radius()
	var want := {}
	if not statistical:
		for i in state.pop.sectors.size():
			var c := state.pop.sector_center(i)
			var d := Vector2(c.x - focus.x, c.z - focus.z).length()
			if d <= r or (_active.has(i) and d <= r * SECTOR_HYSTERESIS):
				want[i] = true
	for i in _active:
		if not want.has(i):
			_fold_sector(int(i))
	var newly: Array[int] = []
	for i in want:
		if not _active.has(i):
			newly.append(int(i))
	_active = want
	if newly.is_empty():
		return
	# Unfold nearest sectors first; share the remaining agent budget.
	newly.sort_custom(func(a: int, b: int) -> bool:
		return state.pop.sector_center(a).distance_squared_to(focus) < state.pop.sector_center(b).distance_squared_to(focus))
	var budget := (perf.agent_budget() if perf != null else 120) - agents.size()
	for i in newly:
		if budget <= 0:
			break
		var per_sector := maxi(2, budget / maxi(1, newly.size()))
		var inds := state.pop.unfold(i, mini(per_sector, budget))
		for ind in inds:
			if spawn(ind) != null:
				budget -= 1


func is_active_sector(i: int) -> bool:
	return _active.has(i)


func _fold_sector(i: int) -> void:
	var list: Array[Individual] = []
	for a in agents.duplicate():
		var ind: Individual = a.get("individual")
		if ind != null and state.pop.sector_index(ind.position) == i:
			if a.has_method("is_possessed") and a.is_possessed():
				continue
			list.append(ind)
			_remove_agent(a)
	if not list.is_empty():
		state.pop.fold(list, i)


func _fold_strays() -> void:
	var groups := {}
	for a in agents.duplicate():
		var ind: Individual = a.get("individual")
		if ind == null:
			continue
		var s := state.pop.sector_index(ind.position)
		if _active.has(s) or (a.has_method("is_possessed") and a.is_possessed()):
			continue
		if not groups.has(s):
			groups[s] = []
		(groups[s] as Array).append(ind)
		_remove_agent(a)
	for s in groups:
		var list: Array[Individual] = []
		list.assign(groups[s])
		state.pop.fold(list, int(s))


## Folds every live agent (statistical mode, saving snapshots).
func fold_all() -> void:
	var groups := {}
	for a in agents.duplicate():
		var ind: Individual = a.get("individual")
		if ind != null and ind.alive:
			var s := state.pop.sector_index(ind.position)
			if not groups.has(s):
				groups[s] = []
			(groups[s] as Array).append(ind)
		_remove_agent(a)
	for s in groups:
		var list: Array[Individual] = []
		list.assign(groups[s])
		state.pop.fold(list, int(s))
	_active.clear()


func clear() -> void:
	for a in agents.duplicate():
		_remove_agent(a)
	_active.clear()


# --- Spawning ------------------------------------------------------------------------

func spawn(ind: Individual) -> Node:
	if _agent_script == null or ind == null or ind.genome == null:
		return null
	var a: Node3D = _agent_script.new()
	add_child(a)
	a.setup(ind, ctx)
	agents.append(a)
	agent_spawned.emit(a)
	Bus.emit(&"creature_spawned", [a])
	return a


func _remove_agent(a: Node) -> void:
	agents.erase(a)
	if is_instance_valid(a):
		if a.has_method("teardown"):
			a.teardown()
		agent_removed.emit(a)
		Bus.emit(&"creature_despawned", [a])
		a.queue_free()


func _on_spawn_individual(ind: Individual) -> Node:
	# Newborns in active sectors become agents; elsewhere they join the pool.
	var s := state.pop.sector_index(ind.position)
	Bus.emit(&"creature_born", [ind])
	if _active.has(s) and agents.size() < (perf.agent_budget() if perf != null else 150):
		return spawn(ind)
	var list: Array[Individual] = [ind]
	state.pop.fold(list, s)
	return null


func _on_agent_died(a: Node, cause: StringName) -> void:
	var ind: Individual = a.get("individual")
	if ind != null:
		var ph: Phenotype = ind.get_phenotype()
		var kg := ph.mass() * pow(ind.growth, 3.0) if ph != null else 1.0
		if state.eco != null and cause != &"eaten":
			state.eco.add_carcass(ind.position, kg, ind.species_id)
		Bus.emit(&"creature_died", [ind, cause])
	_remove_agent(a)


func agent_by_individual_id(id: int) -> Node:
	for a in agents:
		var ind: Individual = a.get("individual")
		if ind != null and ind.id == id:
			return a
	return null


## Nearest agent to a world point within radius (selection by tap).
func pick_near(p: Vector3, radius: float) -> Node:
	var best: Node = null
	var bd := radius * radius
	for a in agents:
		var q: Vector3 = (a as Node3D).global_position
		var d := Vector2(q.x - p.x, q.z - p.z).length_squared()
		if d < bd:
			bd = d
			best = a
	return best


## Agent closest to a screen point (projects positions; tolerant for fingers).
func pick_screen(cam: Camera3D, screen_pos: Vector2, max_px: float) -> Node:
	var best: Node = null
	var bd := max_px
	for a in agents:
		var n := a as Node3D
		var p := n.global_position + Vector3.UP * 0.3 * maxf(0.3, n.scale.y)
		if cam.is_position_behind(p):
			continue
		var d := cam.unproject_position(p).distance_to(screen_pos)
		if d < bd:
			bd = d
			best = a
	return best
