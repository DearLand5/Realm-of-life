extends CanvasLayer
## World HUD: minimal during observation, deep analytics on demand.
##   top bar     — menu, world clock/season/weather/temperature, time controls
##   right rail  — species & evolution, statistics, map layers, journal,
##                 sandbox, experiments, save
##   bottom      — selected creature card
##   sheet       — one analytics/tool page at a time (side sheet / bottom sheet)

const PAGES := {
	&"species": {"icon": &"dna", "label": "Виды и эволюция", "script": "res://src/sim/hud/species_page.gd"},
	&"stats": {"icon": &"chart", "label": "Экология", "script": "res://src/sim/hud/stats_page.gd"},
	&"map": {"icon": &"map", "label": "Карта и слои", "script": "res://src/sim/hud/map_page.gd"},
	&"log": {"icon": &"book", "label": "Журнал", "script": "res://src/sim/hud/log_page.gd"},
	&"sandbox": {"icon": &"flask", "label": "Песочница", "script": "res://src/sim/hud/sandbox_page.gd"},
	&"experiment": {"icon": &"experiment", "label": "Эксперимент", "script": "res://src/sim/hud/experiment_page.gd"},
}

var world: SimWorld
var root: Control
var _surface: Control
var _top: PanelContainer
var _clock: Label
var _weather: Label
var _scale_label: Label
var _pause_btn: IconButton
var _rail: VBoxContainer
var _sheet: PanelContainer
var _sheet_title: Label
var _sheet_body: Control
var _page_id: StringName = &""
var _page: Control
var _card: Control
var _observer_nodes: Array[Control] = []
var _tick := 0.0
var _tutorial: Node
var _layout: Control


func setup(w: SimWorld) -> void:
	world = w
	layer = 10
	root = SafeArea.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	UITheme.attach(root)
	_surface = Control.new()
	_surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_STOP
	# The surface sits behind the panels and receives camera/selection gestures.
	add_child(_surface)
	move_child(_surface, 0)
	var layout := Control.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(layout)
	_layout = layout
	_build_top(layout)
	_build_rail(layout)
	_build_sheet(layout)
	_build_card(layout)
	_build_tutorial()
	world.selection_changed.connect(_on_selection)
	_refresh_clock()


func view_surface() -> Control:
	return _surface


func set_observer_visible(on: bool) -> void:
	for n in _observer_nodes:
		n.visible = on
	if not on:
		_close_sheet()
	_card.visible = on and world.selected != null
	if _tutorial != null and is_instance_valid(_tutorial):
		_tutorial.visible = on
		_place_tutorial.call_deferred()


# --- Top bar ---------------------------------------------------------------------------------

func _build_top(parent: Control) -> void:
	_top = PanelContainer.new()
	_top.theme_type_variation = &"HudPanel"
	_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top.offset_left = 8
	_top.offset_right = -8
	_top.offset_top = 6
	parent.add_child(_top)
	_observer_nodes.append(_top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_top.add_child(row)
	var menu := IconButton.make(&"menu", "", tr("Меню"), &"FlatButton")
	menu.pressed.connect(_open_menu)
	row.add_child(menu)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)
	_clock = Label.new()
	_clock.theme_type_variation = &"HeaderLabel"
	_clock.clip_text = true
	info.add_child(_clock)
	_weather = Label.new()
	_weather.theme_type_variation = &"DimLabel"
	_weather.clip_text = true
	info.add_child(_weather)
	var slower := IconButton.make(&"slow", "", tr("Медленнее"), &"FlatButton")
	slower.pressed.connect(func() -> void: world.time.slower(); _refresh_clock())
	row.add_child(slower)
	_pause_btn = IconButton.make(&"pause", "", tr("Пауза"), &"FlatButton")
	_pause_btn.pressed.connect(func() -> void: world.time.toggle_pause(); _refresh_clock())
	row.add_child(_pause_btn)
	_scale_label = Label.new()
	_scale_label.theme_type_variation = &"ValueLabel"
	_scale_label.custom_minimum_size.x = 64
	_scale_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_scale_label)
	var faster := IconButton.make(&"fast_forward", "", tr("Быстрее"), &"FlatButton")
	faster.pressed.connect(func() -> void: world.time.faster(); _refresh_clock())
	row.add_child(faster)
	var step := IconButton.make(&"step", "", tr("Шаг: +1 час"), &"FlatButton")
	step.pressed.connect(func() -> void: world.time.step_once(); _refresh_clock())
	row.add_child(step)


