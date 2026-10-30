class_name PoolRates
extends RefCounted
## Per-capita rate breakdown of one SpeciesPool from its last sub-step — the
## data behind a "why is this population growing / declining" UI.
## Energy terms are W per capita; demographic terms are events per capita
## per game day (biological time).

const DAY := Units.SECONDS_PER_DAY
const FOOD_LABELS := ["Растения", "Мясо", "Падаль", "Детрит", "Планктон"]

# Energy income (W): digested food by kind, photosynthesis, kills.
var intake_w := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var photo_w: float = 0.0
var predation_w: float = 0.0
# Energy demand (W).
var bmr_w: float = 0.0              # maintenance (basal + immune/brain upkeep)
var activity_w: float = 0.0
var thermo_w: float = 0.0           # thermoregulation beyond basal
var growth_w: float = 0.0           # juvenile growth
var birth_w: float = 0.0            # reproduction investment
# Demography (per capita per day).
var births: float = 0.0             # recruits (offspring surviving to juvenile)
var deaths := {
	"starvation": 0.0, "senescence": 0.0, "juvenile": 0.0, "predation": 0.0,
	"thermal": 0.0, "habitat": 0.0, "water": 0.0, "disease": 0.0, "background": 0.0,
}
var growth_rate: float = 0.0        # net per capita per day
var energy_fraction: float = 0.0


func income_total() -> float:
	var t := photo_w + predation_w
	for v in intake_w:
		t += v
	return t


func demand_total() -> float:
	return bmr_w + activity_w + thermo_w + growth_w + birth_w


func death_total() -> float:
	var t := 0.0
	for k in deaths:
		t += float(deaths[k])
	return t


## Dominant cause of death (key of `deaths`).
func main_cause() -> String:
	var best := ""
	var bv := -1.0
	for k in deaths:
		if float(deaths[k]) > bv:
			bv = float(deaths[k])
			best = str(k)
	return best


func to_dict() -> Dictionary:
	return {
		"intake_w": Array(intake_w), "photo_w": photo_w, "predation_w": predation_w, "bmr_w": bmr_w,
		"activity_w": activity_w, "thermo_w": thermo_w, "growth_w": growth_w, "birth_w": birth_w,
		"births": births, "deaths": deaths.duplicate(), "growth_rate": growth_rate, "energy": energy_fraction,
	}
