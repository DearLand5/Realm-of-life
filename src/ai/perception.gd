class_name Perception
extends RefCounted
## What a creature can perceive of OTHER creatures, eggs, carcasses and calls,
## strictly through the senses its anatomy provides (SenseProfile):
##   vision    FOV cone from the eye directions, range scaled by light, fog,
##             vegetation, medium and target size/motion; blocked by terrain
##   smell     omnidirectional, stronger downwind, scaled by target size
##   hearing   movers and calls; louder when the source runs
##   vibration ground movers on land (no line of sight needed)
##   electro   living bodies in water; thermal: warm bodies; touch: contact range
## Detections update Percept objects inside CreatureMemory.short in place (their
## confidence then decays). Static things (plants, water) are handled by WorldScan.

const FRESH_AGE := 0.6

var agent: CreatureAgent
var memory: CreatureMemory
var sp: SenseProfile

# Per-update cache (set by update()).
var eye := Vector3.ZERO
var fwd := Vector3(0, 0, -1)
var light: float = 1.0
var vision_now: float = 0.0
var smell_now: float = 0.0
var hearing_now: float = 0.0
var wind := Vector2.ZERO
var wind_speed: float = 0.0
var fov_cos: float = -1.0
var in_water := false
var threat_level: float = 0.0       # strongest current danger 0..1
var threat: Percept = null
var neighbours: int = 0             # conspecifics within perception reach
var _rng_salt: int = 0

# Static scenery found by WorldScan (per Food kind) — Vector3.INF = nothing known.
var food_pos: Array[Vector3] = [Vector3.INF, Vector3.INF, Vector3.INF, Vector3.INF, Vector3.INF]
var food_kg := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var food_t := PackedFloat32Array([-1000.0, -1000.0, -1000.0, -1000.0, -1000.0])
var water_pos := Vector3.INF
var water_t: float = -1000.0
var _food_timer: float = 0.0
var _water_timer: float = 0.0


func setup(a: CreatureAgent) -> void:
	agent = a
	memory = a.memory
	sp = a.phenotype.senses
	_rng_salt = a.individual.id * 7919


## Runs one perception pass. `now` = physical time of the agent clock.
func update(now: float) -> void:
	var ctx := agent.ctx
	var m := agent.mover
	in_water = m.medium == &"water" and m.submerged > 0.5
	eye = agent.eye_world()
	fwd = agent.gaze_forward()
	var clim := ctx.climate
	light = clim.light_at(eye) if clim != null else 1.0
	var fog := clim.fog if clim != null else 0.0
	var rain := clim.precipitation if clim != null else 0.0
	wind = clim.wind if clim != null else Vector2.ZERO
	wind_speed = wind.length()
	var growth_k := clampf(sqrt(agent.individual.growth), 0.35, 1.0)
	var veg_k := 1.0
	if m.medium == &"land" and agent.mover.height < 1.6:
		veg_k = 1.0 - 0.3 * WorldScan.vegetation_density(ctx, m.pos)
	var medium_k := 0.55 if in_water else 1.0
	vision_now = sp.vision_at_light(light) * (1.0 - 0.75 * fog) * (1.0 - 0.3 * rain) * veg_k * medium_k * growth_k
	smell_now = sp.smell_range * growth_k * (0.75 if in_water else 1.0)
	hearing_now = sp.hearing_range * (1.0 - 0.35 * rain) * growth_k
	fov_cos = cos(deg_to_rad(clampf(sp.vision_fov * 0.5, 5.0, 180.0)))
	for k in memory.short:
		(memory.short[k] as Percept).fresh = false
	threat_level = 0.0
	threat = null
	neighbours = 0
	# Broad phase: target size/motion, wind and noise extend the nominal ranges (checked per target below).
	var reach := maxf(vision_now * 1.6, maxf(smell_now * 2.0, maxf(hearing_now * 1.0, maxf(sp.electro_range if in_water else 0.0, sp.thermal_range))))
	reach = minf(maxf(reach, sp.vibration_range), 64.0)
	var found := ctx.agents.query(m.pos, reach, agent, 16)
	for o in found:
		_perceive_agent(o as CreatureAgent, now)
	_perceive_stimuli(now)
	WorldScan.perceive_carcasses(self, now)
	memory.decay(now)
	# Threat summary over everything remembered (fresh or not).
	for k in memory.short:
		var p: Percept = memory.short[k]
		p.dist = m.pos.distance_to(p.pos)
		if p.role == Percept.ROLE_PREDATOR and p.kind == Percept.Kind.AGENT:
			var proximity := clampf(1.0 - p.dist / maxf(agent.flight_distance() * 2.5, 1.0), 0.0, 1.0)
			var v := p.threat * p.confidence * (0.35 + 0.65 * proximity)
			if v > threat_level:
				threat_level = v
				threat = p
		elif p.kind == Percept.Kind.SOUND and p.sound_kind == &"alarm":
			var v2 := 0.5 * p.confidence * clampf(1.0 - p.dist / 60.0, 0.0, 1.0)
			if v2 > threat_level:
				threat_level = v2
				threat = p


