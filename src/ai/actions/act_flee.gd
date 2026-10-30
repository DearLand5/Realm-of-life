class_name ActFlee
extends AiAction
## Flee: run from a perceived predator toward the best escape — away from it,
## through passable ground, preferring cover, water (for good swimmers), the
## group and home. Warns the group with an alarm call. Cornered animals fight back.

const ANGLES := [0.0, 25.0, -25.0, 50.0, -50.0, 80.0, -80.0, 115.0, -115.0, 150.0, -150.0, 180.0]

var last_threat := Vector3.INF
var last_seen: float = -100.0
var _dir := Vector3.ZERO
var _alarm_t: float = -100.0


func _init() -> void:
	id = &"flee"
	label = "Убегает"
	min_commit = 2.0
	emergency = true


func score() -> float:
	var thr := 0.14 if a.brain.current == self else 0.32   # hysteresis: keep running a while
	if a.individual.is_egg() or needs.fear < thr:
		return 0.0
	return 0.55 + 1.45 * needs.fear


func start() -> void:
	super.start()
	_dir = Vector3.ZERO
	a.sleeping = false


func activity() -> float:
	return 0.9


func pose() -> StringName:
	return &"flee"


func update(_dt: float) -> void:
	var per := a.perception
	var th := per.threat
	if th != null and th.confidence > 0.2:
		last_threat = th.predicted(a.now)
		last_seen = a.now
		if th.fresh:
			a.memory.note(CreatureMemory.SPOT_DANGER, th.pos, 0.7, a.now)
	if last_threat == Vector3.INF:
		finished = true
		return
	var pos := a.mover.pos
	var away := pos - last_threat
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = -a.mover.forward()
	away = away.normalized()
	# Alarm the group.
	if a.now - _alarm_t > 4.0 and (a.personality.sociality > 0.25 or th != null and th.fresh) and a.perception.neighbours > 0:
		_alarm_t = a.now
		a.emit_call(&"alarm", 1.6)
	# Choose the escape heading.
	var burst := a.burst_speed()
	var run_len := clampf(10.0 + burst * 2.5, 12.0, 38.0)
	var centroid: Array = [Vector3.INF]
	Flocking.pull(a, centroid)
	var home := a.memory.home
	var best_s := -INF
	var best_p := Vector3.INF
	var any_free := false
	for ang in ANGLES:
		var d := away.rotated(Vector3.UP, deg_to_rad(ang))
		var p := pos + d * run_len
		var s := d.dot(away) * 1.0 + 0.2 * d.dot(_dir)
		var ok := a.is_open_ground(p)
		if not ok:
			s -= 2.5
		else:
			any_free = true
		s += 0.35 * WorldScan.vegetation_density(a.ctx, p)
		s -= 0.8 * a.memory.danger_at(p, 20.0)
		if centroid[0] != Vector3.INF:
			s += 0.25 * a.personality.sociality * d.dot((centroid[0] - pos).normalized())
		if home != Vector3.INF and home.distance_to(pos) < 70.0:
			s += 0.2 * d.dot((home - pos).normalized())
		if s > best_s:
			best_s = s
			best_p = p
	if best_p != Vector3.INF:
		_dir = (best_p - pos).normalized()
	# Cornered: turn and fight.
	if not any_free and th != null and th.agent is CreatureAgent and th.dist < a.body_length() + 2.0:
		a.go_node(th.agent, burst, 0.5)
		var res := a.attack(th.agent as CreatureAgent)
		if res.get("hit", false):
			target_text = "защищается"
		return
	a.go(best_p, burst, 0.5)
	a.intent.sprint = a.stamina() > 0.15
	a.intent.urgency = 1.0
	if a.mover.lp.can_fly and not a.mover.flying and a.mover.medium != &"water":
		a.intent.fly = true
		a.intent.altitude = 8.0
	elif a.mover.flying:
		a.intent.fly = true
		a.intent.altitude = 8.0
	target_text = "хищник"
	# Safe again?
	var d_thr := pos.distance_to(last_threat)
	if per.threat_level < 0.08 and a.now - last_seen > 6.0:
		finished = true
	elif d_thr > a.flight_distance() * 3.0 and a.now - last_seen > 3.0 and per.threat_level < 0.2:
		finished = true
