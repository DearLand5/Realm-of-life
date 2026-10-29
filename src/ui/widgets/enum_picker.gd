class_name EnumPicker
extends VBoxContainer
## Touch-friendly choice of one option.
##   SEGMENTED — inline row of chips (best for 2–4 short options);
##   SHEET     — a button showing the current option; tap opens a list of big
##               rows (with icons/descriptions) in a dialog;
##   AUTO      — SEGMENTED when ≤ 4 short options, else SHEET.
##
##   var p := EnumPicker.make(tr("Размер мира"), [
##       {"id": &"small", "label": tr("Малый")}, {"id": &"medium", "label": tr("Средний")},
##       {"id": &"large", "label": tr("Большой"), "icon": &"globe", "description": tr("2 км")}], &"medium")
##   p.selected.connect(func(id): cfg.size = id)
##
## Signals: selected(id) — user choice only.

signal selected(id: Variant)

enum Mode { AUTO, SEGMENTED, SHEET }

var mode: Mode = Mode.AUTO
var title: String = ""
## [{id, label, icon?: StringName, description?: String}]
var items: Array = []
var selected_id: Variant = null:
	set(v):
		selected_id = v
		_refresh()

var _title_label: Label
var _segments: HBoxContainer
var _group := ButtonGroup.new()
var _sheet_button: IconButton


static func make(title_text: String, option_items: Array, current: Variant = null, m: Mode = Mode.AUTO) -> EnumPicker:
	var p := EnumPicker.new()
	p.title = title_text
	p.items = option_items
	p.mode = m
	p.selected_id = current if current != null else (option_items[0]["id"] if not option_items.is_empty() else null)
	return p


## Convenience: items from parallel id/label arrays.
static func items_from(ids: Array, labels: Array) -> Array:
	var out := []
	for i in ids.size():
		out.append({"id": ids[i], "label": str(labels[i]) if i < labels.size() else str(ids[i])})
	return out


func _ready() -> void:
	UITheme.override_const(self, "separation", UITheme.k(self, &"gap"))
	if title != "":
		_title_label = Label.new()
		_title_label.text = title
		add_child(_title_label)
	if _effective_mode() == Mode.SEGMENTED:
		_segments = HBoxContainer.new()
		UITheme.override_const(_segments, "separation", UITheme.k(self, &"gap"))
		add_child(_segments)
		for it in items:
			var b := IconButton.make(it.get("icon", &""), str(it.get("label", "")), str(it.get("description", "")), &"ChipButton")
			b.toggle_mode = true
			b.button_group = _group
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.clip_text = true
			var id: Variant = it.get("id")
			b.set_meta(&"id", id)
			b.pressed.connect(func() -> void: _choose(id))
			_segments.add_child(b)
	else:
		_sheet_button = IconButton.make(&"", "", "", &"")
		_sheet_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_sheet_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_sheet_button.icon_name = &"chevron_down"
		_sheet_button.pressed.connect(_open_sheet)
		add_child(_sheet_button)
	_refresh()


func _effective_mode() -> Mode:
	if mode != Mode.AUTO:
		return mode
	if items.size() > 4:
		return Mode.SHEET
	var chars := 0
	for it in items:
		chars += str(it.get("label", "")).length()
	return Mode.SEGMENTED if chars <= 34 else Mode.SHEET


func label_of(id: Variant) -> String:
	for it in items:
		if it.get("id") == id:
			return str(it.get("label", ""))
	return ""


func _refresh() -> void:
	if _segments != null:
		for b in _segments.get_children():
			(b as Button).set_pressed_no_signal(b.get_meta(&"id") == selected_id)
	if _sheet_button != null:
		_sheet_button.text = label_of(selected_id)


func _choose(id: Variant) -> void:
	if id == selected_id:
		return
	selected_id = id
	selected.emit(id)


func _open_sheet() -> void:
	var d := ModalDialog.create(title if title != "" else tr("Выберите"), "", &"", ModalDialog.SizeClass.SMALL)
	for it in items:
		var id: Variant = it.get("id")
		var row := IconButton.make(it.get("icon", &""), str(it.get("label", "")), "", &"FlatButton")
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.toggle_mode = true
		row.button_pressed = id == selected_id
		if str(it.get("description", "")) != "":
			row.text += "\n" + str(it["description"])
		row.pressed.connect(func() -> void:
			_choose(id)
			d.close(&"picked"))
		d.content.add_child(row)
	d.open()
