class_name CreatureMeshSet
extends RefCounted
## Finished, shareable meshes of one morphology at one LOD (immutable after
## creation; many CreatureVisuals may use the same set).
##   body         ArrayMesh skinned to AnatomyModel.bones (body + soft accessories)
##   accessories  [{mesh: ArrayMesh, bone: int, transform: Transform3D, material_kind: StringName}]
##                bone = -1 means the mesh is skinned with `skin` like the body;
##                otherwise it is rigidly attached to that bone with `transform`.
##   skin         binds (inverse global rest) for every bone, by index

var key: String = ""
var lod: int = 0
var body: ArrayMesh
var accessories: Array[Dictionary] = []
var skin: Skin
var aabb := AABB()
var vertex_count: int = 0
var triangle_count: int = 0
var byte_size: int = 0
var bone_count: int = 0
var stats: Dictionary = {}


## Creates Godot resources from pure buffers. Call on the main thread.
static func from_data(data: CreatureMeshData) -> CreatureMeshSet:
	var s := CreatureMeshSet.new()
	s.key = data.key
	s.lod = data.lod
	s.stats = data.stats
	s.bone_count = data.bind_poses.size()
	s.skin = Skin.new()
	for i in data.bind_poses.size():
		s.skin.add_bind(i, data.bind_poses[i])
	s.body = ArrayMesh.new()
	var first := true
	for kind in CreatureBuildContext.KINDS:
		var buf: MeshBuffer = data.buffers.get(kind)
		if buf == null or buf.is_empty():
			continue
		s.vertex_count += buf.vertex_count()
		s.triangle_count += buf.indices.size() / 3
		s.byte_size += buf.byte_size()
		var bb := buf.aabb()
		s.aabb = bb if first else s.aabb.merge(bb)
		first = false
		if kind == CreatureBuildContext.KIND_BODY:
			s.body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, buf.to_arrays(), [], {}, MeshBuffer.FORMAT)
		else:
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, buf.to_arrays(), [], {}, MeshBuffer.FORMAT)
			s.accessories.append({"mesh": am, "bone": -1, "transform": Transform3D.IDENTITY, "material_kind": kind})
	return s


## Accessory mesh of a material kind (null when the creature has none).
func accessory_mesh(kind: StringName) -> ArrayMesh:
	for a in accessories:
		if a["material_kind"] == kind:
			return a["mesh"]
	return null


func has_kind(kind: StringName) -> bool:
	if kind == CreatureBuildContext.KIND_BODY:
		return body != null and body.get_surface_count() > 0
	return accessory_mesh(kind) != null
