class_name ActNest
extends AiAction
## LayEggs / GiveBirth: a female close to term goes to a safe place — home, a
## remembered shelter, or the water's edge for species whose eggs need water —
## and stays calm there until BiologySystem delivers (agent spawns the young).

var site := Vector3.INF


func _init() -> void:
	id = &"nest"
	label = "Готовится к родам"
	min_commit = 6.0


func _term_fraction() -> float:
	var ind := a.individual
	var p := a.phys
	var total := p.egg_formation_s if p.repro_method in [&"eggs", &"spores"] else p.gestation_s
	return 1.0 - ind.gestation_left / maxf(total, 600.0)


func score() -> float:
	var ind := a.individual
	if not ind.pregnant or ind.is_egg() or _term_fraction() < 0.7:
		return 0.0
	return 0.6 * clampf(1.0 - 1.5 * needs.fear, 0.0, 1.0) * clampf(1.0 - 0.7 * maxf(needs.hunger, needs.thirst), 0.3, 1.0)


func start() -> void:
	super.start()
	site = Vector3.INF
	var p := a.phys
	if p.habitat in [&"water", &"amphibious"] and a.perception.water_pos != Vector3.INF and p.repro_method in [&"eggs", &"spores"]:
		site = a.perception.water_pos
	else:
		site = a.memory.recall(CreatureMemory.SPOT_SHELTER, a.mover.pos)
		if site == Vector3.INF:
			site = a.memory.home
	if site != Vector3.INF and not a.can_reach(site):
		site = Vector3.INF


func activity() -> float:
	return 0.08


func update(_dt: float) -> void:
	target_text = "гнездо"
	if site != Vector3.INF and Vector2(site.x - a.mover.pos.x, site.z - a.mover.pos.z).length() > 3.0 and a.mover.stuck < 2.0:
		a.go(site, a.cruise_speed() * 0.5, 2.0)
		return
	a.stop_moving()
	a.memory.note(CreatureMemory.SPOT_HOME, a.mover.pos, 0.9, a.now)
	if not a.individual.pregnant:
		finished = true
