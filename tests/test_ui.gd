extends TestCase
## UI kit: theme at several scales, palettes, icons, formatting, glossary,
## widgets logic (sliders, steppers, lists, toasts, dialogs), layout helpers.

const REQUIRED_ICONS := [
	"play", "pause", "step", "fast_forward", "slow", "undo", "redo", "save", "load", "folder", "settings",
	"close", "back", "plus", "minus", "trash", "copy", "duplicate", "lock", "unlock", "group", "symmetry",
	"eye", "eye_off", "camera", "person", "follow", "observer", "map", "layers", "chart", "dna", "leaf",
	"paw", "bug", "fish", "bird", "sun", "moon", "cloud", "rain", "snow", "wind", "thermometer", "drop",
	"info", "warning", "search", "star", "star_filled", "grid", "magnet", "move", "rotate", "scale", "test",
	"library", "help", "menu", "edit", "check", "home", "experiment",
]

const REQUIRED_TERMS := [
	"метаболизм", "эндотермия", "аллель", "доминантность", "рецессивность", "полигенный признак", "мутация",
	"кроссинговер", "видообразование", "ниша", "трофический уровень", "нагрузка на крыло", "число фруда",
]


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_theme_builds_at_several_scales() -> void:
	for sc in [0.75, 1.0, 1.5, 2.0]:
		for tsc in [0.8, 1.0, 1.6]:
			var t := UITheme.build(sc, tsc)
			check(t != null, "theme built %s/%s" % [sc, tsc])
			var touch := t.get_constant("touch", UITheme.TYPE)
			check(touch == int(round(52.0 * sc)), "touch target scales (%d at %s)" % [touch, sc])
			for type in ["Button", "LineEdit", "OptionButton", "CheckButton"]:
				var sb := t.get_stylebox("normal", type)
				var h := sb.get_minimum_size().y + ThemeDB.fallback_font.get_height(t.default_font_size)
				check(h >= touch - 1, "%s reaches the touch height at %s/%s (%s)" % [type, sc, tsc, h])
			for pair in [["panel", "PanelContainer"], ["panel", "PopupMenu"], ["slider", "HSlider"], ["tab_selected", "TabBar"],
					["panel", "ItemList"], ["fill", "ProgressBar"], ["panel", "TooltipPanel"], ["grabber", "VScrollBar"],
					["panel", "ScrollContainer"]]:
				check(t.has_stylebox(pair[0], pair[1]), "%s/%s styled" % pair)
			check(t.get_icon("checked", "CheckButton") is ShapeTexture, "switch textures")
			check(t.get_font_size("huge", UITheme.TYPE) > t.get_font_size("normal", UITheme.TYPE), "type scale ordered")
	var normal := UITheme.build(1.0, 1.0, false)
	var hc := UITheme.build(1.0, 1.0, true)
	check(normal.get_color("text", UITheme.TYPE) != hc.get_color("text", UITheme.TYPE) or
		normal.get_color("panel", UITheme.TYPE) != hc.get_color("panel", UITheme.TYPE), "high contrast differs")
	check(hc.get_color("panel", UITheme.TYPE).a >= 0.99, "high contrast panels are opaque")
	for v in ["AccentButton", "FlatButton", "DangerButton", "TitleLabel", "CardPanel", "DialogPanel"]:
		check(normal.get_type_variation_base(v) != &"", "variation %s registered" % v)


func test_text_contrast() -> void:
	var tok := UIPalette.tokens(false)
	var text: Color = tok["text"]
	var panel: Color = (tok["panel_strong"] as Color).blend(Color(tok["bg"], 1.0))
	# WCAG relative luminance needs linear RGB.
	var l1 := text.srgb_to_linear().get_luminance() + 0.05
	var l2 := panel.srgb_to_linear().get_luminance() + 0.05
	check(l1 / l2 >= 7.0, "body text contrast ≥ 7:1 (%.1f)" % (l1 / l2))
	var acc: Color = tok["accent"]
	var acc_text: Color = tok["accent_text"]
	check((acc.srgb_to_linear().get_luminance() + 0.05) / (acc_text.srgb_to_linear().get_luminance() + 0.05) >= 4.5, "text on accent ≥ 4.5:1")


func test_palettes() -> void:
	for mode in UIPalette.MODES:
		var p := UIPalette.series(mode)
		check(p.size() == 8, "%s has 8 series colours" % mode)
		var seen := {}
		for c in p:
			seen[c.to_html()] = true
		check(seen.size() == 8, "%s colours distinct" % mode)
		var st := UIPalette.status(mode)
		for k in ["good", "warn", "bad", "info", "neutral"]:
			check(st.has(k), "%s status %s" % [mode, k])
	check(UIPalette.normalize_mode("garbage") == &"none", "unknown mode falls back")
	check(UITheme.palette(&"deuteranopia")[0] == UIPalette.series(&"deuteranopia")[0], "UITheme.palette passthrough")


