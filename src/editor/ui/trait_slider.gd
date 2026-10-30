class_name TraitSlider
extends RefCounted
## Slider bound to a TraitCatalog trait of the edited genome (homozygous:
## both alleles of every locus take the value). Live edits rebuild cheaply;
## the release is one undo step tagged with `tag`.


static func make(ctx: EditorContext, trait_id: StringName, tag: StringName = &"genetics", on_change: Callable = Callable()) -> ParamSlider:
	var d := TraitCatalog.get_def(trait_id)
	var mn := float(d["min"])
	var mx := float(d["max"])
	var span := mx - mn
	var step := _nice_step(span)
	var s := ParamSlider.make(TranslationServer.translate(str(d["label"])), mn, mx, step, ctx.doc.genome.value(trait_id))
	s.value_changed.connect(func(v: float) -> void:
		ctx.doc.live_edit(func(g: Genome) -> void: g.set_value(trait_id, v))
		if on_change.is_valid():
			on_change.call())
	s.value_committed.connect(func(v: float) -> void:
		ctx.doc.live_edit(func(g: Genome) -> void: g.set_value(trait_id, v))
		ctx.doc.commit(TranslationServer.translate(str(d["label"])), tag)
		if on_change.is_valid():
			on_change.call())
	return s


static func _nice_step(span: float) -> float:
	var raw := span / 100.0
	var mag := pow(10.0, floor(log(raw) / log(10.0)))
	var n := raw / mag
	var m := 1.0 if n < 1.5 else (2.0 if n < 3.5 else (5.0 if n < 7.5 else 10.0))
	return m * mag
