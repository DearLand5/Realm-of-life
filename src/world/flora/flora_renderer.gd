class_name FloraRenderer
extends Node3D
## Vegetation drawn with one MultiMeshInstance3D per chunk per species.
## Instance counts come from a biomass provider
##   Callable(cx: int, cz: int, plant_index: int) -> float   (kg/m², eco grid of cell_size m)
## Placement is deterministic per cell (FloraPlacement). Small plants live in
## 32 m chunks, trees/shrubs in 64 m chunks (fewer draw calls). Per chunk a
## distance band picks the mesh LOD and thins density; the shader fades
## instances out at the form's range. Chunks refresh incrementally: when the
## focus changes their band, when notify_cells_changed() is called, or by a
## slow round-robin poll of the provider.
##   setup(world, species, provider, cell_size = 8.0, climate = null) ; update_focus(pos)

const SHADER_PATH := "res://shaders/plant.gdshader"
const SMALL_CELLS := 4
const LARGE_CELLS := 8
## form -> [lod0 end, lod1 end, max range] in metres at medium quality.
const RANGES := {
	&"grass": [12.0, 24.0, 38.0], &"flower": [12.0, 24.0, 36.0], &"mushroom": [10.0, 20.0, 30.0],
	&"fern": [18.0, 36.0, 60.0], &"algae": [14.0, 28.0, 45.0], &"kelp": [24.0, 48.0, 80.0],
	&"shrub": [32.0, 70.0, 140.0], &"reed": [26.0, 52.0, 95.0], &"cactus": [40.0, 90.0, 220.0],
	&"broadleaf_tree": [55.0, 130.0, 900.0], &"conifer": [55.0, 130.0, 900.0], &"palm": [55.0, 130.0, 900.0],
}
const LARGE_FORMS: Array[StringName] = [&"broadleaf_tree", &"conifer", &"palm", &"shrub", &"cactus", &"reed"]
const MAX_PER_CELL := {
	&"grass": 120, &"flower": 40, &"mushroom": 10, &"fern": 24, &"algae": 30, &"kelp": 14,
	&"shrub": 12, &"reed": 40, &"cactus": 4, &"broadleaf_tree": 6, &"conifer": 7, &"palm": 4,
}
const SWAY := {
	&"grass": 1.0, &"flower": 1.0, &"fern": 0.6, &"reed": 1.1, &"shrub": 0.4, &"cactus": 0.02,
	&"mushroom": 0.0, &"broadleaf_tree": 0.22, &"conifer": 0.18, &"palm": 0.35, &"kelp": 1.0, &"algae": 1.0,
}
const MAX_SLOPE := {&"broadleaf_tree": 0.75, &"conifer": 0.9, &"palm": 0.6, &"cactus": 0.6}
## Density multiplier per band for small plants (trees keep full density).
const BAND_DENSITY: Array[float] = [1.0, 0.5, 0.22]

var world: WorldData
var species: Array[PlantSpecies] = []
var provider: Callable
var cell_size: float = 8.0
var climate: ClimateState
var max_chunk_updates_per_frame: int = 2
## Seconds for the background poll to revisit the nearby chunks.
var poll_interval: float = 3.0
## Milliseconds per frame spent rebuilding chunks (at least one per frame).
var frame_budget_ms: float = 3.0
## The focus must move this far (m) before bands are re-evaluated.
var refocus_distance: float = 4.0

var _dim: int = 0
var _materials: Array[ShaderMaterial] = []
var _chunks: Array[FloraChunk] = []
var _queue: Array[int] = []
var _jobs: Array[FloraJob] = []
var _focus := Vector3.ZERO
var _evaluated_focus := Vector3(INF, INF, INF)
var _range_scale: float = 1.0
var _density_scale: float = 1.0
var _shadows := true
var _uniform_timer := 0.0
var _poll_timer := 0.0
var _poll_cursor := 0


