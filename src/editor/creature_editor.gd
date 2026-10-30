class_name CreatureEditor
extends Control
## Creature editor scene root (scenes/creature_editor.tscn). The UI is built
## in code: a full-screen 3D stage with an HUD of panels around it —
## top bar (navigation, undo/redo, symmetry, gesture mode, test, save), mode
## rail, context sheet (side sheet in landscape, bottom sheet in portrait) and
## a live stats strip.
##
## Scene payload (Game.take_pending()):
##   {"species_uid": uid} | {"preset": id} | {"genome": dict} | {} (start picker)
## Test button: goes to res://scenes/test_arena.tscn with
##   {"genome": dict, "return_to": "editor"} when that scene exists, otherwise
## runs the in-editor turntable test.

## Tutorial hooks: editor_shape_changed, editor_part_added, editor_diagnostics_opened,
## editor_biology_changed, species_saved.
signal tutorial_event(id: StringName)

const ARENA_SCENE := "res://scenes/test_arena.tscn"
const SHEET_PORTRAIT_FRACTIONS := [0.0, 0.46, 0.68]

var ctx: EditorContext
var doc: EditorDocument
var stage: EditorStage
var handles: HandleOverlay
var gestures: EditorGestures
## Skip the start picker for empty payloads (tools and tests).
var auto_start_picker := true

var _surface: Control
var _topbar: PanelContainer
var _top_row: HBoxContainer
var _name_btn: IconButton
var _undo: IconButton
var _redo: IconButton
var _sym: IconButton
var _gesture_btn: IconButton
var _rail: TabStrip
var _sheet: PanelContainer
var _sel_bar: SelectionBar
var _mode_title: Label
var _scroll: ScrollContainer
var _pages_box: VBoxContainer
var _stats: StatsStrip
var _sheet_toggle: IconButton
var _sheet_state := 1
var _pages := {}
var _test_panel: PanelContainer
var _test_label: Label
var _hint: Label
var _layout_queued := false
var _live_dirty := false
var _live_timer := 0.0
var _fitted := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UIOverlay.ensure()
	UITheme.attach(self)
	InputActions.register_defaults()
	var prefs := EditorPrefs.load_prefs()
	doc = EditorDocument.new(_initial_genome())
	ctx = EditorContext.new(doc, prefs)
	_build()
	ctx.action_requested.connect(_on_action)
	ctx.toast.connect(func(t: String, l: StringName) -> void: UIApp.notify(t, l))
	ctx.tutorial_event.connect(func(id: StringName) -> void: tutorial_event.emit(id))
	doc.edited.connect(_on_edited)
	doc.changed.connect(_on_doc_changed)
	doc.selection_changed.connect(_on_selection_changed)
	ctx.mode_changed.connect(_on_mode_changed)
	ctx.view_changed.connect(_sync_toggles)
	ctx.stage_focus.connect(func(id: int) -> void: stage.focus_part(id))
	get_viewport().size_changed.connect(_queue_layout)
	_on_mode_changed(ctx.mode)
	_sync_toggles()
	_layout.call_deferred()
	if _is_empty_payload and auto_start_picker:
		_open_start.call_deferred()
	_attach_tutorial()


## Interactive tutorial hints (steps 1–5) fed by the editor's tutorial events.
func _attach_tutorial() -> void:
	if not bool(UIApp.setting("show_tutorial", true)):
		return
	var overlay: Control = load("res://src/tutorial/tutorial_overlay.gd").new()
	add_child(overlay)
	overlay.setup(&"editor")
	# Right of the mode rail and below the top bar, so no editor control is covered.
	overlay.offset_left = 112.0 * UITheme.ui_scale()
	overlay.offset_top = 130.0 * UITheme.ui_scale()
	tutorial_event.connect(overlay.on_event)


var _is_empty_payload := true


