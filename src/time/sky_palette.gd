class_name SkyPalette
extends RefCounted
## Sky / light colours as a function of sun elevation (degrees), blended
## toward overcast grey by cloud cover and toward haze by fog.

const ELEV: Array[float] = [-18.0, -9.0, -4.0, 1.0, 7.0, 18.0, 40.0]
const ZENITH: Array[Color] = [
	Color(0.006, 0.009, 0.024), Color(0.02, 0.03, 0.08), Color(0.09, 0.12, 0.28),
	Color(0.2, 0.3, 0.56), Color(0.24, 0.42, 0.76), Color(0.2, 0.42, 0.82), Color(0.15, 0.37, 0.8),
]
const HORIZON: Array[Color] = [
	Color(0.014, 0.018, 0.04), Color(0.07, 0.07, 0.13), Color(0.5, 0.31, 0.3),
	Color(0.96, 0.56, 0.33), Color(0.92, 0.74, 0.58), Color(0.72, 0.8, 0.9), Color(0.64, 0.77, 0.92),
]
const SUN: Array[Color] = [
	Color(1.0, 0.35, 0.15), Color(1.0, 0.35, 0.15), Color(1.0, 0.42, 0.2),
	Color(1.0, 0.56, 0.3), Color(1.0, 0.76, 0.52), Color(1.0, 0.91, 0.78), Color(1.0, 0.97, 0.92),
]
const GLOW: Array[float] = [0.0, 0.05, 0.6, 1.0, 0.7, 0.25, 0.08]


static func sample_color(table: Array[Color], elev: float) -> Color:
	if elev <= ELEV[0]:
		return table[0]
	for k in ELEV.size() - 1:
		if elev <= ELEV[k + 1]:
			var t := (elev - ELEV[k]) / (ELEV[k + 1] - ELEV[k])
			return table[k].lerp(table[k + 1], smoothstep(0.0, 1.0, t))
	return table[table.size() - 1]


static func sample_float(table: Array[float], elev: float) -> float:
	if elev <= ELEV[0]:
		return table[0]
	for k in ELEV.size() - 1:
		if elev <= ELEV[k + 1]:
			var t := (elev - ELEV[k]) / (ELEV[k + 1] - ELEV[k])
			return lerpf(table[k], table[k + 1], smoothstep(0.0, 1.0, t))
	return table[table.size() - 1]


## Mixes a clear-sky colour toward overcast grey/fog haze of similar brightness.
static func overcast(c: Color, cloud: float, fog: float, daylight: float) -> Color:
	# Thick cloud is darker underneath.
	var grey_level := lerpf(0.05, 0.62, daylight) * (1.0 - 0.32 * cloud * cloud)
	var grey := Color(grey_level * 0.94, grey_level * 0.98, grey_level * 1.04)
	var out := c.lerp(grey, clampf(pow(cloud, 1.6) * 0.85, 0.0, 1.0))
	var haze := Color(grey_level * 1.02, grey_level * 1.04, grey_level * 1.06)
	return out.lerp(haze, clampf(fog * 0.9, 0.0, 1.0))