class FloraChunk:
	var cx0: int
	var cz0: int
	var cells: int
	var large: bool
	var center: Vector3
	var bands := PackedInt32Array()      # per species, -1 = not built
	var signatures := PackedInt64Array() # per species hash of instance counts
	var nodes: Array = []                # per species MultiMeshInstance3D or null
	var jobs: Array = []                 # per species pending FloraJob or null
	var queued := false


## Resumable instance generation for one chunk × species (time-sliced).
class FloraJob:
	var chunk: FloraChunk
	var plant: int
	var band: int
	var counts: PackedInt32Array
	var next_cell: int = 0
	var n: int = 0
	var buf := PackedFloat32Array()


func setup(w: WorldData, plant_species: Array[PlantSpecies], biomass_provider: Callable = Callable(), eco_cell_size: float = 8.0, shared_climate: ClimateState = null) -> void:
	world = w
	species = plant_species
	cell_size = maxf(eco_cell_size, 1.0)
	climate = shared_climate
	provider = biomass_provider if biomass_provider.is_valid() else FloraSystem.default_biomass_provider(w, plant_species, cell_size)
	for c in get_children():
		c.queue_free()
	_chunks.clear()
	_queue.clear()
	_jobs.clear()
	var q := WorldQuality.level()
	_range_scale = [0.7, 1.0, 1.35][q]
	_density_scale = [0.5, 1.0, 1.4][q]
	if OS.has_feature("mobile"):
		# Alpha-tested foliage is overdraw-heavy on tile-based phone GPUs.
		_density_scale *= 0.75
		_range_scale *= 0.85
	_shadows = q > WorldQuality.LOW
	max_chunk_updates_per_frame = [2, 4, 6][q]
	_dim = int(ceil(w.size / cell_size))
	_build_materials()
	for large in [false, true]:
		var cells: int = LARGE_CELLS if large else SMALL_CELLS
		var n := int(ceil(float(_dim) / float(cells)))
		for cz in n:
			for cx in n:
				var c := FloraChunk.new()
				c.cx0 = cx * cells
				c.cz0 = cz * cells
				c.cells = cells
				c.large = large
				var mx := -w.size * 0.5 + (float(c.cx0) + float(cells) * 0.5) * cell_size
				var mz := -w.size * 0.5 + (float(c.cz0) + float(cells) * 0.5) * cell_size
				c.center = Vector3(mx, w.height_at(mx, mz), mz)
				c.bands.resize(species.size())
				c.bands.fill(-1)
				c.signatures.resize(species.size())
				c.nodes.resize(species.size())
				c.jobs.resize(species.size())
				_chunks.append(c)
	update_focus(_focus, true)
	apply_climate()


func _build_materials() -> void:
	_materials.clear()
	var shader: Shader = load(SHADER_PATH)
	for sp in species:
		var m := ShaderMaterial.new()
		m.shader = shader
		RlNoise.bind(m)
		m.set_shader_parameter("leaf_color", _v3(sp.color_leaf))
		m.set_shader_parameter("trunk_color", _v3(sp.color_trunk))
		m.set_shader_parameter("flower_color", _v3(sp.color_flower))
		var stem := Color(0.88, 0.85, 0.78) if sp.form == &"mushroom" else sp.color_leaf.darkened(0.15)
		m.set_shader_parameter("stem_color", _v3(stem))
		m.set_shader_parameter("plant_height", sp.height)
		m.set_shader_parameter("sway_amount", float(SWAY.get(sp.form, 0.5)))
		m.set_shader_parameter("aquatic", sp.aquatic)
		m.set_shader_parameter("seasonal", sp.seasonal)
		var r: Array = RANGES.get(sp.form, [20.0, 40.0, 60.0])
		m.set_shader_parameter("fade_end", float(r[2]) * _range_scale)
		_materials.append(m)


static func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


