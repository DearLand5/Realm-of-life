class_name CreatureAgent
extends Node3D
## One live individual in the world (ARCHITECTURE §6.4): visual + mover + brain +
## perception + memory + animator + biology, driven by the world through
## sim_update(). Eggs are agents too (immobile, incubating, edible).
##
## WIRING (world / arena):
##   var agent := CreatureAgent.new(); world_root.add_child(agent); agent.setup(ind, ctx)
##   every frame:            agent.sim_update(phys_dt, bio_dt)
##   PerformanceManager:     agent.set_tier(t) / agent.set_lod(l) / agent.is_possessed()
##   ctx callbacks (WorldContext): spawn_individual(ind), agent_died(agent, cause)
## The agent node must live under an un-transformed parent (position == world position).
## Optional: ctx.set_meta(&"headless", true) skips the visual (tests).

signal died(agent: CreatureAgent, cause: StringName)
signal action_changed(agent: CreatureAgent, label: String)

const AI_INTERVAL := [0.16, 0.8]      # s per AI tick for tier A / B
const BIO_STEP := [15.0, 60.0]        # bio s accumulated between biology ticks
const EGG_STEP := 150.0
const STATE_SAVE_EVERY := 6.0
const MUSCLE_TIME_SCALE := 0.4         # slows MuscleSystem fatigue/recovery: bursts last ~10 s, not ~4 s

var individual: Individual
var phenotype: Phenotype
var phys: PhysiologyProfile
var ctx: WorldContext
var visual: CreatureVisual = null
var egg_mesh: MeshInstance3D = null
var mover: CreatureMover
var intent := MoveIntent.new()
var brain: Brain
var perception: Perception
var memory := CreatureMemory.new()
var personality: Personality
var muscles: MuscleSystem
var bio: BiologySystem
var animator: ProceduralAnimator = null
var rng: Rng
var tier: int = 0
var lod: int = 0
var now: float = 0.0
var food_weights := PackedFloat32Array()
var body_scale: float = 1.0
var headless := false

# Behavioural state read by the animator / HUD.
var sleeping := false
var alert: float = 0.0
var head_yaw: float = 0.0
var call_time: float = 0.0
var attack_time: float = 0.0
var mating_done := false
var last_attacker: CreatureAgent = null
var last_attacked_t: float = -100.0
var courted_by: int = -1
var courted_t: float = -100.0
var controller: Object = null
var player_pose: StringName = &""
var selected := false
var _ring: MeshInstance3D = null
var damage_flash: float = 0.0

var _dead := false
var _egg_mode := false
var _ai_timer: float = 0.0
var _ai_acc: float = 0.0
var _bio_acc: float = 0.0
var _move_acc: float = 0.0
var _anim_acc: float = 0.0
var _muscle_acc: float = 0.0
var _frame: int = 0
var _attack_cd: float = 0.0
var _combat_power: float = 1.0
var _dependants: Array[CreatureAgent] = []
var _dep_timer: float = 0.0
var _plant_prefs := PackedFloat32Array()
var _plant_species_n: int = -1
var _save_timer: float = 0.0
var _push_timer: float = 0.0
var _grp: Dictionary = {}
var _flash_timer: float = 0.0
var _last_label: String = ""
var _cat_legs := PackedInt32Array()
var _cat_swim := PackedInt32Array()
var _cat_wing := PackedInt32Array()
var _cat_axial := PackedInt32Array()
var _bulge_timer: float = 0.0


# --- Setup --------------------------------------------------------------------------------

func setup(ind: Individual, context: WorldContext) -> void:
	ctx = context
	individual = ind if ind != null else Individual.new()
	if individual.genome == null:
		push_warning("CreatureAgent.setup: individual without genome, using a fallback body")
		individual.genome = BodyPlanPresets.create(&"cell")
	phenotype = individual.get_phenotype()
	phys = phenotype.physiology
	name = "Creature_%d" % individual.id
	rng = Rng.new(individual.seed if individual.seed != 0 else individual.id * 7919 + 1)
	headless = bool(ctx.get_meta(&"headless", false)) or DisplayServer.get_name() == "headless"
	personality = Personality.from_genome(individual.genome, float(phenotype.anatomy.stats.get("brain", 0.3)))
	memory.configure(personality.learning, personality.brain)
	bio = BiologySystem.new(individual.seed ^ 0x5bd1e995, ctx.mutation_settings, ctx.climate)
	muscles = MuscleSystem.new(phenotype)
	_index_muscles()
	DietModel.food_weights(phys, food_weights)
	_egg_mode = individual.is_egg()
	position = individual.position
	mover = CreatureMover.new()
	mover.setup(phenotype, ctx, individual.position, individual.heading, individual.growth)
	AgentNav.fix_spawn(self)
	_combat_power = Relations.combat_power(phys, phenotype.anatomy.stats, individual.mass())
	body_scale = phenotype.anatomy.size_scale * individual.growth
	_ai_timer = rng.range_f(0.0, AI_INTERVAL[0])
	if _egg_mode:
		_build_egg()
	else:
		_build_creature()
	_restore_state()
	_apply_transform()
	ctx.agents.insert(self, position)


