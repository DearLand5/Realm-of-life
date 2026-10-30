class_name SimState
extends RefCounted
## The complete simulation model of one world (no nodes): geography, climate,
## ecosystem grid, population pools, species/evolution, journal. SimWorld owns
## one and builds renderers/agents around it. Serialisable for saves and for
## in-memory experiment snapshots.

const FORMAT := 1

var name: String = "Новый мир"
var config: Dictionary = {}
var seed_value: int = 1
var world: WorldData
var climate: ClimateState
var plants: Array[PlantSpecies] = []
var eco: EcoGrid
var pop: PopulationManager
var evo: EvolutionSystem
var event_log := EventLog.new()
var rng := Rng.new(1)
var created_at: String = ""
## Saved time/weather (applied by SimWorld to its TimeController/WeatherSystem).
var time_state: Dictionary = {}
var weather_state: Dictionary = {}
## Individuals that were live agents when saved (restored as agents on load).
var saved_agents: Array = []
var camera_state: Dictionary = {}


func registry() -> SpeciesRegistry:
	return evo.registry


func day() -> int:
	return climate.day if climate != null else 0


func total_population() -> float:
	var t := 0.0
	for d in evo.registry.alive():
		t += evo.registry.count(d.id)
	return t


func to_dict(agents: Array = []) -> Dictionary:
	var pd := []
	for p in plants:
		pd.append(p.to_dict())
	var ad := []
	for ind in agents:
		if ind is Individual and (ind as Individual).alive:
			ad.append((ind as Individual).to_dict())
	return {
		"format": FORMAT, "name": name, "config": config.duplicate(true), "seed": seed_value,
		"created_at": created_at, "plants": pd, "climate": climate.to_dict(), "time": time_state,
		"weather": weather_state, "eco": eco.to_dict(), "pop": pop.to_dict(), "evo": evo.to_dict(),
		"log": event_log.to_dict(), "rng": rng.get_state(), "agents": ad, "camera": camera_state,
		# Meta for the load list.
		"day": day(), "species_count": evo.registry.alive().size(), "population": int(total_population()),
	}
