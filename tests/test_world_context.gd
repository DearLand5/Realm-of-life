extends TestCase
## ArenaWorld geometry and WorldContext environment sampling.


func _ctx() -> WorldContext:
	var c := WorldContext.new()
	c.world = ArenaWorld.make()
	c.climate = ClimateState.new()
	c.climate.world = c.world
	return c


func test_arena_has_pond_and_land() -> void:
	var c := _ctx()
	var pond := ArenaWorld.POND_CENTER
	check(c.world.water_depth_at(pond.x, pond.y) > 1.0, "pond is deep enough to swim (%.2f)" % c.world.water_depth_at(pond.x, pond.y))
	check(c.world.water_depth_at(-30.0, 30.0) <= 0.0, "meadow is dry")
	check(c.medium_at(Vector3(pond.x, c.world.water_surface_at(pond.x, pond.y) - 0.5, pond.y)) == &"water", "below surface is water")
	check(c.medium_at(Vector3(-30.0, 10.0, 30.0)) == &"air", "high above ground is air")
	var near := c.world.find_water_near(Vector3(0, 0, 0), 40.0)
	check(near != Vector3.INF, "fresh water findable from the centre")


func test_env_sample() -> void:
	var c := _ctx()
	c.climate.hour = 14.0
	c.climate.daylight = 1.0
	var land := c.env_at(Vector3(-30, c.ground_height(-30, 30), 30))
	check(not land["in_water"], "land sample not in water")
	check(float(land["temperature"]) > 5.0 and float(land["temperature"]) < 35.0, "sane temperature")
	var pond := ArenaWorld.POND_CENTER
	var water := c.env_at(Vector3(pond.x, c.world.water_surface_at(pond.x, pond.y) - 1.0, pond.y))
	check(water["in_water"], "pond sample in water")
	check(float(water["light"]) < float(land["light"]), "less light under water")


func test_stimuli_prune() -> void:
	var c := _ctx()
	c.emit_stimulus(Vector3.ZERO, &"sound", 1.0)
	c.phys_time = 10.0
	c.emit_stimulus(Vector3.ONE, &"alarm", 1.0)
	c.prune_stimuli(3.0)
	check(c.stimuli.size() == 1 and c.stimuli[0]["kind"] == &"alarm", "old stimuli dropped")
