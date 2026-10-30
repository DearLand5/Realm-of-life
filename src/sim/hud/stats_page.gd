extends VBoxContainer
## Ecological statistics: population structure over time, plant biomass by
## species, environment at the focus, simulation load per tier.

var world: SimWorld
var _env: Label
var _perf: Label
var _plants: BarChart


func setup(w: SimWorld) -> void:
	world = w
	add_theme_constant_override("separation", 8)
	var area := StackedAreaChart.new()
	area.title = tr("Численность видов")
	area.x_label = tr("сутки")
	area.custom_minimum_size = Vector2(0, 200)
	var reg := world.state.evo.registry
	var max_len := 0
	for d in reg.all():
		max_len = maxi(max_len, d.history.size())
	for d in reg.all():
		var vals := PackedFloat32Array()
		vals.resize(max_len)
		var off := max_len - d.history.size()
		for i in d.history.size():
			vals[off + i] = float(d.history[i].get("count", 0.0))
		area.add_series(d.name, vals, d.ui_color)
	add_child(area)
	_plants = BarChart.new()
	_plants.title = tr("Растительная биомасса, т")
	_plants.custom_minimum_size = Vector2(0, 180)
	add_child(_plants)
	_env = Label.new()
	_env.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_env)
	_perf = Label.new()
	_perf.theme_type_variation = &"CaptionLabel"
	_perf.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_perf)
	refresh()


func refresh() -> void:
	var st := world.state
	var cats := PackedStringArray()
	var vals := PackedFloat32Array()
	var area := st.eco.cell_area()
	for i in st.plants.size():
		cats.append(st.plants[i].name)
		vals.append(st.eco.total_biomass(i) * area / 1000.0)
	_plants.categories = cats
	_plants.clear_series()
	_plants.add_series(tr("биомасса"), vals)
	var p := world.cam.pivot
	var c := st.climate
	_env.text = tr("В точке наблюдения: %.1f °C, влажность %d%%, освещённость %d%%, ветер %.1f м/с, засуха %d%%, снег %d%%. Биом: %s.") % [
		c.temperature_at(p), int(c.humidity_at(p) * 100.0), int(c.light_at(p) * 100.0), c.wind.length(),
		int(c.drought * 100.0), int(c.snow_cover * 100.0), Biomes.label(st.world.biome_at(p.x, p.z))]
	var ps := world.perf.stats()
	_perf.text = tr("Симуляция: %d особей (A: %d, B: %d), активных секторов %d, популяций в пулах %d; качество %s; %.0f FPS%s") % [
		world.agents.live_count(), int(ps.get("tier_a", 0)), int(ps.get("tier_b", 0)), _active_sectors(),
		int(st.total_population()), str(ps.get("level", "")), float(ps.get("fps", 0.0)),
		tr(" · популяционный режим") if bool(ps.get("statistical", false)) else ""]


func _active_sectors() -> int:
	var n := 0
	for s in world.state.pop.sectors:
		if world.agents.is_active_sector(s.index):
			n += 1
	return n
