class_name ModeAnatomy
extends EditorMode
## «Скелет»: joints (swing / twist / stiffness) per segment, muscle groups with
## force / speed / endurance / energy, and internal organs — add, resize,
## x-ray view and fit warnings.

var _fit_bar: ProgressBar
var _fit_label: Label


func build() -> void:
	var xr := ToggleRow.make(tr("Рентген"), tr("Тело прозрачно, видны внутренние органы"), &"eye", ctx.xray)
	xr.toggled.connect(func(on: bool) -> void: ctx.set_xray(on))
	add_child(xr)
	var org := EditorUI.section(tr("Внутренние органы"), &"heart", true)
	add_child(org)
	_fit_label = EditorUI.caption("")
	org.content.add_child(_fit_label)
	_fit_bar = ProgressBar.new()
	_fit_bar.min_value = 0.0
	_fit_bar.max_value = 1.2
	_fit_bar.show_percentage = false
	_fit_bar.custom_minimum_size.y = 12
	org.content.add_child(_fit_bar)
	_fill_fit()
	var organs := ctx.doc.plan().parts_of_kind(&"organ")
	var chips := []
	for p in organs:
		chips.append({"id": p.id, "label": PartSchema.enum_label(str(p.get_param("organ_type"))), "icon": &"heart"})
	if not chips.is_empty():
		org.content.add_child(EditorUI.chip_flow(chips, ctx.doc.selected_id, func(id: Variant) -> void: ctx.doc.select(int(id))))
	org.content.add_child(EditorUI.caption(tr("Добавить орган:")))
	var flow := HFlowContainer.new()
	for t in PartSchema.PARAMS[&"organ"]["organ_type"]["options"]:
		var ot := str(t)
		var b := IconButton.make(&"plus", PartSchema.enum_label(ot), "", &"ChipButton")
		b.pressed.connect(func() -> void: ctx.request(&"add", {"id": "organ_" + ot}))
		flow.add_child(b)
	org.content.add_child(flow)
	add_part_chips([&"torso", &"neck", &"head", &"tail", &"limb", &"fin", &"wing", &"tentacle", &"antenna", &"flagellum", &"cell"], tr("Части с суставами"))
	add_selected_panel(tr("Выберите часть с сегментами, чтобы настроить суставы и мышцы."))
	var all := EditorUI.section(tr("Все мышечные группы"), &"sprint", false)
	add_child(all)
	for g in ctx.doc.muscles:
		var row := VBoxContainer.new()
		row.add_child(EditorUI.heading(g.name))
		row.add_child(EditorUI.kv(tr("Сила / скорость"), "%s Н · %s дл/с" % [UIFormat.number(g.max_force, 0), UIFormat.number(g.speed, 1)]))
		row.add_child(EditorUI.kv(tr("Выносливость / расход"), "%d%% · %s Вт" % [int(g.endurance * 100.0), UIFormat.number(g.energy_cost, 1)]))
		all.content.add_child(row)
	if ctx.doc.muscles.is_empty():
		all.content.add_child(EditorUI.caption(tr("Мышц нет: задайте долю мышц у частей тела.")))


func on_live() -> void:
	_fill_fit()


func _fill_fit() -> void:
	if _fit_bar == null or not is_instance_valid(_fit_bar):
		return
	var st := ctx.doc.phenotype.anatomy.stats
	var cavity := float(st.get("cavity_volume", 0.0))
	var total := 0.0
	for v in (st.get("organ_volume", {}) as Dictionary).values():
		total += float(v)
	var ratio := total / cavity if cavity > 0.0 else 0.0
	_fit_bar.value = ratio
	_fit_label.text = tr("Заполнение полости тела: %d %%") % int(ratio * 100.0) + (tr(" — органы не помещаются!") if ratio > 1.0 else "")
	_fit_label.modulate = Color(1, 0.7, 0.55) if ratio > 1.0 else Color.WHITE