func _refresh_clock() -> void:
	var t := world.time
	var c := world.state.climate
	_clock.text = "%s · %s" % [world.state.name, t.clock_label()]
	var temp := c.temperature_at(world.cam.pivot)
	_weather.text = "%s · %.0f °C · %s" % [world.weather.label(), temp, tr("ночь") if c.is_night() else tr("день")]
	_scale_label.text = tr("пауза") if t.paused else t.scale_label()
	_pause_btn.icon = Icons.texture(&"play" if t.paused else &"pause", 32)


# --- Right rail & sheet -----------------------------------------------------------------------

func _build_rail(parent: Control) -> void:
	var holder := PanelContainer.new()
	holder.theme_type_variation = &"HudPanel"
	holder.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	holder.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	holder.grow_vertical = Control.GROW_DIRECTION_BOTH
	holder.offset_right = -8
	parent.add_child(holder)
	_observer_nodes.append(holder)
	_rail = VBoxContainer.new()
	_rail.add_theme_constant_override("separation", 4)
	holder.add_child(_rail)
	for id in PAGES:
		var spec: Dictionary = PAGES[id]
		var b := IconButton.make(spec["icon"], "", tr(spec["label"]), &"FlatButton")
		b.pressed.connect(func() -> void: toggle_page(id))
		_rail.add_child(b)
	var save := IconButton.make(&"save", "", tr("Сохранить"), &"FlatButton")
	save.pressed.connect(func() -> void: world.save_world("manual"))
	_rail.add_child(save)


func _build_sheet(parent: Control) -> void:
	_sheet = PanelContainer.new()
	_sheet.theme_type_variation = &"SheetPanel"
	_sheet.visible = false
	parent.add_child(_sheet)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_sheet.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_sheet_title = Label.new()
	_sheet_title.theme_type_variation = &"HeaderLabel"
	_sheet_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_sheet_title)
	var close := IconButton.make(&"close", "", tr("Закрыть"), &"FlatButton")
	close.pressed.connect(_close_sheet)
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_sheet_body = VBoxContainer.new()
	_sheet_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_sheet_body)
	get_viewport().size_changed.connect(_layout_sheet)
	_layout_sheet()


func _portrait() -> bool:
	var s := root.get_viewport_rect().size
	return s.y > s.x


func _layout_sheet() -> void:
	if _sheet == null:
		return
	if _portrait():
		_sheet.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_sheet.anchor_top = 0.42
		_sheet.offset_left = 6
		_sheet.offset_right = -6
		_sheet.offset_top = 0
		_sheet.offset_bottom = -6
	else:
		_sheet.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		_sheet.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_sheet.anchor_left = 0.5
		_sheet.offset_left = 0
		_sheet.offset_right = -84
		_sheet.offset_top = 88
		_sheet.offset_bottom = -8


func toggle_page(id: StringName) -> void:
	if _page_id == id and _sheet.visible:
		_close_sheet()
		return
	open_page(id)


func open_page(id: StringName) -> void:
	_close_sheet()
	var spec: Dictionary = PAGES[id]
	var script: Script = load(spec["script"])
	if script == null:
		return
	_page = script.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sheet_body.add_child(_page)
	_page.setup(world)
	_page_id = id
	_sheet_title.text = tr(spec["label"])
	_sheet.visible = true
	_layout_sheet()
	_place_tutorial.call_deferred()
	if id == &"species":
		tutorial_event(&"evolution_opened")


