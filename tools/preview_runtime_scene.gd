extends Node
## Runtime previews, scene part (loaded by preview_runtime.gd after the first frame).
##   arena: several presets walking / flying across the meadow (mid-stride poses)
##   first: first-person view of a predator hunting grazers
##   third: third-person HUD with context buttons (eat, drink, attack ...)

var arena: TestArena
var cam: Camera3D
var _driven: Array = []   # [agent, direction, speed]


func run(args: PackedStringArray) -> void:
	await get_tree().process_frame
	var what := args[0] if args.size() > 0 else "all"
	var out_dir := "res://screenshots" if what == "all" else "res://screenshots/tmp"
	if what == "sheet":
		await _sheet(args[1] if args.size() > 1 else "res://screenshots/tmp/runtime_sheet.png")
	if what in ["all", "arena"]:
		await _arena_shot(args[1] if args.size() > 1 and what == "arena" else "%s/runtime_arena.png" % out_dir)
	if what in ["all", "first"]:
		await _first_person(args[1] if args.size() > 1 and what == "first" else "%s/runtime_first_person.png" % out_dir)
	if what in ["all", "third"]:
		await _third_person(args[1] if args.size() > 1 and what == "third" else "%s/runtime_third_person.png" % out_dir)


func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame


func _new_arena(preset: String) -> void:
	if arena != null:
		arena.queue_free()
		await get_tree().process_frame
	_driven.clear()
	arena = TestArena.new()
	arena.auto_start = false
	add_child(arena)
	await get_tree().process_frame
	arena.start({"preset": preset})
	arena.time.paused = true
	arena.sim.clear_plants()
	arena.sim.climate.cloud_cover = 0.0
	arena.sim.climate.fog = 0.0
	if OS.get_environment("PREVIEW_NO_SHADOWS") != "":
		arena.day_night.sun.shadow_enabled = false
	cam = Camera3D.new()
	cam.far = 600.0
	arena.add_child(cam)


## Takes a creature away from its brain and walks it along `dir` at `speed` m/s.
func _drive(a: CreatureAgent, dir: Vector3, speed: float, fly: bool = false) -> void:
	a.possess(self)
	a.intent.direct(dir, speed)
	a.intent.fly = fly
	a.intent.altitude = 4.0
	a.intent.avoid_water = true
	_driven.append([a, dir, speed, fly])


func _hold(a: CreatureAgent) -> void:
	a.possess(self)
	a.intent.stop()


