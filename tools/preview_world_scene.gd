extends Node
## World preview scene driven by tools/preview_world.gd (see usage there).
## Debug overrides (environment): PREVIEW_NO_SHADOWS=1, PREVIEW_NO_WATER=1,
## PREVIEW_WEATHER=<state> (forces the weather of every shot).

const LABELS := {
	"rain": "Дождь", "snow": "Снег", "fog": "Туман", "storm": "Гроза",
	"dawn": "Рассвет", "noon": "Полдень", "sunset": "Закат", "night": "Ночь",
}

var world: WorldData
var climate: ClimateState
var time: TimeController
var day_night: DayNightCycle
var terrain: TerrainRenderer
var water: WaterRenderer
var flora: FloraRenderer
var weather: WeatherSystem
var plants: Array[PlantSpecies] = []
var cam: Camera3D
var spots: Dictionary = {}
var caption: Label


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
	if set_name == "final":
		await _final()
		return
	for shot in _shots(set_name):
		var img: Image = await _render(shot)
		_save(img, out_dir.path_join("world_%s.png" % shot["name"]))


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
	cam = Camera3D.new()
	cam.far = 3000.0
	cam.fov = 60.0
	root.add_child(cam)
	weather = WeatherSystem.new()
	root.add_child(weather)
	weather.setup(climate, world, time, cam, int(world.config["seed"]))
	day_night = DayNightCycle.new()
	root.add_child(day_night)
	day_night.setup(climate, weather, time)
	if OS.get_environment("PREVIEW_NO_SHADOWS") != "":
		day_night.sun.shadow_enabled = false
	var t0 := Time.get_ticks_msec()
	terrain = TerrainRenderer.new()
	root.add_child(terrain)
	terrain.setup(world, climate)
	print("terrain setup: %d ms, %d tris" % [Time.get_ticks_msec() - t0, terrain.triangle_count()])
	t0 = Time.get_ticks_msec()
	water = WaterRenderer.new()
	root.add_child(water)
	water.setup(world, climate)
	print("water setup: %d ms" % (Time.get_ticks_msec() - t0))
	water.visible = OS.get_environment("PREVIEW_NO_WATER") == ""
	t0 = Time.get_ticks_msec()
	plants = FloraSystem.generate_species(world, Rng.new(int(world.config["seed"]) * 31 + 7))
	for sp in plants:
		print("  plant %-28s %-15s h=%.1f T=%.1f M=%.2f cap=%.2f" % [sp.name, sp.form, sp.height, sp.temp_opt, sp.moist_opt, sp.capacity])
	flora = FloraRenderer.new()
	root.add_child(flora)
	flora.setup(world, plants, Callable(), 8.0, climate)
	print("flora setup: %d ms" % (Time.get_ticks_msec() - t0))


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
				Biomes.TAIGA, Biomes.TUNDRA:
					_keep(best, "north", -p.z * 0.01 + 1.0 / (1.0 + absf(near_water - 20.0) * 0.1), p)
	spots = best
	print("spots: ", spots)


func _keep(d: Dictionary, key: String, score: float, p: Vector3) -> void:
	if not d.has(key) or float(d[key]["score"]) < score:
		d[key] = {"score": score, "pos": p}


func _spot(key: String, fallback: Vector3) -> Vector3:
	return spots[key]["pos"] if spots.has(key) else fallback


## Eye-level view from `p`: picks the direction with the most open sight line.
func _eye_view(name: String, p: Vector3, eye: float, hour: float, extra: Dictionary = {}) -> Dictionary:
	var best_dir := Vector3.FORWARD
	var best := -INF
	for k in 24:
		var a := float(k) / 24.0 * TAU
		var d := Vector3(cos(a), 0, sin(a))
		var score := 0.0
		for j in range(1, 16):
			var q := p + d * float(j) * 6.0
			if not world.contains(q.x, q.z):
				score -= 1.0
				continue
			var g := maxf(world.height_at(q.x, q.z), world.sea_level)
			var line := p.y + eye - float(j) * 0.5
			score += 1.0 if g < line else -2.0
			if world.water_type_at(q.x, q.z) != WorldData.Water.LAND:
				score += 0.4
		if score > best:
			best = score
			best_dir = d
	var cam := p + Vector3(0, eye, 0) - best_dir * 2.0
	var shot := {"name": name, "pos": cam, "target": cam + best_dir * 40.0 + Vector3(0, -eye * 0.6, 0), "hour": hour}
	shot.merge(extra, true)
	return shot


