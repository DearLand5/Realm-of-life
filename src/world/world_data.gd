class_name WorldData
extends RefCounted
## Static geography of a generated world (filled by WorldGenerator).
## The world is a square centred at the origin: x, z ∈ [-size/2, size/2].
## Grids are `res × res` samples, row-major (index = iz * res + ix), sample
## (ix, iz) sits at world (-size/2 + ix*cell, -size/2 + iz*cell).
## Saves store only `config` (generation is deterministic from the seed).

enum Water { LAND = 0, OCEAN = 1, LAKE = 2, RIVER = 3 }

var config: Dictionary = {}
var size: float = 512.0
var res: int = 257
var cell: float = 2.0
var sea_level: float = 0.0
var heights := PackedFloat32Array()      # ground height (m)
var moisture := PackedFloat32Array()     # 0..1 base humidity
var temperature := PackedFloat32Array()  # annual mean °C at this cell (altitude included)
var fertility := PackedFloat32Array()    # 0..1 soil nutrients
var biome := PackedByteArray()           # Biomes id
var water := PackedByteArray()           # Water enum
var water_surface := PackedFloat32Array()  # water surface height where water != LAND
## Distance (m) to the nearest water cell (0 inside water) and that water's
## surface height. Filled by WorldGenerator; empty for hand-built worlds.
var water_dist := PackedFloat32Array()
var shore_level := PackedFloat32Array()
## Rivers as polylines for rendering: [{points: PackedVector3Array, widths: PackedFloat32Array}]
var rivers: Array = []
var min_height: float = 0.0
var max_height: float = 1.0


func allocate(world_size: float, resolution: int) -> void:
	size = world_size
	res = resolution
	cell = size / float(res - 1)
	var n := res * res
	heights.resize(n)
	moisture.resize(n)
	temperature.resize(n)
	fertility.resize(n)
	biome.resize(n)
	water.resize(n)
	water_surface.resize(n)
	water_dist.resize(n)
	shore_level.resize(n)


func half() -> float:
	return size * 0.5


func index(ix: int, iz: int) -> int:
	return clampi(iz, 0, res - 1) * res + clampi(ix, 0, res - 1)


func world_to_grid(x: float, z: float) -> Vector2:
	return Vector2((x + size * 0.5) / cell, (z + size * 0.5) / cell)


func grid_to_world(ix: int, iz: int) -> Vector3:
	var x := -size * 0.5 + float(ix) * cell
	var z := -size * 0.5 + float(iz) * cell
	return Vector3(x, heights[index(ix, iz)], z)


func contains(x: float, z: float) -> bool:
	var h := size * 0.5
	return x >= -h and x <= h and z >= -h and z <= h


func clamp_xz(p: Vector3, margin: float = 1.0) -> Vector3:
	var h := size * 0.5 - margin
	return Vector3(clampf(p.x, -h, h), p.y, clampf(p.z, -h, h))


func _bilinear(arr: PackedFloat32Array, x: float, z: float) -> float:
	var g := world_to_grid(x, z)
	var gx := clampf(g.x, 0.0, float(res - 1) - 0.0001)
	var gz := clampf(g.y, 0.0, float(res - 1) - 0.0001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - float(ix)
	var fz := gz - float(iz)
	var i00 := iz * res + ix
	var a := lerpf(arr[i00], arr[i00 + 1], fx)
	var b := lerpf(arr[i00 + res], arr[i00 + res + 1], fx)
	return lerpf(a, b, fz)


func _nearest_byte(arr: PackedByteArray, x: float, z: float) -> int:
	var g := world_to_grid(x, z)
	return arr[index(int(round(g.x)), int(round(g.y)))]


func height_at(x: float, z: float) -> float:
	return _bilinear(heights, x, z)


func normal_at(x: float, z: float) -> Vector3:
	var e := cell
	var hx := height_at(x + e, z) - height_at(x - e, z)
	var hz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


## Slope as rise/run (0 = flat, 1 = 45°).
func slope_at(x: float, z: float) -> float:
	var n := normal_at(x, z)
	return sqrt(maxf(0.0, 1.0 - n.y * n.y)) / maxf(n.y, 0.05)


func moisture_at(x: float, z: float) -> float:
	return _bilinear(moisture, x, z)


func base_temperature_at(x: float, z: float) -> float:
	return _bilinear(temperature, x, z)


func fertility_at(x: float, z: float) -> float:
	return _bilinear(fertility, x, z)


func biome_at(x: float, z: float) -> int:
	return _nearest_byte(biome, x, z)


func water_type_at(x: float, z: float) -> int:
	return _nearest_byte(water, x, z)


## Water surface height (meaningful where water_depth_at > 0).
func water_surface_at(x: float, z: float) -> float:
	var g := world_to_grid(x, z)
	var i := index(int(round(g.x)), int(round(g.y)))
	return water_surface[i] if water[i] != Water.LAND else sea_level


## Depth of water above the ground (<= 0 on dry land).
func water_depth_at(x: float, z: float) -> float:
	var g := world_to_grid(x, z)
	var i := index(int(round(g.x)), int(round(g.y)))
	if water[i] == Water.LAND:
		return -maxf(0.0, height_at(x, z) - sea_level)
	return water_surface[i] - height_at(x, z)


func is_water(x: float, z: float) -> bool:
	return water_depth_at(x, z) > 0.05


## Finds the nearest point with drinkable (non-ocean) or any water within radius.
## Returns Vector3.INF when none found. Coarse ring search on the grid.
func find_water_near(p: Vector3, radius: float, fresh_only: bool = true) -> Vector3:
	var g := world_to_grid(p.x, p.z)
	var r_cells := int(ceil(radius / cell))
	var best := Vector3.INF
	var best_d := INF
	var step := maxi(1, r_cells / 12)
	for dz in range(-r_cells, r_cells + 1, step):
		for dx in range(-r_cells, r_cells + 1, step):
			var ix := int(g.x) + dx
			var iz := int(g.y) + dz
			if ix < 0 or iz < 0 or ix >= res or iz >= res:
				continue
			var w := water[iz * res + ix]
			if w == Water.LAND or (fresh_only and w == Water.OCEAN):
				continue
			var wp := grid_to_world(ix, iz)
			var d := Vector2(wp.x - p.x, wp.z - p.z).length_squared()
			if d < best_d:
				best_d = d
				best = wp
	return best


## Distance to the nearest water (m); falls back to a large value when unknown.
func water_distance_at(x: float, z: float) -> float:
	if water_dist.size() != res * res:
		return 0.0 if is_water(x, z) else 1.0e6
	return _bilinear(water_dist, x, z)


func to_dict() -> Dictionary:
	return {"config": config.duplicate(true)}
