class_name AnimRig
extends RefCounted
## Static analysis of an AnatomyModel/Skeleton3D for animation: which bones form
## legs (IK chains to the support tips), wings, fins, tails, the neck/head, the
## axial spine, tentacles and flagella; plus rest data and helpers to rotate a
## bone about a geometry-space axis.

class Leg:
	var bones := PackedInt32Array()          # root -> tip
	var parent: int = 0                      # bone the chain hangs from
	var side: int = 1
	var rank: float = 0.0                    # 0 front .. 1 rear
	var rest_pts := PackedVector3Array()     # joint positions at rest (skeleton space), N+1
	var seg_local := PackedVector3Array()    # segment direction in each bone's own rest frame
	var lens := PackedFloat32Array()
	var reach: float = 0.1
	var home := Vector3.ZERO                 # rest tip position
	var foot_dir := Vector3.DOWN             # rest direction of the last bone
	# Gait state.
	var planted := true
	var plant := Vector3.ZERO                # world position of the tip while planted
	var swing_from := Vector3.ZERO
	var swing_to := Vector3.ZERO
	var swing_t: float = 1.0
	var swing_dur: float = 0.3
	var offset: float = 0.0
	var offset_target: float = 0.0
	var prev_phase: float = 0.0
	var pts := PackedVector3Array()          # IK scratch: joint positions, N+1
	var sub_pts := PackedVector3Array()      # IK scratch for the chain without the foot bone
	var sub_lens := PackedFloat32Array()
	var initialised := false

class Chain:
	var bones := PackedInt32Array()
	var side: int = 0
	var phase: float = 0.0
	var dir := Vector3.ZERO                  # rest direction start -> end of the chain
	var s: float = 0.0                       # position along the body 0 front .. 1 rear
	var spring := PackedFloat32Array()       # secondary-motion state (angle, velocity per bone x2)

var model: AnatomyModel
var sk: Skeleton3D
var legs: Array[Leg] = []
var wings: Array[Chain] = []
var fins: Array[Chain] = []
var tails: Array[Chain] = []
var tentacles: Array[Chain] = []
var flagella: Array[Chain] = []
var antennae: Array[Chain] = []
var paddles: Array[Chain] = []           # swimming limbs that are not support legs
var head_chain := PackedInt32Array()     # neck + head bones, root -> head
var axial := PackedInt32Array()          # torso bones ordered front -> rear
var axial_s := PackedFloat32Array()      # body position of each axial bone
var rest_q: Array[Quaternion] = []       # local rest rotation per bone
var inv_rest_global: Array[Basis] = []   # inverse of the global rest basis per bone
var rest_global: Array[Transform3D] = []
var leg_height: float = 0.5              # mean hip height above the foot rest (geometry)
var body_length: float = 1.0
var hip_height: float = 0.5
var animated := PackedByteArray()        # 1 for bones the animator writes


func build(m: AnatomyModel, skeleton: Skeleton3D, head_bone: int) -> void:
	model = m
	sk = skeleton
	var n := m.bones.size()
	rest_q.clear()
	inv_rest_global.clear()
	rest_global.clear()
	animated.resize(n)
	animated.fill(0)
	for i in n:
		rest_q.append(sk.get_bone_rest(i).basis.get_rotation_quaternion())
		var g := SkeletonBuilder.global_rest(m, i)
		rest_global.append(g)
		inv_rest_global.append(g.basis.inverse())
	body_length = maxf(m.aabb.size.z, 0.05)
	var tips := PackedInt32Array()
	var st_tips: Variant = m.stats.get("support_tips")
	if st_tips is PackedInt32Array:
		tips = st_tips
	elif st_tips is Array:
		for t in st_tips:
			tips.append(int(t))
	var leg_inst := {}
	for t in tips:
		if t > 0 and t < n:
			_add_leg(t)
			leg_inst[m.bones[t].instance] = true
	_rank_legs()
	for inst_i in m.instances.size():
		var inst := m.instances[inst_i]
		if inst.bones.is_empty() or leg_inst.has(inst_i):
			continue
		var c := Chain.new()
		c.bones = inst.bones
		c.side = inst.side
		c.phase = float(inst_i) * 0.37
		var b0 := m.bones[inst.bones[0]]
		var bl := m.bones[inst.bones[inst.bones.size() - 1]]
		c.dir = (bl.end - b0.start).normalized() if (bl.end - b0.start).length_squared() > 1e-8 else Vector3.UP
		c.s = clampf((b0.mid().z - m.aabb.position.z) / maxf(m.aabb.size.z, 0.01), 0.0, 1.0)
		c.spring.resize(inst.bones.size() * 2)
		match inst.kind:
			&"wing":
				wings.append(c)
			&"fin":
				fins.append(c)
			&"tail":
				tails.append(c)
			&"tentacle":
				tentacles.append(c)
			&"flagellum":
				flagella.append(c)
			&"antenna":
				antennae.append(c)
			&"limb":
				paddles.append(c)
	_build_axial(head_bone)
	for c in wings + fins + tails + tentacles + flagella + antennae + paddles:
		for b in c.bones:
			animated[b] = 1
	for b in head_chain:
		animated[b] = 1
	for b in axial:
		animated[b] = 1
	for l in legs:
		for b in l.bones:
			animated[b] = 1
	animated[0] = 1


