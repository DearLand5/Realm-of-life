class_name CreatureMover
extends RefCounted
## Kinematic body of a live creature. Moves it through land, water and air
## within the limits of its LocomotionProfile (speeds per medium, turn rate,
## acceleration, jump, take-off/landing, slope and water limits), follows the
## terrain height/normal, and reports effort and energy use for the biology.
##
## Inputs: MoveIntent (what the brain/player wants), `cond` = 0..1 condition
## factor (health, fatigue, temperature, muscles).
## Outputs: pos, heading, pitch, roll, speed, medium, move_power (W per
## biological second), effort 0..1, submerged fraction, head_underwater.
##
## Conventions: heading is yaw about +Y, the creature faces −Z, so
## forward = (−sin h, 0, −cos h). pitch > 0 = nose up. roll > 0 = right side down.

const MAX_SUBSTEP := 0.25
const MAX_SUBSTEPS := 8
const SUSTAINED_FRACTION := 0.65     # share of the top land speed that is sustainable without sprinting
const LAUNCH_CLEAR := 1.2            # m above ground within which lift is limited by airspeed

var pos := Vector3.ZERO
var vel := Vector3.ZERO              # world velocity (m/s, physical time)
var heading: float = 0.0
var pitch: float = 0.0
var roll: float = 0.0
var speed: float = 0.0               # horizontal speed along the heading
var turn_rate_now: float = 0.0       # rad/s, + = turning left
var medium: StringName = &"land"
var on_ground := true
var flying := false
var taking_off := false
var landing := false
var gliding := false
var move_power: float = 0.0          # W per biological second
var effort: float = 0.0              # 0..1 of the top speed in the current medium
var submerged: float = 0.0           # 0..1 of the body height below the surface
var head_underwater := false
var water_depth: float = 0.0
var ground_y: float = 0.0
var surface_y: float = -1.0e6
var stuck: float = 0.0               # s spent pushing against an obstacle
var last_impact: float = 0.0         # m/s of the last hard landing (read + clear by the agent)
var lateral_accel: float = 0.0
var vertical_speed: float = 0.0
var cheap := false                   # tier B: fewer probes

# Body (updated by set_growth).
var height: float = 0.5              # m, current
var length: float = 0.8
var radius: float = 0.3
var growth: float = 1.0

var ph: Phenotype
var ctx: WorldContext
var lp: LocomotionProfile
var aquatic_only := false            # cannot leave the water (gill breathers of habitat water)
var push := Vector3.ZERO             # separation velocity from neighbours (set by the agent)

var _size_k: float = 1.0
var _slope_max: float = 0.9
var _clear_dir := Vector3.ZERO
var _clear_timer: float = 0.0
var _pitch_target: float = 0.0
var _roll_target: float = 0.0
var _vy: float = 0.0
var _fall_start_y: float = 0.0
var _normal_timer: float = 0.0


func setup(phenotype: Phenotype, context: WorldContext, start: Vector3, start_heading: float, growth_frac: float) -> void:
	ph = phenotype
	ctx = context
	lp = phenotype.locomotion
	pos = start
	heading = start_heading
	var p := phenotype.physiology
	aquatic_only = p.habitat == &"water" and not lp.can_walk and p.respiration in [&"gills", &"cutaneous", &"mixed"] and lp.can_swim
	_slope_max = lerpf(0.55, 1.0, lp.stability)
	if lp.can_climb:
		_slope_max = 1.8
	elif lp.gait == &"serpentine" or lp.gait == &"peristaltic":
		_slope_max = 0.7
	set_growth(growth_frac)
	_sense()
	if medium == &"water":
		_snap_to_water()
	else:
		pos.y = ground_y if not flying else maxf(pos.y, ground_y)


func set_growth(g: float) -> void:
	growth = clampf(g, 0.02, 1.0)
	var st := ph.anatomy.stats
	height = maxf(float(st.get("height", 0.5)), 0.02) * growth
	length = maxf(float(st.get("length", 0.8)), 0.02) * growth
	var width := maxf(float(st.get("width", 0.4)), 0.02) * growth
	radius = maxf(0.5 * maxf(width, length * 0.6), 0.03)
	_size_k = sqrt(growth)


# --- Capabilities -------------------------------------------------------------------

