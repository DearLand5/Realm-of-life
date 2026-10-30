class_name AnimState
extends RefCounted
## Everything the ProceduralAnimator needs to know about a body this frame,
## as plain data (filled from the CreatureAgent, or by hand in tests/previews).

var xf := Transform3D.IDENTITY           # body -> world (rotation * size scale, origin = ground contact)
var scale: float = 1.0                   # uniform size scale inside xf (metres per geometry unit)
var speed: float = 0.0                   # m/s along the heading (physical time)
var vel := Vector3.ZERO                  # world velocity
var turn_rate: float = 0.0               # rad/s, + = left
var lateral_accel: float = 0.0           # m/s² (centripetal), + = to the left
var medium: StringName = &"land"
var on_ground := true
var flying := false
var taking_off := false
var gliding := false
var effort: float = 0.0                  # 0..1 of top speed in the current medium
var max_speed: float = 1.0               # top speed in the current medium (m/s)
var vertical_speed: float = 0.0
var pose: StringName = &""               # eat drink attack sleep rest stalk flee court display call guard
var sleeping := false
var alert: float = 0.0                   # 0..1 raised-head vigilance
var health: float = 1.0
var fatigue: float = 0.0
var look_world := Vector3.INF            # point to look at (INF = none)
var head_idle_yaw: float = 0.0           # slow scanning yaw (rad)
var attack_t: float = 0.0                # remaining s of an attack lunge
var call_t: float = 0.0
var seed_id: int = 0
var ground: Callable                     # Callable(x: float, z: float) -> float terrain height (world)
var time_scale: float = 1.0