func _initial_genome() -> Genome:
	var g: Node = UIApp.game()
	var pend: Dictionary = g.call(&"take_pending") if g != null else {}
	if pend.has("species_uid"):
		var loaded := SpeciesLibrary.load_genome(str(pend["species_uid"]))
		if loaded != null:
			_is_empty_payload = false
			_pending_uid = str(pend["species_uid"])
			return loaded
	if pend.has("preset"):
		_is_empty_payload = false
		return BodyPlanPresets.create(StringName(str(pend["preset"])))
	if pend.has("genome") and pend["genome"] is Dictionary:
		_is_empty_payload = false
		# Returning from the test arena keeps the library link and unsaved state.
		_pending_uid = str(pend.get("species_uid", ""))
		_pending_dirty = bool(pend.get("dirty", false))
		return Genome.from_dict(pend["genome"])
	return null


var _pending_uid := ""
var _pending_dirty := false


# --- Construction ---------------------------------------------------------------------------

func _build() -> void:
	stage = EditorStage.new()
	stage.name = "Stage"
	var safe_mode := EditorCrashGuard.begin()
	if safe_mode:
		stage.idle_lod = EditorCrashGuard.SAFE_IDLE_LOD
		UIApp.notify(tr("Прошлое открытие редактора завершилось сбоем — включён облегчённый режим"), &"warning")
	# Cleared a few seconds after the first full mesh is on screen.
	stage.visual_swapped.connect(func() -> void: get_tree().create_timer(3.0).timeout.connect(EditorCrashGuard.done), CONNECT_ONE_SHOT)
	add_child(stage)
	stage.setup(ctx)
	if _pending_uid != "":
		doc.uid = _pending_uid
	doc.dirty = _pending_dirty
	_surface = Control.new()
	_surface.name = "ViewSurface"
	_surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_surface)
	handles = HandleOverlay.new()
	handles.name = "Handles"
	add_child(handles)
	handles.setup(ctx, stage)
	gestures = EditorGestures.new()
	add_child(gestures)
	gestures.setup(ctx, stage, handles, _surface)
	_build_topbar()
	_build_sheet()
	_build_rail()
	_stats = StatsStrip.new()
	_stats.name = "Stats"
	add_child(_stats)
	_stats.setup(ctx)
	_hint = Label.new()
	_hint.theme_type_variation = &"DimLabel"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint)
	_build_test_panel()


func _tb(icon_id: StringName, tip: String, cb: Callable, toggle: bool = false) -> IconButton:
	var b := IconButton.make(icon_id, "", tip, &"HudButton")
	if toggle:
		b.toggle_mode = true
		b.toggled.connect(cb)
	else:
		b.pressed.connect(cb)
	return b


func _build_topbar() -> void:
	_topbar = PanelContainer.new()
	_topbar.theme_type_variation = &"HudPanel"
	_topbar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_topbar)
	_top_row = HBoxContainer.new()
	_topbar.add_child(_top_row)
	_top_row.add_child(_tb(&"back", tr("Назад в меню"), func() -> void: _on_back()))
	_name_btn = IconButton.make(&"edit", "", tr("Название и сохранение"), &"FlatButton")
	_name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name_btn.clip_text = true
	_name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_btn.pressed.connect(func() -> void: ctx.request(&"save_sheet"))
	_top_row.add_child(_name_btn)
	_undo = _tb(&"undo", tr("Отменить"), func() -> void: doc.undo())
	_redo = _tb(&"redo", tr("Повторить"), func() -> void: doc.redo())
	_top_row.add_child(_undo)
	_top_row.add_child(_redo)
	_sym = _tb(&"symmetry", tr("Симметрия: новые парные части создаются зеркально"), func(on: bool) -> void:
		doc.symmetry = on
		ctx.view_changed.emit(), true)
	_top_row.add_child(_sym)
	_gesture_btn = _tb(&"move", tr("Режим жестов: камера / редактирование (палец двигает части)"), func(on: bool) -> void: ctx.set_edit_gesture(on), true)
	_top_row.add_child(_gesture_btn)
	_top_row.add_child(_tb(&"test", tr("Испытать существо"), func() -> void: ctx.request(&"test")))
	_top_row.add_child(_tb(&"save", tr("Сохранить в библиотеку"), func() -> void: ctx.request(&"save")))
	_top_row.add_child(_tb(&"menu", tr("Ещё"), func() -> void: ctx.request(&"more")))


