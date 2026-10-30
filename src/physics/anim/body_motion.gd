class_name BodyMotion
extends RefCounted
## Non-IK body animation written as bone rotation deltas (see ProceduralAnimator):
## head look/eat/sleep postures, spring-driven tails, travelling body waves
## (swimming, serpentine crawling, peristalsis), wing flapping/folding, fins,
## tentacles, flagella, antennae and swimming paddles. Amplitudes follow speed,
## effort, size and condition so different anatomies move differently.

const UP := Vector3.UP
const RIGHT := Vector3.RIGHT
const FWD := Vector3(0, 0, 1)   # rotation axis along the body (+Z); positive lifts the right side


static func head(a: ProceduralAnimator, st: AnimState, deltas: Array[Quaternion], dt: float) -> void:
	var rig := a.rig
	if rig.head_chain.is_empty():
		return
	var yaw := st.head_idle_yaw
	var pitch := 0.0       # + = head down
	var d := Vector3.ZERO
	if st.look_world != Vector3.INF:
		d = st.xf.basis.inverse() * (st.look_world - st.xf.origin)
		if Vector2(d.x, d.z).length() > 0.05:
			yaw = clampf(atan2(-d.x, -d.z), -1.1, 1.1)
			pitch = clampf(-atan2(d.y - rig.hip_height * 1.0, Vector2(d.x, d.z).length()), -0.5, 0.6)
	match st.pose:
		&"eat", &"drink":
			pitch = 0.95 + 0.12 * sin(a.t * 6.0) * (1.0 if st.pose == &"eat" else 0.3)
			yaw *= 0.2
		&"sleep":
			pitch = 1.0
			yaw = 0.7
		&"rest":
			pitch = 0.5
		&"stalk":
			pitch = 0.45
		&"flee":
			pitch = -0.15
			yaw *= 0.3
		&"attack":
			pitch = -0.2 + 0.5 * clampf(st.attack_t / 0.45, 0.0, 1.0)
		&"call", &"display":
			pitch = -0.5
	pitch -= 0.35 * st.alert
	a.head_yaw = lerpf(a.head_yaw, yaw, clampf(dt * 6.0, 0.0, 1.0))
	a.head_pitch = lerpf(a.head_pitch, pitch, clampf(dt * 5.0, 0.0, 1.0))
	var n := rig.head_chain.size()
	for k in n:
		var w := 1.0 / float(n)
		var b := rig.head_chain[k]
		rig.rotate(deltas, b, UP, a.head_yaw * w)
		rig.rotate(deltas, b, RIGHT, -a.head_pitch * w)


static func tails(a: ProceduralAnimator, st: AnimState, deltas: Array[Quaternion], dt: float) -> void:
	var rig := a.rig
	var step := minf(dt, 0.04)
	var geo_acc := st.lateral_accel / maxf(st.scale, 0.01)
	for c in rig.tails:
		var nb := c.bones.size()
		for k in nb:
			var b := c.bones[k]
			var along := float(k + 1) / float(nb)
			var drive_yaw := -clampf(geo_acc * 0.03, -0.6, 0.6) * along
			var idle := 0.12 * sin(a.t * 1.3 + c.phase) * (0.4 + along)
			if st.pose == &"sleep":
				idle *= 0.2
			var tgt_yaw := drive_yaw + idle
			var lift := (0.18 * a.run_ratio - 0.05 * a.crouch) * along
			var i := k * 2
			# Damped spring on (yaw, pitch) per bone, stored as two values each.
			var ang_y := c.spring[i]
			var ang_p := c.spring[i + 1]
			ang_y += (tgt_yaw - ang_y) * clampf(step * 9.0, 0.0, 1.0)
			ang_p += (lift - ang_p) * clampf(step * 7.0, 0.0, 1.0)
			c.spring[i] = ang_y
			c.spring[i + 1] = ang_p
			rig.rotate(deltas, b, UP, ang_y / float(nb) * 1.6)
			rig.rotate(deltas, b, RIGHT, ang_p / float(nb) * 1.6)


## Travelling lateral wave along torso (+ tail) bones.
static func wave(a: ProceduralAnimator, st: AnimState, deltas: Array[Quaternion], amp: float) -> void:
	var rig := a.rig
	var ph := a.wave_phase * TAU
	var count := rig.axial.size()
	for i in count:
		var s := rig.axial_s[i]
		var ang := amp * (0.15 + 0.85 * s) * sin(ph - TAU * 0.9 * s)
		rig.rotate(deltas, rig.axial[i], UP, ang / maxf(float(count), 1.0) * 2.2)
	for c in rig.tails:
		var nb := c.bones.size()
		for k in nb:
			var b := c.bones[k]
			var s2 := clampf(c.s + (1.0 - c.s) * float(k + 1) / float(nb), 0.0, 1.0)
			var ang2 := amp * (0.25 + 0.75 * s2) * sin(ph - TAU * 0.9 * s2)
			rig.rotate(deltas, b, UP, ang2 / float(nb) * 1.8)


## Peristalsis: slow longitudinal ripples (pitch) for soft apods.
static func ripple(a: ProceduralAnimator, st: AnimState, deltas: Array[Quaternion], amp: float) -> void:
	var rig := a.rig
	var ph := a.wave_phase * TAU
	for i in rig.axial.size():
		var s := rig.axial_s[i]
		rig.rotate(deltas, rig.axial[i], RIGHT, amp * sin(ph - TAU * 1.5 * s) * 0.5)
		rig.rotate(deltas, rig.axial[i], UP, amp * 0.5 * sin(ph * 0.5 - TAU * s))


