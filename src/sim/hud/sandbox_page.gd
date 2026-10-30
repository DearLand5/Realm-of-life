extends VBoxContainer
## Sandbox tools: release/remove creatures by tapping the world, population
## multipliers, climate and resource controls, weather, mutation settings,
## isolation of populations, checkpoints and rollback. Every change is logged
## as an intervention (experiment history).

var world: SimWorld
var _species_ids: Array = []
var _species: int = -1


func setup(w: SimWorld) -> void:
	world = w
	add_theme_constant_override("separation", 8)
	var st := world.state
	for d in st.evo.registry.alive():
		_species_ids.append({"id": d.id, "label": d.name})
	if not _species_ids.is_empty():
		_species = int(_species_ids[0]["id"])
	_section(tr("Касание мира"))
	var tool := EnumPicker.make(tr("Инструмент"), [
		{"id": &"select", "label": tr("Выбор")}, {"id": &"release", "label": tr("Заселить")},
		{"id": &"remove", "label": tr("Удалить")}], world.tool_mode)
	tool.selected.connect(func(id: Variant) -> void: world.set_tool(StringName(str(id)), _species))
	add_child(tool)
	var sp := EnumPicker.make(tr("Вид"), _species_ids, _species, EnumPicker.Mode.SHEET)
	sp.selected.connect(func(id: Variant) -> void:
		_species = int(id)
		world.set_tool(world.tool_mode, _species))
	add_child(sp)
	var row := HBoxContainer.new()
	add_child(row)
	for f in [0.5, 2.0]:
		var b := IconButton.make(&"minus" if f < 1.0 else &"plus", tr("Численность ×%s") % str(f), "", &"ChipButton")
		b.pressed.connect(func() -> void: _scale_population(f))
		row.add_child(b)
	_section(tr("Климат и ресурсы"))
	var c := st.climate
	_slider(tr("Температура"), -15.0, 15.0, 0.5, c.sandbox_temp_offset, "°C", func(v: float) -> void:
		c.sandbox_temp_offset = v
		world.log_intervention("Температура изменена на %+.1f °C." % v, {"temp_offset": v}))
	_slider(tr("Влажность"), -0.5, 0.5, 0.05, c.sandbox_moisture_offset, "", func(v: float) -> void:
		c.sandbox_moisture_offset = v
		world.log_intervention("Влажность изменена на %+.2f." % v, {"moisture_offset": v}))
	_slider(tr("Ресурсы растений"), 0.2, 3.0, 0.1, c.sandbox_resource_mult, "×", func(v: float) -> void:
		c.sandbox_resource_mult = v
		world.log_intervention("Рост растений ×%.1f." % v, {"resource_mult": v}))
	var weather_items := []
	for wid in WeatherModel.STATES:
		weather_items.append({"id": wid, "label": WeatherModel.label(wid)})
	var wp := EnumPicker.make(tr("Погода"), weather_items, world.weather.state, EnumPicker.Mode.SHEET)
	wp.selected.connect(func(id: Variant) -> void:
		world.weather.force_weather(StringName(str(id)), true, 8.0)
		world.log_intervention("Погода установлена: %s." % world.weather.label(), {"weather": str(id)}))
	add_child(wp)
	_section(tr("Эволюция"))
	var evo := st.evo
	_slider(tr("Частота мутаций"), 0.0, 6.0, 0.25, float(evo.settings.get("rate", 1.0)), "×", func(v: float) -> void:
		evo.set_mutation_rate(v)
		world.log_intervention("Частота мутаций ×%.2f." % v, {"mutation_rate": v}))
	_slider(tr("Сила мутаций"), 0.2, 3.0, 0.1, float(evo.settings.get("strength", 1.0)), "×", func(v: float) -> void:
		evo.set_mutation_strength(v)
		world.log_intervention("Сила мутаций ×%.1f." % v, {"mutation_strength": v}))
	var cats: Dictionary = evo.settings.get("categories", {})
	var labels := {"anatomy": "Анатомия", "color": "Окраска", "physiology": "Физиология", "life": "Жизненный цикл",
		"behavior": "Поведение", "senses": "Органы чувств", "structure": "Строение тела"}
	for k in labels:
		var t := ToggleRow.make(tr("Мутации: %s") % tr(labels[k]), "", &"dna", bool(cats.get(k, true)))
		t.toggled.connect(func(on: bool) -> void:
			evo.set_category_locked(k, not on)
			world.log_intervention("Мутации «%s» %s." % [labels[k], "разрешены" if on else "запрещены"], {"category": k, "on": on}))
		add_child(t)
	var iso := ToggleRow.make(tr("Изолировать популяции"), tr("Запрещает миграцию между секторами: группы эволюционируют раздельно"), &"lock", not st.pop.migration_enabled)
	iso.toggled.connect(func(on: bool) -> void:
		st.pop.migration_enabled = not on
		world.log_intervention("Изоляция популяций %s." % ("включена" if on else "выключена"), {"isolation": on}))
	add_child(iso)
	_section(tr("Состояния мира"))
	var cp := IconButton.make(&"star", tr("Сохранить контрольную точку"), "", &"ChipButton")
	cp.pressed.connect(func() -> void:
		world.save_world("checkpoint:день_%d" % st.day())
		world.log_intervention("Контрольная точка (день %d)." % st.day()))
	add_child(cp)
	var rb := IconButton.make(&"undo", tr("Откатить к контрольной точке…"), "", &"ChipButton")
	rb.pressed.connect(_rollback)
	add_child(rb)


func _section(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"SubheaderLabel"
	add_child(l)


func _slider(title: String, lo: float, hi: float, step: float, v: float, unit: String, on_commit: Callable) -> void:
	var s := ParamSlider.make(title, lo, hi, step, v, unit)
	s.value_committed.connect(on_commit)
	add_child(s)


func _scale_population(f: float) -> void:
	if _species < 0:
		return
	for p in world.state.pop.pools_of(_species):
		(p as SpeciesPool).count *= f
	var d := world.state.evo.registry.get_species(_species)
	world.log_intervention("Численность вида «%s» ×%s." % [d.name, str(f)], {"species": _species, "factor": f})


func _rollback() -> void:
	var saves := SaveSystem.list_world_saves().filter(func(e: Dictionary) -> bool:
		return str(e["slot"]) == world.slot and str(e["file"]).begins_with("cp_"))
	if saves.is_empty():
		UIApp.notify(tr("Нет контрольных точек этого мира"), &"warning")
		return
	var dlg := ModalDialog.create(tr("Откат к контрольной точке"), tr("Текущее состояние будет заменено выбранным."), &"undo")
	for e in saves:
		var meta: Dictionary = e["meta"]
		var b := Button.new()
		b.text = "%s · %s %d" % [str(e["file"]).get_basename(), tr("день"), int(meta.get("day", 0))]
		b.pressed.connect(func() -> void:
			dlg.close(&"ok")
			Game.goto_scene(Game.SCENE_WORLD, {"load": {"slot": world.slot, "file": e["file"]}}))
		dlg.content.add_child(b)
	dlg.add_button(&"cancel", tr("Отмена"))
	dlg.open(UIOverlay.dialog_host())
