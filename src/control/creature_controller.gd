class_name CreatureController
extends CanvasLayer
## Lets the player control one CreatureAgent in first or third person.
## Self-contained: owns its CanvasLayer (HUD, joystick/buttons, vision effects)
## and a camera rig. Wiring (SimWorld / arena):
##
##   var c := CreatureController.new()
##   add_child(c)
##   c.possess(agent, &"third_person", world_node)   # &"first_person" | &"third_person"
##   c.exited.connect(...)                           # player pressed "exit"
##   ...
##   c.release()                                     # restores the previous camera, frees nothing else
##   c.queue_free()
##
## Control schemes follow the body (ControlScheme): ground, flyer, swimmer,
## tentacle, crawler, cell. Context buttons appear only when the action is
## possible. PC: WASD/stick + InputActions keys, right-drag to look, wheel to zoom.

signal exited
signal mode_changed(mode: StringName)

var agent: CreatureAgent
var world: Node
var mode: StringName = &"third_person"
var cam: ControlCamera
var hud: CreatureHud
var fx: ColorRect
var scheme: StringName = &"ground"
var gestures: GestureRecognizer
## While true the AI drives the creature and the controller only follows it with the camera.
var ai_driven := false

var _prev_camera: Camera3D = null
var _fly_on := false
var _diving := false
var _resting := false
var _avail: Dictionary = {}
var _avail_timer: float = 0.0
var _fx_mat: ShaderMaterial
var _pulse: float = 0.0
var _released := false
var _hint_timer: float = 0.0
var _hints: Array = []


func _init() -> void:
	layer = 20
	name = "CreatureController"


func possess(target: CreatureAgent, control_mode: StringName = &"third_person", world_node: Node = null) -> void:
	if target == null or not is_instance_valid(target):
		push_warning("CreatureController.possess: no agent")
		return
	agent = target
	world = world_node
	mode = control_mode if control_mode in [&"first_person", &"third_person"] else &"third_person"
	_released = false
	scheme = ControlScheme.kind_of(agent)
	InputActions.register_defaults(false)
	var vp := get_viewport()
	_prev_camera = vp.get_camera_3d() if vp != null else null
	agent.possess(self)
	_fly_on = agent.mover.flying
	cam = ControlCamera.new()
	add_child(cam)
	cam.setup(agent, mode)
	cam.camera.make_current()
	_build_fx()
	hud = CreatureHud.new()
	add_child(hud)
	hud.setup(mode)
	hud.exit_requested.connect(func() -> void: exited.emit())
	gestures = GestureRecognizer.new()
	add_child(gestures)
	gestures.attach_to(hud.look_surface)
	gestures.drag.connect(func(_p: Vector2, rel: Vector2) -> void: cam.look(rel, bool(UIApp.setting("invert_y", false))))
	gestures.orbit_drag.connect(func(rel: Vector2, _p: Vector2) -> void: cam.look(rel, bool(UIApp.setting("invert_y", false))))
	gestures.pinch.connect(func(f: float, _c: Vector2) -> void: cam.zoom_by(f))
	gestures.two_finger_rotate.connect(func(a: float, _c: Vector2) -> void: cam.yaw += a)
	_update_body_visibility()
	mode_changed.emit(mode)


## In first person the camera sits inside the head: hide the creature's own meshes.
func _update_body_visibility() -> void:
	if agent != null and is_instance_valid(agent) and agent.visual != null:
		agent.visual.visible = mode != &"first_person"


## Hands the creature back to the AI, restores the previous camera and removes the HUD.
func release() -> void:
	if _released:
		return
	_released = true
	if agent != null and is_instance_valid(agent):
		if agent.visual != null:
			agent.visual.visible = true
		if agent.controller == self:
			agent.release()
	if _prev_camera != null and is_instance_valid(_prev_camera) and _prev_camera.is_inside_tree():
		_prev_camera.make_current()
	if cam != null:
		cam.queue_free()
	if hud != null:
		hud.queue_free()
	if fx != null:
		fx.queue_free()
	if gestures != null:
		gestures.queue_free()
	cam = null
	hud = null
	fx = null
	gestures = null


func set_mode(m: StringName) -> void:
	if m == mode or cam == null:
		return
	mode = m
	cam.set_mode(m)
	_update_body_visibility()
	mode_changed.emit(m)


