class_name LibrarySheet
extends RefCounted
## Save dialog (name, save / save as) and the start / open dialog (preset
## gallery + the player's species library).

const PRESET_ICONS := {
	&"grazer": &"paw", &"predator": &"claw", &"runner": &"sprint", &"bird": &"bird", &"fish": &"fish",
	&"frog": &"drop", &"turtle": &"shell", &"worm": &"worm", &"centipede": &"bug", &"insect": &"bug",
	&"spider": &"spider", &"octopus": &"octopus", &"jellyfish": &"jellyfish", &"starfish": &"starfish", &"cell": &"cell",
}


static func open_save(ctx: EditorContext, host: Node) -> void:
	var tr_ := TranslationServer
	var d := ModalDialog.create(tr_.translate("Сохранить вид"), tr_.translate("Вид попадёт в личную библиотеку и сможет переноситься между мирами."), &"save", ModalDialog.SizeClass.SMALL)
	var le := LineEdit.new()
	le.text = ctx.doc.design_name()
	le.placeholder_text = tr_.translate("Название вида")
	le.max_length = 40
	le.select_all_on_focus = true
	d.content.add_child(le)
	var do_save := func(as_new: bool) -> void:
		var nm := le.text.strip_edges()
		if nm == "":
			nm = EditorDocument.DEFAULT_NAME
		ctx.doc.set_design_name(nm)
		var uid := ctx.doc.save_to_library("", as_new)
		if uid == "":
			ctx.notify(tr_.translate("Не удалось сохранить вид"), &"error")
			return
		ctx.notify(tr_.translate("Вид «%s» сохранён в библиотеке") % ctx.doc.design_name(), &"success")
		ctx.tutorial_event.emit(&"species_saved")
		ctx.doc.changed.emit(&"commit")
		d.close(&"saved")
	d.add_button(&"cancel", tr_.translate("Отмена"))
	if ctx.doc.uid != "":
		d.add_button(&"save_as", tr_.translate("Как новый"), &"", &"duplicate", false).pressed.connect(func() -> void: do_save.call(true))
	d.add_button(&"save", tr_.translate("Сохранить"), &"AccentButton", &"save", false).pressed.connect(func() -> void: do_save.call(false))
	le.text_submitted.connect(func(_t: String) -> void: do_save.call(false))
	d.open()


## Preset gallery + library. `as_start` = shown when the editor opens empty.
static func open_library(ctx: EditorContext, host: Node, as_start: bool = false) -> void:
	var tr_ := TranslationServer
	var d := ModalDialog.create(tr_.translate("С чего начать?") if as_start else tr_.translate("Открыть или создать"), "", &"library", ModalDialog.SizeClass.LARGE)
	d.expand_content = true
	var tabs := TabStrip.new()
	tabs.add_tab(&"presets", &"plus", tr_.translate("Шаблоны"))
	tabs.add_tab(&"mine", &"library", tr_.translate("Мои виды"))
	d.content.add_child(tabs)
	var load_genome := func(g: Genome, uid: String) -> void:
		var go := func() -> void:
			ctx.request(&"load_genome", {"genome": g, "uid": uid})
			d.close(&"loaded")
		if ctx.doc.dirty and not as_start:
			ModalDialog.confirm(host, tr_.translate("Заменить текущий вид?"), tr_.translate("Несохранённые изменения будут потеряны."), go, tr_.translate("Заменить"), true)
		else:
			go.call()
	# Presets.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	d.content.add_child(scroll)
	var blank := IconButton.make(&"plus", tr_.translate("Пустой организм"), tr_.translate("Простое туловище с головой"), &"ChipButton")
	blank.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blank.pressed.connect(func() -> void: load_genome.call(EditorDocument.default_genome(), ""))
	grid.add_child(blank)
	for id in BodyPlanPresets.IDS:
		var b := IconButton.make(PRESET_ICONS.get(id, &"paw"), tr_.translate(BodyPlanPresets.label(id)), tr_.translate(str(BodyPlanPresets.DESCRIPTIONS.get(id, ""))), &"ChipButton")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var pid: StringName = id
		b.pressed.connect(func() -> void: load_genome.call(BodyPlanPresets.create(pid), ""))
		grid.add_child(b)
	# Library.
	var list := SearchList.new()
	list.placeholder = tr_.translate("Поиск видов")
	list.empty_text = tr_.translate("Здесь появятся сохранённые вами виды.")
	list.empty_icon = &"paw"
	var items := []
	for e in SpeciesLibrary.list_entries():
		items.append({"id": str(e["uid"]), "title": str(e["name"]), "subtitle": str(e.get("description", "")), "icon": &"paw", "favorite": bool(e.get("favorite", false))})
	list.set_items(items)
	list.activate_on_tap = true
	list.item_activated.connect(func(id: Variant) -> void:
		var g := SpeciesLibrary.load_genome(str(id))
		if g == null:
			ctx.notify(tr_.translate("Не удалось открыть вид"), &"error")
			return
		load_genome.call(g, str(id)))
	list.favorite_toggled.connect(func(id: Variant, on: bool) -> void: SpeciesLibrary.set_favorite(str(id), on))
	d.content.add_child(list)
	var show := func(id: StringName) -> void:
		scroll.visible = id == &"presets"
		list.visible = id == &"mine"
	tabs.tab_selected.connect(show)
	show.call(&"presets")
	d.add_button(&"cancel", tr_.translate("Закрыть") if not as_start else tr_.translate("Начать с пустого"))
	d.open()