# --- Agents and eggs -------------------------------------------------------------------

func _perceive_agent(o: CreatureAgent, now: float) -> void:
	if o == null or not o.is_alive():
		return
	var ind := o.individual
	var is_egg := ind.is_egg()
	var m := agent.mover
	var o_pos := o.position
	var d := o_pos - m.pos
	var dist := d.length()
	if dist < 1e-4:
		return
	# Cheap rejection: farther than the best any sense could do for this target.
	var best_reach := maxf(vision_now * o.vis_size_k * 1.3, maxf(smell_now * o.scent_k * 2.2, hearing_now * 1.3))
	best_reach = maxf(best_reach, maxf(sp.vibration_range * 2.5, maxf(sp.touch_range + m.radius + o.mover.length, maxf(sp.thermal_range, sp.electro_range * 1.5))))
	if dist > best_reach:
		return
	var o_len := o.mover.length
	var moving := o.mover.speed > 0.2 and not is_egg
	var o_in_water := o.mover.medium == &"water"
	var best_q := 0.0
	var best_sense: StringName = &""
	var pos_err := 0.0
	var d_flat := Vector2(d.x, d.z)
	var dir_n := d / dist
	# --- Vision -----------------------------------------------------------------
	if sp.eye_count > 0 and vision_now > 0.05:
		var size_k := o.vis_size_k
		var r := vision_now * size_k * (1.3 if moving else 0.8) * (0.35 if is_egg else 1.0)
		if o_in_water and not in_water:
			r *= 0.5
		if dist <= r:
			var in_cone := dist < agent.mover.radius * 2.0 + o_len * 0.5
			if not in_cone:
				var flat_len := d_flat.length()
				if flat_len < 0.2:
					in_cone = true
				else:
					var cs := (fwd.x * d_flat.x + fwd.z * d_flat.y) / (flat_len * maxf(Vector2(fwd.x, fwd.z).length(), 1e-4))
					in_cone = cs >= fov_cos
			if in_cone and WorldScan.line_of_sight(agent.ctx, eye, o_pos + Vector3.UP * (o.mover.height * 0.7 if not is_egg else 0.1)):
				best_q = 1.0 - (dist / r) * (dist / r) * 0.8
				best_sense = &"vision"
				pos_err = dist * 0.01
	# --- Touch -----------------------------------------------------------------
	if dist < sp.touch_range + m.radius + o_len * 0.5 and best_q < 0.9:
		best_q = 0.9
		best_sense = &"touch"
		pos_err = 0.0
	# --- Thermal ---------------------------------------------------------------------
	if sp.thermal_range > 0.0 and not is_egg and dist <= sp.thermal_range and o.phenotype.physiology.endothermy > 0.4 and best_q < 0.8:
		best_q = 0.8
		best_sense = &"thermal"
		pos_err = dist * 0.03
	# --- Electro (water) ----------------------------------------------------------------
	if sp.electro_range > 0.0 and in_water and o_in_water and not is_egg and dist <= sp.electro_range * clampf(pow(o_len / 0.6, 0.3), 0.5, 1.5) and best_q < 0.75:
		best_q = 0.75
		best_sense = &"electro"
		pos_err = dist * 0.04
	# --- Hearing -------------------------------------------------------------------------
	if best_q < 0.7 and not is_egg:
		var noise := o.noise_level()
		if noise > 0.05 and dist <= hearing_now * noise * (0.6 if in_water != o_in_water else 1.0):
			best_q = 0.55 * (1.0 - dist / maxf(hearing_now * noise, 0.1)) + 0.15
			best_sense = &"hearing"
			pos_err = dist * 0.12
	# --- Vibration (ground movers on land) ----------------------------------------------------
	if best_q < 0.6 and moving and m.medium == &"land" and o.mover.medium == &"land" and not agent.mover.flying and not o.mover.flying:
		var vib := pow(maxf(o.mass_kg, 0.01), 0.4) * clampf(o.mover.speed / 3.0, 0.2, 1.5)
		if dist <= sp.vibration_range * vib:
			best_q = 0.5
			best_sense = &"vibration"
			pos_err = dist * 0.2
	# --- Smell (downwind advantage) ----------------------------------------------------------------
	if best_q < 0.5:
		var scent := o.scent_k * (0.5 if is_egg else 1.0)
		var wk := 1.0
		if wind_speed > 0.1:
			# cos > 0 when I am downwind of the source (wind blows source -> me).
			var c := -(dir_n.x * wind.x + dir_n.z * wind.y) / wind_speed
			wk = clampf(1.0 + 0.16 * minf(wind_speed, 8.0) * c, 0.3, 2.2)
		var rs := smell_now * scent * wk * (1.0 if (in_water == o_in_water) else 0.4)
		if dist <= rs:
			best_q = 0.35 * (1.0 - dist / rs) + 0.1
			best_sense = &"smell"
			pos_err = dist * 0.25
	if best_sense == &"":
		return
	var key := Percept.make_key(Percept.Kind.EGG if is_egg else Percept.Kind.AGENT, ind.id)
	var p := memory.get_or_make(key)
	var first := p.agent == null
	if first:
		p.kind = Percept.Kind.EGG if is_egg else Percept.Kind.AGENT
		p.id = ind.id
		p.agent = o
	var o_pos_seen := o_pos
	if pos_err > 0.05:
		var h := Rng.hash01(_rng_salt, ind.id, int(now * 1.5))
		var h2 := Rng.hash01(ind.id, _rng_salt, int(now * 1.5) + 17)
		o_pos_seen += Vector3((h - 0.5) * 2.0, 0.0, (h2 - 0.5) * 2.0) * pos_err
	if p.fresh == false and not first and now > p.t_seen:
		var dt_seen := now - p.t_seen
		if dt_seen < 3.0 and best_sense in [&"vision", &"touch", &"thermal", &"electro"]:
			p.vel = p.vel.lerp((o_pos_seen - p.pos) / dt_seen, 0.6)
	if best_sense in [&"vision", &"touch", &"thermal", &"electro"]:
		p.vel = o.mover.vel
	p.pos = o_pos_seen
	p.dist = dist
	p.confidence = clampf(best_q, 0.15, 1.0)
	p.t_seen = now
	p.sense = best_sense
	p.mass = o.mass_kg
	p.moving = moving
	p.in_water = o_in_water
	p.fresh = true
	if first or (p.role == Percept.ROLE_NEUTRAL and int(now) % 5 == 0):
		_classify(p, o)
	if p.role == Percept.ROLE_CONSPECIFIC:
		neighbours += 1