## Top speed (m/s) in a medium for the current size; `sprint` allows burst speed on land.
func max_speed(m: StringName, sprint: bool = true) -> float:
	match m:
		&"water":
			return lp.swim_speed * _size_k if lp.can_swim else 0.0
		&"air":
			return lp.fly_speed * _size_k if lp.can_fly else (lp.takeoff_speed * 0.7 * _size_k if lp.can_glide else 0.0)
	var top := lp.best_land_speed() * _size_k
	if lp.can_walk and not sprint:
		top = maxf(lp.walk_speed, lp.run_speed * SUSTAINED_FRACTION) * _size_k
	return top


func walk_pace() -> float:
	return (lp.walk_speed if lp.can_walk else lp.crawl_speed) * _size_k


func can_leave_water() -> bool:
	return not aquatic_only


func stall_speed() -> float:
	if lp.can_hover or not lp.can_fly:
		return 0.0
	return lp.takeoff_speed * 0.55 * _size_k


func accel_eff() -> float:
	return clampf(lp.accel * 0.22, 1.5, 9.0) * (0.6 + 0.4 * _size_k)


func forward() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


func body_basis() -> Basis:
	return Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.FORWARD, roll)


func teleport(p: Vector3) -> void:
	pos = p
	vel = Vector3.ZERO
	speed = 0.0
	_sense()
	if medium == &"water":
		_snap_to_water()
	elif not flying:
		pos.y = ground_y


func apply_impulse(v: Vector3) -> void:
	vel += v
	speed = clampf(speed + v.dot(forward()), -2.0, max_speed(medium) * 1.5 + 5.0)


# --- Environment ------------------------------------------------------------------------

func _ground(x: float, z: float) -> float:
	return ctx.world.height_at(x, z) if ctx.world != null else 0.0


func _depth(x: float, z: float) -> float:
	return ctx.world.water_depth_at(x, z) if ctx.world != null else 0.0


func _sense() -> void:
	ground_y = _ground(pos.x, pos.z)
	water_depth = maxf(_depth(pos.x, pos.z), 0.0)
	if water_depth > 0.05:
		surface_y = ctx.world.water_surface_at(pos.x, pos.z)
	else:
		surface_y = -1.0e6
	var wet := water_depth > 0.05 and pos.y < surface_y
	submerged = clampf((surface_y - pos.y) / maxf(height, 0.02), 0.0, 1.0) if wet else 0.0
	head_underwater = wet and pos.y + height * 0.92 < surface_y
	if flying:
		medium = &"air"
	elif wet and (submerged > 0.55 or (aquatic_only and water_depth > 0.05)):
		medium = &"water"
	else:
		medium = &"land"


func _snap_to_water() -> void:
	pos.y = clampf(pos.y, ground_y, maxf(ground_y, surface_y - height * 0.3))


func height_above_ground() -> float:
	return pos.y - ground_y


## Is the XZ point walkable/swimmable for this body at the given medium?
func _passable(x: float, z: float, from: Vector3, avoid_water: bool) -> bool:
	if ctx.world == null:
		return true
	if not ctx.world.contains(x, z) or absf(x) > ctx.world.size * 0.5 - 0.6 or absf(z) > ctx.world.size * 0.5 - 0.6:
		return false
	var d := _depth(x, z)
	if aquatic_only:
		return d > height * 0.55
	if d > 0.05:
		var swimmer := lp.can_swim
		if not swimmer and d > height * 0.55:
			return false
		if swimmer and avoid_water and d > height * 0.8 and not _can_cross_water():
			return false
	if from != Vector3.INF:
		var dist := Vector2(x - from.x, z - from.z).length()
		if dist > 1e-3 and not lp.can_climb:
			var rise := _ground(x, z) - from.y
			if rise / dist > _slope_max * 1.3 and rise > height * 0.3:
				return false
	return true


## Public probe: can the body stand/swim at this XZ point (terrain-independent of slope)?
func can_stand(x: float, z: float, avoid_water: bool = true) -> bool:
	return _passable(x, z, Vector3.INF, avoid_water)


func _can_cross_water() -> bool:
	return ph.physiology.habitat in [&"water", &"amphibious"] or lp.swim_speed > lp.best_land_speed() * 0.5


# --- Stepping ----------------------------------------------------------------------------

