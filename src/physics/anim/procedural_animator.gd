class_name ProceduralAnimator
extends RefCounted
## Drives the Skeleton3D pose (bone ROTATIONS, bone 0 position/rotation) of one
## creature from its movement state. Never touches pose scale (muscle bulge is
## owned by CreatureVisual.set_muscle_bulge).
##   * legs: gait pattern by support count and speed, foot planting in world
##     space, FABRIK IK per limb chain (tier A); pendulum legs in tier B
##   * body: bob, bounding pitch, crouch (tired / stalking / sleeping), lunges
##   * spine/tail: damped springs, swimming and serpentine waves, peristalsis
##   * wings, fins, tentacles, flagella, antennae; head look-at and postures
## `update_pose(dt, AnimState)` is independent of CreatureAgent (tests, previews).

var rig: AnimRig
var sk: Skeleton3D
var lp: LocomotionProfile
var visual: CreatureVisual = null
var cheap := false
var body_basis_offset := Basis.IDENTITY     # kept for CreatureAgent compatibility (always identity)

# Persistent animation state.
var t: float = 0.0
var gait_phase: float = 0.0
var wave_phase: float = 0.0
var flap_phase: float = 0.0
var head_yaw: float = 0.0
var head_pitch: float = 0.0
var fold: float = 1.0
var run_ratio: float = 0.0
var crouch: float = 0.0
var gait: Gait = Gait.new()
var flap_hz: float = 5.0
var last_foot_error: float = 0.0            # diagnostics: largest planted-foot IK error (geometry units)

var _deltas: Array[Quaternion] = []
var _bones := PackedInt32Array()
var _written: Array[Quaternion] = []
var _bob: float = 0.0
var _root_pitch: float = 0.0
var _root_roll: float = 0.0
var _state := AnimState.new()
var _cond_timer: float = 0.0
var _bulge_timer: float = 0.0
var _ground_cb: Callable
var _cheap_acc: float = 0.0
var _last_limp: int = -1


## Binds to a live agent's visual.
func setup(agent: CreatureAgent, vis: CreatureVisual) -> void:
	visual = vis
	setup_rig(agent.phenotype, vis.get_skeleton())
	_ground_cb = agent.ctx.ground_height


## Binds to any skeleton built from the phenotype's model (tests, previews).
func setup_rig(ph: Phenotype, skeleton: Skeleton3D) -> void:
	sk = skeleton
	lp = ph.locomotion
	rig = AnimRig.new()
	rig.build(ph.anatomy, skeleton, ph.senses.head_bone)
	var n := ph.anatomy.bones.size()
	_deltas.clear()
	_written.clear()
	for i in n:
		_deltas.append(Quaternion.IDENTITY)
		_written.append(Quaternion(2, 2, 2, 2))
	_bones = PackedInt32Array()
	for i in range(1, n):
		if rig.animated[i] == 1:
			_bones.append(i)
	var span := 0.0
	for c in rig.wings:
		var l := 0.0
		for b in c.bones:
			l += ph.anatomy.bones[b].length
		span = maxf(span, l * 2.0 * ph.anatomy.size_scale)
	flap_hz = clampf(5.0 / sqrt(maxf(span, 0.05)) * pow(maxf(lp.wing_loading, 20.0) / 100.0, 0.25), 1.2, 14.0) if span > 0.0 else 5.0


func set_cheap(on: bool) -> void:
	cheap = on


# --- Agent bridge ---------------------------------------------------------------------------------