func _classify(p: Percept, o: CreatureAgent) -> void:
	var me := agent
	if p.kind == Percept.Kind.EGG:
		p.role = Percept.ROLE_CONSPECIFIC if o.individual.species_id == me.individual.species_id else Percept.ROLE_PREY
		p.threat = 0.0
		return
	var same := o.individual.species_id == me.individual.species_id and (me.individual.species_id >= 0 or o.phenotype.genome.morph_key() == me.phenotype.genome.morph_key())
	var role := Relations.classify(me.phys, me.phenotype.anatomy.stats, me.individual.mass(),
		o.phys, o.phenotype.anatomy.stats, p.mass, same)
	p.role = role
	if role == Percept.ROLE_PREDATOR:
		var pw := Relations.combat_power(o.phys, o.phenotype.anatomy.stats, p.mass)
		p.threat = Relations.threat_level(me.combat_power(), pw, o.personality.aggression)
	elif role == Percept.ROLE_PREY:
		p.threat = 0.0
		p.value = p.mass
	else:
		p.threat = 0.0


# --- Calls and other stimuli ---------------------------------------------------------------

func _perceive_stimuli(now: float) -> void:
	var ctx := agent.ctx
	if ctx.stimuli.is_empty():
		return
	var m := agent.mover
	var max_r := maxf(hearing_now * 3.0, maxf(smell_now * 3.0, sp.vibration_range * 3.0))
	var max_r2 := max_r * max_r
	var t_now := ctx.phys_time
	for s in ctx.stimuli:
		var src: Node = s.get("source")
		if src == agent or t_now - float(s["t"]) > 2.0:
			continue
		var dp: Vector3 = s["pos"] - m.pos
		if dp.x * dp.x + dp.z * dp.z > max_r2:
			continue
		var sp_pos: Vector3 = s["pos"]
		var dist := m.pos.distance_to(sp_pos)
		var kind: StringName = s["kind"]
		var strength := float(s["strength"])
		var rng_audible := hearing_now * clampf(strength, 0.2, 3.0)
		if kind == &"scent":
			rng_audible = smell_now * clampf(strength, 0.2, 3.0)
		elif kind == &"vibration":
			rng_audible = sp.vibration_range * clampf(strength, 0.2, 3.0) if m.medium == &"land" else 0.0
		if dist > rng_audible or rng_audible <= 0.0:
			continue
		var skey := Percept.make_key(Percept.Kind.SOUND, (src.get("individual").id if src != null and is_instance_valid(src) and src.get("individual") != null else int(sp_pos.x * 13.0 + sp_pos.z * 7.0)) * 8 + _kind_code(kind))
		var p := memory.get_or_make(skey)
		p.kind = Percept.Kind.SOUND
		p.sound_kind = kind
		p.agent = src as Node3D
		var err := dist * 0.12
		var h := Rng.hash01(_rng_salt, int(sp_pos.x * 10.0), int(now))
		p.pos = sp_pos + Vector3(h - 0.5, 0.0, Rng.hash01(int(sp_pos.z * 10.0), _rng_salt, int(now)) - 0.5) * 2.0 * err
		p.dist = dist
		p.confidence = clampf(1.0 - dist / rng_audible, 0.2, 1.0)
		p.t_seen = now
		p.sense = &"hearing"
		p.fresh = true
		p.role = Percept.ROLE_NEUTRAL
		if src is CreatureAgent and (src as CreatureAgent).individual.species_id == agent.individual.species_id:
			p.role = Percept.ROLE_CONSPECIFIC


