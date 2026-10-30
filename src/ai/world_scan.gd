class_name WorldScan
extends RefCounted
## Perception of the non-creature world: terrain line of sight, vegetation
## density, food (plants, detritus, plankton), carcasses and water. Everything
## obeys the creature's senses (range, field of view) — see Perception.

const FOOD_EXPIRE := 25.0       # s a sighted food patch stays "current" without a fresh sighting
const MIN_PLANT_KG_M2 := 0.04   # biomass density a grazer bothers with


## Terrain-only line of sight between two world points (few height samples).
static func line_of_sight(ctx: WorldContext, a: Vector3, b: Vector3) -> bool:
	if ctx.world == null:
		return true
	var d := a.distance_to(b)
	if d < 3.0:
		return true
	var n := clampi(int(d / 5.0), 1, 5)
	for i in range(1, n + 1):
		var t := float(i) / float(n + 1)
		var p := a.lerp(b, t)
		if p.y < ctx.world.height_at(p.x, p.z) + 0.05:
			return false
	return true


## 0..1 amount of low vegetation around a point (EcoGrid biomass; 0 without ecology).
static func vegetation_density(ctx: WorldContext, p: Vector3) -> float:
	var eco := ctx.eco as EcoGrid
	if eco == null:
		return 0.0
	var c := eco.cell_coords(p)
	var total := 0.0
	for sp in eco.plant_species.size():
		total += eco.biomass(c.x, c.y, sp)
	return clampf(total / 1.6, 0.0, 1.0)


static func _in_static_cone(per: Perception, to: Vector3, range_m: float) -> bool:
	var d := to - per.agent.mover.pos
	var flat := Vector2(d.x, d.z)
	var len := flat.length()
	if len > range_m:
		return false
	if len < 3.0:
		return true
	# Head turns: static scenery is scanned over a wider field than moving prey.
	var cs := (per.fwd.x * flat.x + per.fwd.z * flat.y) / (len * maxf(Vector2(per.fwd.x, per.fwd.z).length(), 1e-4))
	var fov_deg := minf(360.0, per.sp.vision_fov + 90.0)
	return cs >= cos(deg_to_rad(fov_deg * 0.5))


# --- Carcasses -------------------------------------------------------------------------------

static func perceive_carcasses(per: Perception, now: float) -> void:
	var eco := per.agent.ctx.eco as EcoGrid
	if eco == null or not Relations.eats_carrion(per.agent.phys) and not Relations.eats_meat(per.agent.phys):
		return
	var cf := eco.carcasses
	if cf.count() == 0:
		return
	var m := per.agent.mover
	var mem := per.memory
	for i in cf.count():
		var cp: Vector3 = cf.positions[i]
		var d := cp - m.pos
		var dist := d.length()
		if dist > 120.0:
			continue
		var kg := cf.kg[i]
		var sensed := &""
		var size_k := clampf(pow(kg / 20.0, 0.25), 0.4, 1.8)
		if per.sp.eye_count > 0 and dist <= per.vision_now * size_k * 0.8 and _in_static_cone(per, cp, per.vision_now * size_k * 0.8) \
				and line_of_sight(per.agent.ctx, per.eye, cp + Vector3.UP * 0.2):
			sensed = &"vision"
		if sensed == &"":
			# Rotting meat smells stronger with age.
			var ripe := 0.6 + clampf(cf.ages[i] / Units.SECONDS_PER_DAY, 0.0, 1.0)
			var wk := 1.0
			if per.wind_speed > 0.1 and dist > 0.1:
				wk = clampf(1.0 + 0.16 * minf(per.wind_speed, 8.0) * (-(d.x * per.wind.x + d.z * per.wind.y) / (dist * per.wind_speed)), 0.3, 2.2)
			if dist <= per.smell_now * size_k * ripe * wk:
				sensed = &"smell"
		if sensed == &"":
			continue
		var key := Percept.make_key(Percept.Kind.CARCASS, cf.ids[i])
		var p := mem.get_or_make(key)
		p.kind = Percept.Kind.CARCASS
		p.id = cf.ids[i]
		p.role = Percept.ROLE_NEUTRAL
		var err := 0.0 if sensed == &"vision" else dist * 0.15
		var h := Rng.hash01(cf.ids[i], per.agent.individual.id, int(now * 0.5))
		p.pos = cp + Vector3(h - 0.5, 0.0, Rng.hash01(per.agent.individual.id, cf.ids[i], int(now * 0.5)) - 0.5) * 2.0 * err
		p.dist = dist
		p.confidence = 1.0 if sensed == &"vision" else 0.6
		p.t_seen = now
		p.sense = sensed
		p.value = kg
		p.mass = kg
		p.fresh = true


# --- Food (plants, detritus, plankton) ---------------------------------------------------------

