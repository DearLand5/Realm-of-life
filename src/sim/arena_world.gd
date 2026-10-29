class_name ArenaWorld
extends RefCounted
## Small hand-shaped WorldData for the editor test polygon and unit tests:
## a meadow with gentle undulations, a pond deep enough to swim, a slope to
## climb and a rocky mound. No generator needed (deterministic, instant).

const POND_CENTER := Vector2(18.0, 10.0)
const POND_RADIUS := 13.0


static func make(size: float = 96.0, res: int = 97) -> WorldData:
	var w := WorldData.new()
	w.allocate(size, res)
	w.sea_level = -50.0
	w.config = {"seed": 0, "size": size, "resolution": res, "arena": true}
	var lo := INF
	var hi := -INF
	for iz in res:
		for ix in res:
			var i := iz * res + ix
			var x := -size * 0.5 + float(ix) * w.cell
			var z := -size * 0.5 + float(iz) * w.cell
			var h := 0.35 * sin(x * 0.11) * cos(z * 0.09) + 0.2 * sin(x * 0.31 + z * 0.17)
			# Climbing slope on the north side, rocky mound west.
			h += maxf(0.0, -z - size * 0.22) * 0.55
			var mound := Vector2(x + 22.0, z - 16.0).length()
			h += maxf(0.0, 6.0 - mound) * 0.6
			var pd := Vector2(x, z).distance_to(POND_CENTER)
			var pond := 0.0
			if pd < POND_RADIUS:
				pond = (1.0 - pd / POND_RADIUS)
				h -= pond * pond * 3.2 + pond * 0.6
			w.heights[i] = h
			lo = minf(lo, h)
			hi = maxf(hi, h)
			w.moisture[i] = 0.55 + 0.4 * pond
			w.temperature[i] = 18.0
			w.fertility[i] = 0.7
			w.biome[i] = Biomes.GRASSLAND if h > -0.4 or pd >= POND_RADIUS else Biomes.LAKE
			if mound < 4.0:
				w.biome[i] = Biomes.MOUNTAIN
			var surface := -0.35
			if pd < POND_RADIUS and h < surface:
				w.water[i] = WorldData.Water.LAKE
				w.water_surface[i] = surface
			else:
				w.water[i] = WorldData.Water.LAND
				w.water_surface[i] = h
	w.min_height = lo
	w.max_height = hi
	return w
