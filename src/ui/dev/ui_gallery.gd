class_name UIGallery
extends RefCounted
## Developer gallery of the UI kit (widgets, charts, icons) and sample data for
## previews (tools/preview_ui.gd). Not used by the game itself.


static func sample_species() -> Array:
	return [
		{"uid": "a1", "name": "Луговой олень", "description": "Стадный травоед с ветвистыми рогами", "favorite": true, "modified": "2026-10-28T17:20:00"},
		{"uid": "a2", "name": "Пятнистая рысь", "description": "", "favorite": false, "modified": "2026-10-27T09:05:00"},
		{"uid": "a3", "name": "Болотная квакша", "description": "Влажная кожа, прыгает на 2 м", "favorite": false, "modified": "2026-10-20T12:00:00"},
		{"uid": "a4", "name": "Песчаный червь", "description": "Детритофаг пустынь", "favorite": true, "modified": "2026-10-11T08:30:00"},
		{"uid": "a5", "name": "Стеклокрыл", "description": "Летающее насекомое", "favorite": false, "modified": "2026-09-30T21:10:00"},
	]


static func sample_saves() -> Array:
	return [
		{"slot": "valley", "file": "autosave_1.sav", "meta": {"name": "Долина Туманов", "kind": "autosave", "day": 214, "species": 17, "population": 3842, "saved_at": "2026-10-29T06:12:00"}},
		{"slot": "valley", "file": "world.sav", "meta": {"name": "Долина Туманов", "kind": "manual", "day": 201, "species": 15, "population": 3510, "saved_at": "2026-10-28T19:40:00"}},
		{"slot": "isles", "file": "cp_before_ice.sav", "meta": {"name": "Архипелаг", "kind": "checkpoint:before_ice", "day": 88, "species": 9, "population": 1204, "saved_at": "2026-10-25T11:02:00"}},
		{"slot": "desert", "file": "world.sav", "meta": {"name": "Красная пустыня", "kind": "manual", "day": 31, "species": 4, "population": 162, "saved_at": "2026-10-19T08:47:00"}},
	]


## Predator–prey style histories (deterministic).
static func sample_history(days: int = 120) -> Dictionary:
	var prey := PackedFloat32Array()
	var pred := PackedFloat32Array()
	var plants := PackedFloat32Array()
	for d in days:
		var t := float(d)
		prey.append(420.0 + 180.0 * sin(t * 0.11) + t * 1.2)
		pred.append(60.0 + 35.0 * sin(t * 0.11 - 1.2) + t * 0.15)
		plants.append(900.0 - 120.0 * sin(t * 0.11 + 0.4) - t * 0.8)
	return {"prey": prey, "pred": pred, "plants": plants}


static func _card(title: String, icon: StringName) -> Card:
	var c := Card.make(title, icon)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func _col() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.override_const(v, "separation", 14)
	return v


