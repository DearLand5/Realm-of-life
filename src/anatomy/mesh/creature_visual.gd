class_name CreatureVisual
extends Node3D
## Visual representation of one individual: Skeleton3D (bones = AnatomyModel
## bones) with the skinned body and accessory meshes from CreatureMeshCache,
## per-individual shader parameters, editor highlight, x-ray mode, condition
## tint, muscle bulge and a blob contact shadow.
##
## Geometry is in geometry space (size_scale = 1): the caller applies the real
## size as node scale. Animation systems drive get_skeleton() bone rotations
## (and positions); pose scale is owned by set_muscle_bulge().

signal meshes_ready(lod: int)

## true: missing LODs are built on worker threads (world); false: synchronously (editor).
var async_build := false
var shadow_enabled := true:
	set(v):
		shadow_enabled = v
		if _shadow != null:
			_shadow.visible = v and not _xray

var model: AnatomyModel
var individual_seed: int = 0
var lod: int = 0
var mesh_set: CreatureMeshSet

var _skeleton: Skeleton3D
var _body: MeshInstance3D
var _parts := {}                 # material kind -> MeshInstance3D
var _shadow: MeshInstance3D
var _params := {}                # instance uniform values shared by all meshes
var _highlight: Array[int] = []
var _xray := false
var _condition := Vector4.ZERO
var _bulge := {}                 # bone -> amount
var _wanted_lod: int = 0


## Builds the creature for `m`. Safe to call again (replaces everything).
func setup(m: AnatomyModel, seed_value: int, level: int = 0) -> void:
	model = m
	individual_seed = seed_value
	_bulge.clear()
	_clear_nodes()
	if m == null:
		push_warning("CreatureVisual.setup: null model")
		return
	_skeleton = SkeletonBuilder.build(m)
	add_child(_skeleton)
	_params = CreatureMaterials.instance_params(m, seed_value, CreatureRig.char_size_of(m))
	_params["cv_condition"] = _condition
	_params["cv_highlight"] = _highlight_vec()
	_make_shadow()
	lod = -1
	set_lod(level)


func get_skeleton() -> Skeleton3D:
	return _skeleton


func get_mesh_set() -> CreatureMeshSet:
	return mesh_set


func bone_index(bone_name: String) -> int:
	return _skeleton.find_bone(bone_name) if _skeleton != null else -1


## Switches LOD; async mode keeps the current meshes until the new set is ready.
func set_lod(level: int) -> void:
	if model == null:
		return
	level = MeshLod.clamp_lod(level)
	_wanted_lod = level
	if level == lod and mesh_set != null:
		return
	var cached := CreatureMeshCache.get_cached(model.morph_key if model.morph_key != "" else _anon_key(), level)
	if cached != null:
		_apply_set(cached)
	elif async_build:
		CreatureMeshCache.request(model, level, _on_set_ready.bind(model, level))
	else:
		_apply_set(CreatureMeshCache.build_now(model, level))


func _anon_key() -> String:
	return CreatureMeshBuilder.cache_key(model, 0).trim_suffix("#0")


func _on_set_ready(s: CreatureMeshSet, for_model: AnatomyModel, level: int) -> void:
	if not is_instance_valid(self) or for_model != model or level != _wanted_lod:
		return
	_apply_set(s)


func _apply_set(s: CreatureMeshSet) -> void:
	if s == null or _skeleton == null:
		return
	mesh_set = s
	lod = s.lod
	if _body == null:
		_body = _make_instance("Body")
	_body.mesh = s.body
	_body.skin = s.skin
	var used := {}
	for entry in s.accessories:
		var kind: StringName = entry["material_kind"]
		used[kind] = true
		var mi: MeshInstance3D = _parts.get(kind)
		if mi == null:
			mi = _make_instance(String(kind).capitalize())
			_parts[kind] = mi
		mi.mesh = entry["mesh"]
		var bone: int = int(entry.get("bone", -1))
		mi.skin = s.skin if bone < 0 else null
		if bone >= 0:
			mi.transform = _skeleton.get_bone_global_rest(bone) * (entry.get("transform", Transform3D.IDENTITY) as Transform3D)
	for kind in _parts.keys():
		if not used.has(kind):
			(_parts[kind] as MeshInstance3D).mesh = null
	_update_materials()
	_apply_params_all()
	_update_shadow_size()
	meshes_ready.emit(lod)