func _build_creature() -> void:
	brain = Brain.new()
	brain.setup(self)
	perception = Perception.new()
	perception.setup(self)
	if not headless:
		visual = CreatureVisual.new()
		visual.async_build = true
		add_child(visual)
		visual.setup(phenotype.anatomy, individual.seed, lod)
		animator = ProceduralAnimator.new()
		animator.setup(self, visual)


func _build_egg() -> void:
	if headless:
		return
	var r := cbrt_radius()
	egg_mesh = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	sph.radial_segments = 14
	sph.rings = 8
	egg_mesh.mesh = sph
	var mat := StandardMaterial3D.new()
	var cov: CoveringDef = phenotype.anatomy.coverings[0] if not phenotype.anatomy.coverings.is_empty() else null
	var base := Color(0.88, 0.84, 0.74)
	mat.albedo_color = base.lerp(cov.color_b, 0.25) if cov != null else base
	mat.roughness = 0.55
	egg_mesh.material_override = mat
	egg_mesh.scale = Vector3(r * 1.7, r * 2.2, r * 1.7)
	egg_mesh.position = Vector3(0, r * 1.1, 0)
	add_child(egg_mesh)


func cbrt_radius() -> float:
	var kg := maxf(phys.mass * pow(phys.birth_growth, 3.0), 1e-4)
	return clampf(pow(3.0 * kg / (4.0 * PI * 1050.0), 1.0 / 3.0), 0.01, 0.6)


func _index_muscles() -> void:
	for g in muscles.groups:
		var i := g.index
		if g.kind == &"wing" or g.function == &"fly":
			_cat_wing.append(i)
		elif g.kind == &"fin" or g.function == &"swim":
			_cat_swim.append(i)
		elif g.kind == &"limb":
			_cat_legs.append(i)
		else:
			_cat_axial.append(i)


# --- Contract ---------------------------------------------------------------------------------

func species_id() -> int:
	return individual.species_id if individual != null else -1


func is_alive() -> bool:
	return not _dead and individual != null and individual.alive


func is_egg() -> bool:
	return _egg_mode


func is_possessed() -> bool:
	return controller != null


func set_tier(t: int) -> void:
	tier = clampi(t, 0, 1)
	if animator != null:
		animator.set_cheap(tier == 1 and controller == null)


func set_lod(l: int) -> void:
	lod = l
	if visual != null:
		visual.set_lod(l)


func possess(c: Object) -> void:
	controller = c
	if brain != null:
		brain.stop_all()
	intent.clear()
	sleeping = false
	tier = 0
	if animator != null:
		animator.set_cheap(false)


func release() -> void:
	controller = null
	intent.clear()
	player_pose = &""
	_ai_timer = 0.0


func teardown() -> void:
	if ctx != null:
		ctx.agents.remove(self)
	if controller != null and is_instance_valid(controller) and controller.has_method("on_agent_removed"):
		controller.call("on_agent_removed")
	controller = null
	_dead = true
	write_state()


# --- Frame update ------------------------------------------------------------------------------

