class_name PlantSpecies
extends RefCounted
## A procedurally generated plant species: ecological parameters (simulated
## by EcosystemSimulation / EcoGrid) + visual parameters (rendered by flora).
## Biomass is stored per grid cell in kg/m².

const FORMS: Array[StringName] = [
	&"grass", &"shrub", &"broadleaf_tree", &"conifer", &"palm", &"cactus", &"fern",
	&"reed", &"flower", &"mushroom", &"kelp", &"algae",
]

var id: int = 0
var name: String = ""
var form: StringName = &"grass"
var aquatic := false             # grows only under water
var temp_opt: float = 18.0       # °C
var temp_tol: float = 10.0       # °C (gaussian width)
var moist_opt: float = 0.5       # 0..1
var moist_tol: float = 0.3
var growth_rate: float = 0.25    # logistic r per biological day
var capacity: float = 0.6        # kg/m² at ideal conditions
var nutrition: float = 1.0       # energy multiplier for herbivores
var toughness: float = 0.3       # 0..1 lowers digestibility
var toxicity: float = 0.0        # 0..1
var height: float = 0.5          # m, visual adult height
var spread: float = 0.05         # seed dispersal fraction per day to neighbours
var seasonal: float = 0.3        # 0 evergreen .. 1 strongly deciduous / annual
var color_leaf := Color(0.3, 0.55, 0.2)
var color_trunk := Color(0.35, 0.25, 0.15)
var color_flower := Color(0.9, 0.8, 0.3)
var biomass_per_instance: float = 2.0  # kg represented by one rendered instance
var seed_value: int = 0          # visual mesh seed


## 0..1 environmental suitability.
func suitability(temp: float, moist: float, in_water: bool) -> float:
	if aquatic != in_water:
		return 0.0
	return MathUtil.tolerance(temp, temp_opt, temp_tol) * MathUtil.tolerance(moist, moist_opt, moist_tol)


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "form": str(form), "aquatic": aquatic, "temp_opt": temp_opt, "temp_tol": temp_tol,
		"moist_opt": moist_opt, "moist_tol": moist_tol, "growth_rate": growth_rate, "capacity": capacity,
		"nutrition": nutrition, "toughness": toughness, "toxicity": toxicity, "height": height, "spread": spread,
		"seasonal": seasonal, "color_leaf": Serial.color(color_leaf), "color_trunk": Serial.color(color_trunk),
		"color_flower": Serial.color(color_flower), "biomass_per_instance": biomass_per_instance, "seed": seed_value,
	}


static func from_dict(d: Dictionary) -> PlantSpecies:
	var p := PlantSpecies.new()
	p.id = Serial.i(d, "id", 0)
	p.name = Serial.s(d, "name", "Растение")
	p.form = Serial.sn(d, "form", &"grass")
	p.aquatic = Serial.b(d, "aquatic", false)
	p.temp_opt = Serial.f(d, "temp_opt", 18.0)
	p.temp_tol = Serial.f(d, "temp_tol", 10.0)
	p.moist_opt = Serial.f(d, "moist_opt", 0.5)
	p.moist_tol = Serial.f(d, "moist_tol", 0.3)
	p.growth_rate = Serial.f(d, "growth_rate", 0.25)
	p.capacity = Serial.f(d, "capacity", 0.6)
	p.nutrition = Serial.f(d, "nutrition", 1.0)
	p.toughness = Serial.f(d, "toughness", 0.3)
	p.toxicity = Serial.f(d, "toxicity", 0.0)
	p.height = Serial.f(d, "height", 0.5)
	p.spread = Serial.f(d, "spread", 0.05)
	p.seasonal = Serial.f(d, "seasonal", 0.3)
	p.color_leaf = Serial.to_color(d.get("color_leaf"), p.color_leaf)
	p.color_trunk = Serial.to_color(d.get("color_trunk"), p.color_trunk)
	p.color_flower = Serial.to_color(d.get("color_flower"), p.color_flower)
	p.biomass_per_instance = Serial.f(d, "biomass_per_instance", 2.0)
	p.seed_value = Serial.i(d, "seed", 0)
	return p