## Widget gallery (designed for a 1600×1080 canvas).
static func build_widgets() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	UITheme.attach(root)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = UIPalette.tokens()["bg"]
	root.add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		UITheme.override_const(m, "margin_" + side, 20)
	root.add_child(m)
	var page := VBoxContainer.new()
	UITheme.override_const(page, "separation", 16)
	m.add_child(page)
	var head := HBoxContainer.new()
	head.custom_minimum_size.y = 84
	UITheme.override_const(head, "separation", 14)
	page.add_child(head)
	var hv := VBoxContainer.new()
	hv.alignment = BoxContainer.ALIGNMENT_BEGIN
	head.add_child(hv)
	var ht := Label.new()
	ht.theme_type_variation = &"TitleLabel"
	ht.text = "Realm of Life · UI kit"
	hv.add_child(ht)
	var hs := Label.new()
	hs.theme_type_variation = &"DimLabel"
	hs.text = "Тема · иконки · виджеты · графики · ввод"
	hv.add_child(hs)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UITheme.override_const(cols, "separation", 16)
	page.add_child(cols)
	var c1 := _col()
	var c2 := _col()
	var c3 := _col()
	var c4 := _col()
	for c in [c1, c2, c3, c4]:
		cols.add_child(c)
	c1.size_flags_stretch_ratio = 0.95
	c2.size_flags_stretch_ratio = 1.0
	c3.size_flags_stretch_ratio = 1.2
	c4.size_flags_stretch_ratio = 0.95
	# --- Buttons
	var btn := _card("Кнопки", &"pointer")
	var v := btn.content
	var a := IconButton.make(&"check", "Создать мир", "", &"AccentButton")
	v.add_child(a)
	var row := HBoxContainer.new()
	UITheme.override_const(row, "separation", 8)
	row.add_child(IconButton.make(&"folder", "Открыть"))
	row.add_child(IconButton.make(&"trash", "Удалить", "", &"DangerButton"))
	v.add_child(row)
	var row2 := HBoxContainer.new()
	UITheme.override_const(row2, "separation", 8)
	var play := IconButton.make(&"pause", "", "Пауза")
	play.toggle_mode = true
	play.button_pressed = true
	row2.add_child(play)
	row2.add_child(IconButton.make(&"fast_forward", "", "Быстрее"))
	var layers := IconButton.make(&"layers", "", "Слои", &"FlatButton")
	layers.badge = "3"
	row2.add_child(layers)
	row2.add_child(IconButton.make(&"undo", "", "Отменить", &"FlatButton"))
	row2.add_child(HelpButton.for_term("аллель"))
	v.add_child(row2)
	var chips := HFlowContainer.new()
	UITheme.override_const(chips, "h_separation", 8)
	UITheme.override_const(chips, "v_separation", 8)
	for i in 3:
		var ch := IconButton.make([&"leaf", &"claw", &"paw"][i], ["Травоеды", "Хищники", "Все"][i], "", &"ChipButton")
		ch.toggle_mode = true
		ch.button_pressed = i == 0
		chips.add_child(ch)
	v.add_child(chips)
	c1.add_child(btn)
	# --- Inputs
	var inp := _card("Ввод", &"edit")
	var le := LineEdit.new()
	le.placeholder_text = "Название вида"
	inp.content.add_child(le)
	inp.content.add_child(MenuUI.field("Случайные виды", Stepper.make(0, 40, 1, 8)))
	var pb := ProgressBar.new()
	pb.value = 64
	inp.content.add_child(MenuUI.field("Генерация мира", pb))
	var col := Collapsible.make("Дополнительно", &"sliders", false)
	inp.content.add_child(col)
	c1.add_child(inp)
	# --- Parameters
	var par := _card("Параметры", &"sliders")
	var wing := ParamSlider.make("Нагрузка на крыло", 1.0, 40.0, 0.5, 12.5, "кг/м²")
	wing.help_term = "нагрузка на крыло"
	par.content.add_child(wing)
	var temp := ParamSlider.make("Температура", -15.0, 15.0, 0.5, 3.5, "°C")
	par.content.add_child(temp)
	par.content.add_child(ToggleRow.make("Эндотермия", "Тёплая кровь: активность в холоде", &"thermometer", true))
	par.content.add_child(ToggleRow.make("Симметрия", "Зеркалить правки", &"symmetry", false))
	par.content.add_child(EnumPicker.make("", EnumPicker.items_from(["s", "m", "l"], ["Малый", "Средний", "Большой"]), "m"))
	c2.add_child(par)
	var tabs := TabStrip.new()
	tabs.add_tab(&"body", &"paw", "Тело")
	tabs.add_tab(&"genes", &"dna", "Гены", "2")
	tabs.add_tab(&"color", &"leaf", "Окраска")
	tabs.add_tab(&"test", &"test", "Тест")
	var tc := _card("Вкладки", &"grid")
	tc.content.add_child(tabs)
	c2.add_child(tc)
	# --- Charts
	var h := sample_history()
	var lc := LineChart.new()
	lc.title = "Численность"
	lc.x_label = "день"
	lc.add_series("Олени", h["prey"])
	lc.add_series("Рыси", h["pred"])
	lc.custom_minimum_size = Vector2(0, 230)
	lc.scrub_index = 74
	lc.name = "Line"
	var bc := BarChart.new()
	bc.title = "Рацион"
	bc.categories = PackedStringArray(["Травы", "Листья", "Семена", "Мясо", "Падаль"])
	bc.add_series("Доля", PackedFloat32Array([42, 23, 15, 12, 8]))
	bc.y_unit = "%"
	bc.custom_minimum_size = Vector2(0, 180)
	var sc := StackedAreaChart.new()
	sc.title = "Биомасса по уровням"
	sc.x_label = "день"
	sc.add_series("Растения", h["plants"])
	sc.add_series("Травоеды", h["prey"])
	sc.add_series("Хищники", h["pred"])
	sc.custom_minimum_size = Vector2(0, 220)
	var chart_card := _card("Графики", &"chart")
	for ch2 in [lc, bc, sc]:
		chart_card.content.add_child(ch2)
	c3.add_child(chart_card)
	# --- Colour + list + touch
	var cc := _card("Окраска", &"leaf")
	var cp := ColorSwatchPicker.new()
	cp.color = Color("#3f6b2f")
	cc.content.add_child(cp)
	c4.add_child(cc)
	var lst := _card("Библиотека", &"library")
	var sl := SearchList.new()
	sl.custom_minimum_size = Vector2(0, 196)
	sl.show_search = false
	var items := []
	for e in sample_species().slice(1, 3):
		items.append({"id": e["uid"], "title": e["name"], "subtitle": e["description"], "icon": &"paw", "favorite": e["favorite"]})
	sl.set_items(items)
	sl.select("a2")
	lst.content.add_child(sl)
	c4.add_child(lst)
	var touch := _card("Сенсорное управление", &"pointer")
	var trow := HBoxContainer.new()
	UITheme.override_const(trow, "separation", 12)
	var joy := TouchJoystick.new()
	joy.name = "Joy"
	joy.mode = TouchJoystick.Mode.FIXED
	joy.base_radius = 58
	joy.custom_minimum_size = Vector2(130, 130)
	trow.add_child(joy)
	var bcol := VBoxContainer.new()
	bcol.alignment = BoxContainer.ALIGNMENT_CENTER
	var brow := HBoxContainer.new()
	UITheme.override_const(brow, "separation", 10)
	for def in [[&"jump", "Прыжок"], [&"claw", ""], [&"bird", ""]]:
		var tb := TouchButton.make(def[0], &"", def[1])
		tb.custom_minimum_size = Vector2(76, 76) if def[1] != "" else Vector2(60, 60)
		tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if def[0] == &"bird":
			tb.toggle_mode = true
			tb.toggled_on = true
		brow.add_child(tb)
	bcol.add_child(brow)
	trow.add_child(bcol)
	touch.content.add_child(trow)
	c2.add_child(touch)
	return root


