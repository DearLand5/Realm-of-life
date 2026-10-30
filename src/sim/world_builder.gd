class_name WorldBuilder
extends RefCounted
## Builds a SimState: a brand-new world from a menu config, or a saved world.
## Pure model construction (no nodes) so tests and experiments can use it.

## Founding densities (individuals per hectare of suitable world) by niche.
const NICHE_DENSITY := {
	&"grazer": 1.6, &"browser": 1.0, &"small_herbivore": 6.0, &"detritivore": 10.0,
	&"predator": 0.35, &"scavenger": 0.5, &"flyer": 2.5, &"fish": 4.0, &"filter": 6.0,
	&"amphibian": 3.0,
}
const PLAYER_DENSITY := 2.0
const SPECIES_COLORS := [
	Color(0.95, 0.72, 0.3), Color(0.45, 0.8, 0.45), Color(0.4, 0.7, 0.95), Color(0.9, 0.45, 0.4),
	Color(0.75, 0.55, 0.9), Color(0.35, 0.85, 0.8), Color(0.95, 0.85, 0.45), Color(0.85, 0.6, 0.75),
	Color(0.6, 0.75, 0.35), Color(0.95, 0.55, 0.25), Color(0.55, 0.6, 0.95), Color(0.8, 0.8, 0.8),
]


## Converts the main-menu "new world" dictionary into a generator config.
static func config_from_menu(menu: Dictionary) -> Dictionary:
	var cfg := {}
	for k in ["seed", "relief", "vegetation", "biome_diversity", "temperature_offset", "moisture_offset", "rivers", "mountains", "water_fraction"]:
		if menu.has(k):
			cfg[k] = menu[k]
	if menu.has("size"):
		cfg["size"] = menu["size"]
	elif menu.has("size_preset"):
		cfg["size"] = menu["size_preset"]
	var size := float(WorldConfig.sanitize(cfg)["size"])
	cfg["resolution"] = 129 if size <= 256.0 else (257 if size <= 512.0 else 385)
	return WorldConfig.sanitize(cfg)


## New world. `player_species`: Array of {genome: Genome, name: String, uid: String}.
static func create(menu: Dictionary, player_species: Array = []) -> SimState:
	var st := SimState.new()
	st.config = config_from_menu(menu)
	st.seed_value = int(st.config["seed"])
	st.name = str(menu.get("name", "Мир %d" % (st.seed_value % 10000)))
	st.created_at = Time.get_datetime_string_from_system(true)
	st.rng = Rng.new(st.seed_value * 7 + 3)
	st.world = WorldGenerator.generate(st.config)
	st.climate = ClimateState.new()
	st.climate.world = st.world
	st.plants = FloraSystem.generate_species(st.world, Rng.new(st.seed_value * 31 + 7))
	st.eco = EcoGrid.new()
	st.eco.setup(st.world, st.plants, st.climate)
	st.eco.initialize(0.6 * clampf(float(st.config.get("vegetation", 1.0)), 0.2, 2.0))
	_build_population(st)
	st.event_log.setup(func() -> Vector2: return Vector2(st.climate.bio_time, st.climate.day))
	var n_fauna := int(menu.get("procedural_species", 6))
	var defs: Array[SpeciesDef] = []
	if n_fauna > 0:
		defs = FaunaGenerator.generate(st.world, st.plants, Rng.new(st.seed_value * 13 + 5), n_fauna)
	for d in defs:
		_register_and_seed(st, d, _density_for(d))
	for entry in player_species:
		var g: Genome = entry.get("genome")
		if g == null:
			continue
		var d := SpeciesDef.new()
		d.name = str(entry.get("name", g.body_plan.name))
		d.template = g
		d.origin = &"player"
		d.library_uid = str(entry.get("uid", ""))
		d.niche = &"player"
		d.description = "Вид, созданный игроком"
		_register_and_seed(st, d, PLAYER_DENSITY)
	st.event_log.add(&"system", "Мир «%s» создан: %d видов растений, %d видов животных." % [st.name, st.plants.size(), st.evo.registry.alive().size()])
	return st