## Moves the LOD focus; chunks whose band changes are queued (nearest first).
## Cheap to call every frame (re-evaluates after `refocus_distance` metres).
func update_focus(pos: Vector3, force: bool = false) -> void:
	_focus = pos
	if not force and pos.distance_squared_to(_evaluated_focus) < refocus_distance * refocus_distance:
		return
	_evaluated_focus = pos
	for i in _chunks.size():
		var c := _chunks[i]
		if c.queued:
			continue
		for p in species.size():
			if _wants_large(p) != c.large:
				continue
			if _band(c, p) != c.bands[p]:
				c.queued = true
				_queue.append(i)
				break
	_sort_queue()


## Marks the chunks covering eco cells as changed (ecosystem growth/grazing).
func notify_cells_changed(cells: Array) -> void:
	for cell in cells:
		var v: Vector2i = cell
		for i in _chunks.size():
			var c := _chunks[i]
			if v.x >= c.cx0 and v.x < c.cx0 + c.cells and v.y >= c.cz0 and v.y < c.cz0 + c.cells and not c.queued:
				c.queued = true
				_queue.append(i)
	_sort_queue()


## Rebuilds everything pending now (setup in tools/tests).
func refresh_all() -> void:
	while not _queue.is_empty():
		_rebuild(_queue.pop_front())
	for job in _jobs:
		_run_job(job, 0x7FFFFFFFFFFFFFFF)
		_commit(job)
	_jobs.clear()


func _process(delta: float) -> void:
	if world == null:
		return
	var t0 := Time.get_ticks_usec()
	var deadline := t0 + int(frame_budget_ms * 1000.0)
	# Re-evaluate a few queued chunks (cheap: counts only), then generate instances.
	var budget := max_chunk_updates_per_frame
	while budget > 0 and not _queue.is_empty():
		_rebuild(_queue.pop_front())
		budget -= 1
	while not _jobs.is_empty() and Time.get_ticks_usec() < deadline:
		var job: FloraJob = _jobs[0]
		if _run_job(job, deadline):
			_jobs.pop_front()
			_commit(job)
	_poll_timer -= delta
	if _poll_timer <= 0.0 and not _chunks.is_empty():
		# Re-check a few chunks against the provider each tick (cheap signatures).
		_poll_timer = poll_interval / 32.0
		for k in 2:
			_poll_cursor = (_poll_cursor + 1) % _chunks.size()
			var c := _chunks[_poll_cursor]
			if not c.queued and _is_active(c):
				c.queued = true
				_queue.append(_poll_cursor)
	_uniform_timer -= delta
	if _uniform_timer <= 0.0:
		_uniform_timer = 0.2
		apply_climate()


func _sort_queue() -> void:
	_queue.sort_custom(func(a: int, b: int) -> bool:
		return _dist(_chunks[a]) < _dist(_chunks[b]))


func _dist(c: FloraChunk) -> float:
	return Vector2(c.center.x - _focus.x, c.center.z - _focus.z).length()


func _wants_large(p: int) -> bool:
	return species[p].form in LARGE_FORMS


func _is_active(c: FloraChunk) -> bool:
	for b in c.bands:
		if b >= 0:
			return true
	return false


## 0/1/2 = LOD band, −1 = beyond range.
func _band(c: FloraChunk, p: int) -> int:
	var r: Array = RANGES.get(species[p].form, [20.0, 40.0, 60.0])
	var half_diag := float(c.cells) * cell_size * 0.7
	var d := maxf(0.0, _dist(c) - half_diag * 0.6)
	if d > float(r[2]) * _range_scale + half_diag * 0.4:
		return -1
	if d < float(r[0]) * _range_scale:
		return 0
	return 1 if d < float(r[1]) * _range_scale else 2


