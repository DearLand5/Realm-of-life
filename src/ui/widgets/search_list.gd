class_name SearchList
extends VBoxContainer
## Filterable list with favourites: search field, "only favourites" chip and
## finger-sized rows (ListRow). Matches title, subtitle and tags,
## case-insensitively (Cyrillic included).
##
##   var list := SearchList.new()
##   list.row_actions = [{"id": &"dup", "icon": &"duplicate", "tooltip": tr("Дублировать")}]
##   list.set_items([{"id": uid, "title": "Лягушка", "subtitle": "изменён вчера",
##                    "icon": &"leaf", "favorite": true, "tags": ["амфибия"]}])
##   list.item_activated.connect(_open)
##
## Signals:
##   item_selected(id)              — tap (selection changes)
##   item_activated(id)             — tap on the already selected row (so a double
##                                    tap activates), or any tap when `activate_on_tap`
##   favorite_toggled(id, favorite) — star toggled (item dict is updated)
##   action_pressed(id, action)     — a `row_actions` button

signal item_selected(id: Variant)
signal item_activated(id: Variant)
signal favorite_toggled(id: Variant, favorite: bool)
signal action_pressed(id: Variant, action: StringName)

var show_search: bool = true
var show_favorites: bool = true
var favorites_first: bool = true
var activate_on_tap: bool = false
## [{id: StringName, icon: StringName, tooltip: String, variation?: StringName}]
var row_actions: Array = []
var placeholder: String = ""
var empty_text: String = ""
var empty_icon: StringName = &"search"

var selected_id: Variant = null

var _items: Array = []
var _search: LineEdit
var _fav_chip: IconButton
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _empty: VBoxContainer
var _empty_label: Label


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var top := HBoxContainer.new()
	top.name = "Top"
	add_child(top)
	_search = LineEdit.new()
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.clear_button_enabled = true
	_search.right_icon = Icons.texture(&"search", 22)
	_search.text_changed.connect(func(_t: String) -> void: refresh())
	top.add_child(_search)
	_fav_chip = IconButton.make(&"star", "", "", &"ChipButton")
	_fav_chip.toggle_mode = true
	_fav_chip.toggled.connect(func(_on: bool) -> void: refresh())
	top.add_child(_fav_chip)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows)
	_empty = VBoxContainer.new()
	_empty.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty.visible = false
	add_child(_empty)
	var iv := IconView.make(empty_icon, 44.0, &"text_faint")
	iv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_empty.add_child(iv)
	_empty_label = Label.new()
	_empty_label.theme_type_variation = &"DimLabel"
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.add_child(_empty_label)


func _ready() -> void:
	_search.placeholder_text = placeholder if placeholder != "" else tr("Поиск")
	_search.get_parent().visible = show_search or show_favorites
	_search.visible = show_search
	_fav_chip.visible = show_favorites
	_fav_chip.text = tr("Избранное")
	(_empty.get_child(0) as IconView).icon = empty_icon
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _rows != null:
		UITheme.override_const(_rows, "separation", UITheme.k(self, &"gap"))
		UITheme.override_const(self, "separation", UITheme.k(self, &"gap_large"))
		UITheme.override_const(_search.get_parent() as HBoxContainer, "separation", UITheme.k(self, &"gap"))


## Replaces the items (Array of Dictionaries, see class doc).
func set_items(items: Array) -> void:
	_items = items.duplicate()
	refresh()


func items() -> Array:
	return _items


func item(id: Variant) -> Dictionary:
	for it in _items:
		if it.get("id") == id:
			return it
	return {}


func set_filter_text(text: String) -> void:
	_search.text = text
	refresh()


## Rebuilds the visible rows from items + current filter.
func refresh() -> void:
	if _rows == null:
		return
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var q := _search.text.strip_edges().to_lower()
	var only_fav := _fav_chip.button_pressed
	var shown := []
	for it in _items:
		if only_fav and not bool(it.get("favorite", false)):
			continue
		if q != "" and not _matches(it, q):
			continue
		shown.append(it)
	if favorites_first and show_favorites:
		var fav := shown.filter(func(e: Dictionary) -> bool: return bool(e.get("favorite", false)))
		var rest := shown.filter(func(e: Dictionary) -> bool: return not bool(e.get("favorite", false)))
		shown = fav + rest
	for it in shown:
		_rows.add_child(_make_row(it))
	_empty.visible = shown.is_empty()
	_scroll.visible = not shown.is_empty()
	if shown.is_empty():
		if _items.is_empty():
			_empty_label.text = empty_text if empty_text != "" else tr("Список пуст")
		else:
			_empty_label.text = tr("Ничего не найдено")


func _matches(it: Dictionary, q: String) -> bool:
	if str(it.get("title", "")).to_lower().contains(q) or str(it.get("subtitle", "")).to_lower().contains(q):
		return true
	for t in it.get("tags", []):
		if str(t).to_lower().contains(q):
			return true
	return false


func _make_row(it: Dictionary) -> ListRow:
	var id: Variant = it.get("id")
	var row := ListRow.make(id, str(it.get("title", "")), str(it.get("subtitle", "")), it.get("icon", &""))
	row.selected = id == selected_id and selected_id != null
	if show_favorites:
		row.enable_favorite(bool(it.get("favorite", false)))
		row.favorite_toggled.connect(func(on: bool) -> void:
			it["favorite"] = on
			favorite_toggled.emit(id, on))
	for a in row_actions:
		row.add_action(a.get("id", &""), a.get("icon", &"info"), str(a.get("tooltip", "")), a.get("variation", &"FlatButton"))
	row.action.connect(func(aid: StringName) -> void: action_pressed.emit(id, aid))
	row.tapped.connect(func() -> void: _on_tap(id))
	return row


func select(id: Variant) -> void:
	selected_id = id
	for r in _rows.get_children():
		(r as ListRow).selected = (r as ListRow).item_id == id


func _on_tap(id: Variant) -> void:
	var was: bool = selected_id == id
	select(id)
	if not was:
		item_selected.emit(id)
	if activate_on_tap or was:
		item_activated.emit(id)