func sim_update(phys_dt: float, bio_dt: float) -> void:
	if _dead or individual == null or not individual.alive:
		return
	now += phys_dt
	if _egg_mode:
		_egg_update(phys_dt, bio_dt)
		return
	_frame += 1
	_attack_cd = maxf(0.0, _attack_cd - phys_dt)
	attack_time = maxf(0.0, attack_time - phys_dt)
	call_time = maxf(0.0, call_time - phys_dt)
	damage_flash = maxf(0.0, damage_flash - phys_dt * 1.5)
	_ai_acc += phys_dt
	_bio_acc += bio_dt
	var possessed := controller != null
	_ai_timer -= phys_dt
	if _ai_timer <= 0.0:
		_ai_timer = AI_INTERVAL[tier] * rng.range_f(0.85, 1.2)
		_think(_ai_acc, possessed)
		_ai_acc = 0.0
	# Movement: tier A every frame, tier B in bigger, rarer steps.
	_move_acc += phys_dt
	if tier == 0 or possessed or _frame % 3 == 0 or _move_acc > 0.5:
		var cond := _condition()
		mover.step(_move_acc, intent, cond, tier == 1 and not possessed)
		_apply_mover_result(_move_acc)
		_move_acc = 0.0
	# Muscles and animation.
	_muscle_acc += phys_dt
	if _muscle_acc >= (0.1 if tier == 0 else 0.5):
		_update_muscles(_muscle_acc)
		_muscle_acc = 0.0
	_anim_acc += phys_dt
	if animator != null and (tier == 0 or _frame % 4 == 0):
		animator.update(_anim_acc, self)
		_anim_acc = 0.0
		_apply_transform()
	elif animator == null:
		_anim_acc = 0.0
	# Biology.
	if _bio_acc >= BIO_STEP[tier]:
		_bio_update(_bio_acc)
		_bio_acc = 0.0
	_save_timer += phys_dt
	if _save_timer > STATE_SAVE_EVERY:
		_save_timer = 0.0
		write_state()


func _think(dt: float, possessed: bool) -> void:
	perception.update(now)
	var hungry := brain.needs.hunger > 0.2
	var thirsty := brain.needs.thirst > 0.2
	perception.scan_static(now, dt, hungry, thirsty)
	alert = lerpf(alert, clampf(perception.threat_level * 2.5, 0.0, 1.0), 0.6)
	_update_group_push()
	if possessed:
		brain.needs.update(self, dt)
		return
	brain.think(dt)
	if brain.current != null and brain.current.label != _last_label:
		_last_label = brain.current.label
		action_changed.emit(self, _last_label)
	# Idle scanning: animals look around.
	head_yaw = sin(now * 0.7 + float(individual.id)) * 0.5 * (1.0 if mover.speed < 0.3 else 0.2) * clampf(1.0 - alert, 0.2, 1.0)


func _condition() -> float:
	var c := bio.speed_factor(individual)
	var f := _force_for(mover.medium)
	return clampf(c * lerpf(1.0, f, 0.8), 0.05, 1.0)


## 0..1 stamina of the muscles that move the body in the current medium.
func stamina() -> float:
	var cat := _cat_legs if mover.medium == &"land" else (_cat_swim if mover.medium == &"water" else _cat_wing)
	if cat.is_empty():
		return 1.0 - muscles.mean_fatigue()
	var acc := 0.0
	var wsum := 0.0
	for i in cat:
		acc += muscles.fatigue[i] * muscles.groups[i].mass
		wsum += muscles.groups[i].mass
	return 1.0 - acc / maxf(wsum, 1e-6)


func _force_for(medium: StringName) -> float:
	var cat := _cat_legs if medium == &"land" else (_cat_swim if medium == &"water" else _cat_wing)
	if cat.is_empty():
		cat = _cat_axial
	if cat.is_empty():
		return 1.0
	var acc := 0.0
	for i in cat:
		acc += 1.0 - 0.75 * muscles.fatigue[i]
	return clampf(acc / float(cat.size()), 0.05, 1.0)


func _update_muscles(dt: float) -> void:
	var e := clampf(mover.effort, 0.0, 1.2)
	var drive := clampf(0.1 + 0.9 * pow(e, 1.25), 0.0, 1.0)
	if intent.sprint and mover.speed > 0.5:
		drive = clampf(drive * 1.15, 0.0, 1.0)
	var legs := 0.05
	var swim := 0.04
	var wing := 0.0
	var axial := 0.1 + 0.3 * e
	match mover.medium:
		&"land":
			legs = drive
		&"water":
			swim = drive
			legs = 0.1 * drive
			axial = 0.15 + 0.7 * e
		_:
			wing = drive
			axial = 0.3 + 0.4 * e
			legs = 0.0
	if sleeping:
		legs = 0.0
		swim = 0.0
		wing = 0.0
		axial = 0.02
	for i in _cat_legs:
		muscles.activation[i] = legs
	for i in _cat_swim:
		muscles.activation[i] = swim
	for i in _cat_wing:
		muscles.activation[i] = wing
	for i in _cat_axial:
		muscles.activation[i] = axial
	muscles.set_oxygen_factor(1.0 - 0.5 * individual.fatigue)
	muscles.update(dt * MUSCLE_TIME_SCALE)