func _rebuild(i: int) -> void:
	var c := _chunks[i]
	c.queued = false
	for p in species.size():
		if _wants_large(p) != c.large:
			continue
		var band := _band(c, p)
		if band < 0:
			if c.nodes[p] != null:
				(c.nodes[p] as Node).queue_free()
				c.nodes[p] = null
			c.jobs[p] = null
			c.bands[p] = -1
			c.signatures[p] = 0
			continue
		var sp := species[p]
		var density := (1.0 if c.large else BAND_DENSITY[band] * _density_scale)
		var counts := PackedInt32Array()
		var sig := band
		var cap := int(float(MAX_PER_CELL.get(sp.form, 20)) * (1.0 if c.large else _density_scale))
		for dz in c.cells:
			for dx in c.cells:
				var cx := c.cx0 + dx
				var cz := c.cz0 + dz
				var n := 0
				if cx < _dim and cz < _dim:
					var bm: float = provider.call(cx, cz, p)
					n = mini(FloraPlacement.count_for(bm, cell_size, sp.biomass_per_instance, density, cx, cz, p), cap)
				counts.append(n)
				sig = (sig * 31 + n) & 0x7FFFFFFFFFFF
		if c.bands[p] == band and c.signatures[p] == sig:
			continue
		c.bands[p] = band
		c.signatures[p] = sig
		_start_job(c, p, band, counts)


## Queues instance generation for one chunk/species; replaces any older job.
func _start_job(c: FloraChunk, p: int, band: int, counts: PackedInt32Array) -> void:
	var job := FloraJob.new()
	job.chunk = c
	job.plant = p
	job.band = band
	job.counts = counts
	c.jobs[p] = job
	_jobs.append(job)


## Generates instances cell by cell until `deadline_usec`; returns true when done.
func _run_job(job: FloraJob, deadline_usec: int) -> bool:
	var c := job.chunk
	var sp := species[job.plant]
	var p := job.plant
	var half := world.size * 0.5
	var max_slope: float = MAX_SLOPE.get(sp.form, 1.2)
	var tilt := sp.form in [&"grass", &"flower", &"fern", &"mushroom", &"algae"]
	var reed := sp.form == &"reed"
	var total := c.cells * c.cells
	while job.next_cell < total:
		var k_cell := job.next_cell
		job.next_cell += 1
		var cx := c.cx0 + k_cell % c.cells
		var cz := c.cz0 + k_cell / c.cells
		var count := job.counts[k_cell]
		if count == 0:
			continue
		# Cells far from water skip per-instance water checks.
		var ccx := -half + (float(cx) + 0.5) * cell_size
		var ccz := -half + (float(cz) + 0.5) * cell_size
		var near_water := world.water_distance_at(ccx, ccz) < cell_size
		var cell_moist := world.moisture_at(ccx, ccz)
		for k in count:
			var s := FloraPlacement.spot(cx, cz, p, k, cell_size)
			var x := -half + float(cx) * cell_size + s.x
			var z := -half + float(cz) * cell_size + s.y
			if not world.contains(x, z):
				continue
			var depth := world.water_depth_at(x, z) if (near_water or sp.aquatic) else -1.0
			if sp.aquatic:
				if depth < 0.4 or (sp.form == &"algae" and depth > sp.height * 1.1 + 1.0):
					continue
			elif depth > (0.45 if reed else 0.0):
				continue
			var hn := _height_normal(x, z)
			var nrm := Vector3(hn.y, hn.z, hn.w)
			if (1.0 - nrm.y * nrm.y) > max_slope * max_slope * nrm.y * nrm.y:
				continue    # slope = tan(angle) > max_slope
			var scale := lerpf(0.72, 1.25, s.z)
			var basis := Basis(Vector3.UP, s.w * TAU).scaled(Vector3.ONE * scale)
			if tilt:
				var axis := Vector3.UP.cross(nrm)
				if axis.length_squared() > 1e-6:
					basis = Basis(axis.normalized(), Vector3.UP.angle_to(nrm) * 0.7) * basis
			var dry := clampf((0.32 - cell_moist) * 1.6, 0.0, 0.55) + s.z * 0.08
			# 12 floats transform, 4 colour (white: COLOR carries mesh AO), 4 custom.
			job.buf.append_array([basis.x.x, basis.y.x, basis.z.x, x, basis.x.y, basis.y.y, basis.z.y, hn.x - 0.04,
				basis.x.z, basis.y.z, basis.z.z, z, 1.0, 1.0, 1.0, 1.0, s.w * 2.0 - 1.0, dry, s.z, 0.0])
			job.n += 1
		if Time.get_ticks_usec() > deadline_usec:
			return job.next_cell >= total
	return true


