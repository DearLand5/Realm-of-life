class_name EditorActions
extends RefCounted
## Document-level commands triggered from buttons: add from the catalogue,
## duplicate, delete, copy/paste, group, lock, mirror, reset. Each one is a
## single undoable `doc.modify`. Shell actions (dialogs, scene changes) live in
## the editor root.

var ctx: EditorContext
var doc: EditorDocument


func _init(c: EditorContext) -> void:
	ctx = c
	doc = c.doc


func selected_ids() -> Array:
	var out: Array = []
	for id in doc.selection:
		out.append(id)
	return out


## Handles an action id. Returns true when it was a document action.
func run(action: StringName, args: Dictionary) -> bool:
	match action:
		&"add":
			add_entry(str(args.get("id", "")), int(args.get("parent", -1)))
		&"duplicate":
			duplicate()
		&"delete":
			delete()
		&"copy":
			copy()
		&"paste":
			paste()
		&"group":
			group(true)
		&"ungroup":
			group(false)
		&"lock":
			lock(bool(args.get("on", true)))
		&"mirror":
			mirror()
		&"reset":
			reset()
		_:
			return false
	return true


func add_entry(entry_id: String, parent_id: int = -1) -> int:
	var e := PartCatalog.get_entry(entry_id)
	if e.is_empty():
		return -1
	var pid := parent_id if parent_id >= 0 else PartCatalog.suggest_parent(doc.plan(), e, doc.selected_id)
	var holder := {"id": -1}
	var sym := doc.symmetry
	doc.modify(TranslationServer.translate("Добавить: %s") % TranslationServer.translate(str(e["label"])), func(g: Genome) -> void:
		holder["id"] = PartCatalog.place(g.body_plan, entry_id, pid, sym), &"part_added", &"structure")
	var nid: int = holder["id"]
	if nid >= 0:
		ctx.prefs.push_recent(entry_id)
		ctx.selected_instance = -1
		doc.select(nid)
		var target_mode := StringName(e["mode"])
		if target_mode != ctx.mode and target_mode in [&"shape", &"limbs", &"senses", &"organs"] and ctx.mode in [&"shape", &"limbs", &"senses", &"organs"]:
			ctx.set_mode(target_mode)
	else:
		ctx.notify(TranslationServer.translate("Не удалось добавить часть"), &"warning")
	return nid


func duplicate() -> void:
	var ids := selected_ids()
	var plan := doc.plan()
	var holder := {"ids": []}
	var any := false
	for id in ids:
		if int(id) != plan.root_id:
			any = true
	if not any:
		ctx.notify(TranslationServer.translate("Корневую часть нельзя дублировать"), &"info")
		return
	doc.modify(TranslationServer.translate("Дублировать"), func(g: Genome) -> void:
		for id in ids:
			var nid := EditorCommands.duplicate_part(g.body_plan, int(id))
			if nid >= 0:
				(holder["ids"] as Array).append(nid), &"part_added", &"structure")
	var made: Array = holder["ids"]
	if not made.is_empty():
		doc.select(int(made[0]))
		for i in range(1, made.size()):
			doc.select(int(made[i]), true)


func delete() -> void:
	var ids := selected_ids()
	var plan := doc.plan()
	var ok := false
	for id in ids:
		if EditorCommands.can_delete(plan, int(id)):
			ok = true
	if not ok:
		ctx.notify(TranslationServer.translate("Эту часть нельзя удалить (корень или заблокирована)"), &"info")
		return
	var parent := doc.selected_part().parent_id if doc.selected_part() != null else -1
	doc.modify(TranslationServer.translate("Удалить часть"), func(g: Genome) -> void:
		EditorCommands.delete_parts(g.body_plan, ids), &"edit", &"structure")
	doc.select(parent)


func copy() -> void:
	var p := doc.selected_part()
	if p == null:
		return
	doc.clipboard = EditorCommands.subtree_dict(doc.plan(), p.id)
	ctx.notify(TranslationServer.translate("Скопировано: %s") % EditorContext.part_name(p), &"info")


func paste() -> void:
	if doc.clipboard.is_empty():
		ctx.notify(TranslationServer.translate("Буфер пуст: сначала скопируйте часть"), &"info")
		return
	var target := doc.selected_id if doc.selected_part() != null else doc.plan().root_id
	var clip := doc.clipboard
	var holder := {"id": -1}
	doc.modify(TranslationServer.translate("Вставить"), func(g: Genome) -> void:
		var parent: BodyPart = g.body_plan.get_part(target)
		var top: Array = Serial.arr(clip, "parts")
		var attach := {}
		if not top.is_empty() and parent != null:
			var t0 := float((top[0] as Dictionary).get("attach_t", 0.5))
			attach["attach_t"] = clampf(t0 + 0.1, 0.02, 0.98) if t0 > 0.02 and t0 < 0.98 else t0
		holder["id"] = EditorCommands.graft(g.body_plan, clip, target, attach), &"part_added", &"structure")
	if int(holder["id"]) >= 0:
		doc.select(int(holder["id"]))


func group(on: bool) -> void:
	var ids := selected_ids()
	if ids.is_empty():
		return
	if on and ids.size() < 2:
		ctx.notify(TranslationServer.translate("Выберите несколько частей (долгое нажатие добавляет в выбор)"), &"info")
		return
	doc.modify(TranslationServer.translate("Группа") if on else TranslationServer.translate("Разгруппировать"), func(g: Genome) -> void:
		if on:
			EditorCommands.group_parts(g.body_plan, ids)
		else:
			EditorCommands.ungroup_parts(g.body_plan, ids), &"edit", &"structure")


func lock(on: bool) -> void:
	var ids := selected_ids()
	if ids.is_empty():
		return
	doc.modify(TranslationServer.translate("Заблокировать") if on else TranslationServer.translate("Разблокировать"), func(g: Genome) -> void:
		EditorCommands.set_locked(g.body_plan, ids, on), &"edit", &"structure")


func mirror() -> void:
	var ids := selected_ids()
	if ids.is_empty():
		return
	doc.modify(TranslationServer.translate("Зеркало"), func(g: Genome) -> void:
		for id in ids:
			EditorCommands.toggle_mirror(g.body_plan, int(id)), &"attach")


func reset() -> void:
	var ids := selected_ids()
	if ids.is_empty():
		return
	doc.modify(TranslationServer.translate("Сбросить часть"), func(g: Genome) -> void:
		for id in ids:
			EditorCommands.reset_part(g.body_plan, int(id)), &"shape")
