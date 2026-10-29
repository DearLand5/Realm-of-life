class_name BodyPart
extends RefCounted
## A node of the body-plan graph. Spine kinds own a chain of BodySegments;
## point kinds (eyes, horns, organs...) are described only by `params`.
##
## Attachment is expressed in the parent's spine parameter space so parts stay
## glued to the surface when the parent is reshaped:
##   attach_t      0..1 along the parent spine (0 = start/rear, 1 = end/front)
##   attach_angle  degrees around the parent axis: 0 = right (+X), 90 = dorsal,
##                 180 = left, 270 = ventral
##   attach_depth  0 = on the axis, 1 = on the surface, <1 inside (organs)
## A part attached at t<=0.001 or t>=0.999 with depth 0 continues the parent
## chain (head on neck, tail on torso rear).
##
## Expansion (done by AnatomyCompiler, never stored):
##   symmetry 1  -> mirrored copy across the sagittal plane
##   symmetry N>=3 -> N copies distributed radially around the parent axis
##   repeat_count -> metameric copies spread over [attach_t, attach_t+repeat_span],
##                   fanned by repeat_yaw (e.g. spider legs splaying forward/back)

var id: int = 0
var kind: StringName = &"torso"
var label: String = ""
var parent_id: int = -1
var attach_t: float = 0.5
var attach_angle: float = 0.0
var attach_depth: float = 1.0
var yaw: float = 0.0     # deg, orientation offset in the attach frame
var pitch: float = 0.0
var roll: float = 0.0
var symmetry: int = 0
var repeat_count: int = 1
var repeat_span: float = 0.0
var repeat_yaw: float = 0.0  # deg, yaw fan across repeats (rear copy -yaw/2 .. front copy +yaw/2)
var scale: float = 1.0   # uniform editor scale of the whole part (and children)
var base_radius: float = 0.1
var segments: Array[BodySegment] = []
var function: StringName = &"none"
var covering: int = 0
var muscle_ratio: float = 0.35  # fraction of part mass that is muscle
var fast_twitch: float = 0.5    # 0 endurance fibres .. 1 explosive fibres
var params: Dictionary = {}
var locked: bool = false
var group: int = -1


func _init(k: StringName = &"torso") -> void:
	kind = k
	params = PartSchema.default_params(k)


func is_spine() -> bool:
	return PartSchema.is_spine(kind)


func get_param(key: String, fallback = null):
	if params.has(key):
		return params[key]
	var specs := PartSchema.param_specs(kind)
	if specs.has(key):
		return PartSchema._default_value(specs[key])
	return fallback


func set_param(key: String, value) -> void:
	params[key] = PartSchema.sanitize(kind, key, value)


func total_length() -> float:
	var l := 0.0
	for s in segments:
		l += s.length
	return l * scale


func copy() -> BodyPart:
	var p := BodyPart.new(kind)
	p.from_dict(to_dict())
	return p


func to_dict() -> Dictionary:
	var segs := []
	for s in segments:
		segs.append(s.to_dict())
	var pj := {}
	for k in params:
		pj[k] = PartSchema.param_to_json(params[k])
	return {
		"id": id, "kind": str(kind), "label": label, "parent_id": parent_id,
		"attach_t": snappedf(attach_t, 0.0001), "attach_angle": snappedf(attach_angle, 0.01),
		"attach_depth": snappedf(attach_depth, 0.0001),
		"yaw": snappedf(yaw, 0.01), "pitch": snappedf(pitch, 0.01), "roll": snappedf(roll, 0.01),
		"symmetry": symmetry, "repeat_count": repeat_count, "repeat_span": repeat_span, "repeat_yaw": repeat_yaw,
		"scale": scale, "base_radius": snappedf(base_radius, 0.0001), "segments": segs,
		"function": str(function), "covering": covering, "muscle_ratio": muscle_ratio,
		"fast_twitch": fast_twitch, "params": pj, "locked": locked, "group": group,
	}


func from_dict(d: Dictionary) -> BodyPart:
	id = Serial.i(d, "id", 0)
	kind = Serial.sn(d, "kind", &"torso")
	label = Serial.s(d, "label", "")
	parent_id = Serial.i(d, "parent_id", -1)
	attach_t = clampf(Serial.f(d, "attach_t", 0.5), 0.0, 1.0)
	attach_angle = Serial.f(d, "attach_angle", 0.0)
	attach_depth = clampf(Serial.f(d, "attach_depth", 1.0), 0.0, 1.5)
	yaw = Serial.f(d, "yaw", 0.0)
	pitch = Serial.f(d, "pitch", 0.0)
	roll = Serial.f(d, "roll", 0.0)
	symmetry = clampi(Serial.i(d, "symmetry", 0), 0, 12)
	if symmetry == 2:
		symmetry = 1
	repeat_count = clampi(Serial.i(d, "repeat_count", 1), 1, 32)
	repeat_span = clampf(Serial.f(d, "repeat_span", 0.0), -1.0, 1.0)
	repeat_yaw = clampf(Serial.f(d, "repeat_yaw", 0.0), -180.0, 180.0)
	scale = clampf(Serial.f(d, "scale", 1.0), 0.05, 20.0)
	base_radius = clampf(Serial.f(d, "base_radius", 0.1), 0.001, 10.0)
	segments.clear()
	for sd in Serial.arr(d, "segments"):
		if sd is Dictionary:
			segments.append(BodySegment.new().from_dict(sd))
	var f := Serial.sn(d, "function", &"none")
	function = f if PartSchema.FUNCTIONS.has(f) else &"none"
	covering = clampi(Serial.i(d, "covering", 0), 0, CoveringDef.MAX_SLOTS - 1)
	muscle_ratio = clampf(Serial.f(d, "muscle_ratio", 0.35), 0.0, 0.9)
	fast_twitch = clampf(Serial.f(d, "fast_twitch", 0.5), 0.0, 1.0)
	params = PartSchema.default_params(kind)
	var pd := Serial.dict(d, "params")
	for k in pd:
		params[k] = PartSchema.sanitize(kind, k, pd[k])
	locked = Serial.b(d, "locked", false)
	group = Serial.i(d, "group", -1)
	return self


## Convenience: builds a chain of `count` equal segments.
static func make_chain(k: StringName, count: int, seg_len: float, r0: float, r1: float, bend_pitch: float = 0.0) -> BodyPart:
	var p := BodyPart.new(k)
	p.base_radius = r0
	for i in count:
		var t := float(i + 1) / float(count)
		p.segments.append(BodySegment.new(seg_len, lerpf(r0, r1, t), bend_pitch if i > 0 else 0.0, 0.0))
	return p