## Looks for edible food in the surroundings; fills per.food_* for each food kind the
## creature eats. Cost ~ (range / cell)² cells; call at low rate.
static func scan_food(per: Perception, now: float) -> void:
	var a := per.agent
	var eco := a.ctx.eco as EcoGrid
	if eco == null:
		return
	var weights := a.food_weights
	var m := a.mover
	var rng_m := clampf(maxf(per.vision_now, per.smell_now * 0.4), 6.0, 36.0)
	if per.sp.eye_count == 0:
		rng_m = clampf(per.smell_now * 0.6, 4.0, 20.0)
	var want_plants := weights[Food.PLANT] > 0.12 and not (m.aquatic_only)
	var want_det := weights[Food.DETRITUS] > 0.2
	var want_plank := weights[Food.PLANKTON] > 0.2
	if not (want_plants or want_det or want_plank):
		return
	var c0 := eco.cell_coords(m.pos)
	var k := int(ceil(rng_m / eco.cell_size))
	var n_cells := eco.dim * eco.dim
	var prefs := a.plant_prefs(eco)
	var best_s := [0.0, 0.0, 0.0, 0.0, 0.0]
	var best_p: Array[Vector3] = [Vector3.INF, Vector3.INF, Vector3.INF, Vector3.INF, Vector3.INF]
	var best_kg := [0.0, 0.0, 0.0, 0.0, 0.0]
	var area := eco.cell_area()
	var n_sp := eco.plant_species.size()
	for dz in range(-k, k + 1):
		var cz := c0.y + dz
		if cz < 0 or cz >= eco.dim:
			continue
		for dx in range(-k, k + 1):
			var cx := c0.x + dx
			if cx < 0 or cx >= eco.dim:
				continue
			var ci := cz * eco.dim + cx
			var center := eco.cell_center(cx, cz)
			var dist := Vector2(center.x - m.pos.x, center.z - m.pos.z).length()
			if dist > rng_m:
				continue
			if dist > 3.0 and not _in_static_cone(per, center, rng_m):
				continue
			var falloff := 1.0 / (1.0 + dist / 14.0)
			if want_plants:
				var amount := 0.0
				for p in n_sp:
					var w := prefs[p]
					if w <= 0.0:
						continue
					var mass := eco.plant_mass[p * n_cells + ci] - 0.05 * eco.plant_species[p].capacity
					if mass > 0.0:
						amount += mass * w
				if amount > MIN_PLANT_KG_M2:
					var s := amount * falloff
					if s > float(best_s[Food.PLANT]):
						best_s[Food.PLANT] = s
						best_p[Food.PLANT] = center
						best_kg[Food.PLANT] = amount * area
			if want_det:
				var det := eco.detritus[ci]
				if det > 0.04:
					var s2 := det * falloff
					if s2 > float(best_s[Food.DETRITUS]):
						best_s[Food.DETRITUS] = s2
						best_p[Food.DETRITUS] = center
						best_kg[Food.DETRITUS] = det * area
			if want_plank:
				var pl := eco.plankton[ci]
				if pl > 0.004 and eco.cell_water[ci] > 0.3:
					var s3 := pl * falloff
					if s3 > float(best_s[Food.PLANKTON]):
						best_s[Food.PLANKTON] = s3
						best_p[Food.PLANKTON] = center
						best_kg[Food.PLANKTON] = pl * area
	for kind in [Food.PLANT, Food.DETRITUS, Food.PLANKTON]:
		var bp: Vector3 = best_p[kind]
		if bp == Vector3.INF:
			continue
		var gy := a.ctx.ground_height(bp.x, bp.z)
		bp.y = gy
		if kind == Food.PLANT and not line_of_sight(a.ctx, per.eye, bp + Vector3.UP * 0.4):
			continue
		per.food_pos[kind] = bp
		per.food_kg[kind] = float(best_kg[kind])
		per.food_t[kind] = now
		if kind == Food.PLANT and float(best_kg[kind]) > 4.0:
			a.memory.note(CreatureMemory.SPOT_FOOD, bp, clampf(float(best_kg[kind]) / 60.0, 0.2, 1.0), now)


# --- Water ----------------------------------------------------------------------------------------

static func scan_water(per: Perception, now: float) -> void:
	var a := per.agent
	var w := a.ctx.world
	if w == null:
		return
	var m := a.mover
	var r := clampf(maxf(per.vision_now * 0.9, per.smell_now * 0.5), 5.0, 45.0)
	if m.medium == &"water" or m.water_depth > 0.05:
		per.water_pos = Vector3(m.pos.x, w.water_surface_at(m.pos.x, m.pos.z), m.pos.z)
		per.water_t = now
		a.memory.note(CreatureMemory.SPOT_WATER, per.water_pos, 0.8, now)
		return
	var wp := w.find_water_near(m.pos, r, false)
	if wp == Vector3.INF:
		return
	var seen := Vector2(wp.x - m.pos.x, wp.z - m.pos.z).length() < 10.0 or (per.sp.eye_count > 0 and _in_static_cone(per, wp, per.vision_now * 0.9))
	if not seen:
		seen = Vector2(wp.x - m.pos.x, wp.z - m.pos.z).length() < per.smell_now * 0.5
	if not seen:
		return
	# Shore point: the nearest water cell lies in the water; remember the bank side.
	per.water_pos = Vector3(wp.x, w.water_surface_at(wp.x, wp.z), wp.z)
	per.water_t = now
	a.memory.note(CreatureMemory.SPOT_WATER, per.water_pos, 0.7, now)