func toggle_mode() -> void:
	set_mode(&"first_person" if mode == &"third_person" else &"third_person")


func set_ai_driven(on: bool) -> void:
	ai_driven = on
	if agent == null or not is_instance_valid(agent):
		return
	if on:
		if agent.controller == self:
			agent.release()
	elif agent.controller == null:
		agent.possess(self)
		_fly_on = agent.mover.flying
	if hud != null:
		hud.stick.visible = not on
		for b in hud.buttons.values():
			(b as Control).modulate.a = 1.0 if not on else 0.0


# --- Callbacks from the agent ----------------------------------------------------------------------

func on_agent_died(cause: StringName) -> void:
	UIApp.notify(tr("Существо погибло") + ": " + str(cause), &"warning")
	exited.emit.call_deferred()


func on_agent_removed() -> void:
	exited.emit.call_deferred()


func _build_fx() -> void:
	fx = ColorRect.new()
	fx.name = "VisionFx"
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_mat = ShaderMaterial.new()
	_fx_mat.shader = load("res://shaders/vision_fx.gdshader")
	fx.material = _fx_mat
	add_child(fx)
	move_child(fx, 0)


# --- Per frame -----------------------------------------------------------------------------------------

func _process(dt: float) -> void:
	if agent == null or _released:
		return
	if not is_instance_valid(agent) or not agent.is_alive():
		return
	_avail_timer -= dt
	if _avail_timer <= 0.0:
		_avail_timer = 0.15
		_avail = PlayerActions.available(agent)
	if Input.is_action_just_pressed(&"camera_mode"):
		toggle_mode()
	if not ai_driven:
		_drive(dt)
	cam.update(dt)
	_update_fx(dt)
	_hint_timer -= dt
	if _hint_timer <= 0.0:
		_hint_timer = 0.2
		_hints = _compute_hints()
	var vis := ControlScheme.visible_buttons(agent, scheme, _avail)
	if ai_driven:
		for k in vis:
			vis[k] = k == &"btn_camera"
	var toggles := {&"btn_fly": _fly_on, &"btn_rest": _resting, &"btn_dive": _diving}
	hud.refresh(agent, vis, _hints, cam.yaw, toggles)


func _drive(dt: float) -> void:
	var it := agent.intent
	var m := agent.mover
	agent.player_pose = &""
	var stick := hud.stick.get_vector()
	var vertical := Input.get_action_strength(&"ascend") - Input.get_action_strength(&"descend")
	var sprint := Input.is_action_pressed(&"sprint")
	if Input.is_action_just_pressed(&"fly_toggle") and agent.phenotype.locomotion.can_fly:
		_fly_on = not _fly_on
	if Input.is_action_just_pressed(&"dive") and _avail.get("dive", false):
		_diving = not _diving
	if m.medium != &"water":
		_diving = false
	var moving := stick.length() > 0.06 or absf(vertical) > 0.1
	if moving:
		_resting = false
	var pace_max := m.max_speed(m.medium if m.medium != &"air" else &"air", sprint)
	if m.medium == &"land" and not sprint:
		pace_max = m.max_speed(&"land", false)
	var mag := clampf(stick.length(), 0.0, 1.0)
	var dir_y := 0.0
	if m.medium == &"water" and m.lp.can_swim:
		dir_y = vertical if not _diving else (vertical - 0.35 if absf(vertical) < 0.1 else vertical)
	elif m.flying:
		dir_y = 0.0
	if moving:
		var d := ControlScheme.move_direction(stick, cam.yaw, dir_y)
		var spd := pace_max * maxf(mag, 0.25 if absf(dir_y) > 0.1 else 0.0)
		it.direct(d if d.length_squared() > 1e-6 else m.forward(), spd)
	else:
		it.stop()
		if mode == &"first_person" and not _resting:
			var off := wrapf(cam.yaw - m.heading, -PI, PI)
			if absf(off) > 0.9:
				it.face = cam.view_forward()
	it.sprint = sprint
	it.jump = Input.is_action_just_pressed(&"jump")
	it.fly = _fly_on and agent.phenotype.locomotion.can_fly
	if it.fly:
		it.altitude = clampf(it.altitude + vertical * dt * 5.0, 0.8, 80.0) if m.flying else maxf(it.altitude, 4.0)
		if not moving and m.flying and not agent.phenotype.locomotion.can_hover:
			it.direct(m.forward(), m.max_speed(&"air") * 0.6)
	it.surface = not _diving
	if _diving:
		it.altitude = clampf(it.altitude + 0.0, 0.5, 30.0)
	it.avoid_water = false
	it.urgency = 0.0
	# Context actions.
	if Input.is_action_pressed(&"eat"):
		PlayerActions.eat(agent, dt)
	if Input.is_action_pressed(&"drink") and _avail.get("drink", false):
		PlayerActions.drink(agent, dt)
	if Input.is_action_just_pressed(&"attack") or (Input.is_action_pressed(&"attack") and _avail.get("attack", false)):
		PlayerActions.attack(agent)
	if Input.is_action_just_pressed(&"call"):
		PlayerActions.call_out(agent)
	if Input.is_action_just_pressed(&"mate"):
		var ok := PlayerActions.mate(agent)
		UIApp.notify(tr("Спаривание удалось") if ok else tr("Партнёр не готов"), &"success" if ok else &"info")
	if Input.is_action_just_pressed(&"rest"):
		_resting = not _resting
	if _resting:
		it.stop()
		agent.sleeping = agent.individual.fatigue > 0.2 or agent.brain.needs.awake < 0.5
		agent.player_pose = &"sleep" if agent.sleeping else &"rest"
	else:
		agent.sleeping = false


