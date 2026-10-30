class_name SimWorld
extends Node3D
## Root of the world scene. Owns the SimState (model) and wires the systems:
##   TimeController → ClimateState ← WeatherSystem, DayNightCycle
##   TerrainRenderer / WaterRenderer / FloraRenderer (rendering, focus LOD)
##   EcoGrid (every frame, time-sliced) → PopulationManager (budgeted, tiers C/D)
##   AgentManager (tiers A/B, fold/unfold around the focus) + PerformanceManager
##   EvolutionSystem.daily, EventLog, autosave, HUD, possession, sandbox.
##
## Scene payload (Game.take_pending):
##   {"new_world": menu_config, "player_species": [uids]} | {"load": {slot, file}}
##   | {"experiment_state": Dictionary}  (internal) | {} → default world

signal world_ready
signal selection_changed(agent: Node)

const AUTOSAVE_INTERVAL := 300.0          # real seconds
const POP_FRAME_BUDGET_MS := 5.0
const BACKLOG_LIMIT := 2.0 * Units.SECONDS_PER_DAY
const CONTROLLER_SCRIPT := "res://src/control/creature_controller.gd"

var state: SimState
var slot: String = ""
var time: TimeController
var weather: WeatherSystem
var day_night: DayNightCycle
var terrain: TerrainRenderer
var water: WaterRenderer
var flora: FloraRenderer
var cam: FreeCamera
var perf: PerformanceManager
var agents: AgentManager
var ctx: WorldContext
var gestures: GestureRecognizer
var hud: Node
var selected: Node = null
var controller: Node = null
var tool_mode: StringName = &"select"      # select | release | remove (sandbox taps)
var tool_species: int = -1
var ready_done := false
## Background controlled experiment (see ExperimentManager), stepped each frame.
var experiment: ExperimentManager

var _loading: CanvasLayer
var _pop_budget: int = 6
var _pop_debt := 0.0
var _autosave_timer := AUTOSAVE_INTERVAL
var _last_day := -1
var _throttle_notified := false
var _pending: Dictionary = {}


func _ready() -> void:
	UIOverlay.ensure()
	InputActions.register_defaults()
	_pending = Game.take_pending()
	_show_loading("Создание мира…" if not _pending.has("load") else "Загрузка мира…")
	# Let the loading screen render before the heavy generation.
	await get_tree().process_frame
	await get_tree().process_frame
	_build_state()
	_build_scene()
	_hide_loading()
	ready_done = true
	Game.register_service(&"world", self)
	EventBus.world_loaded.emit(self)
	world_ready.emit()


func _exit_tree() -> void:
	if ready_done:
		EventBus.world_unloading.emit(self)
	Game.unregister_service(&"world", self)


# --- Building ---------------------------------------------------------------------------

func _build_state() -> void:
	if _pending.has("experiment_state"):
		state = WorldBuilder.restore(_pending["experiment_state"])
		slot = str(_pending.get("slot", ""))
	elif _pending.has("load"):
		var l: Dictionary = _pending["load"]
		slot = str(l.get("slot", ""))
		var r := SaveSystem.load_world(slot, str(l.get("file", "world.sav")))
		if r["ok"]:
			state = WorldBuilder.restore(r["data"])
			if r["from_backup"]:
				Game.notify("Сохранение повреждено — загружена резервная копия", &"warning")
		else:
			Game.notify("Не удалось загрузить мир: %s" % r["error"], &"error")
	if state == null:
		var menu: Dictionary = _pending.get("new_world", {})
		if menu.is_empty():
			menu = {"seed": randi() % 1000000, "size": 512.0, "procedural_species": 6, "name": "Новый мир"}
		var players := []
		for uid in _pending.get("player_species", []):
			var g := SpeciesLibrary.load_genome(str(uid))
			if g != null:
				var entry := SpeciesLibrary.load_entry(str(uid))
				players.append({"genome": g, "uid": str(uid), "name": str(entry["data"].get("name", g.body_plan.name))})
		state = WorldBuilder.create(menu, players)
	if slot == "":
		slot = ("%s_%d" % [state.name, state.seed_value]).validate_filename()


