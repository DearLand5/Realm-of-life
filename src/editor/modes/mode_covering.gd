class_name ModeCovering
extends EditorMode
## «Покровы»: up to four covering slots (type, thickness, colours, pattern,
## roughness, iridescence) and the slot assigned to each part.

var _slot := 0
var _summary: VBoxContainer


func build() -> void:
	var plan := ctx.doc.plan()
	_slot = clampi(_slot, 0, plan.coverings.size() - 1)
	var chips := []
	for i in plan.coverings.size():
		chips.append({"id": i, "label": "%d · %s" % [i + 1, CoveringDef.TYPES[plan.coverings[i].type]["label"]]})
	add_child(EditorUI.caption(tr("Слоты покрова (до 4). Каждая часть тела использует один слот."), true))
	add_child(EditorUI.chip_flow(chips, _slot, func(id: Variant) -> void:
		_slot = int(id)
		mark_dirty()
		ensure_built()))
	var ops := []
	if plan.coverings.size() < CoveringDef.MAX_SLOTS:
		ops.append(EditorUI.button(&"plus", tr("Новый слот"), func() -> void:
			ctx.doc.modify(tr("Новый слот покрова"), func(g: Genome) -> void:
				var c := g.body_plan.ensure_covering(g.body_plan.coverings.size())
				c.from_dict(g.body_plan.coverings[0].to_dict()), &"covering", &"structure")
			_slot = ctx.doc.plan().coverings.size() - 1
			mark_dirty()
			ensure_built()))
	if plan.coverings.size() > 1 and _slot == plan.coverings.size() - 1:
		ops.append(EditorUI.button(&"trash", tr("Удалить слот"), func() -> void:
			ctx.doc.modify(tr("Удалить слот покрова"), func(g: Genome) -> void:
				var last := g.body_plan.coverings.size() - 1
				g.body_plan.coverings.remove_at(last)
				for p in g.body_plan.parts:
					if p.covering >= last:
						p.covering = last - 1, &"covering", &"structure")
			_slot = ctx.doc.plan().coverings.size() - 1
			mark_dirty()
			ensure_built()))
	if not ops.is_empty():
		add_child(EditorUI.button_row(ops))
	var c := plan.coverings[_slot]
	var type_items := []
	for t in CoveringDef.TYPES:
		type_items.append({"id": t, "label": tr(CoveringDef.TYPES[t]["label"])})
	var tp := EnumPicker.make(tr("Тип покрова"), type_items, c.type, EnumPicker.Mode.SHEET)
	tp.selected.connect(func(id: Variant) -> void:
		var slot := _slot
		ctx.doc.modify(tr("Тип покрова"), func(g: Genome) -> void: g.body_plan.ensure_covering(slot).type = StringName(id), &"covering", &"structure"))
	add_child(tp)
	var pat_items := []
	for pt in CoveringDef.PATTERNS:
		pat_items.append({"id": pt, "label": tr(CoveringDef.PATTERN_LABELS[pt])})
	var pp := EnumPicker.make(tr("Узор"), pat_items, c.pattern, EnumPicker.Mode.SHEET)
	pp.selected.connect(func(id: Variant) -> void:
		var slot := _slot
		ctx.doc.modify(tr("Узор"), func(g: Genome) -> void: g.body_plan.ensure_covering(slot).pattern = StringName(id), &"covering"))
	add_child(pp)
	add_child(EditorUI.color_field(tr("Основной цвет"), c.color_a,
		func(col: Color) -> void: _live(func(d: CoveringDef) -> void: d.color_a = col),
		func(col: Color) -> void: _commit(tr("Основной цвет"), func(d: CoveringDef) -> void: d.color_a = col)))
	add_child(EditorUI.color_field(tr("Второй цвет"), c.color_b,
		func(col: Color) -> void: _live(func(d: CoveringDef) -> void: d.color_b = col),
		func(col: Color) -> void: _commit(tr("Второй цвет"), func(d: CoveringDef) -> void: d.color_b = col)))
	_slider(tr("Толщина"), 0.1, 4.0, 0.05, c.thickness, "×", 1.0, func(d: CoveringDef, v: float) -> void: d.thickness = v)
	_slider(tr("Масштаб узора"), 0.1, 5.0, 0.05, c.pattern_scale, "×", 1.0, func(d: CoveringDef, v: float) -> void: d.pattern_scale = v)
	_slider(tr("Контраст узора"), 0.0, 1.0, 0.05, c.pattern_contrast, "%", 100.0, func(d: CoveringDef, v: float) -> void: d.pattern_contrast = v)
	_slider(tr("Шероховатость"), -0.5, 0.5, 0.05, c.roughness_bias, "", 1.0, func(d: CoveringDef, v: float) -> void: d.roughness_bias = v)
	_slider(tr("Радужный блеск"), 0.0, 1.0, 0.05, c.iridescence, "%", 100.0, func(d: CoveringDef, v: float) -> void: d.iridescence = v)
	var props := EditorUI.section(tr("Свойства покрова"), &"info", true)
	add_child(props)
	_summary = VBoxContainer.new()
	props.content.add_child(_summary)
	_fill_summary()
	# Per-part slot.
	var sel := ctx.doc.selected_part()
	var asg := EditorUI.section(tr("Слот частей"), &"paw", true)
	add_child(asg)
	if sel == null:
		asg.content.add_child(EditorUI.caption(tr("Выберите часть тела, чтобы назначить ей слот покрова.")))
	else:
		asg.content.add_child(EditorUI.caption(tr("%s: слот %d") % [EditorContext.part_name(sel), sel.covering + 1], false))
		var slots := []
		for i in plan.coverings.size():
			slots.append({"id": i, "label": str(i + 1)})
		asg.content.add_child(EditorUI.chip_flow(slots, sel.covering, func(id: Variant) -> void:
			var ids := ctx.actions_selected()
			ctx.doc.modify(tr("Слот покрова части"), func(g: Genome) -> void:
				for pid in ids:
					var q := g.body_plan.get_part(int(pid))
					if q != null:
						q.covering = int(id), &"covering", &"structure")))
	asg.content.add_child(EditorUI.button(&"layers", tr("Применить слот %d ко всему телу") % (_slot + 1), func() -> void:
		var slot := _slot
		ctx.doc.modify(tr("Покров всего тела"), func(g: Genome) -> void:
			for q in g.body_plan.parts:
				if q.is_spine() or q.kind == &"shell":
					q.covering = slot, &"covering", &"structure"), &"FlatButton"))