func _build_sheet() -> void:
	_sheet = PanelContainer.new()
	_sheet.theme_type_variation = &"SheetPanel"
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_sheet)
	var v := VBoxContainer.new()
	_sheet.add_child(v)
	var title_row := HBoxContainer.new()
	v.add_child(title_row)
	_mode_title = Label.new()
	_mode_title.theme_type_variation = &"AccentLabel"
	_mode_title.clip_text = true
	_mode_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_mode_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_mode_title)
	_sheet_toggle = IconButton.make(&"chevron_down", "", tr("Размер панели"), &"FlatButton")
	_sheet_toggle.custom_minimum_size = Vector2(44, 44)
	_sheet_toggle.pressed.connect(_cycle_sheet)
	title_row.add_child(_sheet_toggle)
	_sel_bar = SelectionBar.new()
	v.add_child(_sel_bar)
	_sel_bar.setup(ctx)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_pages_box = VBoxContainer.new()
	_pages_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_pages_box)
	# Navigation / duplicate / delete stay pinned at the bottom of the sheet (thumb reach).
	_sel_bar.nav.get_parent().remove_child(_sel_bar.nav)
	v.add_child(_sel_bar.nav)
	var classes := {
		&"shape": ModeShape, &"anatomy": ModeAnatomy, &"limbs": ModeLimbs, &"covering": ModeCovering,
		&"senses": ModeSenses, &"organs": ModeOrgans, &"biology": ModeBiology, &"genetics": ModeGenetics,
		&"diagnostics": ModeDiagnostics,
	}
	for id in classes:
		var page: EditorMode = classes[id].new()
		_pages_box.add_child(page)
		page.setup(ctx)
		page.visible = false
		_pages[id] = page


var _rail_portrait := false


## (Re)creates the mode rail: labelled tabs in portrait, icon-only in landscape
## (nine labelled tabs do not fit the short screen side).
func _build_rail(portrait: bool = false) -> void:
	if _rail != null:
		EditorUI.dispose(_rail)
	_rail_portrait = portrait
	_rail = TabStrip.new()
	_rail.fill = true
	_rail.show_labels = portrait
	_rail.vertical = not portrait
	add_child(_rail)
	for m in EditorContext.MODES:
		var b := _rail.add_tab(m["id"], m["icon"], tr(m.get("short", m["label"])))
		b.tooltip_text = "%s — %s" % [tr(m["label"]), tr(m["tip"])]
	_rail.current = ctx.mode
	_rail.tab_selected.connect(func(id: StringName) -> void: ctx.set_mode(id))
	if portrait:
		# Tighter spacing so all nine labelled tabs fit the phone width.
		(_rail.get_child(0) as BoxContainer).add_theme_constant_override("separation", 2)


func _build_test_panel() -> void:
	_test_panel = PanelContainer.new()
	_test_panel.theme_type_variation = &"HudPanel"
	_test_panel.visible = false
	add_child(_test_panel)
	var v := VBoxContainer.new()
	_test_panel.add_child(v)
	var t := EditorUI.heading(tr("Испытание существа"))
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.add_child(t)
	_test_label = EditorUI.caption("")
	v.add_child(_test_label)
	v.add_child(EditorUI.button(&"back", tr("Вернуться к редактированию"), func() -> void: _stop_test(), &"AccentButton"))


# --- Layout -------------------------------------------------------------------------------------

func _exit_tree() -> void:
	if ctx != null:
		ctx.shutdown()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_queue_layout()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()


func _queue_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	_layout.call_deferred()