func step(dt: float, it: MoveIntent, cond: float, tier_b: bool = false) -> void:
	cheap = tier_b
	var left := dt
	var n := 0
	move_power = 0.0
	while left > 1e-5 and n < MAX_SUBSTEPS:
		var h := minf(left, MAX_SUBSTEP)
		_substep(h, it, clampf(cond, 0.05, 1.0))
		left -= h
		n += 1
	_finish(dt, it)


func _substep(dt: float, it: MoveIntent, cond: float) -> void:
	_sense()
	# Air entry/exit requests.
	if it.fly and lp.can_fly and not flying and medium != &"water":
		flying = true
		taking_off = true
		landing = false
		on_ground = false
	elif flying and not it.fly:
		landing = true
	if flying:
		_air(dt, it, cond)
	elif medium == &"water" and lp.can_swim:
		_swim(dt, it, cond)
	elif not on_ground:
		_ballistic(dt, it, cond)
	else:
		_land(dt, it, cond)
	_sense()


## Desired horizontal direction (unit, zero if none) and the speed fraction left after arrival slow-down.
func _aim(it: MoveIntent) -> Array:
	var d := Vector3.ZERO
	var k := 1.0
	match it.mode:
		MoveIntent.Mode.SEEK:
			var target := it.goal
			if it.goal_node != null and is_instance_valid(it.goal_node):
				target = it.goal_node.position
			d = target - pos
			d.y = 0.0
			var dist := d.length()
			if dist < it.arrive_radius:
				return [Vector3.ZERO, 0.0]
			if dist < it.arrive_radius + 1.5 + speed * 0.5:
				k = clampf((dist - it.arrive_radius) / (1.5 + speed * 0.5), 0.25, 1.0)
		MoveIntent.Mode.FLEE:
			var threat := it.goal
			if it.goal_node != null and is_instance_valid(it.goal_node):
				threat = it.goal_node.position
			d = pos - threat
			d.y = 0.0
		MoveIntent.Mode.DIRECT:
			d = it.dir
			d.y = 0.0
		_:
			return [Vector3.ZERO, 0.0]
	if d.length_squared() < 1e-8:
		return [Vector3.ZERO, 0.0]
	d = d.normalized()
	if it.group_pull.length_squared() > 1e-6:
		d = (d + it.group_pull).normalized()
	return [d, k]


func _turn_toward(dir: Vector3, dt: float, cond: float) -> float:
	var want := atan2(-dir.x, -dir.z)
	var err := wrapf(want - heading, -PI, PI)
	var rate := lp.turn_rate * (0.5 + 0.5 * cond) * (1.0 - 0.35 * clampf(speed / maxf(max_speed(medium), 0.1), 0.0, 1.0))
	rate *= lerpf(1.8, 1.0, _size_k)   # small bodies pivot faster
	var step_a := clampf(err, -rate * dt, rate * dt)
	heading = wrapf(heading + step_a, -PI, PI)
	turn_rate_now = lerpf(turn_rate_now, step_a / maxf(dt, 1e-4), 0.5)
	return wrapf(want - heading, -PI, PI)


func _approach_speed(v_cmd: float, dt: float, cond: float) -> void:
	var a := accel_eff() * (0.4 + 0.6 * cond)
	if speed < v_cmd:
		speed = minf(v_cmd, speed + a * dt)
	else:
		speed = maxf(v_cmd, speed - 2.2 * a * dt)


func _steer_clear(dir: Vector3, dt: float, avoid_water: bool) -> Vector3:
	if dir == Vector3.ZERO or ctx.world == null:
		return dir
	_clear_timer -= dt
	if _clear_timer > 0.0 and _clear_dir != Vector3.ZERO and dir.dot(_clear_dir) > 0.3 and cheap:
		return _clear_dir
	var look := maxf(1.5, speed * 0.9 + radius * 2.0)
	var ahead := pos + dir * look
	if _passable(ahead.x, ahead.z, Vector3.INF, avoid_water) and _passable(pos.x + dir.x * look * 0.5, pos.z + dir.z * look * 0.5, Vector3.INF, avoid_water):
		_clear_dir = dir
		_clear_timer = 0.25
		return dir
	for ang in [30.0, -30.0, 60.0, -60.0, 95.0, -95.0, 140.0, -140.0]:
		var d2 := dir.rotated(Vector3.UP, deg_to_rad(ang))
		var q := pos + d2 * look
		if _passable(q.x, q.z, Vector3.INF, avoid_water):
			_clear_dir = d2
			_clear_timer = 0.4
			return d2
	_clear_dir = Vector3.ZERO
	return dir