## Called after the first layout pass: puts interactive widgets in a "live" state.
static func after_layout(root: Node) -> void:
	var lc := root.find_child("Line", true, false) as LineChart
	if lc != null:
		lc.scrub_index = 74
		lc.queue_redraw()
	var joy := root.find_child("Joy", true, false) as TouchJoystick
	if joy != null:
		var press := InputEventScreenTouch.new()
		press.pressed = true
		press.index = 3
		press.position = joy.size * 0.5
		joy._gui_input(press)
		var dragev := InputEventScreenDrag.new()
		dragev.index = 3
		dragev.position = joy.size * 0.5 + Vector2(34, -24)
		joy._gui_input(dragev)
	var t := UIOverlay.toasts()
	if t != null:
		t.show_toast("Вид «Луговой олень» сохранён в библиотеку", &"success", 30.0)
		t.show_toast("Засуха: растительности стало на 30 % меньше", &"warning", 30.0)


## Icon sheet: every icon with its id.
static func build_icons() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	UITheme.attach(root)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = UIPalette.tokens()["bg"]
	root.add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		UITheme.override_const(m, "margin_" + side, 18)
	root.add_child(m)
	var v := VBoxContainer.new()
	UITheme.override_const(v, "separation", 10)
	m.add_child(v)
	var head := HBoxContainer.new()
	UITheme.override_const(head, "separation", 12)
	var t := Label.new()
	t.theme_type_variation = &"HeaderLabel"
	t.text = "Иконки Realm of Life"
	head.add_child(t)
	var cnt := Label.new()
	cnt.theme_type_variation = &"DimLabel"
	cnt.text = "%d векторных иконок · рисуются кодом, чёткие в любом масштабе" % Icons.names().size()
	cnt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(cnt)
	v.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 15
	UITheme.override_const(grid, "h_separation", 6)
	UITheme.override_const(grid, "v_separation", 6)
	v.add_child(grid)
	var i := 0
	for n in Icons.names():
		var tile := PanelContainer.new()
		tile.theme_type_variation = &"InsetPanel"
		tile.custom_minimum_size = Vector2(76, 70)
		var tv := VBoxContainer.new()
		UITheme.override_const(tv, "separation", 2)
		tile.add_child(tv)
		var iv := IconView.make(n, 30.0, &"accent" if i % 9 == 0 else &"text")
		iv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tv.add_child(iv)
		var l := Label.new()
		l.text = String(n)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", UIPalette.tokens()["text_dim"])
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size.x = 64
		tv.add_child(l)
		grid.add_child(tile)
		i += 1
	return root
