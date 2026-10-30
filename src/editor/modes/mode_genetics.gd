class_name ModeGenetics
extends EditorMode
## «Гены»: every TraitCatalog trait by category with its inheritance type and
## scope. A slider sets the trait homozygous (both alleles); "Аллели" opens the
## per-locus pairs, where a trait can be made heterozygous so that hidden
## recessive alleles are visible and carried to offspring.

var _filter := ""
var _rows: Array[Dictionary] = []   # {box, label}


func build() -> void:
	_rows.clear()
	var intro := Card.make(tr("Как работает наследственность"), &"dna")
	intro.content.add_child(EditorUI.caption(tr("Каждый признак задают пары аллелей: одну получают от матери, другую от отца. У гомозиготы аллели одинаковы. У гетерозиготы проявляется доминантная аллель, а рецессивная остаётся скрытой и может проявиться у потомков.")))
	var terms := HFlowContainer.new()
	for term in ["аллель", "доминантность", "рецессивность", "гомозигота", "гетерозигота", "полигенный признак"]:
		var t: String = term
		terms.add_child(EditorUI.button(&"help", Glossary.display(t), func() -> void: HelpPopup.show_term(t), &"ChipButton"))
	intro.content.add_child(terms)
	add_child(intro)
	var search := LineEdit.new()
	search.placeholder_text = tr("Поиск признака")
	search.clear_button_enabled = true
	search.right_icon = Icons.texture(&"search", 22)
	search.text = _filter
	search.text_changed.connect(func(t: String) -> void:
		_filter = t.strip_edges().to_lower()
		_apply_filter())
	add_child(search)
	var first := true
	for cat in TraitCatalog.CATEGORY_LABELS:
		var sec := EditorUI.section(tr(TraitCatalog.CATEGORY_LABELS[cat]), &"dna", first)
		first = false
		add_child(sec)
		for id in TraitCatalog.ids_in_category(cat):
			var row := _trait_row(id)
			sec.content.add_child(row)
	_apply_filter()


func _apply_filter() -> void:
	for r in _rows:
		(r["box"] as Control).visible = _filter == "" or str(r["label"]).to_lower().contains(_filter)


func _trait_row(id: StringName) -> Control:
	var d := TraitCatalog.get_def(id)
	var ti := TraitCatalog.index_of(id)
	var box := VBoxContainer.new()
	var slider := TraitSlider.make(ctx, id, &"genetics")
	box.add_child(slider)
	var het := ctx.doc.genome.is_heterozygous(id)
	var info := EditorUI.caption("%s%s\n%s" % [TraitCatalog.inheritance_label(ti), tr(" · гетерозигота") if het else "", str(d.get("scope", ""))])
	info.add_theme_font_size_override("font_size", 14)
	box.add_child(info)
	var allele_box := VBoxContainer.new()
	allele_box.visible = het
	var toggle := IconButton.make(&"dna", tr("Аллели"), "", &"ChipButton")
	toggle.toggle_mode = true
	toggle.button_pressed = het
	toggle.pressed.connect(func() -> void: allele_box.visible = toggle.button_pressed)
	box.add_child(toggle)
	box.add_child(allele_box)
	_fill_alleles(allele_box, id, slider, info)
	_rows.append({"box": box, "label": tr(str(d["label"]))})
	return box


func _fill_alleles(box: VBoxContainer, id: StringName, main: ParamSlider, info: Label) -> void:
	for ch in box.get_children():
		box.remove_child(ch)
		EditorUI.dispose(ch)
	var ti := TraitCatalog.index_of(id)
	var d := TraitCatalog.get_def(id)
	var ls := TraitCatalog.locus_start(ti)
	var loci := int(d["loci"])
	var mn := float(d["min"])
	var mx := float(d["max"])
	var step := TraitSlider._nice_step(mx - mn)
	var g := ctx.doc.genome
	for k in loci:
		for side in 2:
			var li := (ls + k) * 2 + side
			var title := tr("Локус %d, аллель %s") % [k + 1, "A" if side == 0 else "B"]
			var s := ParamSlider.make(title, mn, mx, step, lerpf(mn, mx, g.alleles[li]))
			var apply := func(v: float) -> void:
				ctx.doc.live_edit(func(gg: Genome) -> void:
					gg.alleles[li] = TraitCatalog.normalize(ti, v)
					gg.invalidate())
				main.set_value(ctx.doc.genome.value(id))
			s.value_changed.connect(apply)
			s.value_committed.connect(func(v: float) -> void:
				apply.call(v)
				ctx.doc.commit(tr(str(d["label"])), &"genetics"))
			box.add_child(s)
	box.add_child(EditorUI.kv(tr("Проявляется"), UIFormat.number(g.value(id), 2), &"AccentLabel"))
	var carrier := EditorUI.button(&"duplicate", tr("Сделать гетерозиготным (носитель)"), func() -> void:
		ctx.doc.modify(tr("Гетерозигота: %s") % tr(str(d["label"])), func(gg: Genome) -> void:
			for k in loci:
				var a: float = gg.alleles[(ls + k) * 2]
				gg.alleles[(ls + k) * 2 + 1] = 1.0 if a < 0.5 else 0.0
			gg.invalidate(), &"genetics", &"structure"), &"FlatButton")
	box.add_child(carrier)
	box.add_child(EditorUI.button(&"refresh", tr("Сделать гомозиготным"), func() -> void:
		ctx.doc.modify(tr("Гомозигота: %s") % tr(str(d["label"])), func(gg: Genome) -> void: gg.set_value(id, gg.value(id)), &"genetics", &"structure"), &"FlatButton"))