func _land(dt: float, it: MoveIntent, cond: float) -> void:
	var aim := _aim(it)
	var dir: Vector3 = aim[0]
	var kspeed: float = aim[1]
	var vmax := max_speed(&"land", it.sprint) * cond
	var v_cmd := minf(it.speed, vmax) * kspeed
	var wade := clampf(water_depth / maxf(height * 0.55, 0.05), 0.0, 1.0) if water_depth > 0.05 else 0.0
	v_cmd *= 1.0 - 0.45 * wade
	if dir != Vector3.ZERO and v_cmd > 0.0:
		dir = _steer_clear(dir, dt, it.avoid_water)
		var err := _turn_toward(dir, dt, cond)
		v_cmd *= clampf(cos(err) * 1.4 - 0.2, 0.0, 1.0) if absf(err) < 1.9 else 0.0
	else:
		v_cmd = 0.0
		if it.face != Vector3.ZERO:
			_turn_toward(Vector3(it.face.x, 0.0, it.face.z).normalized(), dt, cond)
		else:
			turn_rate_now = lerpf(turn_rate_now, 0.0, 0.3)
	_approach_speed(v_cmd, dt, cond)
	var fwd := forward()
	# Slope: uphill slows, downhill helps a little.
	var step_len := speed * dt
	var slope_k := 1.0
	if step_len > 1e-4 and not cheap:
		var ahead := pos + fwd * maxf(step_len, 0.3)
		var rise := (_ground(ahead.x, ahead.z) - ground_y) / maxf(step_len, 0.3)
		slope_k = clampf(1.0 - 0.55 * rise, 0.3, 1.15) if rise > 0.0 else clampf(1.0 - 0.15 * rise, 1.0, 1.2)
	var move := fwd * (speed * slope_k * dt) + push * dt
	if lp.can_jump and it.jump and on_ground:
		_begin_jump(fwd)
		return
	var target := pos + move
	var ok := _passable(target.x, target.z, pos, it.avoid_water)
	if not ok:
		var tx := Vector3(pos.x + move.x, pos.y, pos.z)
		var tz := Vector3(pos.x, pos.y, pos.z + move.z)
		if absf(move.x) > absf(move.z) and _passable(tx.x, tx.z, pos, it.avoid_water):
			target = tx
			ok = true
		elif _passable(tz.x, tz.z, pos, it.avoid_water):
			target = tz
			ok = true
		elif _passable(tx.x, tx.z, pos, it.avoid_water):
			target = tx
			ok = true
	if ok:
		stuck = maxf(0.0, stuck - dt)
		vel = (target - pos) / maxf(dt, 1e-4)
		pos.x = target.x
		pos.z = target.z
	else:
		stuck += dt
		speed = maxf(0.0, speed - 4.0 * accel_eff() * dt)
		vel = Vector3.ZERO
	var g_new := _ground(pos.x, pos.z)
	if pos.y - g_new > maxf(0.5, height * 0.7) and water_depth <= 0.05:
		on_ground = false
		_vy = 0.0
		_fall_start_y = pos.y
	else:
		pos.y = g_new
	lateral_accel = speed * turn_rate_now
	move_power = lp.land_cost_per_m() * growth * growth * growth * absf(speed) / Units.BIO_TIME_RATIO
	effort = clampf(absf(speed) / maxf(max_speed(&"land", true), 0.05), 0.0, 1.2)


func _begin_jump(fwd: Vector3) -> void:
	var jh := lp.jump_height * _size_k
	_vy = sqrt(2.0 * ctx.gravity * maxf(jh, 0.05))
	on_ground = false
	_fall_start_y = pos.y
	vel = fwd * maxf(speed, 0.5)
	vel.y = _vy


func _ballistic(dt: float, it: MoveIntent, cond: float) -> void:
	_vy -= ctx.gravity * dt
	if lp.can_glide and not lp.can_fly and _fall_start_y - pos.y > 1.0:
		_vy = maxf(_vy, -1.4)
		gliding = true
		speed = maxf(speed, lp.takeoff_speed * 0.5 * _size_k)
	else:
		gliding = false
	var fwd := forward()
	if it.mode != MoveIntent.Mode.NONE:
		var aim := _aim(it)
		if aim[0] != Vector3.ZERO:
			_turn_toward(aim[0], dt * 0.5, cond)
	pos += fwd * speed * dt + Vector3(0, _vy * dt, 0) + push * dt
	var g := _ground(pos.x, pos.z)
	if pos.y <= g:
		pos.y = g
		if _vy < -sqrt(2.0 * ctx.gravity * maxf(height * 2.5, 0.8)):
			last_impact = maxf(last_impact, -_vy)
		_vy = 0.0
		on_ground = true
		gliding = false
	vertical_speed = _vy
	vel = fwd * speed + Vector3(0, _vy, 0)
	effort = 0.5


