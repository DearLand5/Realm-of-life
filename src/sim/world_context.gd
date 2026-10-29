class_name WorldContext
extends RefCounted
## Everything a live creature (CreatureAgent and its AI/physics/biology parts)
## may read or call while simulating. Built by SimWorld; also by test arenas
## and the editor's test polygon with a subset of systems.
##
## Systems that may be absent in a minimal context (arena) are null-checked by
## callers: eco, populations, registry, evolution, event_log.

var world: WorldData
var climate: ClimateState
var eco: Object = null            # EcoGrid
var populations: Object = null    # PopulationManager
var registry: Object = null       # SpeciesRegistry
var evolution: Object = null      # EvolutionSystem
var event_log: EventLog = null
var agents := SpatialHash.new(8.0)   # CreatureAgent nodes by position
var rng := Rng.new(1)
var mutation_settings: Dictionary = Genetics.settings_with_defaults()
var gravity: float = Units.GRAVITY

## Callbacks provided by the owner (SimWorld / arena):
##   spawn_individual.call(ind: Individual) -> Node        create an agent for a newborn/egg
##   agent_died.call(agent: Node, cause: StringName)       remove + carcass + stats
##   stimulus.call(pos: Vector3, kind: StringName, strength: float, source: Node)
##      kinds: &"sound", &"vibration", &"alarm", &"mating_call", &"scent"
var spawn_individual: Callable
var agent_died: Callable
var stimulus: Callable

## Recent stimuli for perception: [{pos, kind, strength, source, t}], pruned by owner.
var stimuli: Array = []
var phys_time: float = 0.0


func ground_height(x: float, z: float) -> float:
	return world.height_at(x, z) if world != null else 0.0


func water_depth(x: float, z: float) -> float:
	return world.water_depth_at(x, z) if world != null else 0.0


func water_surface(x: float, z: float) -> float:
	return world.water_surface_at(x, z) if world != null else 0.0


## &"water" if p is below a water surface, &"air" if well above ground, else &"land".
func medium_at(p: Vector3, air_threshold: float = 0.5) -> StringName:
	if world == null:
		return &"land"
	if world.water_depth_at(p.x, p.z) > 0.05 and p.y < world.water_surface_at(p.x, p.z) - 0.02:
		return &"water"
	if p.y > world.height_at(p.x, p.z) + air_threshold:
		return &"air"
	return &"land"


## Environment sample for BiologySystem.tick (contract with BiologySystem).
func env_at(p: Vector3) -> Dictionary:
	var in_water := medium_at(p) == &"water"
	var water_near := in_water
	if world != null and not in_water:
		water_near = world.water_depth_at(p.x, p.z) > -0.3 and world.water_type_at(p.x, p.z) != WorldData.Water.LAND
	return {
		"temperature": climate.temperature_at(p) if climate != null else 18.0,
		"humidity": climate.humidity_at(p) if climate != null else 0.5,
		"oxygen": climate.oxygen_at(p, in_water) if climate != null else 1.0,
		"in_water": in_water,
		"light": climate.light_at(p) if climate != null else 1.0,
		"water_nearby": water_near,
		"precipitation": climate.precipitation if climate != null else 0.0,
	}


func emit_stimulus(pos: Vector3, kind: StringName, strength: float, source: Node = null) -> void:
	stimuli.append({"pos": pos, "kind": kind, "strength": strength, "source": source, "t": phys_time})
	if stimulus.is_valid():
		stimulus.call(pos, kind, strength, source)


## Drops stimuli older than `max_age` physical seconds.
func prune_stimuli(max_age: float = 3.0) -> void:
	var keep := []
	for s in stimuli:
		if phys_time - float(s["t"]) <= max_age:
			keep.append(s)
	stimuli = keep


func log_event(category: StringName, text: String, data: Dictionary = {}) -> void:
	if event_log != null:
		event_log.add(category, text, data)