func _update_fx(_dt: float) -> void:
	if _fx_mat == null:
		return
	var sp := agent.phenotype.senses
	var gray := 0.0
	var dark := 0.0
	var blur := 0.0
	var mosaic := 0.0
	var edge := 0.0
	var tint := Vector3(0.55, 0.75, 1.0)
	if mode == &"first_person":
		gray = clampf(1.0 - sp.color_vision * 1.6, 0.0, 1.0)
		var light := agent.ctx.climate.light_at(agent.eye_world()) if agent.ctx.climate != null else 1.0
		dark = clampf((1.0 - light) * 1.2, 0.0, 1.0) * (1.0 - sp.night_vision * 0.75)
		blur = clampf(pow(1.0 - sp.acuity, 1.5) * 0.9, 0.0, 0.9)
		mosaic = 1.0 if sp.compound_eyes else 0.0
		edge = clampf((sp.vision_fov - 200.0) / 160.0, 0.0, 0.8)
		if sp.light_only or sp.eye_count == 0:
			blur = 1.0
			gray = 1.0
		if agent.sleeping:
			dark = 1.0
	_pulse += _dt * 7.0
	var hurt := clampf(agent.damage_flash * 0.9 + (1.0 - agent.individual.health) * 0.45, 0.0, 1.0)
	_fx_mat.set_shader_parameter(&"gray", gray)
	_fx_mat.set_shader_parameter(&"darkness", dark)
	_fx_mat.set_shader_parameter(&"night_tint", tint)
	_fx_mat.set_shader_parameter(&"blur", blur)
	_fx_mat.set_shader_parameter(&"mosaic", mosaic)
	_fx_mat.set_shader_parameter(&"edge_blur", edge)
	_fx_mat.set_shader_parameter(&"damage", hurt)
	_fx_mat.set_shader_parameter(&"pulse", _pulse)
	fx.visible = gray > 0.01 or dark > 0.01 or blur > 0.01 or mosaic > 0.01 or edge > 0.01 or hurt > 0.02


## Direction markers for senses the eyes cannot cover: smell, hearing, vibration.
func _compute_hints() -> Array:
	var out: Array = []
	var per := agent.perception
	if per == null:
		return out
	for k in per.memory.short:
		var p: Percept = per.memory.short[k]
		if p.confidence < 0.3 or p.dist < 3.0:
			continue
		if not (p.sense in [&"smell", &"hearing", &"vibration"]) or p.kind == Percept.Kind.PLANT:
			continue
		if p.sense == &"hearing" and p.kind == Percept.Kind.SOUND and p.sound_kind == &"":
			continue
		var d := p.pos - agent.mover.pos
		var yaw_t := atan2(-d.x, -d.z)
		out.append({"angle": -wrapf(yaw_t - cam.yaw, -PI, PI), "kind": p.sense, "strength": p.confidence * clampf(1.0 - p.dist / 80.0, 0.2, 1.0)})
		if out.size() >= 6:
			break
	return out
