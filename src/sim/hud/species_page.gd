extends VBoxContainer
## Species & evolution page: list of species with live counts; for the
## selected species — description, population dynamics, mean trait
## trajectories, changes since the founder, food niche, phylogeny, log.

const TRAIT_SERIES: Array[StringName] = [&"size", &"fur_length", &"endothermy", &"metabolism", &"diet_preference", &"clutch_size"]

var world: SimWorld
var _list: VBoxContainer
var _detail: VBoxContainer
var _selected: int = -1
var _rows := {}


func setup(w: SimWorld) -> void:
	world = w
	add_theme_constant_override("separation", 8)
	_list = VBoxContainer.new()
	add_child(_list)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 8)
	add_child(_detail)
	var alive := world.state.evo.registry.alive()
	if not alive.is_empty():
		_selected = alive[0].id
	_build_list()
	_build_detail()


func _build_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	var defs := world.state.evo.registry.all()
	defs.sort_custom(func(a: SpeciesDef, b: SpeciesDef) -> bool:
		if a.extinct != b.extinct:
			return not a.extinct
		return world.state.evo.registry.count(a.id) > world.state.evo.registry.count(b.id))
	for d in defs:
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = d.id == _selected
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon = _swatch(d.ui_color if not d.extinct else d.ui_color.darkened(0.6))
		b.pressed.connect(func() -> void:
			_selected = d.id
			_build_list()
			_build_detail())
		_list.add_child(b)
		_rows[d.id] = b
	refresh()


static func _swatch(c: Color) -> Texture2D:
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


func refresh() -> void:
	var reg := world.state.evo.registry
	for id in _rows:
		var d := reg.get_species(int(id))
		var origin := {&"player": "игрок", &"procedural": "природный", &"evolved": "эволюция"}
		(_rows[id] as Button).text = "%s — %d  (%s%s)" % [d.name, int(reg.count(d.id)), str(origin.get(d.origin, str(d.origin))),
			", вымер" if d.extinct else ""]


func _build_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	var reg := world.state.evo.registry
	var d := reg.get_species(_selected)
	if d == null:
		return
	var desc := Label.new()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var parent := reg.get_species(d.parent_id)
	desc.text = "%s%s\n%s%s" % [d.name, (" (" + d.latin_name + ")") if d.latin_name != "" else "",
		d.description, ("\nПредок: «%s»" % parent.name) if parent != null else ""]
	_detail.add_child(desc)
	var sel := Button.new()
	sel.text = tr("Показать на карте и выбрать особь")
	sel.pressed.connect(func() -> void: _focus_species(d.id))
	_detail.add_child(sel)
	# Population dynamics.
	var counts := PackedFloat32Array()
	var days := PackedFloat32Array()
	for h in d.history:
		counts.append(float(h.get("count", 0.0)))
		days.append(float(h.get("day", 0.0)))
	var pc := LineChart.new()
	pc.title = tr("Численность")
	pc.x_label = tr("сутки")
	pc.custom_minimum_size = Vector2(0, 170)
	if days.size() > 0:
		pc.x_start = days[0]
		pc.x_step = (days[days.size() - 1] - days[0]) / maxf(1.0, float(days.size() - 1))
	pc.add_series(d.name, counts, d.ui_color)
	_detail.add_child(pc)
	# Mean traits (normalised 0..1).
	var tc := LineChart.new()
	tc.title = tr("Средние признаки популяции (0–1)")
	tc.custom_minimum_size = Vector2(0, 190)
	tc.y_min_fixed = 0.0
	tc.y_max_fixed = 1.0
	if days.size() > 0:
		tc.x_start = days[0]
		tc.x_step = pc.x_step
	for t in TRAIT_SERIES:
		var vals := PackedFloat32Array()
		for h in d.history:
			vals.append(float((h.get("traits", {}) as Dictionary).get(str(t), 0.0)))
		tc.add_series(str(TraitCatalog.get_def(t).get("label", str(t))), vals)
	_detail.add_child(tc)
	# Changes since the founder.
	var cmp := world.state.evo.compare_to_founder(d.id)
	var ch := Label.new()
	ch.theme_type_variation = &"SubheaderLabel"
	ch.text = tr("Изменения относительно основателя")
	_detail.add_child(ch)
	if cmp.is_empty():
		var none := Label.new()
		none.theme_type_variation = &"DimLabel"
		none.text = tr("Пока без заметных изменений")
		_detail.add_child(none)
	for c in cmp:
		var l := Label.new()
		l.theme_type_variation = &"CaptionLabel"
		var arrow := "↑" if float(c["diff"]) > 0.0 else "↓"
		l.text = "%s %s: %.2f → %.2f" % [arrow, c["label"], float(c["a"]), float(c["b"])]
		_detail.add_child(l)
	# Food niche.
	var ph := Phenotype.build(world.state.evo.current_genome(d.id) if world.state.evo.current_genome(d.id) != null else d.template)
	var food := Label.new()
	food.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	food.theme_type_variation = &"CaptionLabel"
	var pp := ph.physiology
	food.text = tr("Питание: %s · дыхание: %s · масса %s · растения %d%%, мясо %d%%, падаль %d%%") % [
		str(pp.diet), str(pp.respiration), AnatomyDiagnostics.format_mass(ph.mass()),
		int(float(pp.diet_eff.get("plant", 0.0)) * 100.0), int(float(pp.diet_eff.get("meat", 0.0)) * 100.0),
		int(float(pp.diet_eff.get("carrion", 0.0)) * 100.0)]
	_detail.add_child(food)
	# Phylogeny.
	var ph_head := Label.new()
	ph_head.theme_type_variation = &"SubheaderLabel"
	ph_head.text = tr("Генеалогическое дерево")
	_detail.add_child(ph_head)
	var tree := preload("res://src/sim/hud/phylogeny_view.gd").new()
	tree.set_data(world.state.evo.phylogeny())
	tree.species_tapped.connect(func(id: int) -> void:
		_selected = id
		_build_list()
		_build_detail())
	_detail.add_child(tree)
	# Evolution log for this species.
	var lh := Label.new()
	lh.theme_type_variation = &"SubheaderLabel"
	lh.text = tr("Журнал эволюции")
	_detail.add_child(lh)
	var shown := 0
	for i in range(world.state.evo.log_entries.size() - 1, -1, -1):
		var e: Dictionary = world.state.evo.log_entries[i]
		var data: Dictionary = e.get("data", {})
		if int(data.get("species", data.get("id", d.id))) != d.id and not str(e.get("text", "")).contains(d.name):
			continue
		var l := Label.new()
		l.theme_type_variation = &"CaptionLabel"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = "%s %d: %s" % [tr("день"), int(float(e.get("day", 0.0))), str(e.get("text", ""))]
		_detail.add_child(l)
		shown += 1
		if shown >= 25:
			break


func _focus_species(id: int) -> void:
	var best: Node = null
	for a in world.agents.agents:
		var ind: Individual = a.get("individual")
		if ind != null and ind.species_id == id:
			best = a
			break
	if best != null:
		world.cam.focus((best as Node3D).global_position, 14.0)
		world.select(best)
		return
	var pools := world.state.pop.pools_of(id)
	var top = null
	for p in pools:
		if top == null or (p as SpeciesPool).count > (top as SpeciesPool).count:
			top = p
	if top != null:
		var c := world.state.pop.sector_center((top as SpeciesPool).sector)
		c.y = world.state.world.height_at(c.x, c.z)
		world.cam.focus(c, 40.0)
