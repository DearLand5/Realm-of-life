class_name CreatureRig
extends RefCounted
## Per-model bone analysis used by every mesh builder (pure data):
##  - along: arc length (m) at each bone start, continuous across part
##    junctions (a leg starts at the torso's arc length at its attach point),
##  - part position: offset/total length of each bone inside its part chain,
##  - related: bones within graph distance 2 (skin weights may only mix
##    bones that move together, preventing "sticky" vertices between e.g. a
##    leg and the belly),
##  - char_size: body diameter of the root part, the unit of pattern space.

var model: AnatomyModel
var along_start := PackedFloat32Array()
var part_offset := PackedFloat32Array()
var part_total := PackedFloat32Array()
var related: Array[PackedInt32Array] = []
var char_size: float = 0.1


func _init(m: AnatomyModel) -> void:
	model = m
	var n := m.bones.size()
	along_start.resize(n)
	part_offset.resize(n)
	part_total.resize(n)
	var inst_len := {}
	for b in m.bones:
		if b.index == 0 or b.parent < 0:
			continue
		var par := m.bones[b.parent]
		if par.instance == b.instance and par.index != 0:
			along_start[b.index] = along_start[par.index] + par.length
			part_offset[b.index] = part_offset[par.index] + par.length
		elif par.index == 0 or par.part_id < 0:
			along_start[b.index] = 0.0
			part_offset[b.index] = 0.0
		else:
			var t := MathUtil.point_segment_t(b.start, par.start, par.end)
			along_start[b.index] = along_start[par.index] + t * par.length
			part_offset[b.index] = 0.0
		inst_len[b.instance] = float(inst_len.get(b.instance, 0.0)) + b.length
	for b in m.bones:
		part_total[b.index] = maxf(float(inst_len.get(b.instance, b.length)), 1e-6)
	_build_related()
	char_size = _char_size()


func _build_related() -> void:
	var m := model
	var n := m.bones.size()
	var adj: Array[PackedInt32Array] = []
	adj.resize(n)
	for i in n:
		adj[i] = PackedInt32Array()
	for b in m.bones:
		if b.parent >= 0 and b.parent < n:
			var a := adj[b.index]
			a.append(b.parent)
			adj[b.index] = a
			var c := adj[b.parent]
			c.append(b.index)
			adj[b.parent] = c
	related.resize(n)
	for i in n:
		var r := PackedInt32Array([i])
		for j in adj[i]:
			if not r.has(j):
				r.append(j)
			for k in adj[j]:
				if not r.has(k):
					r.append(k)
		related[i] = r


func _char_size() -> float:
	var m := model
	var sum := 0.0
	var cnt := 0
	for b in m.bones:
		if b.instance == 0 and b.part_id >= 0:
			sum += (b.r0 + b.r1) * 0.5 * (1.0 + minf(b.flatten, 2.0)) * 0.5
			cnt += 1
	if cnt == 0:
		var ext := m.aabb.size
		return maxf(maxf(ext.x, maxf(ext.y, ext.z)) * 0.25, 1e-3)
	return maxf(sum / float(cnt) * 2.0, 1e-3)


func is_related(a: int, b: int) -> bool:
	if a < 0 or a >= related.size():
		return false
	return related[a].has(b)


## Along-body arc length of point p measured on bone bi.
func along_on_bone(bi: int, p: Vector3) -> float:
	var b := model.bones[bi]
	return along_start[bi] + MathUtil.point_segment_t(p, b.start, b.end) * b.length


## Normalised position of p along the part chain of bone bi (0 root .. 1 tip).
func part_t_on_bone(bi: int, p: Vector3) -> float:
	var b := model.bones[bi]
	return clampf((part_offset[bi] + MathUtil.point_segment_t(p, b.start, b.end) * b.length) / part_total[bi], 0.0, 1.0)


## Bones of the chain (instance) that contains bone bi, root first.
func chain_of(bi: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if bi <= 0 or bi >= model.bones.size():
		return out
	var inst := model.bones[bi].instance
	for b in model.bones:
		if b.instance == inst and b.part_id >= 0:
			out.append(b.index)
	return out


## Bone weights for a point at chain parameter `s` (0..n bones, continuous),
## blending neighbours over `blend` (fraction of a segment) around joints.
## Returns [bones: PackedInt32Array(4), weights: Vector4].
static func chain_weights(chain: PackedInt32Array, s: float, blend: float = 0.3, parent_bone: int = -1, parent_w: float = 0.0) -> Array:
	var bi := PackedInt32Array([0, 0, 0, 0])
	var w := Vector4.ZERO
	var n := chain.size()
	if n == 0:
		if parent_bone >= 0:
			bi[0] = parent_bone
			w.x = 1.0
		return [bi, w]
	var sc := clampf(s, 0.0, float(n) - 1e-4)
	var k := int(floorf(sc))
	var u := sc - float(k)
	var main := chain[k]
	var other := -1
	var ow := 0.0
	if u < blend and k > 0:
		other = chain[k - 1]
		ow = 0.5 * (1.0 - u / blend)
	elif u > 1.0 - blend and k < n - 1:
		other = chain[k + 1]
		ow = 0.5 * (1.0 - (1.0 - u) / blend)
	ow = ow * ow * (3.0 - 2.0 * ow) if ow > 0.0 else 0.0
	var pw := clampf(parent_w, 0.0, 1.0)
	var mw := (1.0 - ow) * (1.0 - pw)
	bi[0] = main
	w.x = mw
	var slot := 1
	if other >= 0 and ow > 0.0:
		bi[slot] = other
		w[slot] = ow * (1.0 - pw)
		slot += 1
	if parent_bone >= 0 and pw > 0.0:
		bi[slot] = parent_bone
		w[slot] = pw
	return [bi, w]
