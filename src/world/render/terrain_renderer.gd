class_name TerrainRenderer
extends Node3D
## Chunked height-field terrain with 3 distance LODs around a focus point.
## Chunks are rebuilt lazily (a few per frame) when the focus moves; skirts
## hide LOD cracks. Shading: shaders/terrain.gdshader (biome colours,
## procedural detail, slope rock, shore sand/wetness, snow, seasonal tint).
##   setup(world, climate) ; update_focus(pos) ; pick_ray(origin, dir)

const SHADER_PATH := "res://shaders/terrain.gdshader"
const LOD_STEPS: Array[int] = [1, 2, 4]

## Distance (m) from the focus where LOD 1 and LOD 2 start.
var lod_distances := Vector2(110.0, 240.0)
var max_rebuilds_per_frame: int = 6
## Milliseconds per frame spent rebuilding chunks (at least one per frame).
var frame_budget_ms: float = 3.0
## The focus must move this far (m) before LODs are re-evaluated.
var refocus_distance: float = 4.0
var world: WorldData
var climate: ClimateState
var material: ShaderMaterial
var chunk_cells: int = 16

var _attrs: TerrainAttributes
var _chunks: Array[TerrainChunk] = []
var _count: int = 0              # chunks per side
var _focus := Vector3.ZERO
var _evaluated_focus := Vector3(INF, INF, INF)
var _queue: Array[int] = []
var _uniform_timer := 0.0


class TerrainChunk:
	var mi: MeshInstance3D
	var x0: int
	var z0: int
	var center: Vector3
	var lod: int = -1
	var wanted: int = 2
	var queued := false


func setup(w: WorldData, shared_climate: ClimateState = null) -> void:
	world = w
	climate = shared_climate
	for c in _chunks:
		c.mi.queue_free()
	_chunks.clear()
	_queue.clear()
	var q := WorldQuality.level()
	lod_distances = [Vector2(70.0, 160.0), Vector2(110.0, 240.0), Vector2(160.0, 340.0)][q]
	# ~32 m chunks, at least 8 cells, power of two.
	chunk_cells = clampi(nearest_po2(int(round(32.0 / w.cell))), 8, 64)
	_attrs = TerrainAttributes.build(w)
	material = ShaderMaterial.new()
	material.shader = load(SHADER_PATH)
	material.set_shader_parameter("sea_level", w.sea_level)
	_count = int(ceil(float(w.res - 1) / float(chunk_cells)))
	for cz in _count:
		for cx in _count:
			var c := TerrainChunk.new()
			c.x0 = cx * chunk_cells
			c.z0 = cz * chunk_cells
			var mid_x := mini(c.x0 + chunk_cells / 2, w.res - 1)
			var mid_z := mini(c.z0 + chunk_cells / 2, w.res - 1)
			c.center = w.grid_to_world(mid_x, mid_z)
			c.mi = MeshInstance3D.new()
			c.mi.material_override = material
			c.mi.name = "Chunk_%d_%d" % [cx, cz]
			add_child(c.mi)
			_chunks.append(c)
	update_focus(_focus, true)
	rebuild_pending(true)
	_apply_uniforms()


## Moves the LOD focus (camera / observed creature). Cheap to call every
## frame: LODs are re-evaluated only after the focus moved `refocus_distance`.
func update_focus(pos: Vector3, force: bool = false) -> void:
	_focus = pos
	if not force and pos.distance_squared_to(_evaluated_focus) < refocus_distance * refocus_distance:
		return
	_evaluated_focus = pos
	for i in _chunks.size():
		var c := _chunks[i]
		var d := Vector2(c.center.x - pos.x, c.center.z - pos.z).length()
		var want := 0 if d < lod_distances.x else (1 if d < lod_distances.y else 2)
		# Hysteresis: only coarsen when clearly beyond the threshold.
		if c.lod >= 0 and want > c.lod:
			var limit := lod_distances.x if c.lod == 0 else lod_distances.y
			if d < limit + 12.0:
				want = c.lod
		c.wanted = want
		if want != c.lod and not c.queued:
			c.queued = true
			_queue.append(i)
	# Nearest first.
	_queue.sort_custom(func(a: int, b: int) -> bool:
		return _focus_dist(_chunks[a]) < _focus_dist(_chunks[b]))


## Builds queued chunks; all of them when `all` (setup, tools).
func rebuild_pending(all: bool = false) -> void:
	var budget := _queue.size() if all else max_rebuilds_per_frame
	var t0 := Time.get_ticks_usec()
	while budget > 0 and not _queue.is_empty():
		var i: int = _queue.pop_front()
		_build(_chunks[i])
		budget -= 1
		if not all and float(Time.get_ticks_usec() - t0) > frame_budget_ms * 1000.0:
			break


func _process(delta: float) -> void:
	if world == null:
		return
	if not _queue.is_empty():
		rebuild_pending(false)
	_uniform_timer -= delta
	if _uniform_timer <= 0.0:
		_uniform_timer = 0.2
		_apply_uniforms()


func _build(c: TerrainChunk) -> void:
	c.queued = false
	var lod := c.wanted
	var step: int = LOD_STEPS[lod]
	var skirt := 1.5 + world.cell * float(step) * 1.5
	c.mi.mesh = TerrainMesher.build_chunk(world, _attrs, c.x0, c.z0, chunk_cells, step, skirt)
	c.mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.lod = lod


func _focus_dist(c: TerrainChunk) -> float:
	return Vector2(c.center.x - _focus.x, c.center.z - _focus.z).length_squared()


## Seasonal / weather uniforms from the shared climate.
func _apply_uniforms() -> void:
	if material == null:
		return
	var look := SeasonalLook.from_climate(climate)
	material.set_shader_parameter("snow_cover", look.snow_cover)
	material.set_shader_parameter("temp_offset", look.temp_offset)
	material.set_shader_parameter("grass_tint", look.grass_tint)
	material.set_shader_parameter("dryness", look.dryness)
	material.set_shader_parameter("wetness", look.wetness)


## Heightfield raycast for tap-to-select. Returns Vector3.INF on miss.
func pick_ray(origin: Vector3, dir: Vector3, max_dist: float = 3000.0) -> Vector3:
	return HeightfieldRay.cast(world, origin, dir, max_dist)


## Triangles currently built (for performance overlays).
func triangle_count() -> int:
	var n := 0
	for c in _chunks:
		if c.mi.mesh != null and c.mi.visible:
			var am := c.mi.mesh as ArrayMesh
			n += am.surface_get_array_index_len(0) / 3
	return n


func get_attributes() -> TerrainAttributes:
	return _attrs
