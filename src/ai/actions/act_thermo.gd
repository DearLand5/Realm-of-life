class_name ActThermo
extends AiAction
## Thermoregulation: when too hot or too cold, move toward a better spot — cooler
## or warmer ground (sampled around the animal), water for amphibious/aquatic
## species when overheated — otherwise keep still to save energy.

var goal := Vector3.INF
var _resample: float = 0.0


func _init() -> void:
	id = &"thermo"
	label = "Ищет комфортную температуру"
	min_commit = 5.0


func score() -> float:
	if needs.thermal < 0.25 or a.individual.is_egg():
		return 0.0
	return needs.thermal * 0.95 * clampf(1.0 - 1.5 * needs.fear, 0.0, 1.0)


func start() -> void:
	super.start()
	goal = Vector3.INF
	_resample = 0.0


func activity() -> float:
	return 0.15


func update(dt: float) -> void:
	_resample -= dt
	if _resample <= 0.0 or goal == Vector3.INF:
		_resample = 4.0
		goal = _choose()
	if goal == Vector3.INF:
		a.stop_moving()
		target_text = "переждать"
		if needs.thermal < 0.12:
			finished = true
		return
	target_text = "прохладнее" if needs.hot else "теплее"
	a.go(goal, a.cruise_speed() * 0.8, 1.2)
	if Vector2(goal.x - a.mover.pos.x, goal.z - a.mover.pos.z).length() < 1.5:
		goal = Vector3.INF
		if needs.thermal < 0.15:
			finished = true


func _choose() -> Vector3:
	var clim := a.ctx.climate
	if clim == null:
		return Vector3.INF
	var p := a.phys
	var here := clim.temperature_at(a.mover.pos)
	var best := Vector3.INF
	var best_err := absf(here - p.thermal_optimum)
	var per := a.perception
	# Overheated: a swim helps if the body can use water.
	if needs.hot and per.water_pos != Vector3.INF and a.now - per.water_t < 60.0 and (p.habitat in [&"water", &"amphibious"] or a.mover.lp.can_swim):
		return per.water_pos
	for i in 8:
		var d := Vector3(cos(TAU * float(i) / 8.0), 0.0, sin(TAU * float(i) / 8.0))
		var q := a.mover.pos + d * 16.0
		if not a.is_open_ground(q):
			continue
		var t := clim.temperature_at(Vector3(q.x, a.ctx.ground_height(q.x, q.z), q.z))
		var err := absf(t - p.thermal_optimum)
		if err < best_err - 0.3:
			best_err = err
			best = q
	return best