func test_all_icons_draw() -> void:
	var names := Icons.names()
	for n in REQUIRED_ICONS:
		check(names.has(StringName(n)), "icon %s exists" % n)
	check(names.size() >= 63, "icon count %d" % names.size())
	var canvas := RenderingServer.canvas_create()
	var item := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(item, canvas)
	for n in names:
		for sz in [12.0, 24.0, 64.0]:
			check(Icons.draw_rid(item, n, Rect2(0, 0, sz, sz), Color.WHITE), "icon %s draws at %s" % [n, sz])
		Icons.draw_rid(item, n, Rect2(0, 0, 32, 32), Color(1, 1, 1, 0.4))
		RenderingServer.canvas_item_clear(item)
	check(Icons.has(&"flask") and Icons.resolve(&"book") == &"library", "aliases resolve")
	var t := Icons.texture(&"save", 28)
	check(t.get_width() == 28 and t.get_height() == 28, "IconTexture size")
	t.draw_rect(item, Rect2(0, 0, 40, 40), false)
	for k in ShapeTexture.Kind.values():
		ShapeTexture.make(k, Vector2i(30, 20), Color.WHITE, Color.BLACK, Color.GRAY).draw(item, Vector2.ZERO)
	RenderingServer.free_rid(item)
	RenderingServer.free_rid(canvas)


func test_format() -> void:
	check(UIFormat.number(12345.5, 1) == "12\u00a0345,5", "grouped thousands + decimal comma")
	check(UIFormat.number(1234.0, 0) == "1234", "4-digit numbers stay unsplit (Russian typography)")
	check(UIFormat.number(0.25) == "0,25", "trimmed decimals")
	check(UIFormat.number(-3.0, 0) == "−3", "unicode minus")
	near(float(UIFormat.parse("12,5")), 12.5, 1e-6, "comma parses")
	near(float(UIFormat.parse(" −2.25 ")), -2.25, 1e-6, "minus and spaces")
	check(UIFormat.parse("abc") == null, "invalid → null")
	check(UIFormat.decimals_for_step(0.05) == 2 and UIFormat.decimals_for_step(1.0) == 0, "decimals from step")
	check(UIFormat.plural(1, "вид", "вида", "видов") == "вид", "1 вид")
	check(UIFormat.plural(3, "вид", "вида", "видов") == "вида", "3 вида")
	check(UIFormat.plural(11, "вид", "вида", "видов") == "видов", "11 видов")
	check(UIFormat.plural(22, "вид", "вида", "видов") == "вида", "22 вида")


func test_glossary() -> void:
	for term in REQUIRED_TERMS:
		var e := Glossary.lookup(term)
		check(not e.is_empty() and str(e["text"]).length() > 40, "term %s explained" % term)
	check(Glossary.lookup("АЛЛЕЛЬ")["term"] == "аллель", "case-insensitive")
	check(Glossary.display("число фруда") == "Число Фруда", "proper noun title")
	for term in Glossary.all_terms():
		for s in Glossary.lookup(term)["see"]:
			check(Glossary.has(str(s)), "link %s → %s resolves" % [term, s])


func test_param_slider_snapping_and_commit() -> void:
	var s := ParamSlider.make("Тест", 0.0, 1.0, 0.05, 0.5, "%")
	s.display_factor = 100.0
	_root().add_child(s)
	var changed := []
	var committed := []
	s.value_changed.connect(func(v: float) -> void: changed.append(v))
	s.value_committed.connect(func(v: float) -> void: committed.append(v))
	s.set_value(0.537)
	near(s.value, 0.55, 1e-6, "set_value snaps to step")
	check(changed.is_empty() and committed.is_empty(), "set_value is silent")
	s._field.value_entered.emit(12.0)  # typed "12" (percent)
	near(s.value, 0.1, 1e-6, "typed value divided by display factor and snapped")
	check(committed.size() == 1, "typing commits")
	s._plus.step.emit()
	near(s.value, 0.15, 1e-6, "+ steps")
	check(changed.size() == 2 and committed.size() == 1, "stepping changes; commit waits for release")
	s._plus.hold_released.emit()
	check(committed.size() == 2, "release commits")
	s._field.value_entered.emit(500.0)
	near(s.value, 1.0, 1e-6, "clamped to range")
	s.free()


func test_stepper() -> void:
	var st := Stepper.make(0, 10, 2, 3)
	_root().add_child(st)
	near(st.value, 4.0, 1e-6, "snapped to step from min")
	st._plus.step.emit()
	st._plus.step.emit()
	st._plus.step.emit()
	st._plus.step.emit()
	near(st.value, 10.0, 1e-6, "clamped at max")
	check(st._plus.disabled, "+ disabled at max")
	st.free()