func _swim(dt: float, it: MoveIntent, cond: float) -> void:
	var aim := _aim(it)
	var dir: Vector3 = aim[0]
	var vmax := max_speed(&"water") * cond
	var v_cmd := minf(it.speed, vmax) * float(aim[1])
	if dir != Vector3.ZERO and v_cmd > 0.0:
		dir = _steer_clear(dir, dt, false)
		var err := _turn_toward(dir, dt, cond)
		v_cmd *= clampf(cos(err) * 1.3 - 0.1, 0.0, 1.0) if absf(err) < 1.9 else 0.0
	else:
		v_cmd = 0.0
		turn_rate_now = lerpf(turn_rate_now, 0.0, 0.3)
		if it.face != Vector3.ZERO:
			_turn_toward(Vector3(it.face.x, 0.0, it.face.z).normalized(), dt, cond)
	_approach_speed(v_cmd, dt, cond)
	var fwd := forward()
	var target := pos + fwd * speed * dt + push * dt
	if _passable(target.x, target.z, Vector3.INF, false):
		pos.x = target.x
		pos.z = target.z
	else:
		speed = maxf(0.0, speed - 3.0 * accel_eff() * dt)
		stuck += dt
	# Depth control.
	var g := _ground(pos.x, pos.z)
	var surf := surface_y if surface_y > -1.0e5 else pos.y + height
	var ty: float
	if it.surface:
		ty = surf - height * 0.62
	else:
		ty = surf - maxf(it.altitude, height * 0.6) - height * 0.5
	if it.mode == MoveIntent.Mode.DIRECT and absf(it.dir.y) > 0.05:
		ty = pos.y + it.dir.y * 3.0
	ty = clampf(ty, g + 0.02, maxf(g + 0.02, surf - height * 0.45))
	var vy_max := maxf(0.25 * vmax, 0.2)
	var vy_target := clampf((ty - pos.y) * 2.0, -vy_max, vy_max)
	vertical_speed = move_toward(vertical_speed, vy_target, accel_eff() * dt)
	pos.y = clampf(pos.y + vertical_speed * dt, g, maxf(g, surf - height * 0.25))
	if pos.y <= g + 1e-4 and vertical_speed < 0.0:
		vertical_speed = 0.0
	_pitch_target = clampf(atan2(vertical_speed, maxf(speed, 0.3)), -0.9, 0.9)
	vel = fwd * speed + Vector3(0, vertical_speed, 0)
	on_ground = false
	lateral_accel = speed * turn_rate_now
	var tot := Vector2(speed, vertical_speed).length()
	move_power = lp.cost_swim * growth * growth * growth * tot / Units.BIO_TIME_RATIO
	effort = clampf(tot / maxf(max_speed(&"water"), 0.05), 0.0, 1.2)


