class_name TestWorlds
extends RefCounted
## Small synthetic WorldData instances for biosim tests and tools (the real
## WorldGenerator lives in src/world). Every world is a square centred at
## the origin; `sample` callables return {h, t, m, f, w} per grid point
## (height above sea, annual mean °C, moisture, fertility, water enum).

const DAY := Units.SECONDS_PER_DAY


static func build(size: float, res: int, sample: Callable) -> WorldData:
	var w := WorldData.new()
	w.allocate(size, res)
	w.sea_level = 0.0
	w.config = {"seed": 1, "size": size, "synthetic": true}
	var lo := INF
	var hi := -INF
	for iz in res:
		for ix in res:
			var i := iz * res + ix
			var p := w.grid_to_world(ix, iz)
			var s: Dictionary = sample.call(p.x, p.z)
			var h := float(s.get("h", 2.0))
			var water := int(s.get("w", WorldData.Water.LAND))
			w.heights[i] = h
			w.temperature[i] = float(s.get("t", 15.0))
			w.moisture[i] = float(s.get("m", 0.5))
			w.fertility[i] = float(s.get("f", 0.6))
			w.water[i] = water
			w.water_surface[i] = 0.0 if water != WorldData.Water.LAND else h
			if water != WorldData.Water.LAND:
				w.biome[i] = Biomes.OCEAN if water == WorldData.Water.OCEAN else Biomes.LAKE
			else:
				w.biome[i] = Biomes.classify(w.temperature[i], w.moisture[i], h, 0.0)
				if w.biome[i] == Biomes.BEACH:
					w.biome[i] = Biomes.GRASSLAND
			lo = minf(lo, h)
			hi = maxf(hi, h)
	w.min_height = lo
	w.max_height = hi
	return w


## Flat land everywhere.
static func flat(temp: float = 15.0, moist: float = 0.55, size: float = 256.0, res: int = 33) -> WorldData:
	return build(size, res, func(_x: float, _z: float) -> Dictionary:
		return {"h": 3.0, "t": temp, "m": moist, "f": 0.6})


static func cold(size: float = 256.0) -> WorldData:
	return flat(-4.0, 0.5, size)


static func warm(size: float = 256.0) -> WorldData:
	return flat(22.0, 0.55, size)


static func hot_dry(size: float = 256.0) -> WorldData:
	return flat(31.0, 0.15, size)


## Land with a round lake in the middle (radius size/5).
static func lake(temp: float = 16.0, size: float = 256.0, res: int = 33) -> WorldData:
	var r := size / 5.0
	return build(size, res, func(x: float, z: float) -> Dictionary:
		var d := sqrt(x * x + z * z)
		if d < r:
			return {"h": -4.0 * (1.0 - d / r) - 0.5, "t": temp, "m": 1.0, "f": 0.7, "w": WorldData.Water.LAKE}
		return {"h": 2.0 + (d - r) * 0.02, "t": temp, "m": 0.6 if d < r * 1.6 else 0.5, "f": 0.6})


## Two round islands (centres ±size·0.31, radius size·0.15) in an ocean; at
## least two 32 m sectors of open water separate them.
static func islands(temp: float = 16.0, size: float = 256.0, res: int = 33) -> WorldData:
	var cx := size * 0.31
	var r := size * 0.15
	return build(size, res, func(x: float, z: float) -> Dictionary:
		var da := Vector2(x + cx, z).length()
		var db := Vector2(x - cx, z).length()
		var d := minf(da, db)
		if d < r:
			return {"h": 2.0 + (r - d) * 0.05, "t": temp, "m": 0.55, "f": 0.6}
		return {"h": -6.0, "t": temp, "m": 1.0, "f": 0.4, "w": WorldData.Water.OCEAN})


static func climate_for(w: WorldData, start_phase: float = 0.1) -> ClimateState:
	var c := ClimateState.new()
	c.world = w
	c.cloud_cover = 0.3
	c.bio_time = start_phase * DAY * float(Units.DAYS_PER_YEAR)
	advance(c, 0.0)
	return c


## Minimal stand-in for TimeController: advances calendar fields.
static func advance(c: ClimateState, dt: float) -> void:
	c.bio_time += dt
	c.day = int(c.bio_time / DAY)
	c.hour = fmod(c.bio_time / 3600.0, 24.0)
	c.year_phase = fmod(c.bio_time / (DAY * float(Units.DAYS_PER_YEAR)), 1.0)
	c.season = int(c.year_phase * 4.0) % 4
	c.daylight = clampf(sin((c.hour - 6.0) / 12.0 * PI), 0.0, 1.0)
	c.sun_elevation = c.daylight * 60.0