static func _build_population(st: SimState) -> void:
	st.evo = EvolutionSystem.new()
	st.pop = PopulationManager.new()
	st.pop.setup(st.world, st.eco, st.climate, st.seed_value, st.evo.settings)
	st.pop.sector_budget = 6
	st.evo.attach_population(st.pop)


static func _density_for(d: SpeciesDef) -> float:
	return float(NICHE_DENSITY.get(d.niche, 2.0))


## Registers a species and seeds founders where its habitat fits.
static func _register_and_seed(st: SimState, d: SpeciesDef, density_per_ha: float) -> void:
	var n := st.evo.registry.species.size()
	d.ui_color = SPECIES_COLORS[n % SPECIES_COLORS.size()]
	d.created_day = float(st.day())
	st.evo.registry.register(d, float(st.day()))
	var hectares := st.world.size * st.world.size / 10000.0
	# Water species live in a fraction of the map; land species in the rest.
	var total := clampf(density_per_ha * hectares * 0.35, 8.0, 900.0)
	st.pop.seed_species(d.id, d.template, total)


## Places extra founders of a species around a position (sandbox "release").
static func release(st: SimState, species_id: int, at: Vector3, count: int, radius: float = 24.0) -> void:
	var d := st.evo.registry.get_species(species_id)
	if d == null:
		return
	var sectors := PackedInt32Array()
	var c := st.pop.sector_index(at)
	sectors.append(c)
	for off in [Vector3(radius, 0, 0), Vector3(-radius, 0, 0), Vector3(0, 0, radius), Vector3(0, 0, -radius)]:
		var s := st.pop.sector_index(st.world.clamp_xz(at + off))
		if not sectors.has(s):
			sectors.append(s)
	st.pop.seed_species(species_id, d.template, float(count), sectors)


## Restores a saved world (geometry regenerated deterministically from config).
static func restore(d: Dictionary) -> SimState:
	var st := SimState.new()
	st.config = WorldConfig.sanitize(Serial.dict(d, "config"))
	st.seed_value = Serial.i(d, "seed", int(st.config["seed"]))
	st.name = Serial.s(d, "name", "Мир")
	st.created_at = Serial.s(d, "created_at", "")
	st.world = WorldGenerator.generate(st.config)
	st.climate = ClimateState.new()
	st.climate.world = st.world
	st.climate.from_dict(Serial.dict(d, "climate"))
	st.plants.clear()
	for pd in Serial.arr(d, "plants"):
		if pd is Dictionary:
			st.plants.append(PlantSpecies.from_dict(pd))
	if st.plants.is_empty():
		st.plants = FloraSystem.generate_species(st.world, Rng.new(st.seed_value * 31 + 7))
	st.eco = EcoGrid.restore(st.world, st.plants, st.climate, Serial.dict(d, "eco"))
	_build_population(st)
	st.pop.from_dict(Serial.dict(d, "pop"))
	st.evo.from_dict(Serial.dict(d, "evo"))
	st.event_log.setup(func() -> Vector2: return Vector2(st.climate.bio_time, st.climate.day))
	st.event_log.from_dict(Serial.dict(d, "log"))
	st.rng = Rng.new(st.seed_value)
	if d.has("rng"):
		st.rng.set_state(int(d["rng"]))
	st.time_state = Serial.dict(d, "time")
	st.weather_state = Serial.dict(d, "weather")
	st.camera_state = Serial.dict(d, "camera")
	st.saved_agents.clear()
	var max_id := 0
	for ad in Serial.arr(d, "agents"):
		if ad is Dictionary:
			var ind := Individual.from_dict(ad)
			if ind != null and ind.genome != null:
				st.saved_agents.append(ind)
				max_id = maxi(max_id, ind.id)
	Individual.ensure_id_counter(max_id + 1)
	return st