func _air(dt: float, it: MoveIntent, cond: float) -> void:
	var aim := _aim(it)
	var dir: Vector3 = aim[0]
	var stall := stall_speed()
	var vmax := max_speed(&"air") * cond
	var cruise := minf(it.speed, vmax)
	var v_cmd := cruise * float(aim[1])
	var hover := lp.can_hover
	if dir != Vector3.ZERO and (v_cmd > 0.0 or not hover):
		var err := _turn_toward(dir, dt, cond)
		if not hover:
			v_cmd = maxf(v_cmd, stall * 1.05)
			v_cmd *= clampf(cos(err) * 0.5 + 0.7, 0.4, 1.0)
	elif not hover:
		v_cmd = maxf(v_cmd, stall * 1.05)
		turn_rate_now = lerpf(turn_rate_now, 0.0, 0.2)
	else:
		v_cmd = 0.0
		turn_rate_now = lerpf(turn_rate_now, 0.0, 0.3)
	if landing:
		var hh := height_above_ground()
		v_cmd = minf(v_cmd, lerpf(stall * 0.6, v_cmd, clampf(hh / 4.0, 0.0, 1.0)))
	_approach_speed(v_cmd, dt, cond)
	var fwd := forward()
	var h_above := height_above_ground()
	var target_alt := 0.0 if landing or not it.fly else maxf(it.altitude, 0.3)
	var climb := (2.5 if hover else 0.35 * maxf(max_speed(&"air"), 1.0))
	var sink := (2.0 if hover else 0.5 * maxf(max_speed(&"air"), 1.0))
	var lift_k := 1.0
	if not hover and speed < stall:
		lift_k = clampf((speed / maxf(stall, 0.1)) - 0.25, 0.0, 1.0) if h_above < LAUNCH_CLEAR * 3.0 else 0.0
	var vy_target := clampf((target_alt - h_above) * 1.1, -sink, climb * lift_k)
	if not hover and speed < stall * 0.9 and h_above > LAUNCH_CLEAR:
		vy_target = -sink * 0.8   # stalled
	vertical_speed = move_toward(vertical_speed, vy_target, 7.0 * dt)
	var target := pos + fwd * speed * dt + push * dt * 0.5
	if ctx.world == null or (ctx.world.contains(target.x, target.z) and absf(target.x) < ctx.world.size * 0.5 - 0.6 and absf(target.z) < ctx.world.size * 0.5 - 0.6):
		pos.x = target.x
		pos.z = target.z
	else:
		_turn_toward(-Vector3(pos.x, 0.0, pos.z).normalized(), dt * 2.0, cond)
	pos.y += vertical_speed * dt
	var g := _ground(pos.x, pos.z)
	if pos.y <= g + 0.02:
		pos.y = g
		if landing or not it.fly:
			flying = false
			landing = false
			taking_off = false
			on_ground = true
			vertical_speed = 0.0
		else:
			vertical_speed = maxf(vertical_speed, 0.0)
	if taking_off and h_above > 0.8:
		taking_off = false
	gliding = it.fly and absf(vertical_speed) < 0.4 and speed > stall and it.speed < 0.6 * max_speed(&"air") and it.urgency < 0.1
	vel = fwd * speed + Vector3(0, vertical_speed, 0)
	lateral_accel = speed * turn_rate_now
	_pitch_target = clampf(atan2(vertical_speed, maxf(speed, 1.0)) * 1.2, -0.7, 0.7)
	move_power = lp.cost_fly * growth * growth * growth * speed / Units.BIO_TIME_RATIO
	effort = clampf(0.35 + 0.65 * speed / maxf(max_speed(&"air"), 0.1), 0.0, 1.2) if not hover else 0.6
	on_ground = false


# --- Post-processing -----------------------------------------------------------------------

func _finish(dt: float, _it: MoveIntent) -> void:
	_sense()
	speed = clampf(speed, -3.0, 1000.0)
	# Body orientation targets.
	var k := clampf(dt * 8.0, 0.0, 1.0)
	match medium:
		&"land":
			if not cheap or _normal_timer <= 0.0:
				_normal_timer = 0.15
				var d := maxf(radius * 0.8, 0.15)
				var fwd := forward()
				var right := fwd.cross(Vector3.UP)
				var hf := _ground(pos.x + fwd.x * d, pos.z + fwd.z * d)
				var hb := _ground(pos.x - fwd.x * d, pos.z - fwd.z * d)
				var hr := _ground(pos.x + right.x * d, pos.z + right.z * d)
				var hl := _ground(pos.x - right.x * d, pos.z - right.z * d)
				_pitch_target = clampf(atan2(hf - hb, 2.0 * d), -0.7, 0.7)
				_roll_target = clampf(atan2(hl - hr, 2.0 * d), -0.7, 0.7)
			_normal_timer -= dt
			if not on_ground:
				_pitch_target = clampf(atan2(_vy, maxf(speed, 1.0)), -0.8, 0.8)
				_roll_target = 0.0
		&"water":
			_roll_target = clampf(-turn_rate_now * 0.35, -0.5, 0.5)
		_:
			var bank := clampf(atan2(lateral_accel, ctx.gravity) * 0.9, -0.9, 0.9)
			_roll_target = -bank
	pitch = lerpf(pitch, _pitch_target, k)
	roll = lerpf(roll, _roll_target, k)
	if stuck > 3.0:
		stuck = 3.0
