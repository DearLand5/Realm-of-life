class_name ModeDiagnostics
extends EditorMode
## «Проверка»: AnatomyDiagnostics grouped by system with icons. Tapping a
## warning highlights the related part on the stage (found by the «part name»
## quoted in the message) and selects it.

const SYSTEMS := {
	&"anatomy": ["Анатомия", &"skull"], &"locomotion": ["Передвижение", &"sprint"],
	&"physiology": ["Физиология", &"heart"], &"senses": ["Чувства", &"eye"], &"rules": ["Правила", &"star"],
}

var _body: VBoxContainer


func build() -> void:
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	add_child(_body)
	_fill()


func on_live() -> void:
	if visible:
		_fill()


func refresh_values() -> void:
	_fill()


func _fill() -> void:
	if _body == null or not is_instance_valid(_body):
		return
	for ch in _body.get_children():
		_body.remove_child(ch)
		EditorUI.dispose(ch)
	var items := ctx.doc.diagnostics
	var v := AnatomyDiagnostics.viability(items)
	var head := Card.make(tr("Жизнеспособность"), &"check")
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = v
	bar.show_percentage = false
	bar.custom_minimum_size.y = 14
	head.content.add_child(bar)
	head.content.add_child(EditorUI.caption(tr("%d%% · критических: %d, предупреждений: %d") % [int(v * 100.0), ctx.doc.critical_count(), ctx.doc.warning_count() - ctx.doc.critical_count()], false))
	head.content.add_child(EditorUI.caption(tr("Диагностика ничего не запрещает: она объясняет, чем грозит выбранное строение.")))
	_body.add_child(head)
	var groups := {}
	for it in items:
		var s: StringName = it["system"]
		if not groups.has(s):
			groups[s] = []
		(groups[s] as Array).append(it)
	var order: Array = SYSTEMS.keys()
	for s in groups:
		if not order.has(s):
			order.append(s)
	for s in order:
		if not groups.has(s):
			continue
		var list: Array = groups[s]
		var info: Array = SYSTEMS.get(s, [str(s), &"info"])
		var worst := &"info"
		for it in list:
			if it["level"] == &"critical" or (it["level"] == &"warning" and worst != &"critical"):
				worst = it["level"]
		var sec := EditorUI.section("%s (%d)" % [tr(str(info[0])), list.size()], StringName(info[1]), worst != &"info" or s == &"anatomy")
		_body.add_child(sec)
		for it in list:
			sec.content.add_child(_row(it))


func _row(it: Dictionary) -> Control:
	var level: StringName = it["level"]
	var text: String = it["text"]
	var b := IconButton.make(EditorUI.level_icon(level), text, "", &"FlatButton")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.clip_text = false
	b.add_theme_color_override("icon_normal_color", EditorUI.level_color(self, level))
	b.add_theme_color_override("icon_hover_color", EditorUI.level_color(self, level))
	var pid := related_part(ctx.doc.plan(), text)
	if pid >= 0:
		b.badge = ""
		b.pressed.connect(func() -> void:
			ctx.hint_part = -1
			ctx.doc.select(pid)
			ctx.hint_part = pid
			ctx.doc.selection_changed.emit()
			ctx.stage_focus.emit(pid))
	else:
		b.disabled = false
	return b


## Part referred to by a «quoted name» in a diagnostics message (-1 if none).
static func related_part(plan: BodyPlan, text: String) -> int:
	var re := RegEx.new()
	re.compile("«([^»]+)»")
	for m in re.search_all(text):
		var name := m.get_string(1)
		for p in plan.parts:
			if EditorContext.part_name(p) == name:
				return p.id
	return -1