func _build_scene() -> void:
	var w := state.world
	time = TimeController.new()
	add_child(time)
	time.setup(state.climate, 8.0, 4)
	if not state.time_state.is_empty():
		time.from_dict(state.time_state)

	cam = FreeCamera.new()
	add_child(cam)
	cam.set_height_provider(func(x: float, z: float) -> float: return maxf(w.height_at(x, z), w.water_surface_at(x, z)))
	var half := w.size * 0.5
	cam.set_bounds(AABB(Vector3(-half, -50.0, -half), Vector3(w.size, 400.0, w.size)))
	cam.max_distance = maxf(cam.max_distance, w.size * 0.9)

	weather = WeatherSystem.new()
	add_child(weather)
	weather.setup(state.climate, w, time, cam.camera, state.seed_value)
	if not state.weather_state.is_empty():
		weather.from_dict(state.weather_state)

	day_night = DayNightCycle.new()
	add_child(day_night)
	day_night.setup(state.climate, weather, time)

	terrain = TerrainRenderer.new()
	add_child(terrain)
	terrain.setup(w, state.climate)
	water = WaterRenderer.new()
	add_child(water)
	water.setup(w, state.climate)
	flora = FloraRenderer.new()
	add_child(flora)
	flora.setup(w, state.plants, state.eco.biomass, state.eco.cell_size, state.climate)

	perf = PerformanceManager.new()
	add_child(perf)
	perf.statistical_mode_changed.connect(_on_statistical_mode)

	ctx = WorldContext.new()
	ctx.world = w
	ctx.climate = state.climate
	ctx.eco = state.eco
	ctx.populations = state.pop
	ctx.registry = state.evo.registry
	ctx.evolution = state.evo
	ctx.event_log = state.event_log
	ctx.rng = Rng.new(state.seed_value * 101 + 17)
	ctx.mutation_settings = state.evo.settings

	agents = AgentManager.new()
	agents.name = "Creatures"
	add_child(agents)
	agents.setup(state, ctx, perf)
	for ind in state.saved_agents:
		agents.spawn(ind)
	state.saved_agents.clear()

	_place_camera()
	_build_input()
	_build_hud()
	_last_day = state.climate.day
	_connect_events()


func _place_camera() -> void:
	if not state.camera_state.is_empty():
		cam.set_state(state.camera_state)
		cam.snap()
		return
	# Start above the most populated land sector.
	var best := -1
	var best_n := -1.0
	for s in state.pop.sectors:
		var n := s.total_count()
		if n > best_n and s.land_frac > 0.5:
			best_n = n
			best = s.index
	var p := state.pop.sector_center(best) if best >= 0 else Vector3.ZERO
	p.y = state.world.height_at(p.x, p.z)
	cam.focus(p, 38.0, true)
	cam.snap()


func _build_input() -> void:
	gestures = GestureRecognizer.new()
	add_child(gestures)
	cam.attach_gestures(gestures)
	gestures.tap.connect(_on_tap)


func _build_hud() -> void:
	var script := load("res://src/sim/hud/sim_hud.gd")
	if script == null:
		return
	hud = script.new()
	add_child(hud)
	hud.setup(self)
	if hud.has_method("view_surface"):
		gestures.attach_to(hud.view_surface())
	else:
		gestures.listen_unhandled = true


func _connect_events() -> void:
	EventBus.species_extinct.connect(func(d: SpeciesDef) -> void:
		state.event_log.add(&"species", "Вымер вид «%s»." % d.name)
		Game.notify("Вымер вид «%s»" % d.name, &"warning"))
	EventBus.speciation.connect(func(parent: SpeciesDef, child: SpeciesDef) -> void:
		state.event_log.add(&"evolution", "Видообразование: от «%s» отделился новый вид «%s»." % [parent.name, child.name])
		Game.notify("Новый вид: «%s»" % child.name, &"info"))
	EventBus.weather_changed.connect(func(wth: StringName) -> void:
		if wth in [&"storm", &"snow"]:
			state.event_log.add(&"weather", "Погода: %s." % weather.label()))


