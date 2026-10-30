class_name ModeBiology
extends EditorMode
## «Биология»: habitat, diet, reproduction, metamorphosis / molting / colony,
## key physiological and behavioural traits, fantasy rules (with a badge) and
## the resulting physiology read-out.

const HABITAT := {"land": "Суша", "water": "Вода", "amphibious": "Амфибия"}
const DIET := {"herbivore": "Травоядное", "carnivore": "Хищник", "omnivore": "Всеядное", "scavenger": "Падальщик",
	"detritivore": "Детритофаг", "filter": "Фильтратор", "parasite": "Паразит", "photosynth": "Фотосинтез"}
const REPRO_MODE := {"sexual": "Раздельнополое", "asexual": "Бесполое", "hermaphrodite": "Гермафродит"}
const REPRO_METHOD := {"eggs": "Яйца", "live": "Живорождение", "fission": "Деление", "budding": "Почкование", "spores": "Споры"}
const KEY_TRAITS: Array[StringName] = [&"metabolism", &"endothermy", &"thermal_optimum", &"thermal_tolerance", &"lifespan", &"clutch_size", &"offspring_investment", &"maturity_age"]
const BEHAVIOUR_TRAITS: Array[StringName] = [&"diet_preference", &"aggression", &"boldness", &"sociality", &"curiosity", &"territoriality", &"parental_care", &"activity_phase", &"vigilance", &"learning"]

var _phys: VBoxContainer


func build() -> void:
	var plan := ctx.doc.plan()
	if bool(plan.rule("fantasy")):
		var badge := PanelContainer.new()
		badge.theme_type_variation = &"BadgePanel"
		var bl := Label.new()
		bl.text = tr("ФАНТАЗИЙНЫЙ ВИД — часть биологических правил отключена")
		bl.add_theme_color_override("font_color", UITheme.color(self, &"accent_text"))
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		badge.add_child(bl)
		add_child(badge)
	var env := EditorUI.section(tr("Среда и питание"), &"globe", true)
	add_child(env)
	env.content.add_child(_pick(tr("Среда обитания"), HABITAT, "habitat"))
	env.content.add_child(_pick(tr("Питание"), DIET, "diet"))
	var rep := EditorUI.section(tr("Размножение и развитие"), &"egg", true)
	add_child(rep)
	rep.content.add_child(_pick(tr("Тип размножения"), REPRO_MODE, "reproduction_mode"))
	rep.content.add_child(_pick(tr("Способ"), REPRO_METHOD, "reproduction_method"))
	rep.content.add_child(_toggle(tr("Метаморфоз"), tr("Личинка с другой средой обитания"), "metamorphosis"))
	rep.content.add_child(_toggle(tr("Линька"), tr("Экзоскелет растёт ступенчато"), "molting"))
	rep.content.add_child(_toggle(tr("Колониальность"), tr("Особи держатся скученно"), "colonial"))
	var key := EditorUI.section(tr("Обмен веществ и жизнь"), &"thermometer", true)
	add_child(key)
	for t in KEY_TRAITS:
		key.content.add_child(_trait(t))
	var beh := EditorUI.section(tr("Поведение"), &"observer", false)
	add_child(beh)
	for t in BEHAVIOUR_TRAITS:
		beh.content.add_child(_trait(t))
	var phys := EditorUI.section(tr("Физиология (итог)"), &"chart", true)
	add_child(phys)
	_phys = VBoxContainer.new()
	phys.content.add_child(_phys)
	_fill_phys()
	var fan := EditorUI.section(tr("Фантазийные правила"), &"star", bool(plan.rule("fantasy")))
	add_child(fan)
	fan.content.add_child(EditorUI.caption(tr("Для вымышленных организмов: ослабляют требования реальной биологии. Вид получает пометку «фантазийный»."), true))
	fan.content.add_child(_rule_toggle(tr("Фантазийный вид"), tr("Помечает вид и смягчает диагностику"), "fantasy"))
	fan.content.add_child(_rule_toggle(tr("Не нужен кислород"), tr("Газообмен не требуется"), "ignore_oxygen"))
	fan.content.add_child(_rule_toggle(tr("Игнорирует опору"), tr("Скелет не перегружается (парение)"), "ignore_support"))
	var fe := ParamSlider.make(tr("Бесплатная энергия"), 0.0, 50.0, 0.5, float(plan.rule("free_energy")), tr("Вт/кг"))
	fe.value_changed.connect(func(v: float) -> void: ctx.doc.live_edit(func(g: Genome) -> void: g.body_plan.custom_rules["free_energy"] = v))
	fe.value_committed.connect(func(v: float) -> void:
		ctx.doc.live_edit(func(g: Genome) -> void: g.body_plan.custom_rules["free_energy"] = v)
		ctx.doc.commit(tr("Бесплатная энергия"), &"biology"))
	fan.content.add_child(fe)


