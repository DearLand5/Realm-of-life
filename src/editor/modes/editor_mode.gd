class_name EditorMode
extends VBoxContainer
## Base class of a mode page (one per tab). A page is rebuilt lazily when it is
## visible and its data changed structurally (selection, parts added/removed,
## undo, load); plain value changes only call `refresh_values()`.

var ctx: EditorContext
var panel: PartPanel
var _dirty := true


func setup(c: EditorContext) -> void:
	ctx = c
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.override_const(self, "separation", UITheme.k(self, &"gap_large"))
	ctx.segment_changed.connect(func(_i: int) -> void:
		if visible and panel != null:
			panel.rebuild_segments())


func _exit_tree() -> void:
	if panel != null:
		panel.dispose()
		panel = null


func mark_dirty() -> void:
	_dirty = true


func ensure_built() -> void:
	if not _dirty:
		return
	_dirty = false
	if panel != null:
		panel.dispose()
	panel = null
	for ch in get_children():
		remove_child(ch)
		EditorUI.dispose(ch)
	build()


## Override: fill the page.
func build() -> void:
	pass


## Override when a page shows derived numbers that change with every edit.
func refresh_values() -> void:
	if panel != null:
		panel.refresh()


## Called on every document change while visible (live edits too). Override
## for cheap read-outs (labels) that must follow dragging.
func on_live() -> void:
	pass


# --- Building blocks ----------------------------------------------------------------------

func add_selected_panel(hint: String = "") -> void:
	var p := ctx.doc.selected_part()
	if p == null:
		add_child(EditorUI.caption(hint if hint != "" else TranslationServer.translate("Коснитесь части тела на сцене или выберите её из списка выше, чтобы изменить параметры.")))
		return
	panel = PartPanel.new(ctx)
	panel.build(self, p)


## Quick-add buttons for catalogue entry ids + a link to the whole catalogue.
func add_quick_add(ids: Array) -> void:
	var btns := []
	var all := IconButton.make(&"list", TranslationServer.translate("Каталог"), "", &"ChipButton")
	all.pressed.connect(func() -> void: ctx.request(&"catalog"))
	btns.append(all)
	for id in ids:
		var e := PartCatalog.get_entry(str(id))
		if e.is_empty():
			continue
		var eid := str(id)
		var b := IconButton.make(StringName(e["icon"]), TranslationServer.translate(str(e["label"])), TranslationServer.translate(str(e.get("desc", ""))), &"ChipButton")
		b.pressed.connect(func() -> void: ctx.request(&"add", {"id": eid}))
		btns.append(b)
	add_child(EditorUI.h_scroll_row(btns))


## Chips selecting the existing parts of the given kinds.
func add_part_chips(kinds: Array, title: String = "") -> void:
	var plan := ctx.doc.plan()
	var btns := []
	var group := ButtonGroup.new()
	for p in plan.parts:
		if kinds.is_empty() or kinds.has(p.kind):
			var b := IconButton.make(SelectionBar._kind_icon(p.kind), EditorContext.part_name(p), "", &"ChipButton")
			b.toggle_mode = true
			b.button_group = group
			b.button_pressed = ctx.doc.is_selected(p.id)
			var pid := p.id
			b.pressed.connect(func() -> void: ctx.doc.select(pid))
			btns.append(b)
	if btns.is_empty():
		return
	if title != "":
		add_child(EditorUI.caption(title))
	add_child(EditorUI.h_scroll_row(btns))
