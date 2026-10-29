extends TestCase
## World generation, rendering helpers and flora (headless).

static var _default_world: WorldData


static func _small(seed_value) -> WorldData:
	return WorldGenerator.generate({"seed": seed_value, "size": 256.0, "resolution": 129})


static func _default() -> WorldData:
	if _default_world == null:
		_default_world = WorldGenerator.generate(WorldConfig.defaults())
	return _default_world


static func _hash_grids(w: WorldData) -> int:
	var h := 17
	for arr in [w.heights, w.moisture, w.temperature, w.fertility, w.water_surface]:
		h = (h * 31 + hash((arr as PackedFloat32Array).to_byte_array())) & 0x7FFFFFFF
	h = (h * 31 + hash(w.biome)) & 0x7FFFFFFF
	h = (h * 31 + hash(w.water)) & 0x7FFFFFFF
	return h


func test_deterministic_per_seed() -> void:
	var a := _small(42)
	var b := _small(42)
	check(_hash_grids(a) == _hash_grids(b), "same seed → identical grids")
	check(a.rivers.size() == b.rivers.size(), "same seed → same river count")
	var c := _small(43)
	check(_hash_grids(a) != _hash_grids(c), "different seeds differ")


func test_string_seed_and_bad_config() -> void:
	var w := WorldGenerator.generate({"seed": "Эдем", "size": "small", "resolution": 3, "relief": "много", "vegetation": 99.0, "rivers": -4})
	check(w.size == 256.0, "size preset 'small' → 256 m")
	check(w.res >= 33, "resolution clamped (%d)" % w.res)
	check(float(w.config["vegetation"]) <= 2.0, "vegetation clamped")
	check(int(w.config["rivers"]) == 0 and w.rivers.is_empty(), "negative rivers → none")
	check(float(w.config["relief"]) == float(WorldConfig.defaults()["relief"]), "invalid relief → default")
	var w2 := WorldGenerator.generate({"seed": "Эдем", "size": "small", "resolution": 3})
	check(_hash_grids(w) != 0 and int(w.config["seed"]) == int(w2.config["seed"]), "string seed hashes stably")


func test_default_world_has_varied_biomes_and_water() -> void:
	var t0 := Time.get_ticks_msec()
	var w := _default()
	var ms := Time.get_ticks_msec() - t0
	print("    default world (512 m / 257): %d ms %s" % [ms, str(WorldGenerator.last_timings)])
	check(w.size == 512.0 and w.res == 257, "default size/resolution")
	var hist := WorldGenerator.biome_histogram(w)
	var land_types := 0
	for b in hist:
		if not Biomes.is_water(b) and float(hist[b]) > 0.005:
			land_types += 1
	check(land_types >= 7, "at least 7 land biomes (got %d: %s)" % [land_types, str(hist)])
	check(float(hist.get(Biomes.OCEAN, 0.0)) > 0.15, "ocean present")
	var lakes := 0
	var rivers := 0
	for t in w.water:
		if t == WorldData.Water.LAKE:
			lakes += 1
		elif t == WorldData.Water.RIVER:
			rivers += 1
	check(lakes > 0, "lake cells present")
	check(rivers > 0 and w.rivers.size() >= 3, "rivers present (%d polylines)" % w.rivers.size())
	# Warm south, cold north: compare mean land temperature of the two halves.
	var south := 0.0
	var north := 0.0
	var ns := 0
	var nn := 0
	for iz in w.res:
		for ix in w.res:
			var i := iz * w.res + ix
			if w.water[i] != WorldData.Water.LAND:
				continue
			if iz > w.res / 2:
				south += w.temperature[i]
				ns += 1
			else:
				north += w.temperature[i]
				nn += 1
	check(ns > 0 and nn > 0 and south / ns > north / nn + 5.0, "south is warmer than north")


func test_grids_finite_and_consistent() -> void:
	var w := _default()
	for arr in [w.heights, w.moisture, w.temperature, w.fertility, w.water_surface, w.water_dist]:
		check(not GridOps.has_nan(arr), "grid has no NaN/Inf")
	var bad := 0
	for i in w.res * w.res:
		if w.moisture[i] < 0.0 or w.moisture[i] > 1.0 or w.fertility[i] < 0.0 or w.fertility[i] > 1.0:
			bad += 1
		if w.water[i] != WorldData.Water.LAND and w.water_surface[i] < w.heights[i] - 1e-4:
			bad += 1
		if w.biome[i] >= Biomes.COUNT:
			bad += 1
	check(bad == 0, "ranges valid, water surface above ground (%d bad)" % bad)
	check(w.min_height < w.sea_level and w.max_height > w.sea_level + 20.0, "relief spans sea level")
	var t_ok := true
	for t in w.temperature:
		if t < -60.0 or t > 60.0:
			t_ok = false
	check(t_ok, "annual temperatures within −60..60 °C")


