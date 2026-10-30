class_name MainMenu
extends Control
## Main menu (scenes/main_menu.tscn). UI is built in code: animated backdrop,
## title, primary actions and a "did you know" card; responsive for portrait
## and landscape, inside the safe area. Dialogs live in src/ui/menu/.
##
## Scene payloads it sends (Game.goto_scene via UIApp.goto_scene):
##   world:  {"new_world": config, "player_species": [uids]} | {"load": {"slot", "file"}}
##           | {"new_world": config, "tutorial": true}
##   editor: {} | {"species_uid": uid} | {"preset": id}

var _continue_btn: Button
var _continue_caption: Label
var _column: VBoxContainer
var _layout: ResponsiveBox
var _tip_card: Card
var _tip_title: Label
var _tip_text: Label
var _tip_term := ""
var _tip_index := 0
var _latest_save: Dictionary = {}
var _rich: Array[IconButton] = []
var _logo: Control
var _title_box: HBoxContainer
var _gap: Control
var _right: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UIOverlay.ensure()
	UITheme.attach(self)
	InputActions.register_defaults()
	_build()
	refresh()
	get_viewport().size_changed.connect(_on_resize)
	_on_resize.call_deferred()


## Re-reads saves (Continue button) — call after dialogs that change saves.
func refresh() -> void:
	var saves := SaveSystem.list_world_saves()
	_latest_save = saves[0] if not saves.is_empty() else {}
	_continue_btn.visible = not _latest_save.is_empty()
	if not _latest_save.is_empty():
		var meta: Dictionary = _latest_save.get("meta", {})
		_continue_caption.text = "%s · %s %s" % [str(meta.get("name", _latest_save.get("slot", ""))), tr("день"),
			UIFormat.integer(int(meta.get("day", 0)))]


func _build() -> void:
	add_child(MenuBackground.new())
	var safe := SafeArea.new()
	safe.extra_margin = 20.0
	add_child(safe)
	_layout = ResponsiveBox.new()
	_layout.layout_changed.connect(func(_v: bool) -> void: _on_resize())
	safe.add_child(_layout)
	_column = VBoxContainer.new()
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_layout.add_child(_column)
	_column.add_child(_build_title())
	_gap = Control.new()
	_column.add_child(_gap)
	var new_world := _rich_button(&"globe", tr("Новый мир"), tr("Сгенерировать планету и заселить её"), &"AccentButton")
	new_world.pressed.connect(func() -> void: NewWorldDialog.new().open())
	_column.add_child(new_world)
	_continue_btn = _rich_button(&"play", tr("Продолжить"), "", &"")
	_continue_caption = _continue_btn.get_meta(&"caption")
	_continue_btn.pressed.connect(_continue)
	_column.add_child(_continue_btn)
	for def in [[&"folder", tr("Загрузить"), _open_load], [&"dna", tr("Редактор существ"), _open_editor],
			[&"library", tr("Библиотека видов"), _open_library], [&"settings", tr("Настройки"), _open_settings],
			[&"help", tr("Обучение"), _open_tutorial], [&"exit", tr("Выход"), _quit]]:
		var b := IconButton.make(def[0], def[1])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(def[2])
		if def[0] == &"exit":
			b.visible = not UIApp.is_mobile()
		_column.add_child(b)
	var right := VBoxContainer.new()
	_right = right
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_END
	_layout.add_child(right)
	_tip_card = _build_tip()
	_tip_card.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(_tip_card)
	var ver := Label.new()
	ver.theme_type_variation = &"CaptionLabel"
	ver.text = "Realm of Life · v%s" % str(ProjectSettings.get_setting("application/config/version", "0.1"))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(ver)


func _build_title() -> Control:
	var box := HBoxContainer.new()
	_title_box = box
	var logo := Logo.new()
	_logo = logo
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(logo)
	var v := VBoxContainer.new()
	UITheme.override_const(v, "separation", 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(v)
	var t := Label.new()
	t.theme_type_variation = &"TitleLabel"
	t.text = "Realm of Life"
	v.add_child(t)
	var sub := Label.new()
	sub.theme_type_variation = &"DimLabel"
	sub.text = tr("Песочница жизни, анатомии и эволюции")
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)
	return box


## Big button with a title and a caption line.
func _rich_button(icon_id: StringName, title: String, caption: String, variation: StringName) -> IconButton:
	var b := IconButton.make(icon_id, "", "", variation)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	UITheme.override_const(v, "separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var tl := Label.new()
	tl.text = title
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tl)
	var cl := Label.new()
	cl.text = caption
	cl.theme_type_variation = &"DimLabel"
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(cl)
	b.set_meta(&"caption", cl)
	b.set_meta(&"title", tl)
	b.set_meta(&"margin", m)
	b.icon_scale = 1.15
	_rich.append(b)
	return b


