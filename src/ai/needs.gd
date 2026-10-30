class_name Needs
extends RefCounted
## Motivational state of a creature, all 0..1. Recomputed at the AI rate.
##   hunger, thirst   from reserves, stomach and hydration
##   sleep            fatigue + circadian rhythm (diurnal / crepuscular / nocturnal)
##   fear             perceived danger (rises fast, decays slowly)
##   thermal          discomfort from heat/cold stress and ambient temperature
##   mate             reproductive drive (maturity, season, energy, readiness)
##   social           loneliness x sociality
##   territory        urge to patrol / defend (territorial adults with a home)
##   parental         urge to stay with eggs / young

var hunger: float = 0.0
var thirst: float = 0.0
var sleep: float = 0.0
var fear: float = 0.0
var thermal: float = 0.0
var mate: float = 0.0
var social: float = 0.0
var territory: float = 0.0
var parental: float = 0.0
var awake: float = 1.0          # circadian readiness to be active
var ready_to_breed := false
var hot := false                # direction of thermal discomfort


func update(a: CreatureAgent, dt: float) -> void:
	var ind := a.individual
	var p := a.phys
	var pers := a.personality
	var ctx := a.ctx
	var clim := ctx.climate
	var ef := ind.energy_fraction()
	if p.diet == &"photosynth":
		hunger = 0.0
	else:
		hunger = clampf(((1.0 - ef) - 0.25) / 0.55, 0.0, 1.0) * (1.0 - 0.6 * ind.stomach_fullness())
	var aquatic_wet := p.habitat == &"water" and a.mover.medium == &"water"
	thirst = 0.0 if (aquatic_wet or p.aquatic) else clampf((1.0 - ind.hydration - 0.04) / 0.2, 0.0, 1.0)
	var day := clim.daylight if clim != null else 1.0
	awake = pers.activity_at(clim.hour if clim != null else 12.0, day)
	var tired := 1.0 - a.stamina()
	sleep = clampf(ind.fatigue * 0.9 + a.muscles.mean_fatigue() * 0.4, 0.0, 1.0) * 0.75 + (1.0 - awake) * 0.55 + 0.6 * tired * tired * tired
	if ind.stage == &"juvenile":
		sleep *= 0.8
	# Fear: instant rise, slow decay; bold animals fear less.
	var f_in := a.perception.threat_level * lerpf(1.25, 0.7, pers.boldness)
	fear = maxf(fear - 0.12 * dt, 0.0)
	if f_in > fear:
		fear = minf(f_in, 1.0)
	# Thermal comfort.
	var stress := maxf(ind.heat_stress, ind.cold_stress)
	hot = ind.heat_stress >= ind.cold_stress
	var env_t := clim.temperature_at(a.mover.pos) if clim != null else p.thermal_optimum
	var ecto := 1.0 - p.endothermy
	var off := absf(env_t - p.thermal_optimum) / maxf(p.thermal_tolerance, 1.0)
	thermal = clampf(stress * 2.0 + ecto * clampf(off - 0.8, 0.0, 1.0) * 0.8, 0.0, 1.0)
	if ecto > 0.3 and stress < 0.05:
		hot = env_t > p.thermal_optimum
	# Reproduction.
	ready_to_breed = Reproduction.is_ready(ind, clim) and p.repro_mode != &"asexual"
	var bred := 0.0
	if ready_to_breed:
		bred = (0.55 + 0.35 * ef) * (1.0 - 0.8 * hunger) * (1.0 - 0.7 * thirst) * lerpf(0.6, 1.0, awake)
	mate = bred
	# Social.
	social = pers.sociality * clampf(1.0 - float(a.perception.neighbours) / 2.5, 0.0, 1.0) * (0.5 if ind.stage == &"adult" else 0.9)
	territory = pers.territoriality * (1.0 if (a.memory.home != Vector3.INF and ind.is_mature()) else 0.0)
	parental = 0.0
	if a.has_dependants():
		parental = clampf(pers.parental_care * 1.2, 0.0, 1.0)


func to_dict() -> Dictionary:
	return {"hunger": hunger, "thirst": thirst, "fatigue": sleep, "fear": fear, "temperature_discomfort": thermal,
		"mate": mate, "social": social}