func test_rivers_flow_downhill() -> void:
	var w := _default()
	for r in w.rivers:
		var pts: PackedVector3Array = r["points"]
		var wid: PackedFloat32Array = r["widths"]
		check(pts.size() == wid.size() and pts.size() >= 2, "polyline has matching widths")
		var ok := true
		for k in range(1, pts.size()):
			if pts[k].y > pts[k - 1].y + 1e-4:
				ok = false
		check(ok, "water surface non-increasing along river")
		var last := pts[pts.size() - 1]
		var g := w.world_to_grid(last.x, last.z)
		var near_water := false
		for dz in range(-3, 4):
			for dx in range(-3, 4):
				if w.water[w.index(int(round(g.x)) + dx, int(round(g.y)) + dz)] != WorldData.Water.LAND:
					near_water = true
		check(near_water, "river ends in water")


func test_pick_ray_hits_terrain() -> void:
	var w := _small(7)
	var hit := HeightfieldRay.cast(w, Vector3(10, 300, 20), Vector3.DOWN)
	check(hit != Vector3.INF, "vertical ray hits")
	near(hit.y, w.height_at(10, 20), 0.05, "hit on the surface")
	var oblique := HeightfieldRay.cast(w, Vector3(-200, 120, -200), Vector3(1, -0.4, 1).normalized())
	check(oblique != Vector3.INF, "oblique ray hits")
	if oblique != Vector3.INF:
		near(oblique.y, w.height_at(oblique.x, oblique.z), 0.1, "oblique hit on the surface")
	check(HeightfieldRay.cast(w, Vector3(0, 300, 0), Vector3.UP) == Vector3.INF, "upward ray misses")
	check(HeightfieldRay.cast(w, Vector3(5000, 10, 0), Vector3.RIGHT) == Vector3.INF, "ray outside world misses")


func test_terrain_mesh_chunks() -> void:
	var w := _small(11)
	var a := TerrainAttributes.build(w)
	check(a.colors.size() == w.res * w.res and a.normals.size() == w.res * w.res, "attributes cover the grid")
	var tris: Array[int] = []
	for step in [1, 2, 4]:
		var m := TerrainMesher.build_chunk(w, a, 16, 16, 16, step, 2.0)
		tris.append(m.surface_get_array_index_len(0) / 3)
	check(tris[0] > tris[1] and tris[1] > tris[2], "LOD reduces triangles %s" % str(tris))
	var edge := TerrainMesher.build_chunk(w, a, w.res - 9, w.res - 9, 16, 4, 2.0)
	check(edge.get_surface_count() == 1, "edge chunk builds")


func test_flora_species() -> void:
	var w := _default()
	var plants := FloraSystem.generate_species(w, Rng.new(99))
	check(plants.size() >= 8 and plants.size() <= 14, "8–14 species (got %d)" % plants.size())
	var forms := {}
	var aquatic := false
	var trees := 0
	for p in plants:
		forms[p.form] = true
		aquatic = aquatic or p.aquatic
		if p.form in [&"broadleaf_tree", &"conifer", &"palm"]:
			trees += 1
		check(p.name != "" and p.capacity > 0.0 and p.height > 0.0 and p.biomass_per_instance > 0.0, "species params valid: %s" % p.name)
		check(p.form in PlantSpecies.FORMS, "known form %s" % p.form)
	check(forms.size() >= 6, "diverse forms (%d)" % forms.size())
	check(trees >= 2, "at least two tree species")
	check(aquatic, "aquatic plant present when water exists")
	var again := FloraSystem.generate_species(w, Rng.new(99))
	check(again.size() == plants.size() and again[0].name == plants[0].name, "species deterministic per rng seed")
	var back := PlantSpecies.from_dict(plants[0].to_dict())
	check(back.name == plants[0].name and back.form == plants[0].form, "species round-trips")