func _layout() -> void:
	_layout_queued = false
	if not is_inside_tree() or _topbar == null:
		return
	var vp := size
	var ins := SafeArea.insets_for(self)
	var sc := UITheme.scale_of(self)
	var touch := float(UITheme.k(self, &"touch"))
	var m := 8.0 * sc
	var portrait := vp.y > vp.x
	var top_h := touch + 14.0 * sc
	var left := ins.x + m
	var right := vp.x - ins.z - m
	var top := ins.y + m * 0.5
	var bottom := vp.y - ins.w - m
	_topbar.position = Vector2(left, top)
	_topbar.size = Vector2(right - left, top_h)
	var y0 := top + top_h + m * 0.5
	var stats_h := touch * 0.8 + 12.0 * sc
	if portrait != _rail_portrait:
		_build_rail(portrait)
	var view := Rect2()
	if portrait:
		var rail_h := touch * 1.15 + 6.0 * sc
		var sheet_frac: float = SHEET_PORTRAIT_FRACTIONS[_sheet_state]
		var sel_h := touch * 2.0 + 40.0 * sc
		var sheet_h := sel_h if _sheet_state == 0 else maxf(sel_h + 60.0, (bottom - y0) * sheet_frac + sel_h * 0.0)
		_sheet.position = Vector2(left, bottom - sheet_h)
		_sheet.size = Vector2(right - left, sheet_h)
		_rail.position = Vector2(left, bottom - sheet_h - rail_h - m * 0.5)
		_rail.size = Vector2(right - left, rail_h)
		_stats.position = Vector2(left, y0)
		_stats.size = Vector2(right - left, stats_h)
		view = Rect2(left, y0 + stats_h, right - left, _rail.position.y - y0 - stats_h)
		_scroll.visible = _sheet_state != 0
	else:
		var sheet_w := clampf(vp.x * 0.34, 380.0 * sc, 500.0 * sc)
		var rail_w := touch * 1.3
		_rail.position = Vector2(left, y0)
		_rail.size = Vector2(rail_w, bottom - y0)
		_sheet.position = Vector2(right - sheet_w, y0)
		_sheet.size = Vector2(sheet_w, bottom - y0)
		var vx0 := left + rail_w + m
		_stats.position = Vector2(vx0, bottom - stats_h)
		_stats.size = Vector2(right - sheet_w - m - vx0, stats_h)
		view = Rect2(vx0, y0, right - sheet_w - m - vx0, bottom - stats_h - y0)
		_scroll.visible = true
	_sheet_toggle.visible = portrait
	_sheet_toggle.icon_name = &"chevron_up" if _sheet_state != 2 else &"chevron_down"

	var sh := maxf(_stats.get_combined_minimum_size().y, stats_h)
	_stats.size.y = sh
	if not portrait:
		_stats.position.y = bottom - sh
		view.size.y = _stats.position.y - view.position.y - m * 0.5
	else:
		view.position.y = y0 + sh
		view.size.y = _rail.position.y - view.position.y
	stage.set_view_rect(view)
	if not _fitted:
		_fitted = true
		stage.fit_camera(true)
	var tw := minf(view.size.x - 2.0 * m, 420.0 * sc)
	_test_panel.custom_minimum_size = Vector2(tw, 0)
	_test_label.custom_minimum_size.x = tw - 40.0 * sc
	_test_panel.reset_size()
	_test_panel.position = Vector2(view.get_center().x - tw * 0.5, view.end.y - _test_panel.size.y - m)
	_hint.position = Vector2(view.position.x + m, view.position.y + m)
	_hint.size = Vector2(view.size.x - 2.0 * m, 10)
	_fit_rail_tabs(portrait, touch, sc)


