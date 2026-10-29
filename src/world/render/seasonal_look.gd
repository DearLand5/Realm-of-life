class_name SeasonalLook
extends RefCounted
## Visual parameters derived from the shared ClimateState (season, drought,
## snow, rain, wind). Terrain, flora and water renderers push these into
## their shader uniforms.

var snow_cover: float = 0.0
var temp_offset: float = 0.0          # seasonal + weather anomaly, °C
var grass_tint := Color(1, 1, 1)
var dryness: float = 0.0
var wetness: float = 0.0
var autumn: float = 0.0               # 0..1 leaf colouring of deciduous plants
var leaf_loss: float = 0.0            # 0..1 bare branches of deciduous plants
var wind := Vector2(1.0, 0.0)         # m/s
var daylight: float = 1.0

## Grass tint keyframes over the year phase (0 = start of spring).
const TINT_KEYS: Array[float] = [0.0, 0.12, 0.37, 0.62, 0.87, 1.0]
const TINT_COLS: Array[Color] = [
	Color(0.92, 0.95, 0.82),   # thaw, still dull
	Color(0.96, 1.1, 0.82),    # fresh spring green
	Color(1.04, 1.0, 0.84),    # summer
	Color(1.18, 0.95, 0.72),   # autumn straw
	Color(0.96, 0.88, 0.78),   # winter dead grass
	Color(0.92, 0.95, 0.82),
]


static func from_climate(c: ClimateState) -> SeasonalLook:
	var l := SeasonalLook.new()
	if c == null:
		return l
	l.snow_cover = clampf(c.snow_cover, 0.0, 1.0)
	l.temp_offset = c.seasonal_offset() + c.weather_temp_offset + c.sandbox_temp_offset
	var p := fposmod(c.year_phase, 1.0)
	l.grass_tint = tint_at(p)
	l.dryness = clampf(c.drought, 0.0, 1.0)
	l.wetness = clampf(maxf(c.wetness, c.precipitation * 0.8), 0.0, 1.0)
	l.autumn = smoothstep(0.47, 0.6, p) * (1.0 - smoothstep(0.74, 0.82, p))
	l.leaf_loss = maxf(smoothstep(0.7, 0.8, p), 1.0 - smoothstep(0.0, 0.09, p))
	l.wind = c.wind
	l.daylight = c.daylight
	return l


static func tint_at(p: float) -> Color:
	for k in TINT_KEYS.size() - 1:
		if p <= TINT_KEYS[k + 1]:
			var t := (p - TINT_KEYS[k]) / maxf(TINT_KEYS[k + 1] - TINT_KEYS[k], 1e-4)
			return TINT_COLS[k].lerp(TINT_COLS[k + 1], smoothstep(0.0, 1.0, t))
	return TINT_COLS[TINT_COLS.size() - 1]
