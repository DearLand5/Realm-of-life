class_name BodySegment
extends RefCounted
## One segment of a spine-like part (torso vertebra group, limb bone, tail
## segment...). Each segment becomes one bone. Angles are degrees, relative to
## the previous segment's frame (bone frame: +Y along bone, +X right, +Z up
## for horizontal torsos; see docs/ARCHITECTURE.md "Frames").

var length: float = 0.3       # m (before genome scaling)
var radius: float = 0.1       # m, radius at the END of this segment
var pitch: float = 0.0        # deg, bend around local X (up/down for torso)
var yaw: float = 0.0          # deg, bend around local Z (sideways for torso)
var roll: float = 0.0         # deg, twist around local Y
var flatten: float = 1.0      # cross-section height/width ratio (0.2..3)
var swing_limit: float = 40.0 # deg, joint swing range at segment start
var twist_limit: float = 15.0 # deg
var stiffness: float = 0.5    # 0 floppy .. 1 rigid (joint resistance)
var soft: float = 0.0         # 0..1 soft-tissue jiggle amount (ears, bellies, tails)


func _init(l: float = 0.3, r: float = 0.1, p: float = 0.0, y: float = 0.0) -> void:
	length = l
	radius = r
	pitch = p
	yaw = y


func copy() -> BodySegment:
	var s := BodySegment.new()
	s.from_dict(to_dict())
	return s


func to_dict() -> Dictionary:
	return {
		"length": snappedf(length, 0.0001), "radius": snappedf(radius, 0.0001),
		"pitch": snappedf(pitch, 0.01), "yaw": snappedf(yaw, 0.01), "roll": snappedf(roll, 0.01),
		"flatten": snappedf(flatten, 0.001), "swing_limit": swing_limit, "twist_limit": twist_limit,
		"stiffness": stiffness, "soft": soft,
	}


func from_dict(d: Dictionary) -> BodySegment:
	length = clampf(Serial.f(d, "length", 0.3), 0.005, 20.0)
	radius = clampf(Serial.f(d, "radius", 0.1), 0.001, 10.0)
	pitch = Serial.f(d, "pitch", 0.0)
	yaw = Serial.f(d, "yaw", 0.0)
	roll = Serial.f(d, "roll", 0.0)
	flatten = clampf(Serial.f(d, "flatten", 1.0), 0.1, 4.0)
	swing_limit = clampf(Serial.f(d, "swing_limit", 40.0), 0.0, 180.0)
	twist_limit = clampf(Serial.f(d, "twist_limit", 15.0), 0.0, 180.0)
	stiffness = clampf(Serial.f(d, "stiffness", 0.5), 0.0, 1.0)
	soft = clampf(Serial.f(d, "soft", 0.0), 0.0, 1.0)
	return self