func _close_sheet() -> void:
	if _page != null and is_instance_valid(_page):
		_page.queue_free()
	_page = null
	_page_id = &""
	if _sheet != null:
		_sheet.visible = false
	_place_tutorial.call_deferred()


# --- Creature card --------------------------------------------------------------------------------

func _build_card(parent: Control) -> void:
	var script: Script = load("res://src/sim/hud/creature_card.gd")
	_card = script.new()
	_card.visible = false
	parent.add_child(_card)
	_card.setup(world)


func _on_selection(a: Node) -> void:
	_card.visible = a != null and world.controller == null
	_card.show_agent(a)
	if a != null:
		tutorial_event(&"creature_selected")
	_place_tutorial.call_deferred()


# --- Tutorial ----------------------------------------------------------------------------------

func _build_tutorial() -> void:
	if not bool(Game.setting("show_tutorial")):
		return
	var script: Script = load("res://src/tutorial/tutorial_overlay.gd")
	if script == null:
		return
	_tutorial = script.new()
	_layout.add_child(_tutorial)
	_tutorial.setup(&"world")


## Short landscape screens: the tutorial card goes between the creature card
## and the side sheet / page rail; with no room for it, it waits hidden.
func _place_tutorial() -> void:
	if _tutorial == null or not is_instance_valid(_tutorial):
		return
	var tut := _tutorial as Control
	var origin := _layout.get_global_rect().position.x
	var left := 8.0
	if _card.visible:
		left = _card.get_global_rect().end.x - origin + 8.0
	var right := _rail.get_global_rect().position.x - origin
	if _sheet.visible:
		right = minf(right, _sheet.get_global_rect().position.x - origin)
	tut.offset_left = left
	var fits := left + tut.get_combined_minimum_size().x <= right - 8.0
	var steps_left: bool = int(_tutorial.get("_index")) < (_tutorial.get("_steps") as Array).size()
	tut.visible = fits and steps_left and world.controller == null


func tutorial_event(id: StringName) -> void:
	if _tutorial != null and is_instance_valid(_tutorial):
		_tutorial.on_event(id)
		_place_tutorial.call_deferred()


# --- Menu ---------------------------------------------------------------------------------------

func _open_menu() -> void:
	var d := ModalDialog.create(tr("Меню мира"), "", &"menu", ModalDialog.SizeClass.SMALL)
	d.add_button(&"save", tr("Сохранить"), &"", &"save")
	d.add_button(&"checkpoint", tr("Контрольная точка"), &"", &"star")
	d.add_button(&"benchmark", tr("Тест производительности"), &"", &"chart")
	d.add_button(&"exit", tr("Выйти в меню"), &"DangerButton", &"exit")
	d.add_button(&"cancel", tr("Продолжить"), &"AccentButton", &"play")
	d.button_pressed.connect(_on_menu_button)
	d.open(UIOverlay.dialog_host())


func _on_menu_button(id: StringName) -> void:
	match id:
		&"save":
			world.save_world("manual")
		&"checkpoint":
			world.save_world("checkpoint:день_%d" % world.state.day())
		&"exit":
			world.exit_to_menu()
		&"benchmark":
			_run_benchmark()


func _run_benchmark() -> void:
	var b := WorldBenchmark.new()
	b.world = world
	world.add_child(b)
	Game.notify(tr("Тест производительности: около 20 секунд, не трогайте экран"), &"info")
	b.finished.connect(func(text: String) -> void:
		b.queue_free()
		print(text)
		LogDialog.show_report(tr("Тест производительности"), text))
	b.run()


func _process(delta: float) -> void:
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		_refresh_clock()
		if _page != null and _page.has_method("refresh"):
			_page.refresh()
		if _card.visible:
			_card.refresh()
