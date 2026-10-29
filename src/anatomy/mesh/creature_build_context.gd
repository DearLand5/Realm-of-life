class_name CreatureBuildContext
extends RefCounted
## Shared state while building one creature mesh set: the model and its rig,
## the SDF field/grid of the body at this LOD, and one MeshBuffer per material
## kind. Accessory builders add geometry through `buffer(kind)` and use
## `snap()` to place decorations (lip lines, gill slits, pores) exactly on
## the polygonized body surface.

## Material kinds (CreatureMeshSet accessory entries, CreatureMaterials).
const KIND_BODY := &"body"
const KIND_HARD := &"hard"
const KIND_EYE := &"eye"
const KIND_MEMBRANE := &"membrane"
const KIND_FEATHER := &"feather"
const KIND_GLOW := &"glow"
const KIND_ORGANELLE := &"organelle"
const KIND_ORGAN := &"organ"
const KINDS: Array[StringName] = [KIND_BODY, KIND_HARD, KIND_EYE, KIND_MEMBRANE, KIND_FEATHER, KIND_GLOW, KIND_ORGANELLE, KIND_ORGAN]

var model: AnatomyModel
var rig: CreatureRig
var field: SdfField
var grid: SdfGrid
var lod: int = 0
var detail: int = 2
var cell: float = 0.01
var buffers := {}
var warnings: Array[String] = []
var _tmp := PackedVector3Array()


func _init(m: AnatomyModel, r: CreatureRig, level: int) -> void:
	model = m
	rig = r
	lod = MeshLod.clamp_lod(level)
	detail = MeshLod.detail(lod)
	for k in KINDS:
		buffers[k] = MeshBuffer.new()


func buffer(kind: StringName) -> MeshBuffer:
	if not buffers.has(kind):
		buffers[kind] = MeshBuffer.new()
	return buffers[kind]


func has_surface() -> bool:
	return field != null and not field.is_empty() and grid != null


## Signed distance to the body (FAR if the point is outside every brick).
func distance(p: Vector3) -> float:
	if not has_surface():
		return SdfField.FAR
	return field.value(p, grid.cand_at(p))


## Projects p onto the body surface offset by `offset` (outwards > 0).
## Returns [position, normal, ok]; ok = false when no surface is near
## (the input point and `fallback_n` are returned).
func snap(p: Vector3, offset: float = 0.0, fallback_n: Vector3 = Vector3.UP, max_dist: float = -1.0) -> Array:
	if not has_surface():
		return [p, fallback_n, false]
	var cand := grid.cand_at(p)
	if cand.is_empty():
		return [p, fallback_n, false]
	var n := field.project(p, cand, 4, cell * 2.0 + absf(offset) + 1e-6, _tmp, offset)
	var q := _tmp[0]
	if max_dist > 0.0 and q.distance_to(p) > max_dist:
		return [p, fallback_n, false]
	if not q.is_finite():
		return [p, fallback_n, false]
	return [q, n, true]


## Rest-space radius of bone bi at point p (lerp of r0/r1 by projection).
func bone_radius_at(bi: int, p: Vector3) -> float:
	if bi <= 0 or bi >= model.bones.size():
		return 0.05
	var b := model.bones[bi]
	return lerpf(b.r0, b.r1, MathUtil.point_segment_t(p, b.start, b.end))


## Covering slot index for an accessory (clamped to the expressed slots).
func slot(i: int) -> int:
	return clampi(i, 0, maxi(0, mini(model.coverings.size(), 4) - 1))


func covering_type(slot_index: int) -> StringName:
	if model.coverings.is_empty():
		return &"skin"
	return model.coverings[clampi(slot_index, 0, model.coverings.size() - 1)].type


## First slot with the given covering type, or -1.
func find_slot(type: StringName) -> int:
	for i in mini(model.coverings.size(), 4):
		if model.coverings[i].type == type:
			return i
	return -1


func bone_or_root(bi: int) -> int:
	return bi if bi >= 0 and bi < model.bones.size() else 0
