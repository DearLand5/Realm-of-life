class_name TerrainAttributes
extends RefCounted
## Per-grid-sample vertex data shared by every terrain chunk and LOD:
## smooth normals, blended biome ground colour (+ grass factor in alpha),
## height above the nearest water surface (sand / wet shore / underwater),
## annual temperature (snow line), moisture and a rock factor.

## Ground colour per biome as seen from a distance (vegetation baked in).
const GROUND: Array[Color] = [
	Color(0.52, 0.48, 0.36),  # OCEAN floor
	Color(0.84, 0.77, 0.58),  # BEACH
	Color(0.82, 0.66, 0.43),  # DESERT
	Color(0.63, 0.58, 0.30),  # SAVANNA
	Color(0.41, 0.50, 0.25),  # GRASSLAND
	Color(0.30, 0.37, 0.18),  # TEMPERATE_FOREST
	Color(0.22, 0.33, 0.13),  # RAINFOREST
	Color(0.30, 0.33, 0.21),  # TAIGA
	Color(0.47, 0.47, 0.35),  # TUNDRA
	Color(0.27, 0.32, 0.16),  # SWAMP
	Color(0.47, 0.47, 0.38),  # MOUNTAIN (alpine meadow; rock comes from slope)
	Color(0.90, 0.92, 0.96),  # SNOW
	Color(0.38, 0.36, 0.28),  # LAKE bed
	Color(0.44, 0.41, 0.33),  # RIVER bed
]
## How much of the ground is grass (seasonal/drought tint applies to it).
const GRASS: Array[float] = [0.0, 0.0, 0.05, 1.0, 1.0, 0.75, 0.65, 0.55, 0.6, 0.8, 0.15, 0.0, 0.0, 0.0]
## Exposed rock tendency independent of slope.
const ROCK: Array[float] = [0.0, 0.0, 0.08, 0.0, 0.0, 0.0, 0.0, 0.05, 0.12, 0.0, 0.4, 0.1, 0.0, 0.1]
const FAR_SHORE := 50.0

var res: int = 0
var normals := PackedVector3Array()
var colors := PackedColorArray()
var shore := PackedFloat32Array()
var temperature := PackedFloat32Array()
var moisture := PackedFloat32Array()
var rock := PackedFloat32Array()


static func build(w: WorldData) -> TerrainAttributes:
	var a := TerrainAttributes.new()
	a.res = w.res
	var n := w.res * w.res
	a.temperature = w.temperature
	a.moisture = w.moisture
	a._build_normals(w)
	var cr := PackedFloat32Array()
	var cg := PackedFloat32Array()
	var cb := PackedFloat32Array()
	var ca := PackedFloat32Array()
	cr.resize(n)
	cg.resize(n)
	cb.resize(n)
	ca.resize(n)
	a.rock.resize(n)
	a.shore.resize(n)
	var has_dist := w.water_dist.size() == n
	for i in n:
		var b := w.biome[i]
		var col := GROUND[b]
		var m := w.moisture[i]
		var g := GRASS[b]
		if g > 0.0:
			# Wetter ground is lusher, drier ground yellower.
			col = col.lerp(Color(col.r * 0.82, col.g * 1.02, col.b * 0.78), clampf((m - 0.45) * 1.6, 0.0, 1.0) * g)
			col = col.lerp(Color(col.r * 1.12, col.g * 1.04, col.b * 0.8), clampf((0.4 - m) * 1.8, 0.0, 1.0) * g)
		var depth := 0.0
		if w.water[i] != WorldData.Water.LAND:
			depth = w.water_surface[i] - w.heights[i]
			if b == Biomes.OCEAN:
				col = Color(0.74, 0.68, 0.5).lerp(GROUND[Biomes.OCEAN], clampf(depth / 8.0, 0.0, 1.0))
			a.shore[i] = -depth
		elif has_dist and w.water_dist[i] < FAR_SHORE:
			a.shore[i] = w.heights[i] - w.shore_level[i]
		else:
			a.shore[i] = FAR_SHORE
		cr[i] = col.r
		cg[i] = col.g
		cb[i] = col.b
		ca[i] = g
		a.rock[i] = ROCK[b]
	var blur := maxi(1, int(round(5.0 / w.cell)))
	GridOps.box_blur(cr, w.res, blur)
	GridOps.box_blur(cg, w.res, blur)
	GridOps.box_blur(cb, w.res, blur)
	GridOps.box_blur(ca, w.res, blur)
	GridOps.box_blur(a.rock, w.res, blur)
	a.colors.resize(n)
	for i in n:
		a.colors[i] = Color(cr[i], cg[i], cb[i], ca[i])
	return a


func _build_normals(w: WorldData) -> void:
	var r := w.res
	normals.resize(r * r)
	var h := w.heights
	var e := 2.0 * w.cell
	var nx := PackedFloat32Array()
	var nz := PackedFloat32Array()
	nx.resize(r * r)
	nz.resize(r * r)
	for iz in r:
		var zm := maxi(iz - 1, 0) * r
		var zp := mini(iz + 1, r - 1) * r
		var row := iz * r
		for ix in r:
			nx[row + ix] = (h[row + maxi(ix - 1, 0)] - h[row + mini(ix + 1, r - 1)]) / e
			nz[row + ix] = (h[zm + ix] - h[zp + ix]) / e
	# A one-cell blur of the gradient removes grid-scale facets on cliffs.
	GridOps.box_blur(nx, r, 1)
	GridOps.box_blur(nz, r, 1)
	for i in r * r:
		normals[i] = Vector3(nx[i], 1.0, nz[i]).normalized()