func test_static_biomass_and_placement() -> void:
	var w := _default()
	var plants := FloraSystem.generate_species(w, Rng.new(5))
	var provider := FloraSystem.default_biomass_provider(w, plants, 8.0)
	var dim := int(ceil(w.size / 8.0))
	var total := 0.0
	var any_aquatic := 0.0
	var invalid := 0
	for cz in range(0, dim, 2):
		for cx in range(0, dim, 2):
			for p in plants.size():
				var bm: float = provider.call(cx, cz, p)
				if bm < 0.0 or is_nan(bm):
					invalid += 1
				total += bm
				if plants[p].aquatic:
					any_aquatic += bm
	check(invalid == 0, "biomass non-negative and finite")
	check(total > 10.0, "vegetation exists (sum %.1f)" % total)
	check(any_aquatic > 0.0, "aquatic biomass in water")
	check(float(provider.call(-1, 0, 0)) == 0.0 and float(provider.call(0, 0, 999)) == 0.0, "out of range → 0")
	# Placement is stable: instance k never moves when the count changes.
	var s1 := FloraPlacement.spot(10, 12, 3, 5, 8.0)
	var s2 := FloraPlacement.spot(10, 12, 3, 5, 8.0)
	check(s1 == s2, "spot deterministic")
	var inside := true
	var slots := {}
	for k in 64:
		var s := FloraPlacement.spot(4, 9, 2, k, 8.0)
		inside = inside and s.x >= 0.0 and s.x <= 8.0 and s.y >= 0.0 and s.y <= 8.0
		slots[Vector2i(int(s.x), int(s.y))] = true
	check(inside, "spots inside the cell")
	check(slots.size() == 64, "first 64 instances use all stratified slots")
	check(FloraPlacement.count_for(0.5, 8.0, 1.0, 1.0, 1, 1, 1) >= 31, "count from biomass")


func test_plant_meshes_all_forms_and_lods() -> void:
	for f in PlantSpecies.FORMS:
		var sp := PlantSpecies.new()
		sp.form = f
		sp.height = 1.5
		sp.seed_value = 321
		var counts: Array[int] = []
		for lod in PlantMeshFactory.LODS:
			var m := PlantMeshFactory.build(sp, lod)
			var n := m.surface_get_array_index_len(0) / 3 if m.get_surface_count() > 0 else 0
			counts.append(n)
		check(counts[0] > 0, "%s LOD0 has geometry" % f)
		check(counts[0] >= counts[2], "%s LOD2 not heavier than LOD0 %s" % [f, str(counts)])


func test_terrain_renderer_lod_follows_focus() -> void:
	var w := _small(21)
	var tr := TerrainRenderer.new()
	tr.setup(w, null)
	check(tr.triangle_count() > 0, "terrain built")
	tr.update_focus(Vector3(-100, 0, -100))
	tr.rebuild_pending(true)
	var tris_a := tr.triangle_count()
	tr.update_focus(Vector3(-100.5, 0, -100))    # tiny move: no re-evaluation
	check(tr._queue.is_empty(), "small focus moves are ignored")
	tr.update_focus(Vector3(100, 0, 100))
	check(not tr._queue.is_empty(), "big focus move queues LOD changes")
	tr.rebuild_pending(true)
	check(tr.triangle_count() > 0 and tris_a > 0, "rebuilt after moving (%d → %d)" % [tris_a, tr.triangle_count()])
	var hit := tr.pick_ray(Vector3(0, 200, 0), Vector3.DOWN)
	near(hit.y, w.height_at(0, 0), 0.05, "pick_ray through renderer")
	tr.free()


func test_flora_renderer_stable_and_incremental() -> void:
	var w := _small(8)
	var plants := FloraSystem.generate_species(w, Rng.new(4))
	var grass := -1
	for p in plants.size():
		if plants[p].form == &"grass":
			grass = p
			break
	check(grass >= 0, "a grass species exists")
	if grass < 0:
		return
	var level := {"v": 0.02}
	var provider := func(_cx: int, _cz: int, p: int) -> float:
		return float(level["v"]) if p == grass else 0.0
	var fr := FloraRenderer.new()
	fr.setup(w, plants, provider, 8.0, null)
	fr.update_focus(Vector3.ZERO, true)
	fr.refresh_all()
	var n1 := fr.instance_count()
	check(n1 > 0, "grass instances placed (%d)" % n1)
	var node := _first_node(fr)
	var before: PackedFloat32Array = node.multimesh.buffer if node != null else PackedFloat32Array()
	level["v"] = 0.04
	fr.notify_cells_changed([Vector2i(16, 16)])
	fr.refresh_all()
	check(fr.instance_count() > n1, "more biomass → more instances (%d → %d)" % [n1, fr.instance_count()])
	var after: PackedFloat32Array = node.multimesh.buffer if node != null else PackedFloat32Array()
	# The first instances of the chunk keep their exact spots (no reshuffle).
	var same := before.size() >= 20 and after.size() >= 20
	for k in mini(20, before.size()):
		if after.size() > k and absf(before[k] - after[k]) > 1e-5:
			same = false
	check(same, "existing instances keep their spots")
	# Time-sliced path: move the focus, run frames until settled.
	fr.update_focus(Vector3(90, 0, 90))
	for f in 400:
		fr._process(0.016)
	check(fr._jobs.is_empty() and fr._queue.is_empty(), "incremental refresh completes")
	fr.free()


func _first_node(fr: FloraRenderer) -> MultiMeshInstance3D:
	for c in fr._chunks:
		for n in c.nodes:
			if n != null:
				return n
	return null
