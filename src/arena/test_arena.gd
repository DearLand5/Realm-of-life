class_name TestArena
extends Node3D
## The editor's "Test" target (scenes/test_arena.tscn): a small meadow with a
## pond, food patches and a few companions where the designed creature can be
## played in third / first person, or watched while its AI drives it.
##
## Payload (Game.take_pending()): {"genome": dict, "return_to": "editor", ...}
## ("preset": id is accepted too). "Back" returns to the editor with the same
## payload keys so the design is restored.
##
## Test hooks: set `auto_start = false` before adding to the tree to build the
## scene manually via `start(payload)`; `headless_world` skips renderers.

signal back_requested

var auto_start := true
var payload: Dictionary = {}
var sim: ArenaSim
var time: TimeController
var day_night: DayNightCycle
var terrain: TerrainRenderer
var water: WaterRenderer
var flora: FloraRenderer
var controller: CreatureController
var player: CreatureAgent
var companions: Array[CreatureAgent] = []
var hud_layer: CanvasLayer
var readout: Label
var observe_btn: IconButton
var start_mode: StringName = &"third_person"

var _readout_timer: float = 0.0
var _genome_dict: Dictionary = {}


func _ready() -> void:
	if auto_start:
		var g: Node = UIApp.game()
		var pend: Dictionary = g.call(&"take_pending") if g != null else {}
		start(pend)


func start(pending: Dictionary) -> void:
	payload = pending.duplicate(true)
	UIOverlay.ensure()
	InputActions.register_defaults()
	_build_world()
	_spawn_creatures()
	_build_controller()
	_build_hud()


# --- World ------------------------------------------------------------------------------------------

func _build_world() -> void:
	sim = ArenaSim.new(false, 7)
	sim.name = "Sim"
	add_child(sim)
	time = TimeController.new()
	time.name = "Time"
	add_child(time)
	time.setup(sim.climate, 11.0)
	day_night = DayNightCycle.new()
	add_child(day_night)
	day_night.setup(sim.climate, null, time)
	terrain = TerrainRenderer.new()
	add_child(terrain)
	terrain.setup(sim.world, sim.climate)
	water = WaterRenderer.new()
	add_child(water)
	water.setup(sim.world, sim.climate)
	sim.clear_plants()
	sim.plant_patch(Vector3(-26, 0, 10), 11.0, 0.8)
	sim.plant_patch(Vector3(-6, 0, -26), 9.0, 0.7)
	sim.plant_patch(Vector3(30, 0, -18), 8.0, 0.75)
	flora = FloraRenderer.new()
	add_child(flora)
	flora.setup(sim.world, sim.plants, sim.eco.biomass, sim.eco.cell_size, sim.climate)


func _player_genome() -> Genome:
	var gd: Variant = payload.get("genome")
	if gd is Dictionary and not (gd as Dictionary).is_empty():
		_genome_dict = gd
		var g := Genome.from_dict(gd)
		if g != null and g.body_plan != null:
			return g
	if payload.has("preset"):
		return BodyPlanPresets.create(StringName(str(payload["preset"])))
	return BodyPlanPresets.create(&"predator")


func _spawn_creatures() -> void:
	var g := _player_genome()
	var ind := Individual.create(g, 100, &"adult", sim.ctx.rng)
	ind.position = Vector3(2, sim.world.height_at(2, -2), -2)
	ind.heading = 0.4
	ind.energy = ind.max_energy() * 0.8
	player = sim.spawn(ind)
	var key := g.morph_key()
	var extras: Array = [[&"grazer", Vector3(-22, 0, 8)], [&"grazer", Vector3(-28, 0, 14)], [&"predator", Vector3(-6, 0, 34)]]
	for e in extras:
		var preset: StringName = e[0]
		if BodyPlanPresets.create(preset).morph_key() == key:
			continue
		var c := sim.spawn_preset(preset, e[1])
		companions.append(c)


func _build_controller() -> void:
	controller = CreatureController.new()
	add_child(controller)
	controller.possess(player, start_mode, self)
	controller.exited.connect(back_to_editor)


# --- HUD --------------------------------------------------------------------------------------------------