func _apply_mover_result(dt: float) -> void:
	position = mover.pos
	individual.position = mover.pos
	individual.heading = mover.heading
	ctx.agents.move(self, position)
	if mover.last_impact > 0.0:
		var impact := mover.last_impact
		mover.last_impact = 0.0
		var dmg := clampf((impact - 6.0) * 0.04, 0.0, 0.6)
		if dmg > 0.0:
			receive_damage(dmg, &"fall", null)
	if dt > 0.0:
		_apply_transform()


func _apply_transform() -> void:
	body_scale = phenotype.anatomy.size_scale * individual.growth
	var b := mover.body_basis()
	if animator != null:
		b = b * animator.body_basis_offset
	transform = Transform3D(b.scaled(Vector3.ONE * body_scale), mover.pos)


func _update_group_push() -> void:
	# Soft separation from close neighbours (set on the mover, applied every frame).
	var m := mover
	var r := m.radius + 0.1
	var near := ctx.agents.query(m.pos, r * 3.0, self, 8)
	var push := Vector3.ZERO
	for o in near:
		var oa := o as CreatureAgent
		if oa == null or oa.is_egg() or not oa.is_alive():
			continue
		var d := m.pos - oa.position
		d.y = 0.0
		var dist := d.length()
		var min_d := r + oa.mover.radius
		if dist < min_d and dist > 1e-3:
			push += d / dist * (min_d - dist) * 2.0
	m.push = push.limit_length(3.0)


# --- Biology -----------------------------------------------------------------------------------

func _bio_update(bio_dt: float) -> void:
	var mid := mover.pos + Vector3.UP * mover.height * 0.5
	var env := ctx.env_at(mid)
	var wet := mover.submerged > 0.5 or mover.medium == &"water" and mover.water_depth > 0.05
	env["in_water"] = wet
	env["air_access"] = not mover.head_underwater
	env["move_power"] = mover.move_power
	env["density"] = clampf(float(perception.neighbours) * 0.5, 0.2, 6.0) if perception != null else 1.0
	if ctx.climate != null:
		env["wind"] = ctx.climate.wind.length()
	if brain != null and brain.current != null and (brain.current.id == &"drink") and (mover.water_depth > 0.05 or water_in_reach()):
		env["water_nearby"] = true
	var act := 0.1
	if brain != null:
		act = brain.activity_level()
	if controller != null:
		act = clampf(0.15 + 0.85 * pow(mover.effort, 1.3), 0.05, 1.0)
	elif mover.effort > 0.05:
		act = maxf(act * 0.5, 0.1 + 0.9 * pow(mover.effort, 1.4))
	if sleeping:
		act = 0.0
	var events := bio.tick(individual, env, bio_dt, act)
	_handle_events(events)


func _handle_events(events: Array[Dictionary]) -> void:
	for e in events:
		match e["type"]:
			&"died":
				_die(e["cause"])
				return
			&"gave_birth":
				_spawn_offspring(e["offspring"])
			&"laid_eggs":
				_spawn_offspring(e["eggs"])
			&"matured":
				ctx.log_event(&"life", "Достиг зрелости: %s" % species_name(), {"id": individual.id})
			_:
				pass


func _spawn_offspring(kids: Array) -> void:
	for k in kids:
		var kid: Individual = k
		kid.position = AgentNav.offspring_position(self, kid)
		kid.heading = rng.range_f(-PI, PI)
		if ctx.spawn_individual.is_valid():
			ctx.spawn_individual.call(kid)
	if not kids.is_empty():
		ctx.log_event(&"birth", "Потомство (%d): %s" % [kids.size(), species_name()], {"mother": individual.id})


func _die(cause: StringName) -> void:
	if _dead:
		return
	_dead = true
	individual.alive = false
	individual.cause = cause
	ctx.agents.remove(self)
	if brain != null:
		brain.stop_all()
	if controller != null and is_instance_valid(controller) and controller.has_method("on_agent_died"):
		controller.call("on_agent_died", cause)
	died.emit(self, cause)
	if ctx.agent_died.is_valid():
		ctx.agent_died.call(self, cause)


