class_name SelectionBar
extends VBoxContainer
## Header of the context sheet: what is selected, tree navigation (parent,
## siblings, first child), duplicate, delete and the "add part" button.

var ctx: EditorContext
var _name: Label
var _kind: Label
var _icon: IconView
var nav: HBoxContainer
var _btns := {}


func setup(c: EditorContext) -> void:
	ctx = c
	var top := HBoxContainer.new()
	add_child(top)
	_icon = IconView.make(&"paw", 30.0, &"accent")
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_icon)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.override_const(v, "separation", 0)
	_name = Label.new()
	_name.theme_type_variation = &"SubheaderLabel"
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_kind = Label.new()
	_kind.theme_type_variation = &"DimLabel"
	_kind.clip_text = true
	v.add_child(_name)
	v.add_child(_kind)
	top.add_child(v)
	var add := IconButton.make(&"plus", TranslationServer.translate("Добавить"), TranslationServer.translate("Каталог частей тела"), &"AccentButton")
	add.pressed.connect(func() -> void: ctx.request(&"catalog"))
	top.add_child(add)
	nav = HBoxContainer.new()
	add_child(nav)  # re-parented by the editor to the sheet footer
	_add_btn(&"parent", &"chevron_up", TranslationServer.translate("К родителю"), _go_parent)
	_add_btn(&"prev", &"chevron_left", TranslationServer.translate("Предыдущая соседняя часть"), func() -> void: _go_sibling(-1))
	_add_btn(&"next", &"chevron_right", TranslationServer.translate("Следующая соседняя часть"), func() -> void: _go_sibling(1))
	_add_btn(&"child", &"chevron_down", TranslationServer.translate("К первой дочерней части"), _go_child)
	_add_btn(&"dup", &"duplicate", TranslationServer.translate("Дублировать часть с потомками"), func() -> void: ctx.request(&"duplicate"))
	_add_btn(&"del", &"trash", TranslationServer.translate("Удалить часть с потомками"), func() -> void: ctx.request(&"delete"))
	ctx.doc.selection_changed.connect(refresh)
	ctx.doc.changed.connect(func(r: StringName) -> void:
		if r != &"live":
			refresh())
	refresh()


func _add_btn(id: StringName, icon_id: StringName, tip: String, cb: Callable) -> void:
	var b := IconButton.make(icon_id, "", tip, &"FlatButton" if id != &"del" else &"FlatButton")
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	nav.add_child(b)
	_btns[id] = b


func refresh() -> void:
	var p := ctx.doc.selected_part()
	var multi := ctx.doc.selection.size()
	if p == null:
		_name.text = TranslationServer.translate("Ничего не выбрано")
		_kind.text = TranslationServer.translate("Коснитесь части тела на сцене или в каталоге")
		_icon.icon = &"pointer"
	else:
		_name.text = EditorContext.part_name(p) + (" (+%d)" % (multi - 1) if multi > 1 else "")
		var parent := ctx.doc.plan().get_part(p.parent_id)
		_kind.text = (PartSchema.label(p.kind) + " → " + EditorContext.part_name(parent)) if parent != null else TranslationServer.translate("Корень тела") + " · " + PartSchema.label(p.kind)
		_icon.icon = _kind_icon(p.kind)
	var plan := ctx.doc.plan()
	(_btns[&"parent"] as Button).disabled = p == null or p.parent_id < 0
	(_btns[&"child"] as Button).disabled = p == null or plan.children_of(p.id).is_empty()
	var sibs := _siblings(p)
	(_btns[&"prev"] as Button).disabled = sibs.size() < 2
	(_btns[&"next"] as Button).disabled = sibs.size() < 2
	(_btns[&"dup"] as Button).disabled = p == null or p.id == plan.root_id
	(_btns[&"del"] as Button).disabled = p == null or not EditorCommands.can_delete(plan, p.id)


static func _kind_icon(kind: StringName) -> StringName:
	match kind:
		&"eye": return &"eye"
		&"ear", &"sensor": return &"sound"
		&"limb": return &"paw"
		&"fin": return &"fish"
		&"wing": return &"bird"
		&"tentacle": return &"octopus"
		&"cell": return &"cell"
		&"shell": return &"shell"
		&"organ": return &"heart"
		&"horn", &"spike", &"claw": return &"claw"
		&"mouth": return &"skull"
		&"head": return &"eye"
		&"light_organ": return &"sun"
		&"gill": return &"drop"
		&"tail", &"flagellum", &"neck": return &"worm"
		&"antenna", &"whisker", &"nose": return &"bug"
	return &"scale"


func _siblings(p: BodyPart) -> Array[BodyPart]:
	if p == null or p.parent_id < 0:
		return []
	return ctx.doc.plan().children_of(p.parent_id)


func _go_parent() -> void:
	var p := ctx.doc.selected_part()
	if p != null and p.parent_id >= 0:
		ctx.doc.select(p.parent_id)


func _go_child() -> void:
	var p := ctx.doc.selected_part()
	if p == null:
		return
	var ch := ctx.doc.plan().children_of(p.id)
	if not ch.is_empty():
		ctx.doc.select(ch[0].id)


func _go_sibling(dir: int) -> void:
	var p := ctx.doc.selected_part()
	var sibs := _siblings(p)
	if p == null or sibs.size() < 2:
		return
	var i := 0
	for k in sibs.size():
		if sibs[k].id == p.id:
			i = k
	ctx.doc.select(sibs[posmod(i + dir, sibs.size())].id)