func update(dt: float, a: CreatureAgent) -> void:
	if rig == null or dt <= 0.0:
		return
	var m := a.mover
	var st := _state
	st.xf = Transform3D(m.body_basis().scaled(Vector3.ONE * a.body_scale), m.pos)
	st.scale = a.body_scale
	st.speed = m.speed
	st.vel = m.vel
	st.turn_rate = m.turn_rate_now
	st.lateral_accel = m.lateral_accel
	st.medium = m.medium
	st.on_ground = m.on_ground and not m.flying
	st.flying = m.flying
	st.taking_off = m.taking_off
	st.gliding = m.gliding
	st.effort = m.effort
	st.max_speed = maxf(m.max_speed(m.medium if m.medium != &"air" else &"air", true), 0.1)
	st.vertical_speed = m.vertical_speed
	st.pose = a.current_pose()
	st.sleeping = a.sleeping
	st.alert = a.alert
	st.health = a.individual.health
	st.fatigue = a.individual.fatigue
	st.look_world = a.look_point()
	st.head_idle_yaw = a.head_yaw
	st.attack_t = a.attack_time
	st.call_t = a.call_time
	st.seed_id = a.individual.id
	st.ground = _ground_cb
	update_pose(dt, st)
	if visual != null:
		_visual_updates(dt, a, m)


func _visual_updates(dt: float, a: CreatureAgent, m: CreatureMover) -> void:
	if m.medium != &"land" or m.flying:
		visual.set_shadow_ground(-m.height_above_ground() / maxf(a.body_scale, 1e-3), 0.35)
	_cond_timer += dt
	if _cond_timer > 0.5:
		_cond_timer = 0.0
		visual.set_condition(m.submerged, clampf(1.0 - a.individual.health, 0.0, 1.0), a.individual.fatigue)
	_bulge_timer += dt
	if _bulge_timer > 0.2 and not cheap and a.lod <= 1:
		_bulge_timer = 0.0
		for g in a.muscles.groups:
			if g.kind == &"limb" or g.kind == &"wing" or g.kind == &"tail":
				var amount := a.muscles.bulge(g.index) * 0.16
				for b in g.bones:
					visual.set_muscle_bulge(b, amount)
					break


# --- Pose -----------------------------------------------------------------------------------------------

