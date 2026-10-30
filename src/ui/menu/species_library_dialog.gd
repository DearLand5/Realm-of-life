class_name SpeciesLibraryDialog
extends ModalDialog
## «Библиотека видов»: the player's species (search, favourite, duplicate,
## delete, open in editor) and "new from preset" (BodyPlanPresets).
##   open in editor → Game.goto_scene(SCENE_EDITOR, {"species_uid": uid})
##   from preset    → Game.goto_scene(SCENE_EDITOR, {"preset": id})

## Emitted with the editor payload (also when `dry_run` prevents the scene change).
signal editor_requested(payload: Dictionary)

const PRESET_ICONS := {
	&"grazer": &"paw", &"predator": &"claw", &"runner": &"sprint", &"bird": &"bird", &"fish": &"fish",
	&"frog": &"drop", &"turtle": &"shell", &"worm": &"worm", &"centipede": &"bug", &"insect": &"bug",
	&"spider": &"spider", &"octopus": &"octopus", &"jellyfish": &"jellyfish", &"starfish": &"starfish", &"cell": &"cell",
}

## For previews/tests: entries like SpeciesLibrary.list_entries().
var entries: Variant = null
var dry_run: bool = false
## Start on the presets tab.
var start_with_presets: bool = false

var _tabs: TabStrip
var _list: SearchList
var _presets: GridContainer
var _presets_scroll: ScrollContainer


func _ready() -> void:
	title = tr("Библиотека видов")
	icon_name = &"library"
	size_class = SizeClass.LARGE
	expand_content = true
	_tabs = TabStrip.new()
	_tabs.add_tab(&"mine", &"library", tr("Мои виды"))
	_tabs.add_tab(&"presets", &"plus", tr("Новый из шаблона"))
	_tabs.tab_selected.connect(_show_tab)
	content.add_child(_tabs)
	_list = SearchList.new()
	_list.placeholder = tr("Поиск видов")
	_list.empty_text = tr("Здесь появятся созданные вами виды. Начните с шаблона!")
	_list.empty_icon = &"paw"
	_list.row_actions = [
		{"id": &"edit", "icon": &"edit", "tooltip": tr("Открыть в редакторе")},
		{"id": &"dup", "icon": &"duplicate", "tooltip": tr("Дублировать")},
		{"id": &"delete", "icon": &"trash", "tooltip": tr("Удалить")},
	]
	_list.item_activated.connect(func(id: Variant) -> void: _open_editor({"species_uid": str(id)}))
	_list.favorite_toggled.connect(_on_favorite)
	_list.action_pressed.connect(_on_action)
	content.add_child(_list)
	_presets_scroll = ScrollContainer.new()
	_presets_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_presets_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_presets_scroll)
	_presets = GridContainer.new()
	_presets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.override_const(_presets, "h_separation", 12)
	UITheme.override_const(_presets, "v_separation", 12)
	_presets_scroll.add_child(_presets)
	_build_presets()
	add_button(&"cancel", tr("Закрыть"))
	reload()
	_tabs.current = &"presets" if start_with_presets else &"mine"
	_show_tab(_tabs.current)
	super()
	resized.connect(_fit_columns)


func reload() -> void:
	var src: Array = entries if entries is Array else SpeciesLibrary.list_entries()
	var items := []
	for e in src:
		var desc := str(e.get("description", ""))
		var mod := str(e.get("modified", ""))
		var sub := desc if desc != "" else (tr("Изменён: %s") % UIFormat.datetime(mod) if mod != "" else "")
		items.append({"id": str(e.get("uid", "")), "title": str(e.get("name", "?")), "subtitle": sub,
			"icon": &"paw", "favorite": bool(e.get("favorite", false))})
	_list.set_items(items)


func _show_tab(id: StringName) -> void:
	_list.visible = id == &"mine"
	_presets_scroll.visible = id == &"presets"
	_fit_columns.call_deferred()


func _fit_columns() -> void:
	if _presets == null or not is_inside_tree():
		return
	var w := _presets_scroll.size.x if _presets_scroll.size.x > 0.0 else size.x
	_presets.columns = clampi(int(w / (260.0 * UITheme.scale_of(self))), 1, 4)


func _build_presets() -> void:
	for id in BodyPlanPresets.IDS:
		var tile := PresetTile.new()
		tile.preset_id = id
		tile.icon_id = PRESET_ICONS.get(id, &"paw")
		tile.title = tr(BodyPlanPresets.label(id))
		tile.description = tr(str(BodyPlanPresets.DESCRIPTIONS.get(id, "")))
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.chosen.connect(func() -> void: _open_editor({"preset": id}))
		_presets.add_child(tile)


func _open_editor(p: Dictionary) -> void:
	editor_requested.emit(p)
	if dry_run or UIApp.goto_scene("SCENE_EDITOR", p):
		close(&"editor")


func _on_favorite(id: Variant, fav: bool) -> void:
	if entries is Array:
		for e in entries:
			if str(e.get("uid", "")) == str(id):
				e["favorite"] = fav
		return
	set_favorite(str(id), fav)


## Persists the favourite flag.
static func set_favorite(uid: String, fav: bool) -> void:
	SpeciesLibrary.set_favorite(uid, fav)


func _on_action(id: Variant, action: StringName) -> void:
	var uid := str(id)
	match action:
		&"edit":
			_open_editor({"species_uid": uid})
		&"dup":
			if not (entries is Array):
				if SpeciesLibrary.duplicate_species(uid) != "":
					UIApp.notify(tr("Копия создана"), &"success")
			reload()
		&"delete":
			var item := _list.item(id)
			ModalDialog.confirm(get_parent(), tr("Удалить вид?"),
				tr("«%s» исчезнет из библиотеки. Миры, где он уже живёт, сохранят свою копию.") % str(item.get("title", "")),
				func() -> void: _delete(uid), tr("Удалить"), true)


func _delete(uid: String) -> void:
	if entries is Array:
		entries = (entries as Array).filter(func(e: Dictionary) -> bool: return str(e.get("uid", "")) != uid)
	else:
		SpeciesLibrary.delete_species(uid)
	reload()


## Tile of the preset grid (private helper).
class PresetTile:
	extends Card
	signal chosen
	var preset_id: StringName
	var icon_id: StringName
	var description: String = ""
	var _press := Vector2(-1, -1)

	func _ready() -> void:
		icon_name = icon_id
		subtitle = ""
		super()
		mouse_filter = Control.MOUSE_FILTER_STOP
		var d := Label.new()
		d.theme_type_variation = &"DimLabel"
		d.text = description
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(d)
		for c in find_children("*", "Control", true, false):
			if not (c is Button):
				(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_press = mb.position
		elif _press.x >= 0.0 and mb.position.distance_to(_press) < 16.0:
			_press = Vector2(-1, -1)
			chosen.emit()
			accept_event()