## Damage from a fight, fall or accident (fraction of max health).
func receive_damage(amount: float, cause: StringName, attacker: CreatureAgent) -> void:
	if _dead or not individual.alive or amount <= 0.0:
		return
	if attacker != null:
		last_attacker = attacker
		last_attacked_t = now
	if _egg_mode:
		bio.kill(individual, cause)
		_die(cause)
		return
	var events := bio.damage(individual, amount, cause)
	damage_flash = 1.0
	if visual != null:
		visual.set_condition(0.0, clampf(1.0 - individual.health, 0.0, 1.0), individual.fatigue)
	if attacker != null and mover != null:
		var away := mover.pos - attacker.mover.pos
		away.y = 0.0
		if away.length_squared() > 1e-4:
			mover.apply_impulse(away.normalized() * clampf(amount * 6.0, 0.0, 3.0))
	if brain != null:
		brain.needs.fear = maxf(brain.needs.fear, clampf(0.35 + amount * 2.0, 0.0, 1.0))
	_handle_events(events)


## Attacks `target` if close enough and off cooldown. Returns {hit, damage, killed}.
func attack(target: CreatureAgent, scale: float = 1.0) -> Dictionary:
	var res := {"hit": false, "damage": 0.0, "killed": false}
	if target == null or not is_instance_valid(target) or not target.is_alive() or _attack_cd > 0.0:
		return res
	var reach := mover.length * 0.55 + target.mover.radius + 0.5
	if mover.pos.distance_to(target.position) > reach + mover.radius:
		return res
	_attack_cd = 0.8 + 0.5 * pow(maxf(individual.mass(), 0.01), 0.15)
	attack_time = 0.45
	var roll := rng.randf()
	var hit_p := 1.0
	if not target.is_egg():
		hit_p = Relations.hit_chance(phenotype.locomotion.agility, target.phenotype.locomotion.agility,
			clampf(target.mover.speed / maxf(target.mover.max_speed(target.mover.medium), 0.1), 0.0, 1.0), target.sleeping)
	var fatigue_cost := 0.012
	for i in _cat_legs:
		muscles.fatigue[i] = minf(1.0, muscles.fatigue[i] + fatigue_cost)
	if roll > hit_p:
		return res
	var dmg := 1.0 if target.is_egg() else Relations.attack_damage(phys, phenotype.anatomy.stats, individual.mass(),
		target.phys, target.individual.mass(), rng.randf())
	dmg *= scale
	var cause: StringName = &"predation" if (Relations.eats_meat(phys) and scale >= 1.0 and target.individual.species_id != individual.species_id) else &"fight"
	var tmass := target.individual.mass()
	target.receive_damage(dmg, cause, self)
	res["hit"] = true
	res["damage"] = dmg
	res["killed"] = not target.is_alive()
	if res["killed"] and (target.is_egg() or ctx.eco == null) and Relations.eats_meat(phys):
		Feeding.eat_body(self, tmass)
	return res


func on_courted(by: CreatureAgent) -> void:
	courted_by = by.individual.id
	courted_t = now


func on_dominated(by: CreatureAgent, lost: bool) -> void:
	last_attacker = by
	last_attacked_t = now
	if lost and brain != null:
		brain.needs.fear = maxf(brain.needs.fear, 0.5)


## Calls: kind = alarm | mating_call | sound. Strength scales the audible range.
func emit_call(kind: StringName, strength: float = 1.0) -> void:
	call_time = 0.8
	ctx.emit_stimulus(mover.pos + Vector3.UP * mover.height, kind, strength * clampf(pow(maxf(individual.mass(), 0.05), 0.12), 0.6, 1.8), self)


func request_perception() -> void:
	_ai_timer = 0.0


# --- Eggs ---------------------------------------------------------------------------------------

func _egg_update(phys_dt: float, bio_dt: float) -> void:
	_bio_acc += bio_dt
	if _bio_acc < EGG_STEP:
		return
	var env := ctx.env_at(mover.pos + Vector3.UP * 0.05)
	var events := bio.tick(individual, env, _bio_acc, 0.0)
	_bio_acc = 0.0
	_handle_events(events)
	if not _dead and not individual.is_egg():
		_hatch()


