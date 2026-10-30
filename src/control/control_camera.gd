class_name ControlCamera
extends Node3D
## Camera rig of the CreatureController.
##   first person   at SenseProfile.eye_point (eye bone), FOV from the eye layout,
##                  yaw/pitch follow the player's look input
##   third person   spring-follow orbit camera, distance auto-framed by body
##                  size (zoomable), terrain collision by height sampling,
##                  free or heading-locked orientation

const MIN_PITCH := -1.25
const MAX_PITCH := 1.0

var camera: Camera3D
var agent: CreatureAgent
var mode: StringName = &"third_person"
var yaw: float = 0.0              # world yaw of the view (forward = (-sin, 0, -cos))
var pitch: float = -0.3           # <0 looks down
var zoom: float = 1.0             # distance multiplier (third person)
var height_k: float = 1.0
var locked := true                # third person: view follows the creature's heading
var look_sensitivity: float = 0.0045

var _pos := Vector3.ZERO
var _dist: float = 4.0
var _fov_fp: float = 75.0


func _init() -> void:
	camera = Camera3D.new()
	camera.name = "ControlCamera"
	camera.far = 4000.0
	add_child(camera)


func setup(a: CreatureAgent, start_mode: StringName) -> void:
	agent = a
	mode = start_mode
	yaw = a.mover.heading
	pitch = -0.3 if mode == &"third_person" else 0.0
	zoom = 1.0
	_fov_fp = fov_for(a.phenotype.senses)
	camera.near = maxf(0.02, 0.02 * a.body_scale) if mode == &"first_person" else maxf(0.05, 0.1 * a.body_scale)
	snap()


## Camera field of view (vertical, degrees) from the eye arrangement: wide-set eyes see
## more of the sides, but a flat screen cannot show 300 degrees.
static func fov_for(sp: SenseProfile) -> float:
	if sp.eye_count == 0:
		return 70.0
	return clampf(62.0 + 0.16 * (sp.vision_fov - 90.0), 55.0, 105.0)


func set_mode(m: StringName) -> void:
	mode = m
	if agent != null:
		camera.near = maxf(0.02, 0.02 * agent.body_scale) if m == &"first_person" else maxf(0.05, 0.1 * agent.body_scale)
		if m == &"first_person":
			pitch = clampf(pitch, -0.6, 0.6)
		else:
			pitch = clampf(pitch, -1.1, 0.1)
	snap()


func look(rel: Vector2, invert_y: bool = false) -> void:
	yaw -= rel.x * look_sensitivity
	pitch = clampf(pitch - rel.y * look_sensitivity * (-1.0 if invert_y else 1.0), MIN_PITCH, MAX_PITCH)


func zoom_by(factor: float) -> void:
	zoom = clampf(zoom / maxf(factor, 0.1), 0.35, 4.0)


## Horizontal forward of the view (for camera-relative movement).
func view_forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func view_dir() -> Vector3:
	var cp := cos(pitch)
	return Vector3(-sin(yaw) * cp, sin(pitch), -cos(yaw) * cp)


func snap() -> void:
	_pos = _desired()[0]
	_apply(_pos, _desired()[1])


func _target_point() -> Vector3:
	var m := agent.mover
	return m.pos + Vector3.UP * m.height * 0.62 * height_k


## [camera position, look target]
func _desired() -> Array:
	var m := agent.mover
	if mode == &"first_person":
		var eye := agent.eye_world()
		return [eye, eye + view_dir() * 10.0]
	var tgt := _target_point()
	var framing := maxf(2.2, m.length * 2.4 + m.height * 1.2) * zoom
	_dist = framing
	var back := -view_dir()
	var want := tgt + back * framing
	# Terrain collision: keep the camera above the ground, pulling it in if needed.
	var ctx := agent.ctx
	var clearance := maxf(0.35, m.height * 0.25)
	var best := want
	for i in range(8, -1, -1):
		var f := float(i) / 8.0
		var p := tgt + back * framing * f
		if p.y >= ctx.ground_height(p.x, p.z) + clearance:
			best = p
			break
		best = Vector3(p.x, ctx.ground_height(p.x, p.z) + clearance, p.z)
	return [best, tgt]


func update(dt: float) -> void:
	if agent == null:
		return
	if mode == &"third_person" and locked:
		var dyaw := wrapf(agent.mover.heading - yaw, -PI, PI)
		if agent.mover.speed > 0.4:
			yaw += dyaw * clampf(dt * 1.6, 0.0, 1.0)
	var d := _desired()
	var k := 1.0 if mode == &"first_person" else clampf(dt * 9.0, 0.0, 1.0)
	_pos = _pos.lerp(d[0], k)
	_apply(_pos, d[1])


func _apply(p: Vector3, look_at: Vector3) -> void:
	camera.fov = _fov_fp if mode == &"first_person" else 62.0
	var dir := look_at - p
	if dir.length_squared() < 1e-6:
		return
	var up := Vector3.UP
	var roll := 0.0
	if mode == &"first_person" and agent.mover.medium != &"land":
		roll = agent.mover.roll * 0.6
	var b := Basis.looking_at(dir.normalized(), up)
	if roll != 0.0:
		b = b * Basis(Vector3.FORWARD, roll)
	camera.global_transform = Transform3D(b, p)