func _build_tip() -> Card:
	var c := Card.make(tr("Знаете ли вы?"), &"leaf")
	_tip_title = Label.new()
	_tip_title.theme_type_variation = &"AccentLabel"
	c.content.add_child(_tip_title)
	_tip_text = Label.new()
	_tip_text.theme_type_variation = &"DimLabel"
	_tip_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.content.add_child(_tip_text)
	var more := IconButton.make(&"refresh", "", tr("Другой факт"), &"FlatButton")
	more.pressed.connect(func() -> void: _show_tip(_tip_index + 1))
	c.add_action(more)
	var help := IconButton.make(&"help", "", tr("Подробнее"), &"FlatButton")
	help.pressed.connect(func() -> void: HelpPopup.show_term(_tip_term))
	c.add_action(help)
	var terms := Glossary.all_terms()
	_show_tip(int(Time.get_unix_time_from_system() / 3600.0) % maxi(terms.size(), 1))
	return c


func _show_tip(i: int) -> void:
	var terms := Glossary.all_terms()
	if terms.is_empty():
		return
	_tip_index = posmod(i, terms.size())
	_tip_term = terms[_tip_index]
	var e := Glossary.lookup(_tip_term)
	_tip_title.text = str(e.get("title", _tip_term))
	_tip_text.text = str(e.get("text", ""))


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _column != null:
		_on_resize.call_deferred()


func _on_resize() -> void:
	if not is_inside_tree() or _tip_card == null:
		return
	_apply_scale()
	var vp := get_viewport_rect().size
	var portrait := vp.y > vp.x
	var sc := UITheme.scale_of(self)
	var col_w := minf(vp.x - 40.0 * sc, 520.0 * sc) if portrait else 440.0 * sc
	_column.custom_minimum_size.x = col_w
	_column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if portrait else Control.SIZE_FILL
	_column.size_flags_vertical = Control.SIZE_EXPAND_FILL if portrait else Control.SIZE_FILL
	UITheme.override_const(_column, "separation", int(10 * sc))
	_right.size_flags_vertical = Control.SIZE_SHRINK_END if portrait else Control.SIZE_EXPAND_FILL
	_tip_card.custom_minimum_size.x = col_w if portrait else 400.0 * sc
	_tip_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if portrait else Control.SIZE_SHRINK_END
	UITheme.override_const(_layout, "separation", int(24 * sc))


## Sizes and colours that depend on the theme (re-run on live re-theme).
func _apply_scale() -> void:
	var sc := UITheme.scale_of(self)
	_logo.custom_minimum_size = Vector2(72, 72) * sc
	_logo.queue_redraw()
	UITheme.override_const(_title_box, "separation", int(16 * sc))
	_gap.custom_minimum_size.y = 14.0 * sc
	for b in _rich:
		b.custom_minimum_size.y = 68.0 * sc
		var m: MarginContainer = b.get_meta(&"margin")
		UITheme.override_const(m, "margin_left", int(58 * sc))
		UITheme.override_const(m, "margin_right", int(14 * sc))
		var tl: Label = b.get_meta(&"title")
		var cl: Label = b.get_meta(&"caption")
		tl.add_theme_font_override("font", UITheme.bold_font(self))
		if b.theme_type_variation == &"AccentButton":
			var fg := UITheme.color(self, &"accent_text")
			tl.add_theme_color_override("font_color", fg)
			cl.add_theme_color_override("font_color", Color(fg, 0.78))


# --- Actions --------------------------------------------------------------------------

func _continue() -> void:
	if _latest_save.is_empty():
		return
	UIApp.goto_scene("SCENE_WORLD", {"load": {"slot": _latest_save["slot"], "file": _latest_save["file"]}})


func _open_load() -> void:
	var d := LoadDialog.new()
	d.closed.connect(func(_r: StringName) -> void: refresh())
	d.open()


func _open_editor() -> void:
	UIApp.goto_scene("SCENE_EDITOR", {})


func _open_library() -> void:
	SpeciesLibraryDialog.new().open()


func _open_settings() -> void:
	SettingsDialog.new().open()


func _open_tutorial() -> void:
	var cfg := NewWorldDialog.default_config()
	cfg["name"] = tr("Обучение")
	cfg["seed"] = 1
	cfg["size"] = 512.0
	cfg["size_preset"] = "small"
	cfg["procedural_species"] = 4
	UIApp.goto_scene("SCENE_WORLD", {"new_world": cfg, "player_species": [], "tutorial": true})


func _quit() -> void:
	get_tree().quit()


## Round logo: leaf + DNA in an accent ring (private helper).
class Logo:
	extends Control

	func _notification(what: int) -> void:
		if what == NOTIFICATION_THEME_CHANGED:
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var accent := UITheme.color(self, &"accent")
		draw_circle(c, r - 1.0, Color(accent, 0.14), true, -1.0, true)
		draw_arc(c, r - 2.0, 0.0, TAU, 64, Color(accent, 0.8), 2.5, true)
		Icons.draw(self, &"leaf", Rect2(c - Vector2(r, r) * 0.58, Vector2(r, r) * 1.16), accent, 1.1)
