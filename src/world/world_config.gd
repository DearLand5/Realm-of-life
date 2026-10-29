class_name WorldConfig
extends RefCounted
## World generation settings (player-editable). `defaults()` documents every key;
## `sanitize()` merges user input over the defaults, coerces types and clamps
## ranges so bad/old configs never break the generator.

const SIZE_PRESETS := {"small": 256.0, "medium": 512.0, "large": 1024.0}
const SIZE_LABELS := {"small": "Малый (256 м)", "medium": "Средний (512 м)", "large": "Большой (1024 м)"}

## Numeric ranges: key -> [min, max]. Keys missing here are not clamped.
const RANGES := {
	"size": [128.0, 2048.0],
	"resolution": [33, 1025],
	"sea_level": [-50.0, 50.0],
	"relief": [0.0, 1.0],
	"mountains": [0.0, 1.0],
	"vegetation": [0.0, 2.0],
	"biome_diversity": [0.0, 1.0],
	"temperature_offset": [-20.0, 20.0],
	"moisture_offset": [-0.5, 0.5],
	"rivers": [0, 32],
	"river_width": [0.3, 3.0],
	"water_fraction": [0.0, 0.8],
	"lakes": [0.0, 1.0],
	"warm_edge_temp": [-30.0, 45.0],
	"cold_edge_temp": [-40.0, 40.0],
	"lapse_rate": [0.0, 0.5],
	"max_height": [10.0, 400.0],
}


static func defaults() -> Dictionary:
	return {
		"seed": 20240611,
		"size": 512.0,              # metres (or "small"/"medium"/"large")
		"resolution": 257,          # grid samples per side (2^n + 1 recommended)
		"sea_level": 0.0,           # metres
		"relief": 0.5,              # 0 smooth plains .. 1 rugged complex terrain
		"mountains": 0.5,           # 0 none .. 1 high ranges
		"vegetation": 1.0,          # plant density multiplier 0..2
		"biome_diversity": 0.5,     # 0 smooth climate bands .. 1 patchwork
		"temperature_offset": 0.0,  # °C added everywhere
		"moisture_offset": 0.0,     # added to 0..1 humidity
		"rivers": 7,                # number of river sources
		"river_width": 1.0,         # river width multiplier
		"water_fraction": 0.32,     # target share of ocean cells
		"lakes": 0.6,               # 0 drain all depressions .. 1 keep every lake
		"warm_side": "south",       # "south" (+z) or "north" (−z): the equator edge
		"warm_edge_temp": 31.0,     # °C at sea level on the warm map edge
		"cold_edge_temp": -3.0,     # °C at sea level on the cold map edge
		"lapse_rate": 0.1,          # °C per metre (exaggerated for small maps)
		"max_height": 120.0,        # metres, peak scale for mountains = 1
	}


## Returns a clean config: defaults overlaid with valid user values.
static func sanitize(user: Dictionary) -> Dictionary:
	var c := defaults()
	for k in user:
		if c.has(k):
			c[k] = user[k]
	c["seed"] = _to_seed(c["seed"])
	c["size"] = _to_size(c["size"])
	for k in RANGES:
		var r: Array = RANGES[k]
		var fallback = defaults()[k]
		var v = c[k]
		if not (v is float or v is int):
			if v is String and (v as String).is_valid_float():
				v = float(v)
			else:
				push_warning("WorldConfig: '%s' has invalid value %s, using %s" % [k, str(v), str(fallback)])
				v = fallback
		if fallback is int:
			c[k] = clampi(int(v), int(r[0]), int(r[1]))
		else:
			var fv := float(v)
			if is_nan(fv) or is_inf(fv):
				fv = float(fallback)
			c[k] = clampf(fv, float(r[0]), float(r[1]))
	if str(c["warm_side"]) != "north":
		c["warm_side"] = "south"
	# Grid must keep cells between ~0.5 m and ~8 m.
	var size: float = c["size"]
	var res: int = c["resolution"]
	var cell := size / float(res - 1)
	if cell > 8.0 or cell < 0.5:
		var fixed := clampi(int(round(size / clampf(cell, 0.5, 8.0))) + 1, 33, 1025)
		push_warning("WorldConfig: resolution %d unsuitable for size %.0f, using %d" % [res, size, fixed])
		c["resolution"] = fixed
	return c


static func _to_seed(v) -> int:
	if v is int:
		return v
	if v is float:
		return int(v)
	if v is String:
		var s: String = v
		if s.is_valid_int():
			return s.to_int()
		return MathUtil.fnv1a(s)
	return int(defaults()["seed"])


static func _to_size(v) -> float:
	if v is String:
		var s: String = v
		if SIZE_PRESETS.has(s):
			return float(SIZE_PRESETS[s])
		if s.is_valid_float():
			return s.to_float()
		push_warning("WorldConfig: unknown size '%s'" % s)
		return float(defaults()["size"])
	if v is float or v is int:
		return float(v)
	return float(defaults()["size"])