func test_search_list_filter_and_favorites() -> void:
	var l := SearchList.new()
	_root().add_child(l)
	l.set_items([
		{"id": 1, "title": "Болотная квакша", "subtitle": "амфибия"},
		{"id": 2, "title": "Луговой олень", "favorite": true, "tags": ["травоед"]},
		{"id": 3, "title": "Рысь", "subtitle": "хищник"},
	])
	check(l._rows.get_child_count() == 3, "all rows")
	check((l._rows.get_child(0) as ListRow).item_id == 2, "favourites first")
	l.set_filter_text("КВАК")
	check(l._rows.get_child_count() == 1, "case-insensitive Cyrillic filter")
	l.set_filter_text("травоед")
	check(l._rows.get_child_count() == 1 and (l._rows.get_child(0) as ListRow).item_id == 2, "tags searched")
	l.set_filter_text("zzz")
	check(l._rows.get_child_count() == 0 and l._empty.visible, "empty state")
	l.set_filter_text("")
	var activated := []
	l.item_activated.connect(func(id: Variant) -> void: activated.append(id))
	l._on_tap(3)
	check(l.selected_id == 3 and activated.is_empty(), "first tap selects")
	l._on_tap(3)
	check(activated == [3], "tap on selected activates")
	l.free()


func test_toasts_from_event_bus() -> void:
	var t := ToastLayer.new()
	_root().add_child(t)
	UIApp.notify("Проверка", &"warning")
	UIApp.notify("Проверка", &"warning")
	UIApp.notify("Другое", &"error")
	check(t._box.get_child_count() == 2, "duplicates collapse (%d)" % t._box.get_child_count())
	check(int(t._box.get_child(0).get_meta(&"count", 1)) == 2, "counter")
	for i in 6:
		t.show_toast("Сообщение %d" % i)
	check(t._box.get_child_count() <= ToastLayer.MAX_VISIBLE, "stack limited")
	t.free()


func test_modal_dialog_builds() -> void:
	var host := Control.new()
	host.size = Vector2(720, 1280)
	_root().add_child(host)
	var d := ModalDialog.create("Удалить?", "Текст", &"warning", ModalDialog.SizeClass.SMALL)
	var pressed := []
	d.button_pressed.connect(func(id: StringName) -> void: pressed.append(id))
	d.add_button(&"cancel", "Отмена")
	var ok := d.add_button(&"ok", "Да", &"DangerButton", &"", false)
	d.open(host)
	check(ModalDialog.top() == d, "dialog on top of the stack")
	ok.pressed.emit()
	check(pressed == [&"ok"], "button id reported")
	var nw := NewWorldDialog.new()
	nw.library_entries = [{"uid": "u1", "name": "Вид"}]
	nw.dry_run = true
	nw.open(host)
	var p := nw.payload()
	for k in ["name", "seed", "size", "size_preset", "relief", "vegetation", "biome_diversity", "temperature_offset",
			"moisture_offset", "procedural_species", "rivers"]:
		check((p["new_world"] as Dictionary).has(k), "new world config has %s" % k)
	check(p["player_species"] is Array, "player species list")
	host.free()


func test_layout_helpers() -> void:
	check(ResponsiveBox.wants_vertical(Vector2(720, 1280), 700, 0.0, false), "portrait → vertical")
	check(not ResponsiveBox.wants_vertical(Vector2(1280, 720), 1200, 0.0, false), "landscape → row")
	check(ResponsiveBox.wants_vertical(Vector2(1280, 720), 500, 600.0, false), "breakpoint → vertical")
	check(UIOverlay.content_size_for(Vector2(1080, 2400), Vector2i(1280, 720)) == Vector2i(720, 1280), "portrait base transposed")
	check(UIOverlay.content_size_for(Vector2(2400, 1080), Vector2i(1280, 720)) == Vector2i(1280, 720), "landscape base kept")
	SafeArea.debug_insets = Vector4(0, 30, 0, 20)
	var c := Control.new()
	_root().add_child(c)
	check(SafeArea.insets_for(c) == Vector4(0, 30, 0, 20), "debug insets applied")
	SafeArea.debug_insets = Vector4.ZERO
	c.free()
	near(ChartBase.nice_step(0.37), 0.5, 1e-6, "nice step 0.5")
	near(ChartBase.nice_step(230.0), 200.0, 1e-6, "nice step 200")


func test_charts_draw_data() -> void:
	var h := UIGallery.sample_history(60)
	var charts: Array = [LineChart.new(), BarChart.new(), StackedAreaChart.new()]
	for ch in charts:
		var chart := ch as ChartBase
		chart.size = Vector2(400, 240)
		chart.add_series("A", h["prey"])
		chart.add_series("B", h["pred"])
		_root().add_child(chart)
		chart.scrub_index = 10
		var rows: Array = chart._readout(10)
		check(rows.size() >= 2, "%s read-out rows" % chart.get_class())
		chart.free()