func _commit(job: FloraJob) -> void:
	var c := job.chunk
	var p := job.plant
	if c.jobs[p] != job:
		return    # superseded by a newer job
	c.jobs[p] = null
	var sp := species[p]
	var node: MultiMeshInstance3D = c.nodes[p]
	if job.n == 0:
		if node != null:
			node.queue_free()
			c.nodes[p] = null
		return
	if node == null:
		node = MultiMeshInstance3D.new()
		node.name = "Flora_%d_%d_%d" % [c.cx0, c.cz0, p]
		node.material_override = _materials[p]
		add_child(node)
		c.nodes[p] = node
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# Instance colours must be enabled: without them the Compatibility renderer
	# multiplies vertex COLOR by zero.
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = PlantMeshFactory.get_mesh(sp, job.band)
	mm.instance_count = job.n
	mm.buffer = job.buf
	node.multimesh = mm
	var casts := _shadows and (c.large and sp.form != &"reed") and job.band < 2
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Fast inline terrain sample: x = bilinear height, yzw = normal (from the
## nearest grid sample's central differences).
func _height_normal(x: float, z: float) -> Vector4:
	var w := world
	var r := w.res
	var gx := clampf((x + w.size * 0.5) / w.cell, 0.0, float(r - 1) - 0.001)
	var gz := clampf((z + w.size * 0.5) / w.cell, 0.0, float(r - 1) - 0.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - float(ix)
	var fz := gz - float(iz)
	var i := iz * r + ix
	var hs := w.heights
	var h := lerpf(lerpf(hs[i], hs[i + 1], fx), lerpf(hs[i + r], hs[i + r + 1], fx), fz)
	var nx := ix + (1 if fx > 0.5 else 0)
	var nz := iz + (1 if fz > 0.5 else 0)
	var c := nz * r + nx
	var dx := hs[nz * r + mini(nx + 1, r - 1)] - hs[nz * r + maxi(nx - 1, 0)]
	var dz := hs[mini(nz + 1, r - 1) * r + nx] - hs[maxi(nz - 1, 0) * r + nx]
	var n := Vector3(-dx, 2.0 * w.cell, -dz).normalized()
	return Vector4(h, n.x, n.y, n.z) if c >= 0 else Vector4(h, 0, 1, 0)


func apply_climate() -> void:
	var look := SeasonalLook.from_climate(climate)
	var snow := 0.0
	var blossom := 0.0
	if climate != null:
		snow = look.snow_cover * clampf((1.5 - climate.regional_temperature) / 2.5, 0.0, 1.0)
		var ph := fposmod(climate.year_phase, 1.0)
		blossom = smoothstep(0.04, 0.1, ph) * (1.0 - smoothstep(0.18, 0.26, ph))
	for m in _materials:
		m.set_shader_parameter("wind", look.wind)
		m.set_shader_parameter("autumn", look.autumn)
		m.set_shader_parameter("leaf_loss", look.leaf_loss)
		m.set_shader_parameter("blossom", blossom)
		m.set_shader_parameter("snow", snow)
		m.set_shader_parameter("dryness", look.dryness)


## Total instances currently drawn (for budgets / overlays).
func instance_count() -> int:
	var n := 0
	for c in _chunks:
		for node in c.nodes:
			if node != null:
				n += (node as MultiMeshInstance3D).multimesh.instance_count
	return n


func draw_calls() -> int:
	var n := 0
	for c in _chunks:
		for node in c.nodes:
			if node != null:
				n += 1
	return n
