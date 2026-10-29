class_name Biomes
extends RefCounted
## Biome catalogue (Whittaker-style: mean temperature × moisture, plus water
## and altitude classes). Ids are stable — they are stored in WorldData.biome.

enum {
	OCEAN, BEACH, DESERT, SAVANNA, GRASSLAND, TEMPERATE_FOREST, RAINFOREST,
	TAIGA, TUNDRA, SWAMP, MOUNTAIN, SNOW, LAKE, RIVER, COUNT,
}

## label, ground colour, vegetation capacity factor (0..1), water flag
const INFO := [
	{"id": "ocean", "label": "Океан", "color": Color(0.10, 0.25, 0.42), "veg": 0.25, "water": true},
	{"id": "beach", "label": "Побережье", "color": Color(0.82, 0.76, 0.56), "veg": 0.2, "water": false},
	{"id": "desert", "label": "Пустыня", "color": Color(0.86, 0.72, 0.46), "veg": 0.08, "water": false},
	{"id": "savanna", "label": "Саванна", "color": Color(0.70, 0.64, 0.32), "veg": 0.45, "water": false},
	{"id": "grassland", "label": "Равнина", "color": Color(0.42, 0.58, 0.24), "veg": 0.7, "water": false},
	{"id": "temperate_forest", "label": "Лес", "color": Color(0.24, 0.42, 0.18), "veg": 0.9, "water": false},
	{"id": "rainforest", "label": "Джунгли", "color": Color(0.14, 0.36, 0.14), "veg": 1.0, "water": false},
	{"id": "taiga", "label": "Тайга", "color": Color(0.22, 0.34, 0.24), "veg": 0.6, "water": false},
	{"id": "tundra", "label": "Тундра", "color": Color(0.55, 0.56, 0.46), "veg": 0.25, "water": false},
	{"id": "swamp", "label": "Болото", "color": Color(0.26, 0.33, 0.2), "veg": 0.85, "water": false},
	{"id": "mountain", "label": "Горы", "color": Color(0.46, 0.43, 0.40), "veg": 0.15, "water": false},
	{"id": "snow", "label": "Ледник", "color": Color(0.92, 0.94, 0.97), "veg": 0.0, "water": false},
	{"id": "lake", "label": "Озеро", "color": Color(0.16, 0.35, 0.45), "veg": 0.3, "water": true},
	{"id": "river", "label": "Река", "color": Color(0.2, 0.4, 0.5), "veg": 0.3, "water": true},
]


static func label(id: int) -> String:
	return INFO[clampi(id, 0, COUNT - 1)]["label"]


static func color(id: int) -> Color:
	return INFO[clampi(id, 0, COUNT - 1)]["color"]


static func vegetation(id: int) -> float:
	return float(INFO[clampi(id, 0, COUNT - 1)]["veg"])


static func is_water(id: int) -> bool:
	return bool(INFO[clampi(id, 0, COUNT - 1)]["water"])


## Whittaker classification for land cells. temp: annual mean °C, moist 0..1.
static func classify(temp: float, moist: float, height_above_sea: float, slope: float) -> int:
	if height_above_sea < 1.2 and slope < 0.25:
		return BEACH
	if temp < -6.0 or height_above_sea > 95.0:
		return SNOW
	if slope > 0.9 or height_above_sea > 70.0:
		return MOUNTAIN
	if temp < 0.0:
		return TUNDRA
	if moist > 0.82 and height_above_sea < 8.0 and temp > 4.0:
		return SWAMP
	if temp < 7.0:
		return TAIGA if moist > 0.35 else TUNDRA
	if temp < 19.0:
		if moist < 0.22:
			return DESERT
		if moist < 0.45:
			return GRASSLAND
		return TEMPERATE_FOREST
	if moist < 0.25:
		return DESERT
	if moist < 0.5:
		return SAVANNA
	return RAINFOREST