func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 25
	add_child(hud_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(root)
	UITheme.attach(root)
	var safe := SafeArea.new()
	root.add_child(safe)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	col.add_theme_constant_override("separation", 6)
	safe.add_child(col)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var back := IconButton.make(&"back", tr("Назад"), tr("Вернуться в редактор"))
	back.pressed.connect(back_to_editor)
	row.add_child(back)
	observe_btn = IconButton.make(&"eye", tr("Наблюдать ИИ"), tr("Пусть существом управляет ИИ"))
	observe_btn.toggle_mode = true
	observe_btn.toggled.connect(_on_observe_toggled)
	row.add_child(observe_btn)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout = Label.new()
	readout.add_theme_font_size_override("font_size", 15)
	panel.add_child(readout)
	panel.self_modulate = Color(1, 1, 1, 0.85)
	col.add_child(panel)
	_update_readout()


func _on_observe_toggled(on: bool) -> void:
	if controller != null:
		controller.set_ai_driven(on)


func back_to_editor() -> void:
	back_requested.emit()
	var back := payload.duplicate(true)
	if not _genome_dict.is_empty():
		back["genome"] = _genome_dict
	elif player != null and player.individual != null and player.individual.genome != null:
		back["genome"] = player.individual.genome.to_dict()
	back.erase("return_to")
	if controller != null:
		controller.release()
	if not UIApp.goto_scene("SCENE_EDITOR", back):
		return


## Capability readout: speeds per medium, abilities, live energy use.
func capability_text() -> String:
	if player == null or not is_instance_valid(player):
		return ""
	var lp := player.phenotype.locomotion
	var p := player.phys
	var abilities := PackedStringArray()
	if lp.can_walk:
		abilities.append(tr("ходит"))
	if lp.can_crawl and not lp.can_walk:
		abilities.append(tr("ползает"))
	if lp.can_swim:
		abilities.append(tr("плавает"))
	if lp.can_fly:
		abilities.append(tr("летает"))
	elif lp.can_glide:
		abilities.append(tr("планирует"))
	if lp.can_jump:
		abilities.append(tr("прыгает на %.1f м") % lp.jump_height)
	if lp.can_climb:
		abilities.append(tr("лазает"))
	if abilities.is_empty():
		abilities.append(tr("не способно двигаться"))
	var speeds := tr("Ходьба %.1f · бег %.1f · плавание %.1f · полёт %.1f м/с") % [
		lp.walk_speed if lp.can_walk else lp.crawl_speed, lp.run_speed if lp.can_walk else lp.crawl_speed,
		lp.swim_speed if lp.can_swim else 0.0, lp.fly_speed if lp.can_fly else 0.0]
	var ind := player.individual
	var mf := ind.mass_factor()
	var basal := p.maintenance_rate(ind.body_temp, mf)
	var act := brain_activity()
	var total := basal + p.activity_power(act, ind.body_temp, mf) + player.mover.move_power
	var sp := tr("Скорость сейчас: %.1f м/с (%s)") % [player.mover.speed, tr(_medium_ru(player.mover.medium))]
	return "%s\n%s\n%s\n%s" % [speeds, tr("Умеет: ") + ", ".join(abilities), sp,
		tr("Расход энергии: %.0f Вт (покой %.0f Вт)") % [total, basal]]


func brain_activity() -> float:
	if player.is_possessed():
		return clampf(0.15 + 0.85 * pow(player.mover.effort, 1.3), 0.05, 1.0)
	return player.brain.activity_level() if player.brain != null else 0.1


static func _medium_ru(m: StringName) -> String:
	match m:
		&"water":
			return "вода"
		&"air":
			return "воздух"
	return "суша"


func _update_readout() -> void:
	if readout != null:
		readout.text = capability_text()


# --- Per frame ------------------------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if sim == null:
		return
	sim.step_dt(time.phys_dt, time.bio_dt)
	if controller != null and controller.cam != null:
		var p := controller.cam.camera.global_position
		terrain.update_focus(p)
		flora.update_focus(p)
	_readout_timer -= dt
	if _readout_timer <= 0.0:
		_readout_timer = 0.25
		_update_readout()
