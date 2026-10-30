class_name PartPanel
extends RefCounted
## Context panel of the selected part, generated from PanelSpec (which is
## generated from PartSchema). The mode decides which sections are shown and
## in which order; sections a kind does not have are skipped.
##
##   var pp := PartPanel.new(ctx)
##   pp.build(box, part)          # for ctx.mode
##   pp.refresh()                 # re-read values after a commit

const ORDER := {
	&"shape": [&"shape", &"segments", &"params", &"attach"],
	&"limbs": [&"params", &"shape", &"segments", &"attach"],
	&"anatomy": [&"joints", &"muscle"],
	&"senses": [&"params", &"attach"],
	&"organs": [&"params", &"attach"],
}

var ctx: EditorContext
var spec: SpecPanel
var _seg_box: VBoxContainer
var _seg_spec: SpecPanel
var _joints_only := false


func _init(c: EditorContext) -> void:
	ctx = c


func refresh() -> void:
	if spec != null:
		spec.refresh()
	if _seg_spec != null:
		_seg_spec.refresh()


func build(box: VBoxContainer, part: BodyPart) -> void:
	spec = SpecPanel.new(ctx, part.id)
	var order: Array = ORDER.get(ctx.mode, [&"params", &"shape", &"segments", &"attach"])
	if ctx.mode == &"anatomy" and not part.is_spine():
		order = [&"params", &"attach"]
	var is_root := part.id == ctx.doc.plan().root_id
	var by_id := {}
	for s in PanelSpec.sections_for(part, is_root):
		by_id[s["id"]] = s
	var owner_mode := owning_mode(part.kind)
	if owner_mode != ctx.mode and ctx.mode in [&"shape", &"limbs", &"senses", &"organs"] and not by_id.is_empty():
		var mi := mode_info(owner_mode)
		if not mi.is_empty():
			box.add_child(EditorUI.button(StringName(mi["icon"]), TranslationServer.translate("Открыть вкладку «%s»") % TranslationServer.translate(mi["label"]),
				func() -> void: ctx.set_mode(owner_mode), &"FlatButton"))
	var shown := 0
	for sid in order:
		var sec := _section(part, sid, by_id)
		if sec != null:
			box.add_child(sec)
			shown += 1
	if shown == 0:
		box.add_child(EditorUI.caption(TranslationServer.translate("Для этой части в текущей вкладке нет параметров.")))


static func owning_mode(kind: StringName) -> StringName:
	for m in PartSchema.MODE_KINDS:
		if (PartSchema.MODE_KINDS[m] as Array).has(kind):
			# antenna belongs to both limbs and senses: limbs owns the structure.
			return m if not (m == &"senses" and kind == &"antenna") else &"limbs"
	return &"anatomy" if kind == &"organ" else &"shape"


static func mode_info(id: StringName) -> Dictionary:
	for m in EditorContext.MODES:
		if m["id"] == id:
			return m
	return {}


func _section(part: BodyPart, sid: StringName, by_id: Dictionary) -> Control:
	match sid:
		&"params", &"shape", &"muscle", &"attach":
			if not by_id.has(sid):
				return null
			var s: Dictionary = by_id[sid]
			var c := EditorUI.section(TranslationServer.translate(str(s["title"])), StringName(s["icon"]), sid != &"attach" or ctx.mode == &"organs" or ctx.mode == &"senses")
			var items: Array = s["items"]
			spec.add_items(c.content, items)
			if sid == &"muscle":
				_muscle_readout(c.content, part)
			return c
		&"segments", &"joints":
			if not part.is_spine():
				return null
			return _segments(part, sid == &"joints")
	return null


func _segments(part: BodyPart, joints_only: bool) -> Control:
	var title := TranslationServer.translate("Суставы по сегментам") if joints_only else TranslationServer.translate("Сегменты")
	var c := EditorUI.section(title, &"list", true)
	_seg_box = c.content
	_joints_only = joints_only
	_build_segments(part, joints_only)
	return c


## Rebuilds the per-segment editor (after the active segment changed elsewhere).
func rebuild_segments() -> void:
	if _seg_box != null and is_instance_valid(_seg_box) and _seg_box.is_inside_tree():
		_build_segments(ctx.doc.selected_part(), _joints_only)


func _build_segments(part: BodyPart, joints_only: bool) -> void:
	if part == null or _seg_box == null:
		return
	for ch in _seg_box.get_children():
		_seg_box.remove_child(ch)
		ch.queue_free()
	var n := part.segments.size()
	var cur := ctx.active_segment()
	var chips := []
	for i in n:
		chips.append({"id": i, "label": str(i + 1)})
	_seg_box.add_child(EditorUI.chip_flow(chips, cur, func(i: Variant) -> void:
		ctx.set_segment(int(i))
		rebuild_segments()))
	var pid := part.id
	if not joints_only:
		_seg_box.add_child(EditorUI.button_row([
			EditorUI.button(&"plus", TranslationServer.translate("Разделить"), func() -> void:
				ctx.doc.modify(TranslationServer.translate("Разделить сегмент"), func(g: Genome) -> void:
					EditorCommands.add_segment(g.body_plan.get_part(pid), cur), &"shape", &"structure"), &"", TranslationServer.translate("Добавить сегмент после выбранного")),
			EditorUI.button(&"minus", TranslationServer.translate("Убрать"), func() -> void:
				ctx.doc.modify(TranslationServer.translate("Убрать сегмент"), func(g: Genome) -> void:
					EditorCommands.remove_segment(g.body_plan.get_part(pid), cur), &"shape", &"structure"), &"", TranslationServer.translate("Удалить выбранный сегмент")),
		]))
	_seg_spec = SpecPanel.new(ctx, part.id)
	var items: Array = PanelSpec.joint_items() if joints_only else PanelSpec.segment_items(true)
	_seg_spec.add_items(_seg_box, items, cur)


func _muscle_readout(box: VBoxContainer, part: BodyPart) -> void:
	var total := MuscleGroup.new()
	var found := 0
	for g in ctx.doc.muscles:
		if g.part_id != part.id:
			continue
		found += 1
		total.max_force += g.max_force
		total.energy_cost += g.energy_cost
		total.speed = g.speed
		total.endurance = g.endurance
	if found == 0:
		box.add_child(EditorUI.caption(TranslationServer.translate("У этой части нет заметной мускулатуры.")))
		return
	box.add_child(EditorUI.caption(TranslationServer.translate("Результат (%d %s)") % [found, UIFormat.plural(found, "копия", "копии", "копий")], false))
	box.add_child(EditorUI.kv(TranslationServer.translate("Сила"), "%s Н" % UIFormat.number(total.max_force, 0)))
	box.add_child(EditorUI.kv(TranslationServer.translate("Скорость сокращения"), "%s дл/с" % UIFormat.number(total.speed, 1)))
	box.add_child(EditorUI.kv(TranslationServer.translate("Выносливость"), "%d %%" % int(total.endurance * 100.0)))
	box.add_child(EditorUI.kv(TranslationServer.translate("Расход энергии"), "%s Вт" % UIFormat.number(total.energy_cost, 1)))