func _hatch() -> void:
	_egg_mode = false
	if egg_mesh != null:
		egg_mesh.queue_free()
		egg_mesh = null
	mover.set_growth(individual.growth)
	_combat_power = Relations.combat_power(phys, phenotype.anatomy.stats, individual.mass())
	_build_creature()
	_apply_transform()
	ctx.log_event(&"birth", "Вылупился: %s" % species_name(), {"id": individual.id})


# --- Animation / selection hooks ----------------------------------------------------------------------

## Posture name for the animator: sleep, attack, call, eat, drink, stalk, flee ...
func current_pose() -> StringName:
	if sleeping:
		return &"sleep"
	if attack_time > 0.0:
		return &"attack"
	if call_time > 0.0:
		return &"call"
	if controller != null:
		return player_pose
	if brain != null and brain.current != null:
		return brain.current.pose()
	return &""


## World point the creature looks at (threat, prey, goal) or Vector3.INF.
func look_point() -> Vector3:
	if perception == null:
		return Vector3.INF
	if perception.threat != null and perception.threat_level > 0.15:
		return perception.threat.pos + Vector3.UP * 0.5
	if controller == null and brain != null and brain.current is ActHunt and (brain.current as ActHunt).prey != null:
		return (brain.current as ActHunt).prey.pos
	if intent.mode == MoveIntent.Mode.SEEK and mover.speed > 0.3:
		return intent.goal + Vector3.UP * mover.height * 0.5
	return Vector3.INF


## Called by the agent manager when the player selects this creature.
func set_selected(on: bool) -> void:
	selected = on
	if headless:
		return
	if on and _ring == null:
		_ring = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.9
		tm.outer_radius = 1.0
		tm.rings = 24
		tm.ring_segments = 6
		_ring.mesh = tm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.85, 0.3, 0.9)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring.material_override = mat
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var r := maxf(mover.radius, 0.3) * 1.5 / maxf(body_scale, 1e-3)
		_ring.scale = Vector3(r, r * 0.25, r)
		_ring.position = Vector3(0, 0.03 / maxf(body_scale, 1e-3), 0)
		add_child(_ring)
	if _ring != null:
		_ring.visible = on


# --- Helpers used by the AI -------------------------------------------------------------------------

func eye_world() -> Vector3:
	if _egg_mode or phenotype == null:
		return mover.pos + Vector3.UP * 0.05
	var local := phenotype.senses.eye_point
	return mover.pos + mover.body_basis() * (local * body_scale)


func gaze_forward() -> Vector3:
	var f := mover.forward()
	return f.rotated(Vector3.UP, head_yaw) if head_yaw != 0.0 else f


func body_length() -> float:
	return mover.length


func combat_power() -> float:
	return _combat_power * (0.5 + 0.5 * individual.health)


func flight_distance() -> float:
	return lerpf(26.0, 8.0, personality.boldness) * clampf(pow(maxf(body_length(), 0.1), 0.35), 0.6, 1.5)


func noise_level() -> float:
	if _egg_mode or sleeping:
		return 0.03 if sleeping else 0.0
	var vmax := maxf(mover.max_speed(mover.medium, true), 0.1)
	var sp := clampf(mover.speed / vmax, 0.0, 1.2)
	var size_k := 0.5 + 0.5 * clampf(log(individual.mass() + 1.0) / log(300.0), 0.0, 1.4)
	var n := (0.12 + 0.88 * sp) * size_k
	if call_time > 0.0:
		n = maxf(n, 0.8)
	return n


func cruise_speed() -> float:
	match mover.medium:
		&"water":
			return mover.max_speed(&"water") * 0.55
		&"air":
			return mover.max_speed(&"air") * 0.7
	if mover.lp.can_fly and AgentNav.prefers_air(self):
		return mover.max_speed(&"air") * 0.7
	return mover.max_speed(&"land", false) * 0.75


func burst_speed() -> float:
	if mover.flying or (mover.lp.can_fly and mover.medium != &"water" and personality.boldness < 2.0 and mover.lp.fly_speed > mover.lp.best_land_speed()):
		return mover.max_speed(&"air")
	return mover.max_speed(mover.medium if mover.medium != &"air" else &"land", true)


func go(target: Vector3, speed: float, arrive: float = 0.5) -> void:
	intent.seek(target, speed, arrive)
	AgentNav.set_travel_mode(self, target)


func go_node(target: Node3D, speed: float, arrive: float = 0.5) -> void:
	intent.seek_node(target, speed, arrive)
	AgentNav.set_travel_mode(self, target.position)


