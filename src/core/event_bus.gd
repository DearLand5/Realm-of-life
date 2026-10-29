extends Node
## Global signal hub (autoload "EventBus").
##
## Systems never call each other's internals for notifications; they emit and
## listen here. Payload objects are RefCounted data (Individual, SpeciesDef...)
## or Nodes (CreatureAgent) as documented per signal.

# --- Selection / control -----------------------------------------------------
## Emitted when the player selects a creature (agent: Node3D CreatureAgent or null).
signal creature_selected(agent: Node)
## Emitted when the player selects a species in UI (species_id or -1).
signal species_selected(species_id: int)
## Emitted when control mode changes: &"observer", &"first_person", &"third_person".
signal control_mode_changed(mode: StringName, agent: Node)

# --- Life events (individual: Individual) ------------------------------------
signal creature_born(individual: RefCounted)
signal creature_died(individual: RefCounted, cause: StringName)
signal creature_spawned(agent: Node)
signal creature_despawned(agent: Node)

# --- Species / evolution (species: SpeciesDef) -------------------------------
signal species_registered(species: RefCounted)
signal species_extinct(species: RefCounted)
signal speciation(parent_species: RefCounted, new_species: RefCounted)

# --- Environment ---------------------------------------------------------------
signal time_scale_changed(scale: float)
signal hour_changed(hour: int)
signal day_changed(day: int)
signal season_changed(season: int)
signal weather_changed(weather: StringName)

# --- Logging / UI ------------------------------------------------------------
## entry: Dictionary {time: float, day: int, category: StringName, text: String, data: Dictionary}
signal sim_event_logged(entry: Dictionary)
## level: &"info", &"warning", &"error"
signal notify(text: String, level: StringName)

# --- Sandbox / experiments -----------------------------------------------------
signal intervention_applied(description: String, data: Dictionary)
signal world_loaded(world: Node)
signal world_unloading(world: Node)
