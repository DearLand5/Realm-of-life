class_name ModeShape
extends EditorMode
## «Форма»: torso, neck, head, tail, shell and cell — body axis, part list,
## whole-chain and per-segment shape.


func build() -> void:
	var axis := ctx.doc.plan().body_axis
	var picker := EnumPicker.make(tr("Ось тела"), [
		{"id": &"horizontal", "label": tr("Горизонтальная")}, {"id": &"vertical", "label": tr("Вертикальная (радиальная)")}], axis, EnumPicker.Mode.SHEET)
	picker.selected.connect(func(id: Variant) -> void:
		ctx.doc.modify(tr("Ось тела"), func(g: Genome) -> void: g.body_plan.body_axis = StringName(id), &"shape", &"structure"))
	add_child(picker)
	add_quick_add(["torso_segment", "neck", "head", "tail", "shell", "cell_body"])
	add_part_chips(PartSchema.MODE_KINDS[&"shape"], tr("Части формы"))
	add_selected_panel()
