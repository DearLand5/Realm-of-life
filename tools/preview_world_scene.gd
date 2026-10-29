extends Node
## World preview scene driven by tools/preview_world.gd (see usage there).

var world: WorldData
var climate: ClimateState
var time: TimeController
var day_night: DayNightCycle
var terrain: TerrainRenderer
var cam: Camera3D
var spots: Dictionary = {}


func run(args: PackedStringArray) -> void:
	var set_name := args[0] if args.size() > 0 else "overview"
	var cfg := WorldConfig.defaults()
	if args.size() > 1 and args[1] != "-":
		cfg["seed"] = args[1]
	var out_dir := args[2] if args.size() > 2 else "res://screenshots/tmp"
	var t0 := Time.get_ticks_msec()
	world = WorldGenerator.generate(cfg)
	print("generate: %d ms %s" % [Time.get_ticks_msec() - t0, str(WorldGenerator.last_timings)])
	_build_scene()
	_find_spots()
	await get_tree().process_frame
	for shot in _shots(set_name):
		await _render(shot, out_dir)


func _build_scene() -> void:
	var root := Node3D.new()
	root.name = "PreviewWorld"
	add_child(root)
	climate = ClimateState.new()
	climate.world = world
	time = TimeController.new()
	root.add_child(time)
	time.setup(climate, 12.0)
	time.paused = true
	day_night = DayNightCycle.new()
	root.add_child(day_night)
	day_night.setup(climate, null, time)
	var t0 := Time.get_ticks_msec()
	terrain = TerrainRenderer.new()
	root.add_child(terrain)
	terrain.setup(world, climate)
	print("terrain setup: %d ms, %d tris" % [Time.get_ticks_msec() - t0, terrain.triangle_count()])
	cam = Camera3D.new()
	cam.far = 3000.0
	cam.fov = 60.0
	root.add_child(cam)


## Picks interesting viewpoints from the generated world.
func _find_spots() -> void:
	var best := {}
	var step := 3
	for iz in range(20, world.res - 20, step):
		for ix in range(20, world.res - 20, step):
			var i := iz * world.res + ix
			if world.water[i] != WorldData.Water.LAND:
				continue
			var b := world.biome[i]
			var p := world.grid_to_world(ix, iz)
			var near_water := world.water_dist[i]
			var score := 0.0
			match b:
				Biomes.TEMPERATE_FOREST, Biomes.GRASSLAND:
					score = 1.0 / (1.0 + absf(near_water - 18.0) * 0.2)
					_keep(best, "ground", score, p)
				Biomes.BEACH:
					_keep(best, "beach", 1.0 / (1.0 + absf(p.z) * 0.01), p)
				Biomes.MOUNTAIN, Biomes.SNOW:
					_keep(best, "mountain", p.y, p)
	spots = best
	print("spots: ", spots)


func _keep(d: Dictionary, key: String, score: float, p: Vector3) -> void:
	if not d.has(key) or float(d[key]["score"]) < score:
		d[key] = {"score": score, "pos": p}


func _spot(key: String, fallback: Vector3) -> Vector3:
	return spots[key]["pos"] if spots.has(key) else fallback


func _shots(set_name: String) -> Array:
	var half := world.size * 0.5
	var ground := _spot("ground", Vector3.ZERO)
	var g_dir := (Vector3(-ground.x, 0, -ground.z)).normalized()
	if g_dir.length_squared() < 0.1:
		g_dir = Vector3.FORWARD
	var all := [
		{"name": "overview", "pos": Vector3(0, half * 0.75, half * 1.05), "target": Vector3(0, 0, half * 0.1), "hour": 10.5},
		{"name": "ground", "pos": ground + Vector3(0, 3.0, 0) - g_dir * 6.0, "target": ground + g_dir * 40.0 + Vector3(0, 2, 0), "hour": 9.5},
		{"name": "dawn", "pos": Vector3(half * 0.6, 60, half * 0.6), "target": Vector3(0, 0, 0), "hour": 6.2},
		{"name": "noon", "pos": Vector3(half * 0.6, 60, half * 0.6), "target": Vector3(0, 0, 0), "hour": 12.5},
		{"name": "sunset", "pos": Vector3(-half * 0.6, 60, half * 0.4), "target": Vector3(0, 0, -half * 0.2), "hour": 18.6},
		{"name": "night", "pos": Vector3(half * 0.6, 60, half * 0.6), "target": Vector3(0, 0, 0), "hour": 23.0},
	]
	var out := []
	for s in all:
		if set_name == "all" or s["name"] == set_name \
				or (set_name == "times" and s["name"] in ["dawn", "noon", "sunset", "night"]):
			out.append(s)
	return out


func _render(shot: Dictionary, out_dir: String) -> void:
	time.set_hour(float(shot.get("hour", 12.0)))
	var pos: Vector3 = shot["pos"]
	var target: Vector3 = shot["target"]
	cam.look_at_from_position(pos, target)
	cam.make_current()
	terrain.update_focus(target.lerp(pos, 0.3))
	terrain.rebuild_pending(true)
	day_night.update_now()
	for f in 3:
		await get_tree().process_frame
	var path := ProjectSettings.globalize_path(out_dir.path_join("world_%s.png" % shot["name"]))
	await ShotUtil.save_viewport(get_viewport(), path)
