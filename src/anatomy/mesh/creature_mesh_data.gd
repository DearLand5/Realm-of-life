class_name CreatureMeshData
extends RefCounted
## Pure-data result of CreatureMeshBuilder (no Godot resources): safe to build
## on worker threads; CreatureMeshSet.from_data() turns it into meshes.

var key: String = ""
var lod: int = 0
var buffers := {}                       # material kind -> MeshBuffer
var bind_poses: Array[Transform3D] = [] # inverse global rest per bone index
var stats: Dictionary = {}


func vertex_count() -> int:
	var n := 0
	for k in buffers:
		n += (buffers[k] as MeshBuffer).vertex_count()
	return n


func body_vertex_count() -> int:
	var b: MeshBuffer = buffers.get(CreatureBuildContext.KIND_BODY)
	return b.vertex_count() if b != null else 0
