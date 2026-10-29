class_name EcoDefaults
extends RefCounted
## Default plant species for worlds without a generated flora (tests, tools,
## sandbox presets). The real world supplies its own list from FloraSystem.
## Ecological parameters: temp/moisture optimum & tolerance, logistic growth
## r (per day), capacity (kg/m²), nutrition/toughness/toxicity for herbivores.

const SPECS := [
	{"name": "Луговая трава", "form": &"grass", "temp_opt": 16.0, "temp_tol": 12.0, "moist_opt": 0.5, "moist_tol": 0.3,
		"growth_rate": 0.35, "capacity": 0.6, "nutrition": 1.0, "toughness": 0.3, "toxicity": 0.0, "height": 0.4,
		"spread": 0.08, "seasonal": 0.5, "leaf": Color(0.42, 0.62, 0.22)},
	{"name": "Колючий кустарник", "form": &"shrub", "temp_opt": 18.0, "temp_tol": 11.0, "moist_opt": 0.45, "moist_tol": 0.3,
		"growth_rate": 0.12, "capacity": 1.5, "nutrition": 0.8, "toughness": 0.5, "toxicity": 0.1, "height": 1.5,
		"spread": 0.03, "seasonal": 0.3, "leaf": Color(0.3, 0.5, 0.2)},
	{"name": "Широколиственное дерево", "form": &"broadleaf_tree", "temp_opt": 16.0, "temp_tol": 9.0, "moist_opt": 0.65, "moist_tol": 0.25,
		"growth_rate": 0.05, "capacity": 8.0, "nutrition": 0.6, "toughness": 0.7, "toxicity": 0.05, "height": 8.0,
		"spread": 0.01, "seasonal": 0.8, "leaf": Color(0.24, 0.48, 0.16)},
	{"name": "Хвойное дерево", "form": &"conifer", "temp_opt": 4.0, "temp_tol": 9.0, "moist_opt": 0.55, "moist_tol": 0.3,
		"growth_rate": 0.04, "capacity": 6.0, "nutrition": 0.4, "toughness": 0.8, "toxicity": 0.15, "height": 10.0,
		"spread": 0.01, "seasonal": 0.05, "leaf": Color(0.15, 0.32, 0.2)},
	{"name": "Мох и лишайник", "form": &"grass", "temp_opt": 0.0, "temp_tol": 10.0, "moist_opt": 0.5, "moist_tol": 0.35,
		"growth_rate": 0.15, "capacity": 0.35, "nutrition": 0.6, "toughness": 0.4, "toxicity": 0.0, "height": 0.05,
		"spread": 0.05, "seasonal": 0.2, "leaf": Color(0.55, 0.6, 0.45)},
	{"name": "Кактус", "form": &"cactus", "temp_opt": 30.0, "temp_tol": 8.0, "moist_opt": 0.12, "moist_tol": 0.15,
		"growth_rate": 0.05, "capacity": 0.8, "nutrition": 0.7, "toughness": 0.6, "toxicity": 0.2, "height": 1.2,
		"spread": 0.02, "seasonal": 0.0, "leaf": Color(0.35, 0.55, 0.3)},
	{"name": "Тростник", "form": &"reed", "temp_opt": 20.0, "temp_tol": 10.0, "moist_opt": 0.85, "moist_tol": 0.15,
		"growth_rate": 0.25, "capacity": 1.2, "nutrition": 0.8, "toughness": 0.45, "toxicity": 0.0, "height": 1.8,
		"spread": 0.05, "seasonal": 0.4, "leaf": Color(0.5, 0.6, 0.3)},
	{"name": "Водоросли", "form": &"algae", "aquatic": true, "temp_opt": 18.0, "temp_tol": 12.0, "moist_opt": 1.0, "moist_tol": 1.0,
		"growth_rate": 0.5, "capacity": 0.4, "nutrition": 1.1, "toughness": 0.1, "toxicity": 0.0, "height": 0.3,
		"spread": 0.1, "seasonal": 0.3, "leaf": Color(0.25, 0.5, 0.3)},
]


static func plants() -> Array[PlantSpecies]:
	var out: Array[PlantSpecies] = []
	for i in SPECS.size():
		var d: Dictionary = SPECS[i]
		var p := PlantSpecies.new()
		p.id = i
		p.name = str(d["name"])
		p.form = d["form"]
		p.aquatic = bool(d.get("aquatic", false))
		p.temp_opt = float(d["temp_opt"])
		p.temp_tol = float(d["temp_tol"])
		p.moist_opt = float(d["moist_opt"])
		p.moist_tol = float(d["moist_tol"])
		p.growth_rate = float(d["growth_rate"])
		p.capacity = float(d["capacity"])
		p.nutrition = float(d["nutrition"])
		p.toughness = float(d["toughness"])
		p.toxicity = float(d["toxicity"])
		p.height = float(d["height"])
		p.spread = float(d["spread"])
		p.seasonal = float(d["seasonal"])
		p.color_leaf = d["leaf"]
		p.biomass_per_instance = maxf(0.5, p.capacity * 3.0)
		p.seed_value = 1000 + i
		out.append(p)
	return out