func update_pose(dt: float, st: AnimState) -> void:
	if rig == null or dt <= 0.0:
		return
	dt = minf(dt, 0.25)
	t += dt
	for b in _bones:
		_deltas[b] = Quaternion.IDENTITY
	var legged := not rig.legs.is_empty() and st.on_ground and st.medium == &"land" and not st.flying
	var r := clampf(st.speed / maxf(st.max_speed, 0.1), 0.0, 1.2)
	run_ratio = lerpf(run_ratio, minf(r, 1.0), clampf(dt * 6.0, 0.0, 1.0))
	var scaled_len := rig.body_length * st.scale
	var prev_phase := gait_phase
	var freq := 0.0
	var moving := false
	var limp_leg := -1
	if legged:
		gait = Gait.pick(lp.stance, rig.legs.size(), r)
		var radius := 0.0
		for leg in rig.legs:
			radius += Vector2(leg.home.x, leg.home.z).length()
		radius = radius / float(rig.legs.size()) * st.scale
		var v_eff := absf(st.speed) + absf(st.turn_rate) * radius * 0.7
		# Stride from what the legs can reach: a foot travels +-half a step around its home.
		var slack := INF
		for leg in rig.legs:
			slack = minf(slack, leg.slack)
		var half := 0.6 * slack * (1.0 + 0.5 * clampf(r, 0.0, 1.0))
		var stride_w := maxf(2.0 * half * st.scale / gait.duty, 0.02)
		freq = clampf(v_eff / stride_w, 0.0, 7.0)
		moving = freq > 0.08
		if moving:
			gait_phase = fposmod(gait_phase + freq * dt, 1.0)
		var i := 0
		for leg in rig.legs:
			leg.offset_target = gait.offset(lp.stance, leg.side, leg.rank, i, rig.legs.size())
			var dlt := wrapf(leg.offset_target - leg.offset, -0.5, 0.5)
			leg.offset = fposmod(leg.offset + dlt * clampf(dt * 2.5, 0.0, 1.0), 1.0)
			i += 1
		if st.health < 0.45:
			limp_leg = st.seed_id % rig.legs.size()
	# Travelling-wave clock (swimming, crawling, tentacles).
	var wave_f := 0.0
	var wave_amp := 0.0
	var ripple_amp := 0.0
	match st.medium:
		&"water":
			wave_f = clampf(1.4 * absf(st.speed) / maxf(scaled_len, 0.05), 0.45, 6.0)
			wave_amp = 0.1 + 0.32 * minf(st.effort, 1.0)
		_:
			if not legged and not st.flying and st.on_ground:
				match lp.gait:
					&"serpentine":
						wave_f = clampf(absf(st.speed) / maxf(scaled_len * 0.9, 0.05), 0.3, 4.0) if st.speed > 0.05 else 0.0
						wave_amp = 0.12 + 0.3 * minf(st.effort, 1.0) if st.speed > 0.05 else 0.04
					&"peristaltic":
						wave_f = clampf(absf(st.speed) / maxf(scaled_len * 0.5, 0.05), 0.2, 2.0)
						ripple_amp = 0.2 if st.speed > 0.02 else 0.04
					&"tentacle":
						wave_f = 0.35 + clampf(absf(st.speed) / maxf(scaled_len, 0.1), 0.0, 2.5)
					&"flagellar":
						wave_f = 0.5
	if st.flying or not legged and st.medium == &"air":
		wave_f = 0.0
	wave_phase = fposmod(wave_phase + wave_f * dt, 1.0)
	if st.flying:
		var fh := flap_hz * (0.35 if st.gliding else 1.0)
		flap_phase = fposmod(flap_phase + fh * dt, 1.0)
	# --- Crouch / posture ---------------------------------------------------------------------
	var crouch_t := 0.15 * st.fatigue
	match st.pose:
		&"stalk":
			crouch_t += 0.3
		&"sleep":
			crouch_t = 0.9
		&"rest":
			crouch_t += 0.45
		&"flee":
			crouch_t -= 0.05
		&"drink", &"eat":
			crouch_t += 0.05
	if st.sleeping:
		crouch_t = 0.9
	crouch = lerpf(crouch, clampf(crouch_t, 0.0, 0.95), clampf(dt * 3.0, 0.0, 1.0))
	# --- Behaviours ----------------------------------------------------------------------------------
	BodyMotion.head(self, st, _deltas, dt)
	if wave_amp > 0.0 and (not rig.axial.is_empty() or not rig.tails.is_empty()):
		BodyMotion.wave(self, st, _deltas, wave_amp)
	else:
		BodyMotion.tails(self, st, _deltas, dt)
		if legged and moving and not rig.axial.is_empty():
			wave_phase = gait_phase
			BodyMotion.wave(self, st, _deltas, 0.05 * run_ratio + 0.01)
	if ripple_amp > 0.0:
		BodyMotion.ripple(self, st, _deltas, ripple_amp)
	BodyMotion.wings(self, st, _deltas, dt)
	BodyMotion.fins(self, st, _deltas)
	BodyMotion.paddles(self, st, _deltas)
	BodyMotion.tentacles(self, st, _deltas)
	BodyMotion.flagella(self, st, _deltas)
	BodyMotion.antennae(self, st, _deltas)
	var ik := legged and not cheap and not rig.legs.is_empty()
	if legged and not ik:
		var amp := (0.12 + 0.55 * clampf(r, 0.0, 1.0)) if moving else 0.0
		BodyMotion.pendulum_legs(self, st, _deltas, gait_phase, amp)
	elif not legged and st.medium == &"water" and not rig.legs.is_empty():
		BodyMotion.pendulum_legs(self, st, _deltas, wave_phase, 0.3)
	# --- Root bone ------------------------------------------------------------------------------------
	_root(st, dt, legged, moving, freq)
	# --- Write -----------------------------------------------------------------------------------------
	for b in _bones:
		var q := rig.rest_q[b] * _deltas[b]
		if not q.is_equal_approx(_written[b]):
			sk.set_bone_pose_rotation(b, q)
			_written[b] = q
	if ik:
		LegStepper.update(rig, st, gait, dt, gait_phase, prev_phase, freq, moving, limp_leg)
		_solve_legs(st, limp_leg)


