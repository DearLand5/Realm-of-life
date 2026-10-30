class_name EditorUI
extends RefCounted
## Small widget factories shared by the editor panels (keeps the mode pages
## short and visually consistent).


static func caption(text: String, dim: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.theme_type_variation = &"DimLabel" if dim else &"SubheaderLabel"
	return l


static func heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"SubheaderLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(icon_id: StringName, text: String, cb: Callable, variation: StringName = &"", tip: String = "") -> IconButton:
	var b := IconButton.make(icon_id, text, tip, variation)
	b.pressed.connect(cb)
	return b


## Row of equally wide buttons.
static func button_row(buttons: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	for b in buttons:
		(b as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(b)
	return h


## Wrapping row of chips: items [{id, label, icon?}], one selected.
static func chip_flow(items: Array, selected: Variant, on_pick: Callable) -> HFlowContainer:
	var f := HFlowContainer.new()
	var group := ButtonGroup.new()
	for it in items:
		var b := IconButton.make(it.get("icon", &""), str(it["label"]), str(it.get("tip", "")), &"ChipButton")
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = it["id"] == selected
		var id: Variant = it["id"]
		b.pressed.connect(func() -> void: on_pick.call(id))
		f.add_child(b)
	return f


## "label ........ value" line.
static func kv(label_text: String, value_text: String, value_role: StringName = &"") -> HBoxContainer:
	var h := HBoxContainer.new()
	var a := Label.new()
	a.text = label_text
	a.theme_type_variation = &"DimLabel"
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var b := Label.new()
	b.text = value_text
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if value_role != &"":
		b.theme_type_variation = value_role
	h.add_child(a)
	h.add_child(b)
	return h


static func section(title: String, icon_id: StringName = &"", open: bool = true) -> Collapsible:
	return Collapsible.make(title, icon_id, open)


## Level → (icon, theme colour name).
static func level_icon(level: StringName) -> StringName:
	match level:
		&"critical":
			return &"error"
		&"warning":
			return &"warning"
	return &"info"


static func level_color(c: Control, level: StringName) -> Color:
	var st := UITheme.status_colors()
	match level:
		&"critical":
			return st["bad"]
		&"warning":
			return st["warn"]
	return st["info"]


## Colour swatch button; opens a picker dialog. `on_live(color)` while dragging,
## `on_commit(color)` when finished.
static func color_field(title: String, current: Color, on_live: Callable, on_commit: Callable) -> Control:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = title
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(l)
	var b := IconButton.make(&"", "", title, &"ChipButton")
	b.custom_minimum_size = Vector2(96, 0)
	var sw := ColorRect.new()
	sw.color = current
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sw.set_anchors_preset(Control.PRESET_FULL_RECT)
	sw.offset_left = 10
	sw.offset_right = -10
	sw.offset_top = 10
	sw.offset_bottom = -10
	b.add_child(sw)
	b.set_meta(&"swatch", sw)
	b.pressed.connect(func() -> void:
		var d := ModalDialog.create(title, "", &"", ModalDialog.SizeClass.SMALL)
		var cp := ColorSwatchPicker.new()
		cp.color = sw.color
		cp.color_changed.connect(func(c: Color) -> void:
			sw.color = c
			on_live.call(c))
		cp.color_committed.connect(func(c: Color) -> void:
			sw.color = c
			on_commit.call(c))
		d.content.add_child(cp)
		d.add_button(&"ok", TranslationServer.translate("Готово"), &"AccentButton")
		d.open())
	h.add_child(b)
	return h


## Single row of buttons that scrolls sideways (saves vertical space on phones).
static func h_scroll_row(buttons: Array) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	for b in buttons:
		h.add_child(b)
	sc.add_child(h)
	sc.custom_minimum_size.y = 58.0
	return sc
