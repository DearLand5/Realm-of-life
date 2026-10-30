class_name Percept
extends RefCounted
## One thing a creature knows about: perceived this moment or remembered with
## decaying confidence. Instances live in CreatureMemory.short and are updated
## in place by Perception (no per-tick allocation).

enum Kind { AGENT, EGG, CARCASS, SOUND, PLANT, WATER }

const ROLE_CONSPECIFIC := &"conspecific"
const ROLE_PREDATOR := &"predator"
const ROLE_PREY := &"prey"
const ROLE_COMPETITOR := &"competitor"
const ROLE_NEUTRAL := &"neutral"

var key: int = 0
var kind: int = Kind.AGENT
var role: StringName = ROLE_NEUTRAL
var agent: Node3D = null          # CreatureAgent for AGENT/EGG kinds (may become invalid)
var id: int = 0                   # Individual id / carcass id
var pos := Vector3.ZERO           # last known position
var vel := Vector3.ZERO           # last known velocity (m/s)
var dist: float = 0.0             # distance at the last perception update
var confidence: float = 1.0       # 1 = perceived right now, decays
var t_seen: float = 0.0           # physical time of the last detection
var sense: StringName = &"vision" # strongest sense that detected it
var mass: float = 1.0
var threat: float = 0.0           # 0..1 danger to me (predators, aggressive rivals)
var value: float = 0.0            # food: kg available; mate: quality
var moving := false
var in_water := false
var sound_kind: StringName = &""  # SOUND: alarm / mating_call / sound
var fresh := false                # detected during the latest perception update
var flags: int = 0


static func make_key(k: int, ident: int) -> int:
	return k * 1000000007 + ident


func age(now: float) -> float:
	return now - t_seen


## Position extrapolated along the last known velocity (capped), for pursuit.
func predicted(now: float, max_lead: float = 1.5) -> Vector3:
	if not moving:
		return pos
	return pos + vel * minf(age(now), max_lead)


func is_valid_target() -> bool:
	if agent == null:
		return kind != Kind.AGENT and kind != Kind.EGG
	return is_instance_valid(agent)