func _root(st: AnimState, dt: float, legged: bool, moving: bool, freq: float) -> void:
	var leg_h := rig.leg_height if legged else rig.body_length * 0.15
	var y := -crouch * leg_h * 0.8
	if legged:
		y -= 0.1 * leg_h * clampf(run_ratio * 3.0, 0.0, 1.0)   # slightly bent legs reach further
	var pitch := 0.0
	var roll := 0.0
	if legged and moving:
		y += gait.bob * rig.leg_height * sin(gait_phase * TAU * 2.0 + 0.6)
		pitch += gait.bound * sin(gait_phase * TAU + 1.0)
		roll += 0.025 * sin(gait_phase * TAU)
	y += 0.004 * rig.body_length * sin(t * 1.9)   # breathing
	var z := 0.0
	if st.attack_t > 0.0:
		var k := sin(clampf(st.attack_t / 0.45, 0.0, 1.0) * PI)
		z = -0.12 * rig.body_length * k
		pitch += 0.12 * k
	if st.pose == &"drink" or st.pose == &"eat":
		pitch += 0.06
	if st.pose == &"call":
		pitch -= 0.1
	_bob = lerpf(_bob, y, clampf(dt * 12.0, 0.0, 1.0))
	_root_pitch = lerpf(_root_pitch, pitch, clampf(dt * 10.0, 0.0, 1.0))
	_root_roll = lerpf(_root_roll, roll, clampf(dt * 10.0, 0.0, 1.0))
	var rot := Basis(Vector3.RIGHT, _root_pitch) * Basis(Vector3(0, 0, 1), _root_roll)
	var pivot := Vector3(0.0, rig.hip_height, rig.model.aabb.get_center().z)
	var pos := pivot - rot * pivot + Vector3(0.0, _bob, z)
	sk.set_bone_pose_position(0, pos)
	sk.set_bone_pose_rotation(0, rot.get_rotation_quaternion())


func _solve_legs(st: AnimState, limp_leg: int) -> void:
	var inv := st.xf.affine_inverse()
	var leg_h := rig.leg_height * st.scale
	var lift := 0.28 * leg_h * (0.5 + 0.5 * run_ratio)
	var worst := 0.0
	var i := 0
	for leg in rig.legs:
		var foot: Vector3
		if i == limp_leg:
			foot = LegStepper.home_world(rig, leg, st, 0.0) + Vector3.UP * 0.35 * leg_h
		else:
			foot = LegStepper.foot_world(leg, st, lift)
		i += 1
		var target := inv * foot
		var gp := rig.fk(leg.parent)
		var pb := gp.basis.orthonormalized()
		var hip := (gp * sk.get_bone_rest(leg.bones[0])).origin
		var q := pb * rig.inv_rest_global[leg.parent]
		var n := leg.bones.size()
		var fdir := (q * leg.foot_dir).normalized()
		var last_len := leg.lens[n - 1]
		for k in n:
			leg.pts[k] = hip + q * (leg.rest_pts[k] - leg.rest_pts[0])
		if n >= 3:
			# Flat foot: solve the leg without the foot bone to the ankle.
			var ankle := target - fdir * last_len
			for k in n:
				leg.sub_pts[k] = leg.pts[k]
			var err := LimbIK.fabrik(leg.sub_pts, leg.sub_lens, ankle, 6)
			for k in n:
				leg.pts[k] = leg.sub_pts[k]
			leg.pts[n] = leg.pts[n - 1] + fdir * last_len
			if leg.planted:
				worst = maxf(worst, err)
		else:
			var err2 := LimbIK.fabrik(leg.pts, leg.lens, target, 6)
			if leg.planted:
				worst = maxf(worst, err2)
			fdir = Vector3.ZERO
		LimbIK.apply(sk, leg.bones, leg.pts, pb, leg.seg_local, fdir)
	last_foot_error = worst


## World position of a leg's foot tip as currently posed (diagnostics / tests).
func foot_tip_world(leg_index: int, st: AnimState) -> Vector3:
	var leg := rig.legs[leg_index]
	var g := rig.fk(leg.bones[leg.bones.size() - 1])
	var tip_local := g * (leg.seg_local[leg.bones.size() - 1] * leg.lens[leg.bones.size() - 1])
	return st.xf * tip_local