static func _kind_code(k: StringName) -> int:
	match k:
		&"alarm":
			return 1
		&"mating_call":
			return 2
		&"scent":
			return 3
		&"vibration":
			return 4
	return 0


## Rescans plants/detritus/plankton and water at a low rate (more often when `urgent`).
func scan_static(now: float, dt: float, hungry: bool, thirsty: bool) -> void:
	_food_timer -= dt
	_water_timer -= dt
	if _food_timer <= 0.0:
		_food_timer = (1.0 if hungry else 4.0) * (1.0 if agent.tier == 0 else 2.0)
		WorldScan.scan_food(self, now)
	if _water_timer <= 0.0:
		_water_timer = (1.0 if thirsty else 5.0) * (1.0 if agent.tier == 0 else 2.0)
		WorldScan.scan_water(self, now)


func food_known(kind: int, now: float) -> bool:
	return food_pos[kind] != Vector3.INF and now - food_t[kind] < WorldScan.FOOD_EXPIRE


func forget_food(kind: int) -> void:
	food_pos[kind] = Vector3.INF
	food_kg[kind] = 0.0


# --- Queries used by the brain ----------------------------------------------------------------

## Remembered percepts of an agent role, nearest first (confidence-weighted).
func list(kind: int, role: StringName = &"", min_conf: float = 0.15) -> Array[Percept]:
	var out: Array[Percept] = []
	for k in memory.short:
		var p: Percept = memory.short[k]
		if p.kind != kind or p.confidence < min_conf:
			continue
		if role != &"" and p.role != role:
			continue
		if p.agent != null and not is_instance_valid(p.agent):
			continue
		out.append(p)
	out.sort_custom(func(a: Percept, b: Percept) -> bool: return a.dist / maxf(a.confidence, 0.1) < b.dist / maxf(b.confidence, 0.1))
	return out


func nearest(kind: int, role: StringName = &"", min_conf: float = 0.15) -> Percept:
	var best: Percept = null
	var best_d := INF
	for k in memory.short:
		var p: Percept = memory.short[k]
		if p.kind != kind or p.confidence < min_conf:
			continue
		if role != &"" and p.role != role:
			continue
		if p.agent != null and not is_instance_valid(p.agent):
			continue
		var dd := p.dist / maxf(p.confidence, 0.1)
		if dd < best_d:
			best_d = dd
			best = p
	return best


func can_see(world_pos: Vector3) -> bool:
	if sp.eye_count == 0:
		return false
	var d := world_pos - agent.mover.pos
	var flat := Vector2(d.x, d.z)
	if flat.length() < 0.5:
		return true
	if flat.length() > vision_now:
		return false
	var cs := (fwd.x * flat.x + fwd.z * flat.y) / (flat.length() * maxf(Vector2(fwd.x, fwd.z).length(), 1e-4))
	return cs >= fov_cos and WorldScan.line_of_sight(agent.ctx, eye, world_pos + Vector3.UP * 0.3)
