class_name LoadDialog
extends ModalDialog
## «Загрузить»: saved worlds (newest first) with day / species / population /
## date; tap to load, trash to delete. Loading sends
## Game.goto_scene(SCENE_WORLD, {"load": {"slot": s, "file": f}}).

## Emitted with the payload before changing scene (or instead, when `dry_run`).
signal load_requested(payload: Dictionary)

## For previews/tests: entries like SaveSystem.list_world_saves() returns.
var entries: Variant = null
var dry_run: bool = false

var _list: SearchList
var _saves: Array = []

const KIND_LABELS := {"manual": "Сохранение", "autosave": "Автосохранение"}


func _ready() -> void:
	title = tr("Загрузить мир")
	icon_name = &"folder"
	size_class = SizeClass.MEDIUM
	expand_content = true
	_list = SearchList.new()
	_list.show_favorites = false
	_list.activate_on_tap = true
	_list.placeholder = tr("Поиск по названию")
	_list.empty_text = tr("Сохранений пока нет. Создайте новый мир — игра сохраняется автоматически.")
	_list.empty_icon = &"folder"
	_list.row_actions = [{"id": &"delete", "icon": &"trash", "tooltip": tr("Удалить")}]
	_list.item_activated.connect(_load)
	_list.action_pressed.connect(func(id: Variant, _a: StringName) -> void: _ask_delete(int(id)))
	content.add_child(_list)
	add_button(&"cancel", tr("Закрыть"))
	reload()
	super()


func reload() -> void:
	_saves = entries if entries is Array else SaveSystem.list_world_saves()
	var items := []
	for i in _saves.size():
		var e: Dictionary = _saves[i]
		var meta: Dictionary = e.get("meta", {})
		var kind := str(meta.get("kind", "manual"))
		var kind_text := tr(str(KIND_LABELS.get(kind, "Контрольная точка")))
		var line1 := "%s %s · %s · %s" % [tr("День"), UIFormat.integer(int(meta.get("day", 0))),
			UIFormat.count(int(meta.get("species", 0)), tr("вид"), tr("вида"), tr("видов")),
			UIFormat.count(int(meta.get("population", 0)), tr("особь"), tr("особи"), tr("особей"))]
		var line2 := "%s · %s" % [kind_text, UIFormat.datetime(str(meta.get("saved_at", "")))]
		items.append({"id": i, "title": str(meta.get("name", e.get("slot", "?"))), "subtitle": line1 + "\n" + line2,
			"icon": &"clock" if kind == "autosave" else (&"save" if kind == "manual" else &"star"), "tags": [str(e.get("slot", ""))]})
	_list.set_items(items)


func _load(i: Variant) -> void:
	var e: Dictionary = _saves[int(i)]
	var p := {"load": {"slot": e["slot"], "file": e["file"]}}
	load_requested.emit(p)
	if dry_run or UIApp.goto_scene("SCENE_WORLD", p):
		close(&"load")


func _ask_delete(i: int) -> void:
	var e: Dictionary = _saves[i]
	var name_s := str((e.get("meta", {}) as Dictionary).get("name", e.get("slot", "")))
	ModalDialog.confirm(get_parent(), tr("Удалить сохранение?"),
		tr("«%s» будет удалено без возможности восстановления.") % name_s, func() -> void: _delete(e), tr("Удалить"), true)


func _delete(e: Dictionary) -> void:
	if not dry_run:
		var slot := str(e["slot"])
		var all_saves: Array = entries if entries is Array else SaveSystem.list_world_saves()
		var siblings := all_saves.filter(
			func(x: Dictionary) -> bool: return str(x["slot"]) == slot)
		if siblings.size() <= 1:
			SaveSystem.delete_world(slot)
		else:
			# Only this file of a world with several saves (SaveSystem has no per-file delete yet).
			var dir := SaveSystem.world_dir(slot)
			var base := str(e["file"]).get_basename()
			for f in [base + ".sav", base + ".sav.bak", base + ".meta", base + ".meta.bak"]:
				if FileAccess.file_exists(dir.path_join(f)):
					DirAccess.remove_absolute(dir.path_join(f))
	if entries is Array:
		(entries as Array).erase(e)
	UIApp.notify(tr("Сохранение удалено"), &"info")
	reload()