func stop_moving() -> void:
	intent.stop()
	intent.fly = false
	intent.group_pull = Vector3.ZERO


func face_toward(p: Vector3) -> void:
	var d := p - mover.pos
	d.y = 0.0
	intent.face = d.normalized() if d.length_squared() > 1e-4 else Vector3.ZERO


func pick_wander_goal(radius: float) -> Vector3:
	return AgentNav.pick_wander_goal(self, radius)


func is_open_ground(p: Vector3) -> bool:
	return AgentNav.is_open_ground(self, p)


func can_reach(p: Vector3) -> bool:
	return AgentNav.can_reach(self, p)


func water_in_reach() -> bool:
	return AgentNav.water_in_reach(self)


func distance_to_water() -> float:
	return AgentNav.distance_to_water(self)


func plant_prefs(eco: EcoGrid) -> PackedFloat32Array:
	if _plant_species_n != eco.plant_species.size() or _plant_prefs.is_empty():
		_plant_prefs = Feeding.plant_prefs(self, eco)
		_plant_species_n = eco.plant_species.size()
	return _plant_prefs


func dependants() -> Array[CreatureAgent]:
	if now - _dep_timer > 1.5:
		_dep_timer = now
		_dependants.clear()
		for o in ctx.agents.query(mover.pos, 30.0, self, 24):
			var oa := o as CreatureAgent
			if oa == null or not oa.is_alive():
				continue
			var oi := oa.individual
			if (oi.mother_id == individual.id or oi.father_id == individual.id) and (oi.is_egg() or oi.growth < 0.6):
				_dependants.append(oa)
	return _dependants


func has_dependants() -> bool:
	return not dependants().is_empty()


func species_name() -> String:
	var reg := ctx.registry as SpeciesRegistry
	if reg != null:
		var sd := reg.get_species(individual.species_id)
		if sd != null:
			return str(sd.name)
	return "Существо"


# --- Status for the HUD -------------------------------------------------------------------------------

func get_status() -> Dictionary:
	var needs: Dictionary = brain.needs.to_dict() if brain != null else {"hunger": 0.0, "thirst": 0.0, "fatigue": 0.0, "fear": 0.0,
		"temperature_discomfort": 0.0, "mate": 0.0, "social": 0.0}
	var action := "Яйцо" if _egg_mode else (player_pose_text() if controller != null else (brain.action_label() if brain != null else ""))
	var ind := individual
	return {
		"action": tr(action), "needs": needs, "energy_frac": ind.energy_fraction(), "health": ind.health,
		"hydration": ind.hydration, "body_temp": ind.body_temp, "age_days": ind.age / Units.SECONDS_PER_DAY,
		"stage": ind.stage, "sex": ind.sex, "generation": ind.generation, "species_id": ind.species_id,
		"medium": mover.medium if mover != null else &"land", "speed": mover.speed if mover != null else 0.0,
		"target_desc": tr(brain.target_text()) if brain != null and controller == null else "",
		"fatigue": ind.fatigue, "stamina": stamina(), "mass": ind.mass(), "name": species_name(),
	}


func player_pose_text() -> String:
	match player_pose:
		&"eat":
			return "Ест"
		&"drink":
			return "Пьёт"
		&"attack":
			return "Атакует"
		&"rest":
			return "Отдыхает"
		&"call":
			return "Зовёт"
	return "Под управлением"


# --- Persistence ---------------------------------------------------------------------------------------------

## Stores AI/muscle state in Individual.tags so Individual.to_dict() carries it.
func write_state() -> void:
	if individual == null:
		return
	individual.tags["ai"] = {
		"memory": memory.to_dict(), "muscle": muscles.to_dict() if muscles != null else {},
		"fear": brain.needs.fear if brain != null else 0.0, "clock": now,
	}
	if mover != null:
		individual.position = mover.pos
		individual.heading = mover.heading


func _restore_state() -> void:
	var st: Variant = individual.tags.get("ai")
	if not (st is Dictionary):
		return
	memory.from_dict(Serial.dict(st, "memory"))
	muscles.from_dict(Serial.dict(st, "muscle"))
	now = Serial.f(st, "clock", 0.0)
	if brain != null:
		brain.needs.fear = clampf(Serial.f(st, "fear", 0.0), 0.0, 1.0)