func _make_instance(node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	_skeleton.add_child(mi)
	mi.skeleton = NodePath("..")
	return mi


func _update_materials() -> void:
	var translucent := String(CreatureMaterials.body_kind(model)).begins_with("body_translucent")
	if _body != null:
		_body.material_override = CreatureMaterials.material(&"xray") if _xray else CreatureMaterials.material(CreatureMaterials.body_kind(model))
		_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _xray else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for kind in _parts:
		var mi: MeshInstance3D = _parts[kind]
		if kind == CreatureBuildContext.KIND_ORGAN:
			mi.material_override = CreatureMaterials.material(kind)
			mi.visible = _xray
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif _xray:
			mi.material_override = CreatureMaterials.material(&"xray")
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mi.material_override = CreatureMaterials.material(kind)
			mi.visible = true
			# Translucent bodies cast no shadow, so neither do the parts inside them.
			var no_shadow: bool = kind == CreatureBuildContext.KIND_MEMBRANE or kind == CreatureBuildContext.KIND_GLOW \
				or (translucent and kind != CreatureBuildContext.KIND_HARD)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if no_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if _shadow != null:
		_shadow.visible = shadow_enabled and not _xray


func _apply_params_all() -> void:
	CreatureMaterials.apply(_body, _params)
	for kind in _parts:
		CreatureMaterials.apply(_parts[kind], _params)


func _set_param(pname: String, value) -> void:
	_params[pname] = value
	if _body != null:
		_body.set_instance_shader_parameter(StringName(pname), value)
	for kind in _parts:
		(_parts[kind] as MeshInstance3D).set_instance_shader_parameter(StringName(pname), value)


# --- Editor / state API ------------------------------------------------------------------

## Highlights (or un-highlights) every mesh region of a BodyPart (up to 4 at once).
func set_highlight(part_id: int, on: bool) -> void:
	if on:
		if not _highlight.has(part_id):
			_highlight.append(part_id)
			while _highlight.size() > 4:
				_highlight.remove_at(0)
	else:
		_highlight.erase(part_id)
	_set_param("cv_highlight", _highlight_vec())


func clear_highlight() -> void:
	_highlight.clear()
	_set_param("cv_highlight", _highlight_vec())


func _highlight_vec() -> Vector4:
	var v := Vector4(-1, -1, -1, -1)
	for i in mini(_highlight.size(), 4):
		v[i] = float(_highlight[i])
	return v


## X-ray: the body becomes a translucent ghost and internal organs appear.
func set_xray(on: bool) -> void:
	_xray = on
	_update_materials()


func is_xray() -> bool:
	return _xray


## Shader state: wetness (glossy, darker), damage (wounds), fatigue (dull) — 0..1.
func set_condition(wetness: float, damage: float, fatigue: float) -> void:
	_condition = Vector4(clampf(wetness, 0.0, 1.0), clampf(damage, 0.0, 1.0), clampf(fatigue, 0.0, 1.0), 0.0)
	_set_param("cv_condition", _condition)


## Muscle bulge: scales a bone across its axis (local x/z) by 1 + amount and
## compensates its children so the bulge does not propagate down the chain.
func set_muscle_bulge(bone: int, amount: float) -> void:
	if _skeleton == null or bone < 0 or bone >= _skeleton.get_bone_count():
		return
	var a := clampf(amount, -0.5, 1.0)
	if is_zero_approx(a):
		_bulge.erase(bone)
	else:
		_bulge[bone] = a
	_apply_bulge_to(bone)
	for c in _skeleton.get_bone_children(bone):
		_apply_bulge_to(c)


func _apply_bulge_to(bone: int) -> void:
	var a: float = float(_bulge.get(bone, 0.0))
	var s := Vector3(1.0 + a, 1.0, 1.0 + a)
	var parent := _skeleton.get_bone_parent(bone)
	if parent >= 0 and _bulge.has(parent):
		# Inverse of the parent's cross-axis scale, expressed (diagonally) in this bone's frame.
		var pa: float = float(_bulge[parent])
		var inv_p := Basis.from_scale(Vector3(1.0 / (1.0 + pa), 1.0, 1.0 / (1.0 + pa)))
		var r := _skeleton.get_bone_rest(bone).basis.orthonormalized()
		var m := r.inverse() * inv_p * r
		s *= Vector3(absf(m.x.x), absf(m.y.y), absf(m.z.z))
	_skeleton.set_bone_pose_scale(bone, s)


# --- Blob shadow -------------------------------------------------------------------------

func _make_shadow() -> void:
	_shadow = MeshInstance3D.new()
	_shadow.name = "BlobShadow"
	var q := PlaneMesh.new()
	q.size = Vector2.ONE
	_shadow.mesh = q
	_shadow.material_override = CreatureMaterials.material(&"shadow")
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.visible = shadow_enabled
	add_child(_shadow)


func _update_shadow_size() -> void:
	if _shadow == null or model == null:
		return
	var bb := model.aabb
	var sx := maxf(bb.size.x, 0.01) * 1.25
	var sz := maxf(bb.size.z, 0.01) * 1.15
	_shadow.scale = Vector3(sx, 1.0, sz)
	_shadow.position = Vector3(bb.get_center().x, maxf(bb.size.y, 0.01) * 0.004, bb.get_center().z)


## Moves the contact shadow to a ground height (geometry space, default 0).
func set_shadow_ground(y: float, strength: float = 0.55) -> void:
	if _shadow == null:
		return
	_shadow.position.y = y + maxf(model.aabb.size.y if model != null else 0.01, 0.01) * 0.004
	_shadow.set_instance_shader_parameter(&"cv_shadow_strength", clampf(strength, 0.0, 1.0))


func _clear_nodes() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_skeleton = null
	_body = null
	_parts.clear()
	_shadow = null
	mesh_set = null
