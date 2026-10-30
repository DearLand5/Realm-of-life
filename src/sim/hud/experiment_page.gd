extends VBoxContainer
## Controlled experiment UI: choose ONE parameter to change, duration, run.
## A control copy and a variant copy of the current world are simulated in
## the background; charts compare their populations day by day.

var world: SimWorld
var _var: StringName = &"temperature"
var _value: float = -6.0
var _days: int = 20
var _value_slider: ParamSlider
var _progress: ProgressBar
var _result: VBoxContainer
var _run_btn: IconButton


func setup(w: SimWorld) -> void:
	world = w
	add_theme_constant_override("separation", 8)
	var intro := Label.new()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.theme_type_variation = &"DimLabel"
	intro.text = tr("Мир копируется дважды: контроль остаётся как есть, в варианте меняется один параметр. Обе копии моделируются одинаково, затем сравниваются.")
	add_child(intro)
	var items := []
	for id in ExperimentManager.VARIABLES:
		items.append({"id": id, "label": tr(ExperimentManager.VARIABLES[id]["label"])})
	var pick := EnumPicker.make(tr("Изменяемый параметр"), items, _var, EnumPicker.Mode.SHEET)
	pick.selected.connect(func(id: Variant) -> void:
		_var = StringName(str(id))
		_rebuild_value())
	add_child(pick)
	_value_slider = ParamSlider.make(tr("Значение"), -15.0, 15.0, 0.5, _value)
	_value_slider.value_committed.connect(func(v: float) -> void: _value = v)
	add_child(_value_slider)
	var dur := ParamSlider.make(tr("Длительность"), 5.0, 120.0, 1.0, float(_days), tr("сут"))
	dur.value_committed.connect(func(v: float) -> void: _days = int(v))
	add_child(dur)
	_run_btn = IconButton.make(&"play", tr("Запустить эксперимент"), "", &"AccentButton")
	_run_btn.pressed.connect(_run)
	add_child(_run_btn)
	_progress = ProgressBar.new()
	_progress.max_value = 1.0
	add_child(_progress)
	_result = VBoxContainer.new()
	add_child(_result)
	_rebuild_value()
	refresh()


func _rebuild_value() -> void:
	var spec: Dictionary = ExperimentManager.VARIABLES[_var]
	_value = float(spec["default"])
	var idx := _value_slider.get_index()
	_value_slider.queue_free()
	_value_slider = ParamSlider.make(tr("Значение"), float(spec["min"]), float(spec["max"]), float(spec["step"]), _value)
	_value_slider.value_committed.connect(func(v: float) -> void: _value = v)
	add_child(_value_slider)
	move_child(_value_slider, idx)


func _run() -> void:
	if world.experiment != null and world.experiment.running:
		world.experiment.cancel()
	world.experiment = ExperimentManager.new()
	world.experiment.start(world.snapshot(), _var, _value, _days)
	world.log_intervention("Запущен контролируемый эксперимент: %s, %d сут." % [ExperimentManager.describe(_var, _value), _days],
		{"experiment": str(_var), "value": _value, "days": _days})
	for c in _result.get_children():
		c.queue_free()


func _process(_delta: float) -> void:
	if world.experiment != null:
		_progress.value = world.experiment.progress()
		if world.experiment.finished and _result.get_child_count() == 0:
			_show_results()


func refresh() -> void:
	if world.experiment != null:
		_progress.value = world.experiment.progress()
		_run_btn.text = tr("Перезапустить") if world.experiment.running else tr("Запустить эксперимент")
		if world.experiment.finished and _result.get_child_count() == 0:
			_show_results()


func _show_results() -> void:
	for c in _result.get_children():
		c.queue_free()
	var r := world.experiment.results
	var days: PackedFloat32Array = r["days"]
	for id in r["species"]:
		var e: Dictionary = r["species"][id]
		var ch := LineChart.new()
		ch.title = "%s" % e["name"]
		ch.x_label = tr("сутки")
		ch.custom_minimum_size = Vector2(0, 150)
		ch.x_step = 1.0
		ch.add_series(tr("контроль"), e["control"], Color(0.7, 0.75, 0.8))
		ch.add_series(tr("вариант"), e["variant"], e["color"])
		_result.add_child(ch)
		var td: Dictionary = r["traits"].get(id, {})
		var parts := PackedStringArray()
		for t in td:
			var pair: Array = td[t]
			if absf(float(pair[1]) - float(pair[0])) > 0.01:
				parts.append("%s %.2f→%.2f" % [TraitCatalog.get_def(StringName(t)).get("label", t), float(pair[0]), float(pair[1])])
		if not parts.is_empty():
			var l := Label.new()
			l.theme_type_variation = &"CaptionLabel"
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.text = tr("Признаки (контроль→вариант): ") + ", ".join(parts)
			_result.add_child(l)
	var sum := Label.new()
	sum.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sum.text = world.experiment.summary()
	_result.add_child(sum)
	var apply := IconButton.make(&"check", tr("Применить изменение к миру"), "", &"ChipButton")
	apply.pressed.connect(func() -> void:
		ExperimentManager.apply_change(world.state, world.experiment.variable, world.experiment.value)
		world.log_intervention("Изменение применено к миру: %s." % ExperimentManager.describe(world.experiment.variable, world.experiment.value)))
	_result.add_child(apply)
	if days.size() == 0:
		return
