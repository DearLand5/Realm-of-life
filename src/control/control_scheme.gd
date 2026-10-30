class_name ControlScheme
extends RefCounted
## Control scheme by body type: which on-screen buttons make sense and when.
##   ground    camera-relative stick, sprint, jump (if the body can)
##   flyer     + take-off/land toggle, climb/dive buttons while airborne
##   swimmer   3D swimming: ascend/dive
##   tentacle  radial crawlers/swimmers (octopus, jellyfish, starfish)
##   crawler   legless/limbless crawlers (worms, snakes)
##   cell      single cells: drifting swimmers
## Context buttons (eat, drink, attack, mate) appear only when the action is
## possible right now.

const BUTTON_ACTION := {
	&"btn_jump": &"jump", &"btn_attack": &"attack", &"btn_interact": &"interact", &"btn_sprint": &"sprint",
	&"btn_fly": &"fly_toggle", &"btn_dive": &"dive", &"btn_eat": &"eat", &"btn_drink": &"drink",
	&"btn_mate": &"mate", &"btn_call": &"call", &"btn_rest": &"rest", &"btn_ascend": &"ascend",
	&"btn_descend": &"descend", &"btn_camera": &"camera_mode",
}


static func kind_of(a: CreatureAgent) -> StringName:
	var lp := a.mover.lp
	if lp.can_fly:
		return &"flyer"
	if a.mover.aquatic_only:
		return &"cell" if lp.gait == &"flagellar" else (&"tentacle" if lp.gait == &"tentacle" else &"swimmer")
	if lp.can_walk:
		return &"ground"
	if lp.gait == &"tentacle" or lp.stance == &"radial":
		return &"tentacle"
	if lp.gait == &"flagellar":
		return &"cell"
	if lp.can_swim and a.phys.habitat == &"water":
		return &"swimmer"
	return &"crawler"


## Visibility of every layout button for the current moment.
static func visible_buttons(a: CreatureAgent, scheme: StringName, avail: Dictionary) -> Dictionary:
	var lp := a.mover.lp
	var airborne := a.mover.flying
	var swimming := a.mover.medium == &"water"
	return {
		&"btn_jump": bool(avail["jump"]) and scheme in [&"ground", &"flyer"],
		&"btn_attack": bool(avail["attack"]),
		&"btn_interact": false,
		&"btn_sprint": bool(avail["sprint"]) and scheme in [&"ground", &"flyer", &"crawler"],
		&"btn_fly": lp.can_fly,
		&"btn_dive": bool(avail["dive"]) and not airborne and scheme != &"cell",
		&"btn_eat": bool(avail["eat"]),
		&"btn_drink": bool(avail["drink"]),
		&"btn_mate": bool(avail["mate"]),
		&"btn_call": scheme not in [&"cell", &"tentacle"] or a.phys.endothermy > 0.3,
		&"btn_rest": true,
		&"btn_ascend": (airborne or swimming) and (bool(avail["ascend"])),
		&"btn_descend": (airborne or swimming) and (bool(avail["descend"])),
		&"btn_camera": true,
	}


## Maps the stick + vertical input to a movement request for the agent.
## `view_yaw` is the camera yaw; stick is (x right, y down) like Input.get_vector.
## Returns the world direction (y = vertical component for fliers/swimmers).
static func move_direction(stick: Vector2, view_yaw: float, vertical: float) -> Vector3:
	var fwd := Vector3(-sin(view_yaw), 0.0, -cos(view_yaw))
	var right := Vector3(cos(view_yaw), 0.0, -sin(view_yaw))
	var d := right * stick.x + fwd * (-stick.y)
	d.y = vertical
	return d