func _fit_rail_tabs(portrait: bool, touch: float, sc: float) -> void:
	var count := EditorContext.MODES.size()
	for m in EditorContext.MODES:
		var b := _rail.tab_button(m["id"])
		if b == null:
			continue
		if not b.has_meta(&"compact"):
			b.set_meta(&"compact", true)
			b.add_theme_constant_override("h_separation", 0)
			b.icon_scale = 0.85
			for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				var sb := b.get_theme_stylebox(st)
				if sb is StyleBoxFlat:
					var c := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
					c.content_margin_top = 3.0 * sc
					c.content_margin_bottom = 3.0 * sc
					if portrait:
						c.content_margin_left = 2.0 * sc
						c.content_margin_right = 2.0 * sc
					b.add_theme_stylebox_override(st, c)
		if portrait:
			b.custom_minimum_size = Vector2(maxf(40.0 * sc, (_rail.size.x - 8.0 * sc * float(count - 1)) / float(count) - 1.0), touch * 1.1)
		else:
			var avail := (_rail.size.y - 8.0 * sc * float(count - 1)) / float(count)
			b.custom_minimum_size = Vector2(touch * 1.1, clampf(avail, 46.0 * sc, touch * 1.2))


func _cycle_sheet() -> void:
	_sheet_state = (_sheet_state + 1) % 3
	_layout()


# --- Reactions -----------------------------------------------------------------------------------

func _on_mode_changed(m: StringName) -> void:
	for id in _pages:
		(_pages[id] as EditorMode).visible = id == m
	var page: EditorMode = _pages[m]
	page.ensure_built()
	_rail.current = m
	var tab := _rail.tab_button(m)
	if tab != null and tab.is_inside_tree():
		_rail.ensure_control_visible.call_deferred(tab)
	var info := PartPanel.mode_info(m)
	_mode_title.text = "%s — %s" % [tr(info["label"]), tr(info["tip"])]
	_sel_bar.visible = m not in [&"biology", &"genetics"]
	_sel_bar.nav.visible = _sel_bar.visible
	_scroll.scroll_vertical = 0
	if m == &"diagnostics":
		ctx.tutorial_event.emit(&"editor_diagnostics_opened")
	if m != &"diagnostics":
		ctx.hint_part = -1
		stage._refresh_highlight()
	if _sheet_state == 0 and _layout_queued == false:
		_sheet_state = 1
		_layout()
	_update_hint()


func _on_selection_changed() -> void:
	for id in _pages:
		(_pages[id] as EditorMode).mark_dirty()
	ctx.segment = clampi(ctx.segment, 0, maxi(0, (doc.selected_part().segments.size() - 1) if doc.selected_part() != null else 0))
	(_pages[ctx.mode] as EditorMode).ensure_built()
	_update_hint()


func _on_doc_changed(reason: StringName) -> void:
	_sync_toggles()
	var page: EditorMode = _pages[ctx.mode]
	match reason:
		&"live":
			_live_dirty = true      # read-outs refresh at <= 10 Hz (see _process)
		&"commit":
			page.refresh_values()
			page.on_live()
			_live_dirty = false
		_:
			for id in _pages:
				(_pages[id] as EditorMode).mark_dirty()
			page.ensure_built()
	_update_hint()


func _process(delta: float) -> void:
	_live_timer -= delta
	if _live_dirty and _live_timer <= 0.0:
		_live_dirty = false
		_live_timer = 0.1
		(_pages[ctx.mode] as EditorMode).on_live()
		_stats.refresh()
		_sel_bar.refresh()


func _on_edited(tag: StringName) -> void:
	match tag:
		&"shape", &"attach", &"params", &"covering", &"undo", &"redo":
			if tag != &"undo" and tag != &"redo":
				ctx.tutorial_event.emit(&"editor_shape_changed")
		&"part_added":
			ctx.tutorial_event.emit(&"editor_part_added")
			ctx.tutorial_event.emit(&"editor_shape_changed")
		&"biology":
			ctx.tutorial_event.emit(&"editor_biology_changed")


func _sync_toggles() -> void:
	if _undo == null:
		return
	_undo.disabled = not doc.can_undo()
	_redo.disabled = not doc.can_redo()
	_sym.set_pressed_no_signal(doc.symmetry)
	_gesture_btn.set_pressed_no_signal(ctx.edit_gesture)
	_gesture_btn.icon_name = &"move" if ctx.edit_gesture else &"camera"
	_name_btn.text = doc.design_name() + (" •" if doc.dirty else "")