func _shots(set_name: String) -> Array:
	var half := world.size * 0.5
	var all := [
		{"name": "overview", "pos": Vector3(0, half * 0.75, half * 1.05), "target": Vector3(0, 0, half * 0.1), "hour": 10.5},
		_eye_view("ground", _spot("ground", Vector3.ZERO), 1.8, 9.5),
		_eye_view("beach", _spot("beach", Vector3.ZERO), 2.5, 15.0),
		_eye_view("mountain", _spot("mountain", Vector3.ZERO), 3.0, 11.0),
		{"name": "dawn", "pos": Vector3(half * 0.6, 60, half * 0.6), "target": Vector3(0, 0, 0), "sun": 3.0},
		_eye_view("rain", _spot("ground", Vector3.ZERO), 1.8, 14.0, {"weather": &"rain", "wetness": 0.9}),
		_eye_view("snow", _spot("north", Vector3.ZERO), 2.2, 11.0, {"weather": &"snow", "season": 3, "snow_cover": 0.9}),
		_eye_view("fog", _spot("ground", Vector3.ZERO), 2.0, 7.5, {"weather": &"fog", "season": 2}),
		{"name": "storm", "pos": Vector3(half * 0.5, 45, half * 0.7), "target": Vector3(0, 0, 0), "hour": 16.0, "weather": &"storm", "wetness": 1.0},
		{"name": "noon", "pos": Vector3(half * 0.6, 60, half * 0.6), "target": Vector3(0, 0, 0), "hour": 12.5},
		{"name": "sunset", "pos": Vector3(-half * 0.6, 60, half * 0.4), "target": Vector3(0, 0, -half * 0.2), "sun": -2.0},
		{"name": "night", "pos": Vector3(half * 0.6, 60, half * 0.6), "target": Vector3(0, 0, 0), "hour": 23.0},
	]
	var out := []
	for s in all:
		if set_name == "all" or s["name"] == set_name \
				or (set_name == "times" and s["name"] in ["dawn", "noon", "sunset", "night"]) \
				or (set_name == "weather" and s["name"] in ["rain", "snow", "fog", "storm"]):
			out.append(s)
	return out


## Committed screenshots: overview, ground, weather sheet, time-of-day sheet.
func _final() -> void:
	var by_name := {}
	for shot in _shots("all"):
		by_name[shot["name"]] = shot
	_save(await _render(by_name["overview"]), "res://screenshots/world_overview.png")
	_save(await _render(by_name["ground"]), "res://screenshots/world_ground.png")
	_save(await _sheet(by_name, ["rain", "snow", "fog", "storm"]), "res://screenshots/world_weather.png")
	_save(await _sheet(by_name, ["dawn", "noon", "sunset", "night"]), "res://screenshots/world_times.png")


## 2×2 contact sheet of labelled shots at half resolution.
func _sheet(by_name: Dictionary, names: Array) -> Image:
	var tiles: Array[Image] = []
	for n in names:
		tiles.append(await _render(by_name[n], LABELS.get(n, "")))
	var tw := tiles[0].get_width() / 2
	var th := tiles[0].get_height() / 2
	var out := Image.create(tw * 2, th * 2, false, tiles[0].get_format())
	for k in tiles.size():
		var t := tiles[k]
		t.resize(tw, th, Image.INTERPOLATE_LANCZOS)
		out.blit_rect(t, Rect2i(0, 0, tw, th), Vector2i((k % 2) * tw, (k / 2) * th))
	return out


func _save(img: Image, path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	img.save_png(abs_path)
	print("saved ", abs_path, " ", img.get_size())


func _render(shot: Dictionary, label: String = "") -> Image:
	time.set_season(int(shot.get("season", 1)))
	var hour := float(shot.get("hour", 12.0))
	if shot.has("sun"):
		# Solar elevation target: positive = morning, negative = evening.
		var e: float = shot["sun"]
		hour = SunModel.hour_for_elevation(absf(e), climate.year_phase + 0.03, time.latitude, e > 0.0)
	time.set_hour(hour)
	var forced := OS.get_environment("PREVIEW_WEATHER")
	weather.force_weather(StringName(forced) if forced != "" else shot.get("weather", &"clear"), true)
	climate.snow_cover = float(shot.get("snow_cover", 0.0))
	climate.wetness = float(shot.get("wetness", 0.0))
	climate.drought = float(shot.get("drought", 0.0))
	var pos: Vector3 = shot["pos"]
	var target: Vector3 = shot["target"]
	cam.look_at_from_position(pos, target)
	cam.make_current()
	terrain.update_focus(pos)
	terrain.rebuild_pending(true)
	var t0 := Time.get_ticks_msec()
	flora.update_focus(pos)
	flora.refresh_all()
	print("%s: flora %d instances, %d draws (%d ms), terrain %d tris" % [shot["name"], flora.instance_count(), flora.draw_calls(), Time.get_ticks_msec() - t0, terrain.triangle_count()])
	day_night.update_now()
	terrain.apply_climate()
	water.apply_climate()
	flora.apply_climate()
	if weather.fx != null:
		weather.fx.lightning_enabled = false
		weather.focus = pos
		weather.fx.update_fx(0.016)
		weather.fx.prewarm()
	for f in 3:
		await get_tree().process_frame
	_set_caption(label)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _set_caption(text: String) -> void:
	if caption == null:
		var layer := CanvasLayer.new()
		add_child(layer)
		caption = Label.new()
		caption.position = Vector2(28, 20)
		caption.add_theme_font_size_override("font_size", 46)
		caption.add_theme_color_override("font_color", Color(1, 1, 1))
		caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		caption.add_theme_constant_override("outline_size", 10)
		layer.add_child(caption)
	caption.text = text
	caption.visible = text != ""