func _run_driven(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		for d in _driven:
			var a: CreatureAgent = d[0]
			if is_instance_valid(a) and a.is_alive():
				a.intent.direct(d[1], d[2])
				a.intent.fly = d[3]
		arena.sim.step_dt(1.0 / 30.0, 1.0 / 30.0 * 60.0)
		t += 1.0 / 30.0


func _arena_shot(path: String) -> void:
	await _new_arena("predator")
	arena.controller.release()
	cam.make_current()
	var s := arena.sim
	var cast := [
		[&"grazer", 1.6], [&"runner", 3.6], [&"predator", 3.4], [&"turtle", 0.8], [&"spider", 0.6],
		[&"centipede", 0.5], [&"bird", 9.0],
	]
	s.deaths.clear()
	arena.player.queue_free()
	arena.readout.get_parent().visible = false
	var x := -7.0
	var zi := 0
	for c in cast:
		var a := s.spawn_preset(c[0], Vector3(x, 0, 20.0 + [0.0, 1.3, -1.0, 0.6, 1.6, -0.4, 0.0][zi]))
		zi += 1
		a.mover.heading = -PI * 0.5
		a.individual.heading = a.mover.heading
		var fly: bool = c[0] == &"bird"
		if fly:
			a.mover.flying = true
			a.mover.pos.y += 3.0
			a.mover.speed = 6.0
		_drive(a, Vector3(1, 0, 0), float(c[1]), fly)
		x += 2.5
	# Keep the pond life in the picture: fish and an octopus.
	for f in [[&"fish", Vector3(15, 0, 9)], [&"fish", Vector3(18, 0, 12)], [&"octopus", Vector3(19, 0, 7)]]:
		var a2 := s.spawn_preset(f[0], f[1])
		_hold(a2)
	_run_driven(2.6)
	cam.fov = 52.0
	cam.look_at_from_position(Vector3(4.0, 2.2, 29.0), Vector3(4.0, 1.0, 20.0))
	await _settle()
	await ShotUtil.save_viewport(get_tree().root, ProjectSettings.globalize_path(path))


func _first_person(path: String) -> void:
	await _new_arena("predator")
	var s := arena.sim
	var pl := arena.player
	arena.controller.set_mode(&"first_person")
	pl.mover.teleport(Vector3(-24, 0, 4))
	pl.mover.heading = -PI * 0.5
	arena.sim.plant_patch(Vector3(-12, 0, 3), 8.0, 0.8)
	for p in [Vector3(-16, 0, 2), Vector3(-19, 0, 6.5), Vector3(-13, 0, 5), Vector3(-21, 0, 0)]:
		var g := s.spawn_preset(&"grazer", p)
		_hold(g)
		g.mover.heading = 0.4
	await get_tree().process_frame
	pl.individual.hydration = 0.95
	s.step_dt(0.05, 3.0)
	arena.controller.cam.yaw = pl.mover.heading
	arena.controller.cam.pitch = -0.04
	arena.controller.cam.snap()
	await _settle(8)
	if OS.get_environment("PREVIEW_NO_FX") != "":
		arena.controller.fx.queue_free()
		await _settle(3)
	var m: ShaderMaterial = arena.controller.fx.material if is_instance_valid(arena.controller.fx) else ShaderMaterial.new()
	print("FX gray=%s dark=%s blur=%s mosaic=%s edge=%s damage=%s daylight=%s light=%s sleeping=%s" % [m.get_shader_parameter(&"gray"), m.get_shader_parameter(&"darkness"), m.get_shader_parameter(&"blur"), m.get_shader_parameter(&"mosaic"), m.get_shader_parameter(&"edge_blur"), m.get_shader_parameter(&"damage"), arena.sim.climate.daylight, arena.sim.climate.light_at(Vector3.ZERO), arena.player.sleeping])
	await ShotUtil.save_viewport(get_tree().root, ProjectSettings.globalize_path(path))


func _third_person(path: String) -> void:
	await _new_arena("grazer")
	var s := arena.sim
	var pl := arena.player
	# Plants and the pond bank: eat and drink buttons both appear; a turtle in front: attack.
	s.plant_patch(Vector3(4, 0, 12), 10.0, 0.8)
	pl.mover.teleport(Vector3(5.4, 0, 10.5))
	pl.mover.heading = -PI * 0.5
	pl.individual.energy = pl.individual.max_energy() * 0.4
	pl.individual.hydration = 0.85
	var t := s.spawn_preset(&"turtle", Vector3(7.0, 0, 8.6))
	_hold(t)
	arena.controller.cam.yaw = pl.mover.heading
	arena.controller.cam.pitch = -0.42
	var friend := s.spawn_preset(&"grazer", Vector3(0, 0, 14))
	_hold(friend)
	for i in 6:
		s.step_dt(0.1, 6.0)
		await get_tree().process_frame
	arena.controller.cam.snap()
	await _settle(10)
	await ShotUtil.save_viewport(get_tree().root, ProjectSettings.globalize_path(path))


## Close-ups of very different anatomies in motion (animator check): tiles in one sheet.
func _sheet(path: String) -> void:
	await _new_arena("grazer")
	arena.controller.release()
	arena.hud_layer.visible = false
	arena.sim.climate.cloud_cover = 0.0
	cam.make_current()
	cam.fov = 40.0
	var specs := [
		[&"grazer", 1.5, "land"], [&"predator", 3.5, "land"], [&"bird", 8.0, "air"], [&"fish", 1.5, "water"],
		[&"octopus", 0.8, "water"], [&"worm", 0.2, "land"], [&"centipede", 0.5, "land"], [&"spider", 0.7, "land"],
		[&"frog", 1.0, "land"], [&"insect", 1.0, "air"], [&"runner", 3.5, "land"], [&"turtle", 0.7, "land"],
	]
	var tile := Vector2i(427, 360)
	var sheet := Image.create(tile.x * 3, tile.y * 4, false, Image.FORMAT_RGBA8)
	var i := 0
	for sp in specs:
		var s := arena.sim
		var pos := Vector3(-6, 0, 20)
		if sp[2] == "water":
			pos = Vector3(17, 0, 10)
		var a := s.spawn_preset(sp[0], pos)
		_driven.clear()
		var fly: bool = sp[2] == "air"
		if fly:
			a.mover.flying = true
			a.mover.pos.y += 3.0
			a.mover.speed = float(sp[1]) * 0.7
		a.mover.heading = -PI * 0.5
		_drive(a, Vector3(1, 0, 0), float(sp[1]), fly)
		if sp[2] == "water":
			a.intent.surface = false
		_run_driven(2.2)
		var c := a.mover.pos + Vector3.UP * maxf(a.mover.height * 0.5, 0.05)
		var ext := maxf(a.mover.length, a.mover.height * 1.5)
		var dist := ext * 2.6 + 0.4
		cam.look_at_from_position(c + Vector3(0.0, ext * 0.25, dist), c)
		await _settle(5)
		var img := get_tree().root.get_texture().get_image()
		var rect := Rect2i((img.get_width() - tile.x) / 2, (img.get_height() - tile.y) / 2, tile.x, tile.y)
		sheet.blit_rect(img, rect, Vector2i((i % 3) * tile.x, (i / 3) * tile.y))
		a.teardown()
		a.queue_free()
		s.agent_list.erase(a)
		i += 1
	var out := ProjectSettings.globalize_path(path)
	sheet.save_png(out)
	print("saved ", out)
