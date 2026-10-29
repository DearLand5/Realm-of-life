class_name CoveringDef
extends RefCounted
## One body covering (integument) slot of a body plan. A plan has 1..4 slots;
## every BodyPart references a slot index. Biological properties come from
## TYPES (scaled by thickness and genome traits), visuals from colors/pattern.

const MAX_SLOTS := 4

## Per-type biological + visual baseline.
##   insulation: thermal insulation (0..1 per unit thickness)
##   armor: mechanical damage reduction (0..1 per unit thickness)
##   water_retention: resistance to desiccation (0..1)
##   flexibility: 1 = fully flexible (low locomotion penalty)
##   mass_per_area: kg/m^2 at thickness 1
##   roughness/specular/sheen/wet: shader baselines
##   needs_moisture: dries out on land without water (amphibian skin, slime)
const TYPES := {
	&"skin":     {"label": "Кожа",      "insulation": 0.15, "armor": 0.05, "water_retention": 0.5,  "flexibility": 1.0,  "mass_per_area": 1.5, "roughness": 0.55, "specular": 0.35, "sheen": 0.1, "wet": 0.05, "needs_moisture": false},
	&"scales":   {"label": "Чешуя",     "insulation": 0.1,  "armor": 0.25, "water_retention": 0.9,  "flexibility": 0.85, "mass_per_area": 3.0, "roughness": 0.4,  "specular": 0.5,  "sheen": 0.0, "wet": 0.0,  "needs_moisture": false},
	&"plates":   {"label": "Пластины",  "insulation": 0.1,  "armor": 0.55, "water_retention": 0.85, "flexibility": 0.6,  "mass_per_area": 8.0, "roughness": 0.6,  "specular": 0.3,  "sheen": 0.0, "wet": 0.0,  "needs_moisture": false},
	&"shell":    {"label": "Панцирь",   "insulation": 0.2,  "armor": 0.8,  "water_retention": 0.95, "flexibility": 0.25, "mass_per_area": 14.0, "roughness": 0.45, "specular": 0.45, "sheen": 0.0, "wet": 0.0, "needs_moisture": false},
	&"chitin":   {"label": "Хитин",     "insulation": 0.08, "armor": 0.45, "water_retention": 0.95, "flexibility": 0.55, "mass_per_area": 4.0, "roughness": 0.25, "specular": 0.7,  "sheen": 0.0, "wet": 0.0,  "needs_moisture": false},
	&"fur":      {"label": "Шерсть",    "insulation": 0.8,  "armor": 0.08, "water_retention": 0.55, "flexibility": 1.0,  "mass_per_area": 1.2, "roughness": 0.9,  "specular": 0.05, "sheen": 0.6, "wet": 0.0,  "needs_moisture": false},
	&"feathers": {"label": "Перья",     "insulation": 0.7,  "armor": 0.06, "water_retention": 0.6,  "flexibility": 0.95, "mass_per_area": 0.8, "roughness": 0.7,  "specular": 0.2,  "sheen": 0.35, "wet": 0.0, "needs_moisture": false},
	&"bristles": {"label": "Щетина",    "insulation": 0.4,  "armor": 0.15, "water_retention": 0.5,  "flexibility": 0.95, "mass_per_area": 1.0, "roughness": 0.85, "specular": 0.1,  "sheen": 0.3, "wet": 0.0,  "needs_moisture": false},
	&"slime":    {"label": "Слизь",     "insulation": 0.05, "armor": 0.02, "water_retention": 0.15, "flexibility": 1.0,  "mass_per_area": 1.0, "roughness": 0.08, "specular": 0.8,  "sheen": 0.0, "wet": 1.0,  "needs_moisture": true},
	&"membrane": {"label": "Мембрана",  "insulation": 0.02, "armor": 0.0,  "water_retention": 0.1,  "flexibility": 1.0,  "mass_per_area": 0.3, "roughness": 0.2,  "specular": 0.6,  "sheen": 0.0, "wet": 0.6,  "needs_moisture": true},
}

const PATTERNS: Array[StringName] = [
	&"none", &"countershade", &"stripes", &"spots", &"rosettes", &"bands", &"rings", &"mottled", &"gradient", &"reticulated",
]
const PATTERN_LABELS := {
	&"none": "Однотонный", &"countershade": "Противотень", &"stripes": "Полосы", &"spots": "Пятна",
	&"rosettes": "Розетки", &"bands": "Поперечные полосы", &"rings": "Кольца", &"mottled": "Крапчатый",
	&"gradient": "Градиент", &"reticulated": "Сетчатый",
}

var type: StringName = &"skin"
var color_a: Color = Color(0.55, 0.45, 0.35)   # primary (dorsal) color
var color_b: Color = Color(0.85, 0.8, 0.7)     # secondary (pattern / ventral) color
var pattern: StringName = &"countershade"
var pattern_scale: float = 1.0
var pattern_contrast: float = 0.6
var thickness: float = 1.0      # relative (0.2 .. 3)
var roughness_bias: float = 0.0 # -0.5 .. 0.5 on top of type baseline
var iridescence: float = 0.0    # 0..1 (chitin, feathers, scales)


func props() -> Dictionary:
	return TYPES.get(type, TYPES[&"skin"])


func insulation() -> float:
	return float(props()["insulation"]) * thickness


func armor() -> float:
	return clampf(float(props()["armor"]) * thickness, 0.0, 0.95)


func water_retention() -> float:
	return clampf(float(props()["water_retention"]) * (0.7 + 0.3 * thickness), 0.0, 1.0)


func flexibility() -> float:
	return clampf(float(props()["flexibility"]) - 0.1 * maxf(0.0, thickness - 1.0), 0.05, 1.0)


func mass_per_area() -> float:
	return float(props()["mass_per_area"]) * thickness


func duplicate_def() -> CoveringDef:
	var c := CoveringDef.new()
	c.from_dict(to_dict())
	return c


func to_dict() -> Dictionary:
	return {
		"type": str(type), "color_a": Serial.color(color_a), "color_b": Serial.color(color_b),
		"pattern": str(pattern), "pattern_scale": pattern_scale, "pattern_contrast": pattern_contrast,
		"thickness": thickness, "roughness_bias": roughness_bias, "iridescence": iridescence,
	}


func from_dict(d: Dictionary) -> CoveringDef:
	var t := Serial.sn(d, "type", &"skin")
	type = t if TYPES.has(t) else &"skin"
	color_a = Serial.to_color(d.get("color_a"), color_a)
	color_b = Serial.to_color(d.get("color_b"), color_b)
	var p := Serial.sn(d, "pattern", &"none")
	pattern = p if PATTERNS.has(p) else &"none"
	pattern_scale = clampf(Serial.f(d, "pattern_scale", 1.0), 0.1, 5.0)
	pattern_contrast = clampf(Serial.f(d, "pattern_contrast", 0.6), 0.0, 1.0)
	thickness = clampf(Serial.f(d, "thickness", 1.0), 0.1, 4.0)
	roughness_bias = clampf(Serial.f(d, "roughness_bias", 0.0), -0.5, 0.5)
	iridescence = clampf(Serial.f(d, "iridescence", 0.0), 0.0, 1.0)
	return self


static func make(t: StringName, a: Color, b: Color, pat: StringName = &"countershade") -> CoveringDef:
	var c := CoveringDef.new()
	c.type = t
	c.color_a = a
	c.color_b = b
	c.pattern = pat
	return c
