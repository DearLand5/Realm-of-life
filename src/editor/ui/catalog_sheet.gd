class_name CatalogSheet
extends RefCounted
## Parts catalogue dialog: search, filters (this tab / all / favourites /
## recent), favourite stars and one-tap adding of kinds and quick presets.


static func open(ctx: EditorContext, host: Node) -> void:
	var d := ModalDialog.create(TranslationServer.translate("Каталог частей тела"), "", &"plus", ModalDialog.SizeClass.LARGE)
	d.expand_content = true
	var filter := {"id": &"mode"}
	var list := SearchList.new()
	list.placeholder = TranslationServer.translate("Поиск: лапа, крыло, глаз…")
	list.empty_text = TranslationServer.translate("Ничего не найдено")
	list.activate_on_tap = true
	var tabs := TabStrip.new()
	tabs.show_labels = true
	tabs.add_tab(&"mode", &"list", TranslationServer.translate("Эта вкладка"))
	tabs.add_tab(&"all", &"layers", TranslationServer.translate("Все"))
	tabs.add_tab(&"recent", &"clock", TranslationServer.translate("Недавние"))
	d.content.add_child(tabs)
	d.content.add_child(list)
	var fill := func() -> void:
		var items := []
		var src: Array[Dictionary] = []
		match filter["id"]:
			&"mode":
				src = PartCatalog.for_mode(ctx.mode)
				if src.is_empty():
					src = PartCatalog.entries()
			&"recent":
				for rid in ctx.prefs.recent:
					var e := PartCatalog.get_entry(rid)
					if not e.is_empty():
						src.append(e)
			_:
				src = PartCatalog.entries()
		for e in src:
			var sub := TranslationServer.translate(str(e.get("desc", "")))
			var kind_lbl := PartSchema.label(StringName(e["kind"]))
			items.append({"id": e["id"], "title": TranslationServer.translate(str(e["label"])),
				"subtitle": "%s · %s" % [kind_lbl, sub], "icon": StringName(e["icon"]),
				"favorite": ctx.prefs.is_favorite(str(e["id"])), "tags": e.get("tags", [])})
		list.set_items(items)
	tabs.tab_selected.connect(func(id: StringName) -> void:
		filter["id"] = id
		fill.call())
	list.favorite_toggled.connect(func(id: Variant, on: bool) -> void: ctx.prefs.set_favorite(str(id), on))
	list.item_activated.connect(func(id: Variant) -> void:
		ctx.request(&"add", {"id": str(id)})
		d.close(&"added"))
	fill.call()
	d.add_button(&"cancel", TranslationServer.translate("Закрыть"))
	d.open()
