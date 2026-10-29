class_name SkeletonBuilder
extends RefCounted
## AnatomyModel.bones -> Skeleton3D. Bone i of the skeleton is bone i of the
## model (same name and parent); rests are relative to the parent, global
## rests equal Bone.rest_transform() in geometry space (root bone 0 at the
## origin). Mesh skins use bind poses from bind_poses() so the rest pose
## renders the undeformed mesh.


## Global rest transform of a model bone (orthonormalised, finite).
static func global_rest(m: AnatomyModel, i: int) -> Transform3D:
	if i <= 0 or i >= m.bones.size():
		return Transform3D.IDENTITY
	var b := m.bones[i]
	var basis := b.basis.orthonormalized()
	if not basis.is_finite() or absf(basis.determinant() - 1.0) > 0.01:
		basis = MathUtil.basis_from_y(b.end - b.start)
	var origin := b.start if b.start.is_finite() else Vector3.ZERO
	return Transform3D(basis, origin)


## Inverse global rest of every bone (Skin binds by bone index).
static func bind_poses(m: AnatomyModel) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var n := maxi(m.bones.size(), 1)
	for i in n:
		out.append(global_rest(m, i).affine_inverse())
	return out


static func build(m: AnatomyModel) -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "Skeleton"
	var used := {}
	var n := maxi(m.bones.size(), 1)
	var globals: Array[Transform3D] = []
	for i in n:
		globals.append(global_rest(m, i))
		var nm := m.bones[i].name if i < m.bones.size() and m.bones[i].name != "" else "bone_%d" % i
		if used.has(nm):
			nm = "%s#%d" % [nm, i]
		used[nm] = true
		sk.add_bone(nm)
	for i in n:
		var parent := m.bones[i].parent if i < m.bones.size() else -1
		if i == 0 or parent < 0 or parent >= i:
			parent = -1 if i == 0 else 0
		sk.set_bone_parent(i, parent)
		var local := globals[i] if parent < 0 else globals[parent].affine_inverse() * globals[i]
		sk.set_bone_rest(i, local)
		sk.set_bone_pose_position(i, local.origin)
		sk.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())
		sk.set_bone_pose_scale(i, Vector3.ONE)
	return sk
