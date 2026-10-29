class_name AnatomyModel
extends RefCounted
## Output of AnatomyCompiler: the developed (phenotypic) anatomy of one genome.
## Pure data, no nodes. Consumed by:
##   ProceduralAnatomy (mesh), SkeletonSystem (Skeleton3D), MuscleSystem,
##   CreaturePhysics (LocomotionProfile), BiologySystem (PhysiologyProfile),
##   AI (SenseProfile), CreatureEditor (picking, diagnostics).
##
## GEOMETRY SPACE: all positions are in creature-local space at size_scale = 1
## (the body plan's own dimensions with proportion traits applied), +Y up,
## creature faces -Z, the lowest ground contact touches y = 0.
## Real-world dimensions = geometry × size_scale (applied as node scale).
## `stats` are already in REAL units (kg, m, m², m³).


class Bone:
	var index: int = 0
	var name: String = ""
	var parent: int = -1         # bone index, -1 for the root bone
	var part_id: int = -1        # source BodyPart id (-1 for the root bone)
	var instance: int = -1       # index into AnatomyModel.instances
	var segment: int = -1        # segment index in the part chain
	var kind: StringName = &"root"
	var function: StringName = &"none"
	var start := Vector3.ZERO
	var end := Vector3.ZERO
	var basis := Basis.IDENTITY  # rest orientation; +Y along the bone
	var length: float = 0.0
	var r0: float = 0.0          # radius at start
	var r1: float = 0.0          # radius at end
	var flatten: float = 1.0
	var swing_limit: float = 40.0
	var twist_limit: float = 15.0
	var stiffness: float = 0.5
	var soft: float = 0.0
	var side: int = 0            # -1 left, 0 midline, +1 right
	var mass: float = 0.0        # kg, real units (tissue of this segment)
	var muscle_mass: float = 0.0 # kg, real units
	var fast_twitch: float = 0.5
	var covering: int = 0
	var depth: int = 0           # segment index within the chain
	var is_tip: bool = false     # last segment of its chain
	var thin: bool = false       # rendered as a tube, not part of the SDF body

	func mid() -> Vector3:
		return (start + end) * 0.5

	func rest_transform() -> Transform3D:
		return Transform3D(basis, start)


class Primitive:
	var bone: int = 0
	var kind: int = 0            # 0 = round cone a->b, 1 = ellipsoid (centre a, radii in `radii`)
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var ra: float = 0.1
	var rb: float = 0.1
	var radii := Vector3.ONE     # ellipsoid radii in the primitive frame
	var basis := Basis.IDENTITY  # frame: X width, Y along, Z height
	var inv_basis := Basis.IDENTITY
	var flatten: float = 1.0
	var blend: float = 0.05      # smooth-union radius (m)
	var covering: int = 0
	var aabb := AABB()


class Accessory:
	## type: eye, ear, nose, mouth, horn, spike, claw, whisker, gill, sensor,
	##       gland, light, organ (internal), membrane (wing/fin), fluke, tube
	##       (thin spine part rendered as a skinned tube), cell_organelle
	var type: StringName = &""
	var bone: int = 0
	var part_id: int = -1
	var instance: int = -1
	var transform := Transform3D.IDENTITY  # geometry space; basis Y = outward/along
	var size: float = 0.05                 # characteristic size, m (geometry space)
	var side: int = 0
	var covering: int = 0
	var params: Dictionary = {}            # part params + derived data (see compiler)


class Instance:
	var part_id: int = -1
	var kind: StringName = &""
	var parent_instance: int = -1
	var mirrored: bool = false
	var radial_index: int = 0
	var repeat_index: int = 0
	var side: int = 0
	var bones := PackedInt32Array()
	var accessories := PackedInt32Array()
	var anchor := Vector3.ZERO   # attach point (geometry space) for picking


var bones: Array[Bone] = []
var primitives: Array[Primitive] = []
var accessories: Array[Accessory] = []
var instances: Array[Instance] = []
var coverings: Array[CoveringDef] = []   # expressed (genome-modulated) coverings
var size_scale: float = 1.0
var aabb := AABB()
var morph_key: String = ""
var body_axis: StringName = &"horizontal"
## Real-unit statistics, see AnatomyCompiler._compute_stats for the key list.
var stats: Dictionary = {}
var warnings: Array[String] = []


func bone_count() -> int:
	return bones.size()


func instances_of_part(part_id: int) -> Array[Instance]:
	var out: Array[Instance] = []
	for inst in instances:
		if inst.part_id == part_id:
			out.append(inst)
	return out


func bones_of_part(part_id: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for b in bones:
		if b.part_id == part_id:
			out.append(b.index)
	return out


func accessories_of_type(t: StringName) -> Array[Accessory]:
	var out: Array[Accessory] = []
	for a in accessories:
		if a.type == t:
			out.append(a)
	return out


## Child bone indices of a bone.
func children_of_bone(bi: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for b in bones:
		if b.parent == bi:
			out.append(b.index)
	return out


## Tip bone indices of chains with a given function (e.g. &"walk").
func tips_with_function(functions: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for b in bones:
		if b.is_tip and functions.has(b.function):
			out.append(b.index)
	return out


## Chain (root..tip) of bone indices ending at `tip`, limited to one part instance.
func chain_to(tip: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var inst := bones[tip].instance
	var cur := tip
	while cur >= 0 and bones[cur].instance == inst:
		out.insert(0, cur)
		cur = bones[cur].parent
	return out
