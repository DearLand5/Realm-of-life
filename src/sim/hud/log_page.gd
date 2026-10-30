extends VBoxContainer
## World journal with category filter (life, species, evolution, weather,
## interventions, system) — the interventions list is the experiment history.

var world: SimWorld
var _filter: StringName = &""
var _list: VBoxContainer


func setup(w: SimWorld) -> void:
	world = w
	var items := [{"id": "", "label": tr("Все")}]
	for c in EventLog.CATEGORIES:
		items.append({"id": str(c), "label": tr(EventLog.CATEGORIES[c])})
	var pick := EnumPicker.make(tr("Категория"), items, "")
	pick.selected.connect(func(id: Variant) -> void:
		_filter = StringName(str(id))
		refresh())
	add_child(pick)
	_list = VBoxContainer.new()
	add_child(_list)
	refresh()


func refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var cats: Array = [] if _filter == &"" else [_filter]
	var entries := world.state.event_log.filtered(cats, 120)
	if _filter == &"" or _filter == &"evolution":
		# Merge the evolution system's own log.
		for i in range(world.state.evo.log_entries.size() - 1, maxi(-1, world.state.evo.log_entries.size() - 60), -1):
			var e: Dictionary = world.state.evo.log_entries[i]
			entries.append({"day": int(float(e.get("day", 0))), "category": "evolution", "text": str(e.get("text", ""))})
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["day"]) > int(b["day"]))
	if entries.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = &"DimLabel"
		empty.text = tr("Пока событий нет")
		_list.add_child(empty)
	for e in entries.slice(0, 150):
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.theme_type_variation = &"CaptionLabel"
		var cat := str(EventLog.CATEGORIES.get(StringName(str(e["category"])), str(e["category"])))
		l.text = "%s %d · %s · %s" % [tr("день"), int(e["day"]), cat, str(e["text"])]
		_list.add_child(l)
