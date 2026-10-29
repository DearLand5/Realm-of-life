extends SceneTree
## Top-down biome map of a generated world (hill-shaded, with water depth,
## rivers and a Russian legend when a renderer is available).
##   godot --headless --path . -s tools/world_map.gd -- [seed] [out.png] [size] [scale] [layer]
## layer: biome (default) | temp | moist | fert — debug views of the climate grids.
##   tools/shot.sh tools/world_map.gd -- 20240611 res://screenshots/world_map.png
## Headless runs save the bare map; rendered runs add the legend panel.

const LEGEND_W := 260


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var cfg := WorldConfig.defaults()
	if args.size() > 0 and args[0] != "-":
		cfg["seed"] = args[0]
	var out := args[1] if args.size() > 1 else "res://screenshots/tmp/world_map.png"
	if args.size() > 2:
		cfg["size"] = args[2]
	var px_per_cell := int(args[3]) if args.size() > 3 else 3
	var layer := args[4] if args.size() > 4 else "biome"
	var w := WorldGenerator.generate(cfg)
	print("generation ms: ", WorldGenerator.last_timings)
	var hist := WorldGenerator.biome_histogram(w)
	var keys := hist.keys()
	keys.sort()
	for b in keys:
		print("  %-12s %5.1f%%" % [Biomes.label(b), float(hist[b]) * 100.0])
	print("rivers: ", w.rivers.size(), "  height ", w.min_height, " .. ", w.max_height)
	_print_land_stats(w)
	var img := render_map(w, px_per_cell, layer)
	var path := ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if DisplayServer.get_name() == "headless":
		img.save_png(path)
		print("saved ", path, " ", img.get_size())
		quit()
		return
	await _save_with_legend(img, hist, path)
	quit()


static func render_map(w: WorldData, k: int, layer: String = "biome") -> Image:
	var dim := (w.res - 1) * k
	var img := Image.create(dim, dim, false, Image.FORMAT_RGB8)
	var light := Vector3(-0.6, 0.75, -0.45).normalized()
	var span := w.size / float(dim)
	var half := w.size * 0.5
	for py in dim:
		var z := -half + (float(py) + 0.5) * span
		for px in dim:
			var x := -half + (float(px) + 0.5) * span
			var b := w.biome_at(x, z)
			var col := Biomes.color(b)
			match layer:
				"temp":
					col = Color.from_hsv(clampf(0.66 - (w.base_temperature_at(x, z) + 10.0) / 45.0 * 0.66, 0.0, 0.66), 0.8, 0.9)
				"moist":
					col = Color(0.85, 0.7, 0.4).lerp(Color(0.1, 0.35, 0.8), w.moisture_at(x, z))
				"fert":
					col = Color(0.3, 0.2, 0.1).lerp(Color(0.2, 0.9, 0.2), w.fertility_at(x, z))
			var wt := w.water_type_at(x, z)
			if wt == WorldData.Water.LAND:
				var nrm := w.normal_at(x, z)
				var shade := clampf(nrm.dot(light) * 1.25, 0.25, 1.25)
				col = col * shade
			else:
				var depth := maxf(0.0, w.water_surface_at(x, z) - w.height_at(x, z))
				var shallow := Color(0.30, 0.62, 0.70) if wt != WorldData.Water.OCEAN else Color(0.24, 0.55, 0.68)
				col = shallow.lerp(Biomes.color(b) * 0.8, clampf(depth / 14.0, 0.0, 1.0))
			img.set_pixel(px, py, Color(col.r, col.g, col.b))
	return img


static func _print_land_stats(w: WorldData) -> void:
	var t := PackedFloat32Array()
	var m := PackedFloat32Array()
	for i in w.res * w.res:
		if w.water[i] == WorldData.Water.LAND:
			t.append(w.temperature[i])
			m.append(w.moisture[i])
	if t.is_empty():
		return
	print("land temp p10/50/90: %.1f %.1f %.1f  moist p10/50/90: %.2f %.2f %.2f" % [
		GridOps.percentile(t, 0.1), GridOps.percentile(t, 0.5), GridOps.percentile(t, 0.9),
		GridOps.percentile(m, 0.1), GridOps.percentile(m, 0.5), GridOps.percentile(m, 0.9)])


func _save_with_legend(img: Image, hist: Dictionary, path: String) -> void:
	var map_dim := img.get_width()
	get_root().size = Vector2i(map_dim + LEGEND_W, map_dim)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.11, 0.13)
	bg.size = Vector2(map_dim + LEGEND_W, map_dim)
	get_root().add_child(bg)
	var tex := TextureRect.new()
	tex.texture = ImageTexture.create_from_image(img)
	tex.position = Vector2.ZERO
	get_root().add_child(tex)
	var y := 16.0
	var title := Label.new()
	title.text = "Карта биомов"
	title.add_theme_font_size_override("font_size", 22)
	title.position = Vector2(map_dim + 16, y)
	get_root().add_child(title)
	y += 40.0
	for b in Biomes.COUNT:
		if float(hist.get(b, 0.0)) <= 0.0:
			continue
		var sw := ColorRect.new()
		sw.color = Biomes.color(b)
		sw.position = Vector2(map_dim + 16, y + 3)
		sw.size = Vector2(22, 22)
		get_root().add_child(sw)
		var lab := Label.new()
		lab.text = "%s  %.1f%%" % [Biomes.label(b), float(hist[b]) * 100.0]
		lab.add_theme_font_size_override("font_size", 17)
		lab.position = Vector2(map_dim + 46, y)
		get_root().add_child(lab)
		y += 30.0
	var north := Label.new()
	north.text = "↑ Север (холод)\n↓ Юг (тепло)"
	north.add_theme_font_size_override("font_size", 15)
	north.position = Vector2(map_dim + 16, map_dim - 60)
	get_root().add_child(north)
	for f in 3:
		await process_frame
	await ShotUtil.save_viewport(get_root(), path)
