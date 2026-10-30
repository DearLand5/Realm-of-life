extends VBoxContainer
## Map with visual layers: biomes, temperature, humidity, plant biomass,
## population density (all or one species), species ranges. Tap the map to
## move the camera there.

const LAYERS := [
	[&"biome", "Биомы"], [&"temperature", "Температура"], [&"humidity", "Влажность"],
	[&"biomass", "Растительность"], [&"density", "Плотность животных"], [&"range", "Ареал вида"],
]

var world: SimWorld
var layer: StringName = &"biome"
var species_id: int = -1
var _rect: TextureRect
var _legend: Label
var _img: Image
var _tex: ImageTexture
var _res: int = 128


func setup(w: SimWorld) -> void:
	world = w
	add_theme_constant_override("separation", 6)
	var items := []
	for l in LAYERS:
		items.append({"id": l[0], "label": tr(l[1])})
	var pick := EnumPicker.make(tr("Слой"), items, layer)
	pick.selected.connect(func(id: Variant) -> void:
		layer = StringName(str(id))
		redraw())
	add_child(pick)
	var sp_items := [{"id": -1, "label": tr("Все виды")}]
	for d in world.state.evo.registry.alive():
		sp_items.append({"id": d.id, "label": d.name})
	var sp := EnumPicker.make(tr("Вид"), sp_items, -1)
	sp.selected.connect(func(id: Variant) -> void:
		species_id = int(id)
		redraw())
	add_child(sp)
	_rect = TextureRect.new()
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rect.custom_minimum_size = Vector2(0, 320)
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_rect.gui_input.connect(_on_map_input)
	add_child(_rect)
	_legend = Label.new()
	_legend.theme_type_variation = &"CaptionLabel"
	_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_legend)
	_img = Image.create(_res, _res, false, Image.FORMAT_RGB8)
	_tex = ImageTexture.create_from_image(_img)
	_rect.texture = _tex
	redraw()


func refresh() -> void:
	if layer in [&"density", &"range", &"biomass"]:
		redraw()


func redraw() -> void:
	var st := world.state
	var w := st.world
	var counts := {}
	var max_count := 0.001
	if layer in [&"density", &"range"]:
		for s in st.pop.sectors:
			var n := 0.0
			for sid in s.pools:
				if species_id < 0 or int(sid) == species_id:
					n += (s.pools[sid] as SpeciesPool).count
			counts[s.index] = n
			max_count = maxf(max_count, n)
		for a in world.agents.agents:
			var ind: Individual = a.get("individual")
			if ind != null and (species_id < 0 or ind.species_id == species_id):
				var k := st.pop.sector_index(ind.position)
				counts[k] = float(counts.get(k, 0.0)) + 1.0
				max_count = maxf(max_count, float(counts[k]))
	var max_bio := 0.001
	if layer == &"biomass":
		for i in st.eco.cell_count():
			var t := 0.0
			for p in st.plants.size():
				t += st.eco.plant_mass[p * st.eco.cell_count() + i]
			max_bio = maxf(max_bio, t)
	for y in _res:
		for x in _res:
			var wx := -w.size * 0.5 + (float(x) + 0.5) / _res * w.size
			var wz := -w.size * 0.5 + (float(y) + 0.5) / _res * w.size
			var p := Vector3(wx, w.height_at(wx, wz), wz)
			var col := Biomes.color(w.biome_at(wx, wz))
			var shade := clampf(0.75 + (p.y - w.sea_level) / maxf(1.0, w.max_height - w.sea_level) * 0.4, 0.6, 1.15)
			match layer:
				&"biome":
					col = col * shade
				&"temperature":
					var t := st.climate.temperature_at(p)
					col = _ramp(clampf((t + 15.0) / 50.0, 0.0, 1.0), Color(0.2, 0.35, 0.9), Color(0.95, 0.9, 0.4), Color(0.9, 0.2, 0.15))
				&"humidity":
					col = _ramp(st.climate.humidity_at(p), Color(0.85, 0.7, 0.4), Color(0.4, 0.75, 0.5), Color(0.15, 0.35, 0.85))
				&"biomass":
					var i := st.eco.cell_index(p)
					var t := 0.0
					for pi in st.plants.size():
						t += st.eco.plant_mass[pi * st.eco.cell_count() + i]
					col = _ramp(clampf(t / max_bio, 0.0, 1.0), Color(0.55, 0.45, 0.35), Color(0.6, 0.75, 0.3), Color(0.1, 0.45, 0.12))
				&"density", &"range":
					var k := st.pop.sector_index(p)
					var v := float(counts.get(k, 0.0)) / max_count
					var base := col.darkened(0.55)
					if layer == &"range":
						col = base.lerp(Color(0.95, 0.75, 0.2), 0.85) if v > 0.01 else base
					else:
						col = base.lerp(Color(0.95, 0.35, 0.25), clampf(sqrt(v), 0.0, 1.0))
			if w.is_water(wx, wz) and layer != &"biomass":
				col = col.lerp(Color(0.12, 0.3, 0.5), 0.55)
			_img.set_pixel(x, y, col)
	_mark_camera()
	_tex.update(_img)
	_legend.text = _legend_text()


func _mark_camera() -> void:
	var w := world.state.world
	var p := world.cam.pivot
	var cx := int((p.x + w.size * 0.5) / w.size * _res)
	var cy := int((p.z + w.size * 0.5) / w.size * _res)
	for d in range(-3, 4):
		for q in [Vector2i(cx + d, cy), Vector2i(cx, cy + d)]:
			if q.x >= 0 and q.y >= 0 and q.x < _res and q.y < _res:
				_img.set_pixelv(q, Color.WHITE)


static func _ramp(t: float, a: Color, b: Color, c: Color) -> Color:
	return a.lerp(b, t * 2.0) if t < 0.5 else b.lerp(c, (t - 0.5) * 2.0)


func _legend_text() -> String:
	match layer:
		&"temperature":
			return tr("Синий — холодно (−15 °C), жёлтый — умеренно, красный — жарко (35 °C). Учитываются сезон, погода и вмешательства.")
		&"humidity":
			return tr("Песочный — сухо, зелёный — умеренно, синий — влажно.")
		&"biomass":
			return tr("Тёмно-зелёный — густая растительность; светлые участки выедены или засушливы.")
		&"density":
			return tr("Красный — высокая плотность животных в секторе (пулы + живые особи).")
		&"range":
			return tr("Жёлтым отмечены сектора, где обитает выбранный вид.")
	return tr("Цвет — биом, яркость — высота. Белый крест — точка наблюдения. Коснитесь карты, чтобы перенести камеру.")


func _on_map_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		var r := _rect.get_rect()
		var side := minf(r.size.x, r.size.y)
		var origin := (r.size - Vector2(side, side)) * 0.5
		var local: Vector2 = ((event as InputEventScreenTouch).position - origin) / side
		if local.x < 0.0 or local.y < 0.0 or local.x > 1.0 or local.y > 1.0:
			return
		var w := world.state.world
		var x := -w.size * 0.5 + local.x * w.size
		var z := -w.size * 0.5 + local.y * w.size
		world.cam.unfollow()
		world.cam.focus(Vector3(x, w.height_at(x, z), z), 45.0)
		redraw()
