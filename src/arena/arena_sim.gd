class_name ArenaSim
extends Node3D
## Minimal simulated world around ArenaWorld: WorldContext, ClimateState, EcoGrid
## with a few plant species, agent spawning, death/carcass handling and a step()
## that drives every CreatureAgent. Used by the test arena scene and — headless,
## without any rendering — by the runtime tests. It doubles as the reference for
## wiring CreatureAgent into a full world.

var world: WorldData
var climate: ClimateState
var ctx: WorldContext
var eco: EcoGrid
var plants: Array[PlantSpecies] = []
var agent_list: Array[CreatureAgent] = []
var deaths: Array[Dictionary] = []     # {id, cause, species_id, pos}
var births: Array[Individual] = []
var headless := true
var time_scale: float = 1.0
var paused := false
var _rng: Rng
var _remove_queue: Array[CreatureAgent] = []
var _graveyard: Array[CreatureAgent] = []   # dead agents of a tree-less sim stay alive until the sim is freed


func _init(is_headless: bool = true, seed_value: int = 1) -> void:
	headless = is_headless
	_rng = Rng.new(seed_value)
	world = ArenaWorld.make()
	climate = ClimateState.new()
	climate.world = world
	climate.hour = 12.0
	climate.daylight = 1.0
	climate.year_phase = 0.15
	climate.wind = Vector2(1.6, 0.6)
	ctx = WorldContext.new()
	ctx.world = world
	ctx.climate = climate
	ctx.rng = Rng.new(seed_value + 1)
	ctx.set_meta(&"headless", headless)
	_fill_shore_data()
	plants = make_plants()
	eco = EcoGrid.new()
	eco.setup(world, plants, climate, 8.0)
	ctx.eco = eco
	ctx.spawn_individual = _on_spawn
	ctx.agent_died = _on_died


## ArenaWorld has no generator pass: derive distance-to-water for the renderers.
func _fill_shore_data() -> void:
	var c := ArenaWorld.POND_CENTER
	for iz in world.res:
		for ix in world.res:
			var i := iz * world.res + ix
			var p := world.grid_to_world(ix, iz)
			var d := maxf(0.0, Vector2(p.x, p.z).distance_to(c) - ArenaWorld.POND_RADIUS * 0.75)
			world.water_dist[i] = d if world.water[i] == WorldData.Water.LAND else 0.0
			world.shore_level[i] = -0.35


static func make_plants() -> Array[PlantSpecies]:
	var out: Array[PlantSpecies] = []
	var grass := PlantSpecies.new()
	grass.id = 0
	grass.name = "Луговая трава"
	grass.form = &"grass"
	grass.height = 0.35
	grass.capacity = 0.9
	grass.growth_rate = 0.35
	grass.temp_opt = 18.0
	grass.temp_tol = 14.0
	grass.moist_opt = 0.55
	grass.moist_tol = 0.5
	grass.toughness = 0.2
	grass.nutrition = 1.0
	grass.seasonal = 0.1
	out.append(grass)
	var bush := PlantSpecies.new()
	bush.id = 1
	bush.name = "Кустарник"
	bush.form = &"shrub"
	bush.height = 1.4
	bush.capacity = 0.6
	bush.growth_rate = 0.2
	bush.temp_opt = 18.0
	bush.temp_tol = 14.0
	bush.moist_opt = 0.55
	bush.moist_tol = 0.5
	bush.toughness = 0.4
	bush.seasonal = 0.1
	bush.color_leaf = Color(0.25, 0.5, 0.2)
	out.append(bush)
	return out


# --- Content ---------------------------------------------------------------------------------

## Founder individual of a preset at a position (y is snapped to the ground).
func make_individual(preset: StringName, at: Vector3, stage: StringName = &"adult", energy_frac: float = 0.8) -> Individual:
	var g := BodyPlanPresets.create(preset)
	var species := BodyPlanPresets.IDS.find(preset) + 1
	var ind := Individual.create(g, species, stage, _rng)
	ind.position = Vector3(at.x, world.height_at(at.x, at.z), at.z)
	ind.heading = _rng.range_f(-PI, PI)
	ind.energy = ind.max_energy() * energy_frac
	return ind


func spawn(ind: Individual) -> CreatureAgent:
	var agent := CreatureAgent.new()
	add_child(agent)
	agent.setup(ind, ctx)
	agent_list.append(agent)
	return agent


func spawn_preset(preset: StringName, at: Vector3, stage: StringName = &"adult", energy_frac: float = 0.8) -> CreatureAgent:
	return spawn(make_individual(preset, at, stage, energy_frac))


## Sets plant biomass (kg/m²) of every species in a disc; others stay as they are.
func plant_patch(centre: Vector3, radius: float, kg_m2: float, species: int = -1) -> void:
	var n := eco.dim * eco.dim
	for cz in eco.dim:
		for cx in eco.dim:
			var c := eco.cell_center(cx, cz)
			if Vector2(c.x - centre.x, c.z - centre.z).length() <= radius:
				for p in plants.size():
					if species < 0 or p == species:
						eco.plant_mass[p * n + cz * eco.dim + cx] = kg_m2 * (1.0 if p == 0 else 0.4)


func clear_plants() -> void:
	eco.plant_mass.fill(0.0)


# --- Simulation ----------------------------------------------------------------------------------

func step(phys_dt: float) -> void:
	var dt := phys_dt * time_scale
	step_dt(dt, dt * Units.BIO_TIME_RATIO, true)


## Steps with explicit deltas (from a TimeController). `advance_clock`: also advance climate.bio_time.
func step_dt(dt: float, bio_dt: float, advance_clock: bool = false) -> void:
	if paused or dt <= 0.0:
		return
	ctx.phys_time += dt
	if advance_clock:
		climate.bio_time += bio_dt
	eco.step(bio_dt)
	ctx.prune_stimuli(3.0)
	for a in agent_list.duplicate():
		if is_instance_valid(a):
			a.sim_update(dt, bio_dt)
	_flush_removals()


## Runs `seconds` of simulated physical time in `dt` frames.
func run(seconds: float, dt: float = 1.0 / 30.0) -> void:
	var t := 0.0
	while t < seconds:
		step(dt)
		t += dt


func _flush_removals() -> void:
	for a in _remove_queue:
		agent_list.erase(a)
		if is_instance_valid(a):
			a.teardown()
			if a.is_inside_tree():
				a.queue_free()
			else:
				remove_child(a)
				_graveyard.append(a)
	_remove_queue.clear()


func alive_count() -> int:
	var n := 0
	for a in agent_list:
		if is_instance_valid(a) and a.is_alive():
			n += 1
	return n


func agents_of(preset_species: int) -> Array[CreatureAgent]:
	var out: Array[CreatureAgent] = []
	for a in agent_list:
		if is_instance_valid(a) and a.individual.species_id == preset_species and a.is_alive():
			out.append(a)
	return out


func _on_spawn(ind: Individual) -> Node:
	births.append(ind)
	return spawn(ind)


func _on_died(agent: Node, cause: StringName) -> void:
	var a := agent as CreatureAgent
	if a == null:
		return
	deaths.append({"id": a.individual.id, "cause": cause, "species_id": a.individual.species_id, "pos": a.position})
	eco.add_carcass(a.position, a.individual.mass(), a.individual.species_id)
	_remove_queue.append(a)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for a in _graveyard:
			if is_instance_valid(a):
				a.free()
		_graveyard.clear()