func _update_hint() -> void:
	if _hint == null:
		return
	if doc.selected_part() == null:
		_hint.text = tr("Коснитесь части тела, чтобы выбрать её. Двумя пальцами — вращение, масштаб, сдвиг.") if not ctx.edit_gesture else tr("Режим редактирования: перетащите часть по телу. Двумя пальцами — камера.")
	else:
		_hint.text = ""
	_hint.visible = _hint.text != "" and not _test_panel.visible


# --- Actions -------------------------------------------------------------------------------------

var _actions: EditorActions


func _on_action(action: StringName, args: Dictionary) -> void:
	if _actions == null:
		_actions = EditorActions.new(ctx)
	if _actions.run(action, args):
		return
	match action:
		&"catalog":
			CatalogSheet.open(ctx, self)
		&"more":
			MoreSheet.open(ctx, self)
		&"save":
			_save(false)
		&"save_sheet":
			LibrarySheet.open_save(ctx, self)
		&"open":
			LibrarySheet.open_library(ctx, self)
		&"test":
			_test()
		&"fit":
			stage.fit_camera()
		&"back":
			_on_back()
		&"stop_test":
			_stop_test()
		&"load_genome":
			var gen: Genome = args.get("genome")
			if gen != null:
				doc.load_genome(gen, str(args.get("uid", "")))
				stage.fit_camera(true)
				ctx.set_mode(&"shape")


## Desktop shortcuts (touch UI has buttons for everything).
func _unhandled_key_input(event: InputEvent) -> void:
	if EditorShortcuts.handle(ctx, event):
		get_viewport().set_input_as_handled()


func _on_back() -> void:
	if doc.dirty:
		ModalDialog.confirm(self, tr("Выйти из редактора?"), tr("Несохранённые изменения будут потеряны."),
			func() -> void: UIApp.goto_scene("SCENE_MENU"), tr("Выйти"), true)
	else:
		UIApp.goto_scene("SCENE_MENU")


func _save(as_new: bool) -> void:
	if doc.uid == "" and not as_new:
		LibrarySheet.open_save(ctx, self)
		return
	var uid := doc.save_to_library("", as_new)
	if uid == "":
		ctx.notify(tr("Не удалось сохранить вид"), &"error")
		return
	ctx.notify(tr("Вид «%s» сохранён в библиотеке") % doc.design_name(), &"success")
	ctx.tutorial_event.emit(&"species_saved")
	_sync_toggles()


func _test() -> void:
	if ResourceLoader.exists(ARENA_SCENE):
		UIApp.goto_scene(ARENA_SCENE, {"genome": doc.genome.to_dict(), "return_to": "editor",
			"species_uid": doc.uid, "dirty": doc.dirty})
		return
	var lp := doc.phenotype.locomotion
	var m := TestDriver.best_medium(lp)
	var lines := PackedStringArray()
	if lp.can_walk or lp.can_crawl:
		lines.append(tr("Суша: %s м/с%s") % [UIFormat.number(lp.best_land_speed(), 1), tr(" (ползание)") if not lp.can_walk else ""])
	if lp.can_swim:
		lines.append(tr("Вода: %s м/с") % UIFormat.number(lp.swim_speed, 1))
	if lp.can_fly:
		lines.append(tr("Воздух: %s м/с") % UIFormat.number(lp.fly_speed, 1))
	elif lp.can_glide:
		lines.append(tr("Планирование"))
	if lp.can_jump:
		lines.append(tr("Прыжок: %s м") % UIFormat.number(lp.jump_height, 2))
	if lines.is_empty():
		lines.append(tr("Не способно передвигаться — подумайте о конечностях, плавниках или крыльях."))
	_test_label.text = "\n".join(lines)
	_test_panel.visible = true
	handles.visible = false
	stage.driver.start(m)
	stage.cam.focus(Vector3(0.0, 0.5, 0.0), 5.8)
	_layout()


func _stop_test() -> void:
	stage.driver.stop()
	stage.fit_camera()
	_test_panel.visible = false
	handles.visible = true


func _open_start() -> void:
	LibrarySheet.open_library(ctx, self, true)