func _add_leg(tip: int) -> void:
	var chain := model.chain_to(tip)
	if chain.size() < 1:
		return
	var l := Leg.new()
	l.bones = chain
	l.parent = model.bones[chain[0]].parent
	l.side = model.bones[chain[0]].side
	if l.side == 0:
		l.side = 1 if model.bones[tip].end.x >= 0.0 else -1
	for i in chain.size():
		var b := model.bones[chain[i]]
		l.rest_pts.append(b.start)
		l.lens.append(maxf((b.end - b.start).length(), 1e-4))
		l.seg_local.append((inv_rest_global[chain[i]] * (b.end - b.start)).normalized())
	var last := model.bones[chain[chain.size() - 1]]
	l.rest_pts.append(last.end)
	l.home = last.end
	l.foot_dir = (last.end - last.start).normalized()
	l.reach = 0.0
	for x in l.lens:
		l.reach += x
	l.pts = l.rest_pts.duplicate()
	for i in range(chain.size()):
		l.sub_pts.append(Vector3.ZERO)
	for i in range(chain.size() - 1):
		l.sub_lens.append(l.lens[i])
	legs.append(l)


func _rank_legs() -> void:
	if legs.is_empty():
		return
	var zmin := INF
	var zmax := -INF
	var h := 0.0
	for l in legs:
		zmin = minf(zmin, l.home.z)
		zmax = maxf(zmax, l.home.z)
		h += model.bones[l.bones[0]].start.y - l.home.y
	for l in legs:
		l.rank = (l.home.z - zmin) / maxf(zmax - zmin, 1e-4) if zmax - zmin > 1e-4 else 0.5
	leg_height = h / float(legs.size())
	hip_height = leg_height


func _build_axial(head_bone: int) -> void:
	head_chain = PackedInt32Array()
	var cur := head_bone
	while cur > 0 and (model.bones[cur].kind == &"head" or model.bones[cur].kind == &"neck"):
		head_chain.insert(0, cur)
		cur = model.bones[cur].parent
	var items: Array = []
	for b in model.bones:
		if b.part_id < 0:
			continue
		if b.kind == &"torso" or b.kind == &"cell":
			items.append([b.index, b.mid().z])
	items.sort_custom(func(x: Array, y: Array) -> bool: return float(x[1]) < float(y[1]))
	axial = PackedInt32Array()
	axial_s = PackedFloat32Array()
	for it in items:
		axial.append(int(it[0]))
		axial_s.append(clampf((float(it[1]) - model.aabb.position.z) / maxf(model.aabb.size.z, 0.01), 0.0, 1.0))


# --- Bone pose helpers ---------------------------------------------------------------------------

## Bone-local axis for a geometry-space axis.
func local_axis(bone: int, axis: Vector3) -> Vector3:
	return (inv_rest_global[bone] * axis).normalized()


## Accumulates a rotation of `angle` about geometry `axis` into `deltas[bone]`.
func rotate(deltas: Array[Quaternion], bone: int, axis: Vector3, angle: float) -> void:
	if absf(angle) < 1e-5:
		return
	deltas[bone] = deltas[bone] * Quaternion(local_axis(bone, axis), angle)


## Global (skeleton-space) transform of a bone from the CURRENT local poses.
## Computed here because Skeleton3D's cached global poses are not reliable for
## skeletons outside the scene tree (tests) when poses change several times a frame.
func fk(bone: int) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur := bone
	while cur >= 0:
		var local := Transform3D(Basis(sk.get_bone_pose_rotation(cur)), sk.get_bone_pose_position(cur))
		xf = local * xf
		cur = sk.get_bone_parent(cur)
	return xf
