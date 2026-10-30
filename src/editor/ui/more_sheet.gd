class_name MoreSheet
extends RefCounted
## "More" sheet: rarely used tools (edit, selection, view options, structure
## tree, file actions) so the main screen stays uncluttered.


static func open(ctx: EditorContext, host: Node) -> void:
	var tr_ := TranslationServer
	var d := ModalDialog.create(tr_.translate("Ещё"), "", &"menu", ModalDialog.SizeClass.MEDIUM)
	var close := func() -> void: d.close(&"done")
	var act := func(a: StringName, args: Dictionary = {}) -> Callable:
		return func() -> void:
			d.close(&"done")
			ctx.request(a, args)
	var has_sel := ctx.doc.selected_part() != null
	d.content.add_child(EditorUI.heading(tr_.translate("Правка")))
	var r1 := EditorUI.button_row([
		_btn(&"copy", tr_.translate("Копировать"), act.call(&"copy"), not has_sel),
		_btn(&"load", tr_.translate("Вставить"), act.call(&"paste"), ctx.doc.clipboard.is_empty()),
		_btn(&"duplicate", tr_.translate("Дублировать"), act.call(&"duplicate"), not has_sel)])
	d.content.add_child(r1)
	d.content.add_child(EditorUI.button_row([
		_btn(&"refresh", tr_.translate("Сбросить часть"), act.call(&"reset"), not has_sel),
		_btn(&"symmetry", tr_.translate("Зеркало вкл/выкл"), act.call(&"mirror"), not has_sel),
		_btn(&"trash", tr_.translate("Удалить"), act.call(&"delete"), not has_sel)]))
	d.content.add_child(EditorUI.heading(tr_.translate("Выбор и группы")))
	d.content.add_child(EditorUI.button_row([
		_btn(&"group", tr_.translate("Сгруппировать"), act.call(&"group"), ctx.doc.selection.size() < 2),
		_btn(&"close", tr_.translate("Разгруппировать"), act.call(&"ungroup"), not has_sel),
		_btn(&"lock", tr_.translate("Заблокировать"), act.call(&"lock", {"on": true}), not has_sel),
		_btn(&"unlock", tr_.translate("Разблокировать"), act.call(&"lock", {"on": false}), not has_sel)]))
	d.content.add_child(_btn(&"list", tr_.translate("Структура тела (дерево частей)"), func() -> void:
		d.close(&"tree")
		open_tree(ctx, host), false))
	d.content.add_child(EditorUI.heading(tr_.translate("Вид")))
	d.content.add_child(_toggle(tr_.translate("Рентген"), tr_.translate("Прозрачное тело, видны внутренние органы"), &"eye", ctx.xray, func(on: bool) -> void: ctx.set_xray(on)))
	d.content.add_child(_toggle(tr_.translate("Поле зрения глаз"), "", &"observer", ctx.show_fov, func(on: bool) -> void: ctx.set_show_fov(on)))
	d.content.add_child(_toggle(tr_.translate("Маркеры на сцене"), tr_.translate("Манипуляторы длины, толщины, перемещения и поворота"), &"move", ctx.show_handles, func(on: bool) -> void:
		ctx.show_handles = on
		ctx.view_changed.emit()))
	d.content.add_child(_toggle(tr_.translate("Привязка"), tr_.translate("Ось симметрии, шаг углов, суставы родителя"), &"magnet", ctx.snapping, func(on: bool) -> void: ctx.set_snapping(on)))
	var step := EnumPicker.make(tr_.translate("Шаг угла привязки"), [
		{"id": 5, "label": "5°"}, {"id": 15, "label": "15°"}, {"id": 30, "label": "30°"}, {"id": 45, "label": "45°"}], int(ctx.prefs.angle_step))
	step.selected.connect(func(id: Variant) -> void:
		ctx.prefs.angle_step = float(id)
		ctx.prefs.save())
	d.content.add_child(step)
	d.content.add_child(_toggle(tr_.translate("Пояснения к параметрам"), tr_.translate("Подписи под ползунками"), &"help", ctx.hints, func(on: bool) -> void:
		ctx.hints = on
		ctx.doc.changed.emit(&"history")))
	d.content.add_child(_btn(&"scale", tr_.translate("Вписать существо в экран"), act.call(&"fit"), false))
	d.content.add_child(EditorUI.heading(tr_.translate("Файл")))
	d.content.add_child(EditorUI.button_row([
		_btn(&"folder", tr_.translate("Открыть / новый"), act.call(&"open"), false),
		_btn(&"save", tr_.translate("Сохранить как…"), act.call(&"save_sheet"), false)]))
	d.add_button(&"ok", tr_.translate("Готово"), &"AccentButton")
	d.open()


static func _btn(icon_id: StringName, text: String, cb: Callable, disabled: bool) -> IconButton:
	var b := IconButton.make(icon_id, text)
	b.pressed.connect(cb)
	b.disabled = disabled
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


static func _toggle(title: String, desc: String, icon_id: StringName, on: bool, cb: Callable) -> ToggleRow:
	var t := ToggleRow.make(title, desc, icon_id, on)
	t.toggled.connect(cb)
	return t


## Tree of all parts with indentation; tap selects.
static func open_tree(ctx: EditorContext, host: Node) -> void:
	var d := ModalDialog.create(TranslationServer.translate("Структура тела"), "", &"list", ModalDialog.SizeClass.MEDIUM)
	var plan := ctx.doc.plan()
	var walk: Callable
	walk = func(id: int, depth: int) -> void:
		var p := plan.get_part(id)
		if p == null:
			return
		var txt := EditorContext.part_name(p)
		var tags := ""
		if p.locked:
			tags += " 🔒"
		if p.group >= 0:
			tags += " [%d]" % p.group
		var b := IconButton.make(SelectionBar._kind_icon(p.kind), "%s%s" % [txt, tags], "", &"FlatButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = ctx.doc.is_selected(id)
		b.pressed.connect(func() -> void:
			ctx.doc.select(id)
			d.close(&"picked"))
		var hb := HBoxContainer.new()
		var pad := Control.new()
		pad.custom_minimum_size.x = depth * 22
		hb.add_child(pad)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(b)
		d.content.add_child(hb)
		for c in plan.children_of(id):
			walk.call(c.id, depth + 1)
	walk.call(plan.root_id, 0)
	d.add_button(&"ok", TranslationServer.translate("Закрыть"))
	d.open()
