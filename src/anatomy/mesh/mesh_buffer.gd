class_name MeshBuffer
extends RefCounted
## Growable vertex/index arrays in the creature vertex format, shared by the
## body and all accessory builders. Pure data (thread-safe to fill).
##
## Attribute contract (body / "skin-like" accessories, material kind &"body"):
##   VERTEX/NORMAL   rest (geometry-space) position and normal
##   COLOR           weights of covering slots 0..3 (sum 1)
##   TEX_UV          x = along-body arc length (m), y = ventral factor 0..1
##   TEX_UV2         x = ambient occlusion 0..1, y = normalised position along the part 0..1
##   CUSTOM0 (RGBA float)  xyz = rest position (m), w = dominant covering slot
##   CUSTOM1 (RG float)    x = BodyPart id (highlight), y = detail code (kind specific)
##   BONES/WEIGHTS   4 influences, indices = AnatomyModel.bones
## Other material kinds reuse the same arrays with meanings documented in
## CreatureMaterials (e.g. eyes keep the eye-local sphere position in CUSTOM0).

const FORMAT := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uv := PackedVector2Array()
var uv2 := PackedVector2Array()
var custom0 := PackedFloat32Array()
var custom1 := PackedFloat32Array()
var bones := PackedInt32Array()
var weights := PackedFloat32Array()
var indices := PackedInt32Array()


func vertex_count() -> int:
	return verts.size()


func is_empty() -> bool:
	return verts.is_empty() or indices.is_empty()


## Appends one vertex. `bw` = Vector4 weights for bones `bi` (4 ints).
func add(p: Vector3, n: Vector3, col: Color, t: Vector2, t2: Vector2, c0: Vector4, c1: Vector2,
		bi: PackedInt32Array, bw: Vector4) -> int:
	var k := verts.size()
	verts.append(p)
	normals.append(n)
	colors.append(col)
	uv.append(t)
	uv2.append(t2)
	custom0.append_array([c0.x, c0.y, c0.z, c0.w])
	custom1.append_array([c1.x, c1.y])
	bones.append_array(bi)
	weights.append_array([bw.x, bw.y, bw.z, bw.w])
	return k


func tri(a: int, b: int, c: int) -> void:
	indices.append_array(PackedInt32Array([a, b, c]))


## Quad a-b-c-d (clockwise seen from the front).
func quad(a: int, b: int, c: int, d: int) -> void:
	indices.append_array(PackedInt32Array([a, b, c, a, c, d]))


## Appends another buffer (indices offset).
func append_buffer(o: MeshBuffer) -> void:
	if o == null or o.verts.is_empty():
		return
	var base := verts.size()
	verts.append_array(o.verts)
	normals.append_array(o.normals)
	colors.append_array(o.colors)
	uv.append_array(o.uv)
	uv2.append_array(o.uv2)
	custom0.append_array(o.custom0)
	custom1.append_array(o.custom1)
	bones.append_array(o.bones)
	weights.append_array(o.weights)
	var start := indices.size()
	indices.append_array(o.indices)
	for i in range(start, indices.size()):
		indices[i] += base


## Godot surface arrays (ARRAY_MAX entries).
func to_arrays() -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_CUSTOM0] = custom0
	arr[Mesh.ARRAY_CUSTOM1] = custom1
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	arr[Mesh.ARRAY_INDEX] = indices
	return arr


## Approximate GPU/CPU memory of the arrays in bytes (cache accounting).
func byte_size() -> int:
	return verts.size() * (12 + 12 + 16 + 8 + 8 + 16 + 8 + 16 + 16) + indices.size() * 4


func aabb() -> AABB:
	if verts.is_empty():
		return AABB()
	var lo := verts[0]
	var hi := verts[0]
	for v in verts:
		lo = lo.min(v)
		hi = hi.max(v)
	return AABB(lo, hi - lo)


## Sanity pass: replaces non-finite data so a broken model never produces a
## mesh the renderer rejects. Returns the number of repaired values.
func sanitize() -> int:
	var fixed := 0
	for i in verts.size():
		if not verts[i].is_finite():
			verts[i] = Vector3.ZERO
			fixed += 1
		var n := normals[i]
		if not n.is_finite() or n.length_squared() < 1e-12:
			normals[i] = Vector3.UP
			fixed += 1
	for i in weights.size():
		if not is_finite(weights[i]):
			weights[i] = 0.0
			fixed += 1
	for i in custom0.size():
		if not is_finite(custom0[i]):
			custom0[i] = 0.0
			fixed += 1
	for i in uv.size():
		if not uv[i].is_finite():
			uv[i] = Vector2.ZERO
			fixed += 1
	return fixed