func _fill_summary() -> void:
	for ch in _summary.get_children():
		EditorUI.dispose(ch)
	var c := ctx.doc.plan().coverings[_slot]
	_summary.add_child(EditorUI.kv(tr("Теплоизоляция"), "%d %%" % int(c.insulation() * 100.0)))
	_summary.add_child(EditorUI.kv(tr("Броня"), "%d %%" % int(c.armor() * 100.0)))
	_summary.add_child(EditorUI.kv(tr("Удержание воды"), "%d %%" % int(c.water_retention() * 100.0)))
	_summary.add_child(EditorUI.kv(tr("Гибкость"), "%d %%" % int(c.flexibility() * 100.0)))
	_summary.add_child(EditorUI.kv(tr("Масса на м²"), "%s кг" % UIFormat.number(c.mass_per_area(), 1)))
	if bool(c.props().get("needs_moisture", false)):
		_summary.add_child(EditorUI.caption(tr("Высыхает на суше без воды — подходит водным и околоводным видам.")))


func _live(fn: Callable) -> void:
	var slot := _slot
	ctx.doc.live_edit(func(g: Genome) -> void: fn.call(g.body_plan.ensure_covering(slot)))


func _commit(label: String, fn: Callable) -> void:
	_live(fn)
	ctx.doc.commit(label, &"covering")
	if _summary != null:
		_fill_summary()


func _slider(title: String, mn: float, mx: float, st: float, v: float, unit: String, fac: float, setter: Callable) -> void:
	var s := ParamSlider.make(title, mn, mx, st, v, unit)
	s.display_factor = fac
	s.value_changed.connect(func(val: float) -> void: _live(func(d: CoveringDef) -> void: setter.call(d, val)))
	s.value_committed.connect(func(val: float) -> void: _commit(title, func(d: CoveringDef) -> void: setter.call(d, val)))
	add_child(s)
