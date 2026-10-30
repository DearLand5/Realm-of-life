class_name SettingsDialog
extends ModalDialog
## «Настройки»: graphics, interface, camera, sound and touch controls. Every
## change is applied immediately through Game.set_setting (UI scale / text size
## on release, so the dialog doesn't re-layout under the finger); the theme
## re-applies live via ThemeBinder.

const QUALITY := ["auto", "low", "medium", "high"]


func _ready() -> void:
	title = tr("Настройки")
	icon_name = &"settings"
	size_class = SizeClass.MEDIUM
	_build()
	add_button(&"reset", tr("По умолчанию"), &"FlatButton", &"refresh", false).pressed.connect(_ask_reset)
	add_button(&"ok", tr("Готово"), &"AccentButton")
	super()


func _set_s(key: String, value: Variant) -> void:
	UIApp.set_setting(key, value)


func _build() -> void:
	var col := MenuUI.column()
	content.add_child(col)
	# Graphics
	col.add_child(MenuUI.section(tr("Графика"), &"eye"))
	var q := EnumPicker.make(tr("Качество"), [
		{"id": "auto", "label": tr("Авто")}, {"id": "low", "label": tr("Низкое")},
		{"id": "medium", "label": tr("Среднее")}, {"id": "high", "label": tr("Высокое")}],
		str(_val("quality", "auto")), EnumPicker.Mode.SEGMENTED)
	q.selected.connect(func(id: Variant) -> void: _set_s("quality", str(id)))
	col.add_child(q)
	var sh := EnumPicker.make(tr("Материалы существ"), [
		{"id": "auto", "label": tr("Авто")}, {"id": "full", "label": tr("Детальные")},
		{"id": "lite", "label": tr("Простые")}],
		str(_val("creature_shading", "auto")), EnumPicker.Mode.SEGMENTED)
	sh.selected.connect(func(id: Variant) -> void: _set_s("creature_shading", str(id)))
	col.add_child(sh)
	col.add_child(MenuUI.dim_label(tr("«Простые» — облегчённый шейдер тела для телефонов. Включите, если тела существ не видны.")))
	col.add_child(_toggle("battery_saver", tr("Экономия батареи"), tr("Ограничить до 30 кадров в секунду"), &"sun"))
	# Interface
	col.add_child(MenuUI.section(tr("Интерфейс"), &"grid"))
	col.add_child(_slider("ui_scale", tr("Размер интерфейса"), 0.75, 1.75, 0.05, "%", 100.0, true))
	col.add_child(_slider("text_scale", tr("Размер текста"), 0.8, 1.6, 0.05, "%", 100.0, true))
	var cb_items := []
	for m in UIPalette.MODES:
		cb_items.append({"id": String(m), "label": tr(str(UIPalette.MODE_LABELS[m]))})
	var cbm := EnumPicker.make(tr("Цветовое зрение (графики и индикаторы)"), cb_items, str(_val("colorblind_mode", "none")), EnumPicker.Mode.SHEET)
	cbm.selected.connect(func(id: Variant) -> void: _set_s("colorblind_mode", str(id)))
	col.add_child(cbm)
	col.add_child(_toggle("high_contrast", tr("Высокий контраст"), tr("Непрозрачные панели, яркие рамки"), &"eye"))
	col.add_child(_toggle("left_handed", tr("Для левшей"), tr("Зеркально расположить экранные кнопки"), &"symmetry"))
	col.add_child(_toggle("show_tutorial", tr("Подсказки обучения"), "", &"help"))
	# Camera
	col.add_child(MenuUI.section(tr("Камера"), &"camera"))
	col.add_child(_slider("camera_sensitivity", tr("Чувствительность"), 0.2, 3.0, 0.1, "×", 1.0, false))
	col.add_child(_toggle("invert_y", tr("Инвертировать по вертикали"), "", &"move"))
	# Sound
	col.add_child(MenuUI.section(tr("Звук"), &"sound"))
	col.add_child(_slider("music_volume", tr("Музыка"), 0.0, 1.0, 0.05, "%", 100.0, false))
	col.add_child(_slider("sfx_volume", tr("Эффекты"), 0.0, 1.0, 0.05, "%", 100.0, false))
	# Controls
	col.add_child(MenuUI.section(tr("Экранное управление"), &"pointer"))
	col.add_child(MenuUI.dim_label(tr("Перетаскивайте кнопки и меняйте их размер для каждого режима.")))
	var flow := HFlowContainer.new()
	UITheme.override_const(flow, "h_separation", 8)
	UITheme.override_const(flow, "v_separation", 8)
	for m in [&"third_person", &"first_person", &"observer"]:
		var b := IconButton.make(&"edit", ControlLayout.mode_label(m))
		b.pressed.connect(func() -> void: _edit_layout(m))
		flow.add_child(b)
	col.add_child(flow)


func _val(key: String, fallback: Variant) -> Variant:
	return UIApp.setting(key, fallback)


func _toggle(key: String, label: String, desc: String, icon_id: StringName) -> ToggleRow:
	var r := ToggleRow.make(label, desc, icon_id, bool(_val(key, false)))
	r.toggled.connect(func(on: bool) -> void: _set_s(key, on))
	return r


func _slider(key: String, label: String, lo: float, hi: float, step_v: float, unit_text: String, factor: float, on_commit: bool) -> ParamSlider:
	var s := ParamSlider.make(label, lo, hi, step_v, float(_val(key, 1.0)), unit_text)
	s.display_factor = factor
	if on_commit:
		s.value_committed.connect(func(v: float) -> void:
			if not is_equal_approx(float(_val(key, v)), v):
				_set_s(key, v))
	else:
		s.value_changed.connect(func(v: float) -> void: _set_s(key, v))
		s.value_committed.connect(func(v: float) -> void: _set_s(key, v))
	return s


func _edit_layout(mode: StringName) -> void:
	var l := ControlLayout.load_saved()
	var host := get_parent()
	close(&"layout")
	var ed := LayoutEditor.open_for(l, mode, host)
	ed.closed.connect(func(saved: bool) -> void:
		if saved:
			UIApp.notify(tr("Раскладка сохранена"), &"success"))


func _ask_reset() -> void:
	ModalDialog.confirm(get_parent(), tr("Сбросить настройки?"), tr("Все параметры вернутся к значениям по умолчанию."),
		_reset, tr("Сбросить"), true)


func _reset() -> void:
	var g := UIApp.game()
	if g == null:
		return
	var defaults: Dictionary = g.get("DEFAULT_SETTINGS")
	for k in defaults:
		UIApp.set_setting(str(k), defaults[k])
	UIApp.set_setting("high_contrast", false)
	close(&"reset")
	SettingsDialog.new().open(get_parent())
