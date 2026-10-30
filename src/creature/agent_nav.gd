class_name AgentNav
extends RefCounted
## Navigation helpers of CreatureAgent: valid spawn/goal selection by body type
## (water for fish, dry ground for walkers), travel mode (walk, fly, swim depth).


## Fixes a spawn position the body cannot use: fish on land are moved to water,
## walkers in deep water to the nearest shore.
static func fix_spawn(a: CreatureAgent) -> void:
	var m := a.mover
	if a.ctx.world == null or a.individual.is_egg():
		return
	var ok := m.can_stand(m.pos.x, m.pos.z, false) or m.flying
	if ok:
		return
	var want_water := m.aquatic_only
	var spot := _nearest_valid(a, m.pos, 80.0, want_water)
	if spot != Vector3.INF:
		m.teleport(spot)
		a.position = m.pos


static func _nearest_valid(a: CreatureAgent, from: Vector3, radius: float, water: bool) -> Vector3:
	var m := a.mover
	if water:
		var wp := a.ctx.world.find_water_near(from, radius, false)
		if wp != Vector3.INF and m.can_stand(wp.x, wp.z, false):
			return Vector3(wp.x, wp.y, wp.z)
	var step := 3.0
	var r := step
	while r <= radius:
		for i in 12:
			var ang := TAU * float(i) / 12.0
			var q := from + Vector3(cos(ang), 0.0, sin(ang)) * r
			if m.can_stand(q.x, q.z, true) and (not water or a.ctx.world.water_depth_at(q.x, q.z) > m.height * 0.6):
				return Vector3(q.x, a.ctx.ground_height(q.x, q.z), q.z)
		r += step
	return Vector3.INF


static func offspring_position(a: CreatureAgent, kid: Individual) -> Vector3:
	var p := kid.position
	if a.ctx.world == null:
		return p
	var kid_water := kid.physiology().habitat == &"water"
	var depth := a.ctx.world.water_depth_at(p.x, p.z)
	if kid_water and depth > 0.1:
		return Vector3(p.x, a.ctx.world.water_surface_at(p.x, p.z) - minf(depth, 0.5), p.z)
	p.y = a.ctx.ground_height(p.x, p.z)
	return p


## Small, quick fliers use the air for travel; heavy gliders and ground birds walk.
static func prefers_air(a: CreatureAgent) -> bool:
	var lp := a.mover.lp
	return lp.can_fly and (lp.fly_speed > 2.0 * lp.best_land_speed() or lp.can_hover)


## Sets fly/swim parameters of the intent for a trip to `target`.
static func set_travel_mode(a: CreatureAgent, target: Vector3) -> void:
	var m := a.mover
	var it := a.intent
	var lp := m.lp
	var flat := Vector2(target.x - m.pos.x, target.z - m.pos.z).length()
	if lp.can_fly and m.medium != &"water":
		if lp.can_hover:
			it.fly = true
			it.altitude = clampf(m.height * 2.0 + 0.6, 0.8, 3.0)
		elif m.flying:
			it.fly = flat > 5.0
			it.altitude = 6.0 + minf(flat * 0.1, 8.0)
		else:
			it.fly = flat > 28.0 and prefers_air(a)
			it.altitude = 7.0
	else:
		it.fly = false
	var phys := a.phys
	it.avoid_water = not (phys.habitat == &"water" or phys.habitat == &"amphibious")
	if m.medium == &"water":
		var gills_only := phys.gills_w > 0.0 and phys.lungs_w <= 0.0
		it.surface = not gills_only
		it.altitude = clampf(m.water_depth * 0.45, 0.4, 6.0)


static func is_open_ground(a: CreatureAgent, p: Vector3) -> bool:
	if a.mover.lp.can_fly and a.mover.flying:
		return a.ctx.world == null or a.ctx.world.contains(p.x, p.z)
	return a.mover.can_stand(p.x, p.z, true)


static func can_reach(a: CreatureAgent, p: Vector3) -> bool:
	if a.mover.flying:
		return true
	return a.mover.can_stand(p.x, p.z, false)


static func pick_wander_goal(a: CreatureAgent, radius: float) -> Vector3:
	var m := a.mover
	var rng := a.rng
	var best := Vector3.INF
	var best_s := -INF
	var home := a.memory.home
	for i in 7:
		var ang := rng.range_f(0.0, TAU)
		var dist := rng.range_f(radius * 0.35, radius)
		var d := Vector3(cos(ang), 0.0, sin(ang))
		var p := m.pos + d * dist
		if not is_open_ground(a, p):
			continue
		var s := rng.range_f(0.0, 0.4)
		# Keep within reach of home, avoid remembered danger and prefer straight continuation.
		if home != Vector3.INF:
			var hd := p.distance_to(home)
			s -= clampf((hd - 60.0) / 60.0, 0.0, 1.0)
		s -= 1.2 * a.memory.danger_at(p, 20.0)
		s += 0.25 * d.dot(m.forward())
		if a.brain != null and a.brain.needs.hunger > 0.3:
			var food := a.memory.recall(CreatureMemory.SPOT_FOOD, m.pos)
			if food != Vector3.INF:
				s += 0.6 * d.dot((food - m.pos).normalized())
		if s > best_s:
			best_s = s
			best = p
	if best != Vector3.INF:
		best.y = a.ctx.ground_height(best.x, best.z)
	return best


## Is there water right in front of the mouth (or underfoot)?
static func water_in_reach(a: CreatureAgent) -> bool:
	var w := a.ctx.world
	if w == null:
		return false
	var m := a.mover
	var f := m.forward()
	var L := m.length
	for t in [0.0, 0.55, 1.05]:
		var q := m.pos + f * (L * float(t))
		if w.water_depth_at(q.x, q.z) > 0.03:
			return true
	return false


static func distance_to_water(a: CreatureAgent) -> float:
	var w := a.ctx.world
	if w == null:
		return INF
	var wp := w.find_water_near(a.mover.pos, 12.0, false)
	if wp == Vector3.INF:
		return INF
	return Vector2(wp.x - a.mover.pos.x, wp.z - a.mover.pos.z).length()
