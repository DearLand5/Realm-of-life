class_name ModeOrgans
extends EditorMode
## «Органы»: mouths, teeth and venom, horns, spikes, claws, gills, glands and
## light organs — every point part of PartSchema that is not a sense organ.

var _summary: VBoxContainer


func build() -> void:
	add_quick_add(["mouth_jaws", "mouth_beak", "mouth_mandibles", "horns", "spike", "claw", "gills", "gland_venom", "light_organ"])
	_summary = VBoxContainer.new()
	var c := EditorUI.section(tr("Итоговые возможности"), &"claw", true)
	c.content.add_child(_summary)
	add_child(c)
	_fill_summary()
	add_part_chips(PartSchema.MODE_KINDS[&"organs"].filter(func(k: StringName) -> bool: return k != &"organ"), tr("Органы и оружие"))
	add_selected_panel()


func on_live() -> void:
	_fill_summary()


func _fill_summary() -> void:
	if _summary == null or not is_instance_valid(_summary):
		return
	for ch in _summary.get_children():
		_summary.remove_child(ch)
		EditorUI.dispose(ch)
	var st := ctx.doc.phenotype.anatomy.stats
	var mouth: Dictionary = st.get("mouth", {})
	if int(mouth.get("count", 0)) == 0:
		_summary.add_child(EditorUI.kv(tr("Рот"), tr("нет")))
	else:
		_summary.add_child(EditorUI.kv(tr("Рот"), "%s, %s" % [PartSchema.enum_label(str(mouth.get("type", ""))), PartSchema.enum_label(str(mouth.get("teeth", "")))]))
		_summary.add_child(EditorUI.kv(tr("Сила укуса"), "%s Н" % UIFormat.number(float(mouth.get("bite_force", 0.0)), 0)))
	var w: Dictionary = st.get("weapons", {})
	var names := {"bite": "укус", "horn": "рога", "claw": "когти", "spike": "шипы", "venom": "яд"}
	for k in w:
		if float(w[k]) > 0.0:
			_summary.add_child(EditorUI.kv(tr("Оружие: %s") % tr(str(names.get(str(k), str(k)))), UIFormat.number(float(w[k]), 1)))
	_summary.add_child(EditorUI.kv(tr("Броня"), "%d %%" % int(float(st.get("armor", 0.0)) * 100.0)))
