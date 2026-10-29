class_name TabStrip
extends ScrollContainer
## Big icon tabs (icon above a short label), horizontally scrollable when they
## don't fit; `vertical = true` makes a side rail (landscape tool panels).
##
##   var tabs := TabStrip.new()
##   tabs.add_tab(&"body", &"paw", tr("Тело"))
##   tabs.add_tab(&"genes", &"dna", tr("Гены"))
##   tabs.tab_selected.connect(func(id): _show_page(id))
##   tabs.current = &"body"
##
## Signals: tab_selected(id: StringName) — user taps only.

signal tab_selected(id: StringName)

var vertical: bool = false:
	set(v):
		vertical = v
		_rebuild_box()
## Show labels under icons.
var show_labels: bool = true
## Stretch tabs to fill the strip when they fit.
var fill: bool = true

var current: StringName = &"":
	set(v):
		current = v
		_refresh()

var _box: BoxContainer
var _group := ButtonGroup.new()


func _init() -> void:
	_rebuild_box()


func _rebuild_box() -> void:
	var old := _box
	_box = VBoxContainer.new() if vertical else HBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if vertical else ScrollContainer.SCROLL_MODE_AUTO
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if vertical else ScrollContainer.SCROLL_MODE_DISABLED
	if old != null:
		for b in old.get_children():
			old.remove_child(b)
			_box.add_child(b)
		old.queue_free()
	add_child(_box)


func add_tab(id: StringName, icon_id: StringName, label: String, badge: String = "") -> IconButton:
	var b := IconButton.make(icon_id, label if show_labels else "", label, &"TabButton")
	b.vertical = true
	b.toggle_mode = true
	b.button_group = _group
	b.badge = badge
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta(&"tab_id", id)
	if fill:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void:
		if current != id:
			current = id
			tab_selected.emit(id))
	_box.add_child(b)
	if current == &"":
		current = id
	_refresh()
	return b


func tab_button(id: StringName) -> IconButton:
	for b in _box.get_children():
		if b.get_meta(&"tab_id") == id:
			return b
	return null


func set_badge(id: StringName, badge: String) -> void:
	var b := tab_button(id)
	if b != null:
		b.badge = badge


func _refresh() -> void:
	if _box == null:
		return
	for b in _box.get_children():
		(b as Button).set_pressed_no_signal(b.get_meta(&"tab_id") == current)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _box != null:
		_box.add_theme_constant_override("separation", UITheme.k(self, &"gap"))
		var t := UITheme.k(self, &"touch")
		if vertical:
			custom_minimum_size = Vector2(t * 1.5, 0)
		else:
			custom_minimum_size = Vector2(0, t * 1.4)
