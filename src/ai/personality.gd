class_name Personality
extends RefCounted
## Behavioural traits of one individual (genome `behavior` category) cached as
## plain floats for the utility AI.

var aggression: float = 0.3
var boldness: float = 0.5
var sociality: float = 0.5
var curiosity: float = 0.5
var territoriality: float = 0.3
var parental_care: float = 0.5
var activity_phase: float = 0.0     # 0 diurnal .. 0.5 crepuscular .. 1 nocturnal
var vigilance: float = 0.5
var mate_selectivity: float = 0.4
var diet_preference: float = 0.1
var learning: float = 0.4
var brain: float = 0.3              # anatomy brain index


static func from_genome(g: Genome, brain_index: float = 0.3) -> Personality:
	var p := Personality.new()
	if g == null:
		return p
	p.aggression = g.value(&"aggression")
	p.boldness = g.value(&"boldness")
	p.sociality = g.value(&"sociality")
	p.curiosity = g.value(&"curiosity")
	p.territoriality = g.value(&"territoriality")
	p.parental_care = g.value(&"parental_care")
	p.activity_phase = g.value(&"activity_phase")
	p.vigilance = g.value(&"vigilance")
	p.mate_selectivity = g.value(&"mate_selectivity")
	p.diet_preference = g.value(&"diet_preference")
	p.learning = g.value(&"learning")
	p.brain = brain_index
	return p


## 1 when the creature's rhythm says it should be awake at this hour (0..24).
## Diurnal: awake by day; nocturnal: by night; crepuscular: dawn and dusk.
func activity_at(hour: float, daylight: float) -> float:
	var day := clampf(daylight, 0.0, 1.0)
	var twilight := clampf(1.0 - absf(day - 0.35) / 0.35, 0.0, 1.0)
	var diurnal := day
	var nocturnal := 1.0 - day
	var w_d := clampf(1.0 - activity_phase * 2.0, 0.0, 1.0)
	var w_n := clampf(activity_phase * 2.0 - 1.0, 0.0, 1.0)
	var w_c := 1.0 - w_d - w_n
	return clampf(w_d * diurnal + w_n * nocturnal + w_c * maxf(twilight, 0.35 * (diurnal + nocturnal)), 0.0, 1.0)
