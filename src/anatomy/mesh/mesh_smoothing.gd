class_name MeshSmoothing
extends RefCounted
## Taubin (λ|μ) smoothing on indexed triangle meshes: relaxes the vertex
## distribution of Surface Nets meshes without shrinking them. Callers project
## the vertices back onto the iso-surface afterwards.

const LAMBDA := 0.5
const MU := -0.53


static func taubin(pos: PackedVector3Array, idx: PackedInt32Array, passes: int) -> void:
	var n := pos.size()
	if n == 0 or idx.size() < 3:
		return
	var cnt := PackedFloat32Array()
	cnt.resize(n)
	for t in range(0, idx.size(), 3):
		cnt[idx[t]] += 2.0
		cnt[idx[t + 1]] += 2.0
		cnt[idx[t + 2]] += 2.0
	for _p in passes:
		_step(pos, idx, cnt, LAMBDA)
		_step(pos, idx, cnt, MU)


static func _step(pos: PackedVector3Array, idx: PackedInt32Array, cnt: PackedFloat32Array, factor: float) -> void:
	var n := pos.size()
	var acc := PackedVector3Array()
	acc.resize(n)
	for t in range(0, idx.size(), 3):
		var a := idx[t]
		var b := idx[t + 1]
		var c := idx[t + 2]
		var pa := pos[a]
		var pb := pos[b]
		var pc := pos[c]
		acc[a] += pb + pc
		acc[b] += pa + pc
		acc[c] += pa + pb
	for k in n:
		var cn := cnt[k]
		if cn > 0.0:
			pos[k] += (acc[k] / cn - pos[k]) * factor