func on_live() -> void:
	_fill_phys()


func _fill_phys() -> void:
	if _phys == null or not is_instance_valid(_phys):
		return
	for ch in _phys.get_children():
		_phys.remove_child(ch)
		ch.queue_free()
	var pf := ctx.doc.phenotype.physiology
	_phys.add_child(EditorUI.kv(tr("Базовый обмен"), "%s Вт" % UIFormat.number(pf.bmr_watts, 1)))
	_phys.add_child(EditorUI.kv(tr("Запас энергии"), "%s кДж" % UIFormat.number(pf.max_energy / 1000.0, 0)))
	_phys.add_child(EditorUI.kv(tr("Дыхание"), str({"lungs": "лёгкие", "gills": "жабры", "trachea": "трахеи", "cutaneous": "кожное", "mixed": "смешанное", "none": "нет"}.get(str(pf.respiration), str(pf.respiration)))))
	_phys.add_child(EditorUI.kv(tr("Продолжительность жизни"), tr("%s сут") % UIFormat.number(pf.lifespan / Units.SECONDS_PER_DAY, 0)))
	_phys.add_child(EditorUI.kv(tr("Усвоение: растения / мясо"), "%d%% / %d%%" % [int(float(pf.diet_eff["plant"]) * 100.0), int(float(pf.diet_eff["meat"]) * 100.0)]))
	_phys.add_child(EditorUI.kv(tr("Среда: суша / вода"), "%s / %s" % [tr("да") if pf.habitat_ok["land"] else tr("нет"), tr("да") if pf.habitat_ok["water"] else tr("нет")]))


func _pick(title: String, labels: Dictionary, key: String) -> EnumPicker:
	var items := []
	for k in labels:
		items.append({"id": k, "label": tr(labels[k])})
	var p := EnumPicker.make(title, items, str(ctx.doc.plan().bio(key)), EnumPicker.Mode.SHEET)
	p.selected.connect(func(id: Variant) -> void:
		ctx.doc.modify(title, func(g: Genome) -> void: g.body_plan.biology[key] = str(id), &"biology"))
	return p


func _toggle(title: String, desc: String, key: String) -> ToggleRow:
	var t := ToggleRow.make(title, desc, &"", bool(ctx.doc.plan().bio(key)))
	t.toggled.connect(func(on: bool) -> void:
		ctx.doc.modify(title, func(g: Genome) -> void: g.body_plan.biology[key] = on, &"biology"))
	return t


func _rule_toggle(title: String, desc: String, key: String) -> ToggleRow:
	var t := ToggleRow.make(title, desc, &"", bool(ctx.doc.plan().rule(key)))
	t.toggled.connect(func(on: bool) -> void:
		ctx.doc.modify(title, func(g: Genome) -> void: g.body_plan.custom_rules[key] = on, &"biology", &"structure"))
	return t


func _trait(id: StringName) -> Control:
	var box := VBoxContainer.new()
	box.add_child(TraitSlider.make(ctx, id, &"biology", _fill_phys))
	var d := TraitCatalog.get_def(id)
	var cap := EditorUI.caption(str(d.get("scope", "")))
	cap.add_theme_font_size_override("font_size", 14)
	if ctx.hints:
		box.add_child(cap)
	return box
