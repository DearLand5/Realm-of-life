extends PanelContainer
## Selected-creature card: individual state, needs, current behaviour,
## genetics, and buttons to follow / control in 1st or 3rd person.

const NEEDS := [
	["hunger", "Голод"], ["thirst", "Жажда"], ["fatigue", "Усталость"], ["fear", "Страх"],
	["temperature_discomfort", "Терморегуляция"], ["mate", "Размножение"],
]

var world: SimWorld
var agent: Node
var _title: Label
var _subtitle: Label
var _action: Label
var _bars := {}
var _vitals: Label


func setup(w: SimWorld) -> void:
	world = w
	theme_type_variation = &"CardPanel"
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = 8
	offset_bottom = -8
	custom_minimum_size.x = 360
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var tbox := VBoxContainer.new()
	tbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tbox)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	tbox.add_child(_title)
	_subtitle = Label.new()
	_subtitle.theme_type_variation = &"DimLabel"
	tbox.add_child(_subtitle)
	var close := IconButton.make(&"close", "", tr("Снять выбор"), &"FlatButton")
	close.pressed.connect(func() -> void: world.select(null))
	head.add_child(close)
	_action = Label.new()
	_action.theme_type_variation = &"AccentLabel"
	box.add_child(_action)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	box.add_child(grid)
	for n in NEEDS:
		var l := Label.new()
		l.text = tr(n[1])
		l.theme_type_variation = &"CaptionLabel"
		grid.add_child(l)
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(150, 10)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(bar)
		_bars[n[0]] = bar
	_vitals = Label.new()
	_vitals.theme_type_variation = &"CaptionLabel"
	_vitals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_vitals)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	var follow := IconButton.make(&"follow", tr("Следить"), tr("Камера следует за особью"), &"ChipButton")
	follow.pressed.connect(world.follow_selected)
	row.add_child(follow)
	var fp := IconButton.make(&"person", tr("1-е лицо"), tr("Управлять от первого лица"), &"ChipButton")
	fp.pressed.connect(func() -> void: world.possess(&"first_person"))
	row.add_child(fp)
	var tp := IconButton.make(&"camera", tr("3-е лицо"), tr("Управлять от третьего лица"), &"ChipButton")
	tp.pressed.connect(func() -> void: world.possess(&"third_person"))
	row.add_child(tp)
	var genes := IconButton.make(&"dna", tr("Гены"), tr("Генетика особи"), &"ChipButton")
	genes.pressed.connect(_show_genes)
	row.add_child(genes)


func show_agent(a: Node) -> void:
	agent = a
	refresh()


func refresh() -> void:
	if agent == null or not is_instance_valid(agent):
		visible = false
		return
	var ind: Individual = agent.get("individual")
	var st: Dictionary = agent.get_status() if agent.has_method("get_status") else {}
	var d: SpeciesDef = world.state.evo.registry.get_species(ind.species_id) if ind != null else null
	_title.text = d.name if d != null else tr("Существо")
	var sex := {0: "♀", 1: "♂", 2: "⚥", 3: "—"}
	_subtitle.text = "%s · %s · %s %s · %s %d" % [
		str(sex.get(ind.sex, "")) if ind != null else "", _stage_label(ind.stage if ind != null else &""),
		tr("возраст"), _age_text(float(st.get("age_days", 0.0))), tr("поколение"), ind.generation if ind != null else 0]
	_action.text = "▶ " + str(st.get("action", tr("…")))
	var needs: Dictionary = st.get("needs", {})
	for k in _bars:
		(_bars[k] as ProgressBar).value = clampf(float(needs.get(k, 0.0)), 0.0, 1.0)
	_vitals.text = tr("Энергия %d%% · Здоровье %d%% · Вода %d%% · Тело %.1f °C · Скорость %.1f м/с · Среда: %s") % [
		int(float(st.get("energy_frac", 0.0)) * 100.0), int(float(st.get("health", 1.0)) * 100.0),
		int(float(st.get("hydration", 1.0)) * 100.0), float(st.get("body_temp", 0.0)), float(st.get("speed", 0.0)),
		{&"land": tr("суша"), &"water": tr("вода"), &"air": tr("воздух")}.get(StringName(str(st.get("medium", "land"))), "?")]


static func _stage_label(s: StringName) -> String:
	return {&"egg": "яйцо", &"juvenile": "детёныш", &"adolescent": "подросток", &"adult": "взрослый", &"elder": "старый"}.get(s, str(s))


static func _age_text(days: float) -> String:
	return "%.1f сут" % days if days < 10.0 else "%d сут" % int(days)


func _show_genes() -> void:
	if agent == null or not is_instance_valid(agent):
		return
	var ind: Individual = agent.get("individual")
	if ind == null or ind.genome == null:
		return
	var g := ind.genome
	var dlg := ModalDialog.create(tr("Гены особи"), tr("Аллели каждого локуса (0–1) и выраженное значение. Доминантный аллель проявляется у гетерозигот, рецессивный — только у гомозигот."), &"dna", ModalDialog.SizeClass.LARGE)
	var list := VBoxContainer.new()
	dlg.content.add_child(list)
	for cat in TraitCatalog.CATEGORY_LABELS:
		var head := Label.new()
		head.text = TraitCatalog.CATEGORY_LABELS[cat]
		head.theme_type_variation = &"SubheaderLabel"
		list.add_child(head)
		for id in TraitCatalog.ids_in_category(cat):
			var ti := TraitCatalog.index_of(id)
			var def := TraitCatalog.def_at(ti)
			var pairs := g.trait_alleles(id)
			var al := PackedStringArray()
			for p in pairs:
				al.append("%.2f/%.2f" % [float(p[0]), float(p[1])])
			var l := Label.new()
			l.theme_type_variation = &"CaptionLabel"
			var het := " · гетерозигота" if g.is_heterozygous(id) else ""
			l.text = "%s: %.2f  [%s] — %s%s" % [def["label"], g.value(id), ", ".join(al), TraitCatalog.inheritance_label(ti), het]
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			list.add_child(l)
	if not g.mutation_log.is_empty():
		var mh := Label.new()
		mh.text = tr("Мутации в родословной")
		mh.theme_type_variation = &"SubheaderLabel"
		list.add_child(mh)
		for m in g.mutation_log:
			var ml := Label.new()
			ml.theme_type_variation = &"CaptionLabel"
			ml.text = "%s %d: %s" % [tr("пок."), int(m["gen"]), str(m["text"])]
			list.add_child(ml)
	dlg.add_button(&"ok", tr("Закрыть"), &"AccentButton")
	dlg.open(UIOverlay.dialog_host())
	world.hud.tutorial_event(&"genes_opened")