# --- Frame loop ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not ready_done:
		return
	var phys_dt := time.phys_dt
	var bio_dt := time.bio_dt
	perf.update_time_scale(time.time_scale)
	state.eco.step(bio_dt)
	_step_populations(bio_dt)
	if state.climate.day != _last_day:
		_last_day = state.climate.day
		state.evo.daily(float(_last_day))
	agents.focus = _focus_point()
	agents.sim_update(phys_dt, bio_dt, delta)
	var cpos := cam.camera.global_position
	terrain.update_focus(cpos)
	flora.update_focus(cpos)
	if experiment != null and experiment.running and experiment.step(6.0):
		log_intervention(experiment.summary())
		Game.notify("Эксперимент завершён — результаты в панели «Эксперимент»", &"success")
	_autosave_timer -= delta
	if _autosave_timer <= 0.0:
		_autosave_timer = AUTOSAVE_INTERVAL
		save_world("autosave")


## Population pools: time-sliced with an adaptive sector budget so a frame
## never spends more than ~POP_FRAME_BUDGET_MS. If the simulated backlog
## grows (CPU slower than the chosen speed) time is throttled.
func _step_populations(bio_dt: float) -> void:
	_pop_debt += bio_dt
	if _pop_debt <= 0.0:
		return
	state.pop.sector_budget = _pop_budget
	var t0 := Time.get_ticks_usec()
	state.pop.step(_pop_debt)
	_pop_debt = 0.0
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	if ms > POP_FRAME_BUDGET_MS and _pop_budget > 1:
		_pop_budget -= 1
	elif ms < POP_FRAME_BUDGET_MS * 0.5 and _pop_budget < state.pop.sectors.size():
		_pop_budget += 1
	var backlog := 0.0
	for s in state.pop.sectors:
		backlog = maxf(backlog, s.pending_dt)
	if backlog > BACKLOG_LIMIT and time.scale_index > 0 and time.time_scale > 16.0:
		time.slower()
		if not _throttle_notified:
			_throttle_notified = true
			Game.notify("Скорость снижена: устройство не успевает считать популяции", &"warning")


func _focus_point() -> Vector3:
	if controller != null and is_instance_valid(controller) and selected != null and is_instance_valid(selected):
		return (selected as Node3D).global_position
	return cam.pivot


func _on_statistical_mode(on: bool) -> void:
	if on:
		if controller != null:
			release_control()
		agents.fold_all()
		select(null)
		Game.notify("Сверхускорение: особи свёрнуты в популяционную модель", &"info")


# --- Selection & control ---------------------------------------------------------------------

func _on_tap(pos: Vector2) -> void:
	if controller != null:
		return
	match tool_mode:
		&"release", &"remove":
			var gp = cam.ground_point(pos)
			if gp == null:
				gp = terrain.pick_ray(cam.screen_ray(pos)["origin"], cam.screen_ray(pos)["dir"])
			if gp is Vector3 and gp != Vector3.INF:
				_apply_tool_at(gp)
			return
	var a := agents.pick_screen(cam.camera, pos, 64.0 * UITheme.ui_scale())
	select(a)


func select(a: Node) -> void:
	if selected == a:
		return
	if selected != null and is_instance_valid(selected) and selected.has_method("set_selected"):
		selected.set_selected(false)
	selected = a
	if a != null and a.has_method("set_selected"):
		a.set_selected(true)
	selection_changed.emit(a)
	EventBus.creature_selected.emit(a)


func follow_selected() -> void:
	if selected != null and is_instance_valid(selected):
		cam.follow(selected as Node3D, Vector3(0, 0.6, 0))


