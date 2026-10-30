class_name LegStepper
extends RefCounted
## Foot planting for IK legs. Each foot is either planted at a fixed world
## position or swinging along an arc to a predicted landing spot; the gait clock
## (phase + per-leg offset + duty factor) decides when a foot lifts. Planted feet
## never slide: their world position is only rewritten when a new step starts.


static func home_world(rig: AnimRig, leg: AnimRig.Leg, st: AnimState, lead_t: float) -> Vector3:
	var pos := st.xf.origin + st.vel * lead_t
	pos.y = st.xf.origin.y
	var b := Basis(Vector3.UP, st.turn_rate * lead_t) * st.xf.basis
	var h := b * Vector3(leg.home.x, 0.0, leg.home.z)
	var p := pos + h
	p.y = _ground(st, p.x, p.z) + leg.home.y * st.scale
	return p


static func _ground(st: AnimState, x: float, z: float) -> float:
	return float(st.ground.call(x, z)) if st.ground.is_valid() else st.xf.origin.y


## Initialises planted feet under the body (first frame, after teleports).
static func plant_all(rig: AnimRig, st: AnimState) -> void:
	for leg in rig.legs:
		leg.plant = home_world(rig, leg, st, 0.0)
		leg.swing_from = leg.plant
		leg.swing_to = leg.plant
		leg.planted = true
		leg.swing_t = 1.0
		leg.initialised = true


## Advances all legs. `phase`: gait clock 0..1; `moving`: the clock is advancing.
static func update(rig: AnimRig, st: AnimState, gait: Gait, dt: float, phase: float, prev_phase: float, freq: float, moving: bool, limp_leg: int) -> void:
	var swing_dur := clampf((1.0 - gait.duty) / maxf(freq, 0.3), 0.1, 0.45)
	var stance_dur := gait.duty / maxf(freq, 0.3)
	var leg_h := rig.leg_height * st.scale
	var any_swinging := false
	for leg in rig.legs:
		if not leg.initialised:
			plant_all(rig, st)
		# Teleport / huge drift: re-plant under the body.
		var home_now := home_world(rig, leg, st, 0.0)
		if Vector2(leg.plant.x - home_now.x, leg.plant.z - home_now.z).length() > leg.reach * st.scale * 3.0:
			leg.plant = home_now
			leg.planted = true
			leg.swing_t = 1.0
		if not leg.planted:
			leg.swing_t += dt / maxf(leg.swing_dur, 0.05)
			if leg.swing_t >= 1.0:
				leg.swing_t = 1.0
				leg.planted = true
				leg.plant = leg.swing_to
			else:
				any_swinging = true
	var ix := 0
	for leg in rig.legs:
		var is_limp := ix == limp_leg
		ix += 1
		if is_limp:
			continue
		if leg.planted and moving:
			var p := fposmod(phase + leg.offset, 1.0)
			var pp := fposmod(prev_phase + leg.offset, 1.0)
			if pp < gait.duty and (p >= gait.duty or p < pp):
				_start_swing(rig, leg, st, swing_dur, stance_dur)
	# Idle: bring stranded feet back under the body one at a time.
	if not moving and not any_swinging:
		var worst: AnimRig.Leg = null
		var worst_e := 0.0
		var thresh := 0.3 * leg_h
		for leg in rig.legs:
			var e := Vector2(leg.plant.x - home_world(rig, leg, st, 0.0).x, leg.plant.z - home_world(rig, leg, st, 0.0).z).length()
			if e > worst_e:
				worst_e = e
				worst = leg
		if worst != null and worst_e > thresh:
			worst.swing_from = worst.plant
			worst.swing_to = home_world(rig, worst, st, 0.0)
			worst.swing_t = 0.0
			worst.swing_dur = 0.24
			worst.planted = false


static func _start_swing(rig: AnimRig, leg: AnimRig.Leg, st: AnimState, swing_dur: float, stance_dur: float) -> void:
	leg.swing_from = leg.plant
	leg.swing_to = home_world(rig, leg, st, swing_dur + 0.5 * stance_dur)
	leg.swing_t = 0.0
	leg.swing_dur = swing_dur
	leg.planted = false


## Current world position of a foot (tip end).
static func foot_world(leg: AnimRig.Leg, st: AnimState, lift: float) -> Vector3:
	if leg.planted:
		return leg.plant
	var t := leg.swing_t
	var e := t * t * (3.0 - 2.0 * t)
	var p := leg.swing_from.lerp(leg.swing_to, e)
	p.y += lift * 4.0 * t * (1.0 - t)
	return p