static func wings(a: ProceduralAnimator, st: AnimState, deltas: Array[Quaternion], dt: float) -> void:
	var rig := a.rig
	if rig.wings.is_empty():
		return
	var flying := st.flying
	var fold_t := 0.0 if flying else 1.0
	a.fold = lerpf(a.fold, fold_t, clampf(dt * 4.0, 0.0, 1.0))
	var flap_amp := 0.0
	if flying:
		flap_amp = 0.95
		if st.taking_off:
			flap_amp = 1.25
		elif st.gliding:
			flap_amp = 0.06
		else:
			flap_amp *= 0.55 + 0.45 * clampf(st.effort + absf(st.vertical_speed) * 0.15, 0.0, 1.0)
	for c in rig.wings:
		var side := float(c.side if c.side != 0 else 1)
		var nb := c.bones.size()
		for k in nb:
			var b := c.bones[k]
			var lag := float(k) * 0.55
			var up := flap_amp * sin(a.flap_phase * TAU - lag) * (0.55 + 0.45 * float(k + 1) / float(nb))
			if k == 0:
				up += 0.12 * (1.0 if flying else 0.0)   # dihedral in flight
			rig.rotate(deltas, b, FWD, up * side)
			var fold := a.fold
			if k == 0:
				rig.rotate(deltas, b, UP, -side * 1.15 * fold)
			elif k == 1:
				rig.rotate(deltas, b, UP, side * 2.1 * fold)
			else:
				rig.rotate(deltas, b, UP, -side * 0.8 * fold)


static func fins(a: ProceduralAnimator, st: AnimState, deltas: Array[Quaternion]) -> void:
	var rig := a.rig
	var swim := 1.0 if st.medium == &"water" else 0.35
	var amp := (0.1 + 0.35 * st.effort) * swim
	for c in rig.fins:
		var axis := UP if absf(c.dir.z) > 0.7 else FWD
		for k in c.bones.size():
			var ang := amp * sin(a.wave_phase * TAU - TAU * 0.9 * c.s - float(k) * 0.6 + c.phase)
			rig.rotate(deltas, c.bones[k], axis, ang)


static func paddles(a: ProceduralAnimator, st: AnimState, deltas: Array[Quaternion]) -> void:
	var rig := a.rig
	var swimming := st.medium == &"water"
	for c in rig.paddles:
		var amp := (0.25 + 0.5 * st.effort) if swimming else 0.05
		var ph := a.wave_phase * TAU + c.phase + (PI if c.side < 0 else 0.0)
		for k in c.bones.size():
			rig.rotate(deltas, c.bones[k], RIGHT, amp * sin(ph - float(k) * 0.7) * (0.5 if k > 0 else 1.0))
			if swimming:
				rig.rotate(deltas, c.bones[k], FWD, 0.25 * float(c.side) * (1.0 if k == 0 else 0.0))


static func tentacles(a: ProceduralAnimator, st: AnimState, deltas: Array[Quaternion]) -> void:
	var rig := a.rig
	var moving := clampf(st.effort * 2.0, 0.0, 1.0)
	var amp := 0.18 + 0.35 * moving
	for c in rig.tentacles:
		var d := c.dir
		var a1 := d.cross(UP)
		if a1.length_squared() < 1e-4:
			a1 = RIGHT
		a1 = a1.normalized()
		var a2 := d.cross(a1).normalized()
		var nb := c.bones.size()
		for k in nb:
			var ph := a.wave_phase * TAU - float(k) * 0.9 + c.phase * 3.0
			var w := 0.4 + 0.6 * float(k + 1) / float(nb)
			rig.rotate(deltas, c.bones[k], a1, amp * w * sin(ph) / float(nb) * 2.0)
			rig.rotate(deltas, c.bones[k], a2, amp * 0.6 * w * cos(ph * 0.8) / float(nb) * 2.0)
			if st.pose == &"eat" or st.pose == &"attack":
				rig.rotate(deltas, c.bones[k], a1, -0.35 / float(nb))


static func flagella(a: ProceduralAnimator, st: AnimState, deltas: Array[Quaternion]) -> void:
	var rig := a.rig
	for c in rig.flagella:
		var nb := c.bones.size()
		for k in nb:
			rig.rotate(deltas, c.bones[k], UP, (0.35 + 0.3 * st.effort) * sin(a.t * 14.0 - float(k) * 1.1) / float(nb) * 2.0)


static func antennae(a: ProceduralAnimator, st: AnimState, deltas: Array[Quaternion]) -> void:
	var rig := a.rig
	for c in rig.antennae:
		for k in c.bones.size():
			rig.rotate(deltas, c.bones[k], UP, 0.12 * sin(a.t * 2.3 + c.phase + float(k)))
			rig.rotate(deltas, c.bones[k], RIGHT, 0.08 * sin(a.t * 1.7 + c.phase * 2.0))


## Simple pendulum legs for tier B / non-IK use.
static func pendulum_legs(a: ProceduralAnimator, st: AnimState, deltas: Array[Quaternion], phase: float, amp: float) -> void:
	var rig := a.rig
	for leg in rig.legs:
		var ph := fposmod(phase + leg.offset, 1.0)
		var sw := sin(ph * TAU)
		rig.rotate(deltas, leg.bones[0], RIGHT, amp * sw)
		if leg.bones.size() > 1:
			rig.rotate(deltas, leg.bones[1], RIGHT, -amp * 0.8 * maxf(0.0, -cos(ph * TAU)) - amp * 0.2 * sw)