## mode: &"first_person" | &"third_person"
func possess(mode: StringName) -> void:
	if selected == null or not is_instance_valid(selected) or not ResourceLoader.exists(CONTROLLER_SCRIPT):
		Game.notify("Управление существом недоступно", &"warning")
		return
	if time.time_scale > 4.0:
		time.set_scale_index(TimeController.DEFAULT_SCALE_INDEX)
	release_control()
	controller = load(CONTROLLER_SCRIPT).new()
	add_child(controller)
	if controller.has_signal("exited"):
		controller.exited.connect(release_control)
	controller.possess(selected, mode, self)
	cam.visible = false
	if hud != null and hud.has_method("set_observer_visible"):
		hud.set_observer_visible(false)
	EventBus.control_mode_changed.emit(mode, selected)


func release_control() -> void:
	if controller == null:
		return
	var c := controller
	controller = null
	if is_instance_valid(c):
		if c.has_method("release"):
			c.release()
		c.queue_free()
	cam.visible = true
	cam.camera.make_current()
	if selected != null and is_instance_valid(selected):
		cam.focus((selected as Node3D).global_position, 12.0)
	if hud != null and hud.has_method("set_observer_visible"):
		hud.set_observer_visible(true)
	EventBus.control_mode_changed.emit(&"observer", null)


# --- Sandbox -----------------------------------------------------------------------------------

func set_tool(mode: StringName, species_id: int = -1) -> void:
	tool_mode = mode
	tool_species = species_id


func _apply_tool_at(p: Vector3) -> void:
	match tool_mode:
		&"release":
			if tool_species < 0:
				return
			var d := state.evo.registry.get_species(tool_species)
			WorldBuilder.release(state, tool_species, p, 12)
			log_intervention("Заселение: 12 особей вида «%s» в точке (%d, %d)." % [d.name, int(p.x), int(p.z)],
				{"tool": "release", "species": tool_species, "pos": Serial.v3(p)})
			# Re-activate the sector so the newcomers appear immediately.
			agents.fold_all()
			_tutorial(&"species_placed")
		&"remove":
			var n := 0
			for a in agents.agents.duplicate():
				if (a as Node3D).global_position.distance_to(p) < 12.0:
					var ind: Individual = a.get("individual")
					if ind != null:
						ind.alive = false
						ind.cause = &"removed"
					agents._remove_agent(a)
					n += 1
			log_intervention("Удалено %d особей в радиусе 12 м." % n, {"tool": "remove", "pos": Serial.v3(p)})


func log_intervention(text: String, data: Dictionary = {}) -> void:
	state.event_log.add(&"intervention", text, data)
	EventBus.intervention_applied.emit(text, data)


func _tutorial(id: StringName) -> void:
	if hud != null and hud.has_method("tutorial_event"):
		hud.tutorial_event(id)


# --- Persistence -------------------------------------------------------------------------------

func snapshot() -> Dictionary:
	state.time_state = time.to_dict()
	state.weather_state = weather.to_dict()
	state.camera_state = cam.get_state()
	return state.to_dict(agents.all_individuals())


func save_world(kind: String = "manual") -> bool:
	var d := snapshot()
	var err := SaveSystem.save_world(slot, d, kind)
	if err == OK:
		if kind != "autosave":
			Game.notify("Мир сохранён", &"success")
		return true
	Game.notify("Ошибка сохранения: %s" % error_string(err), &"error")
	return false


func exit_to_menu() -> void:
	save_world("autosave")
	Game.goto_scene(Game.SCENE_MENU)


# --- Loading overlay -----------------------------------------------------------------------------

func _show_loading(text: String) -> void:
	_loading = CanvasLayer.new()
	_loading.layer = 50
	add_child(_loading)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.09, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	UITheme.attach(bg)
	var lab := Label.new()
	lab.text = text
	lab.theme_type_variation = &"TitleLabel"
	lab.set_anchors_preset(Control.PRESET_CENTER)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lab.grow_vertical = Control.GROW_DIRECTION_BOTH
	bg.add_child(lab)


func _hide_loading() -> void:
	if _loading != null:
		_loading.queue_free()
		_loading = null
