class_name LimbIK
extends RefCounted
## Inverse kinematics for bone chains (legs, tentacles). FABRIK on the joint
## positions with fixed bone lengths, then conversion of the solution to local
## bone rotations that keep the rest twist (swing-only). Works in skeleton space.


## Solves for the chain `pts` (joint positions, root first, N+1 points for N bones)
## reaching `target` while the root stays fixed. Returns the remaining tip error.
static func fabrik(pts: PackedVector3Array, lens: PackedFloat32Array, target: Vector3, iterations: int = 6, tol: float = 0.0005) -> float:
	var n := lens.size()
	if n == 0 or pts.size() != n + 1:
		return 0.0
	var root := pts[0]
	var total := 0.0
	for l in lens:
		total += l
	var to_t := target - root
	if to_t.length() >= total * 0.9995:
		# Unreachable: stretch straight toward the target.
		var d := to_t.normalized() if to_t.length() > 1e-6 else Vector3.DOWN
		var acc := 0.0
		for i in n:
			pts[i + 1] = root + d * (acc + lens[i])
			acc += lens[i]
		return (target - pts[n]).length()
	for it in iterations:
		if (pts[n] - target).length() < tol:
			break
		# Backward: tip to target.
		pts[n] = target
		for i in range(n - 1, -1, -1):
			var d2 := pts[i] - pts[i + 1]
			var dl := d2.length()
			pts[i] = pts[i + 1] + (d2 / dl * lens[i] if dl > 1e-9 else Vector3.UP * lens[i])
		# Forward: root back in place.
		pts[0] = root
		for i in n:
			var d3 := pts[i + 1] - pts[i]
			var dl3 := d3.length()
			pts[i + 1] = pts[i] + (d3 / dl3 * lens[i] if dl3 > 1e-9 else Vector3.DOWN * lens[i])
	return (target - pts[n]).length()


## Writes swing rotations so each bone points along pts[k] -> pts[k+1].
## `parent_basis`: final (orthonormal) global basis of the chain's parent bone.
## `seg_local`: direction of each bone's segment (start -> end) in the bone's own rest frame.
## `last_dir`: if non-zero the last bone keeps that direction instead (flat feet).
## `dirs_out` (optional): receives the final global basis Y of every bone.
static func apply(sk: Skeleton3D, bones: PackedInt32Array, pts: PackedVector3Array, parent_basis: Basis,
		seg_local: PackedVector3Array, last_dir: Vector3 = Vector3.ZERO) -> void:
	var pb := parent_basis
	var last := bones.size() - 1
	for k in bones.size():
		var b := bones[k]
		var rest_local := sk.get_bone_rest(b).basis
		var unposed := pb * rest_local
		var d: Vector3
		if k == last and last_dir != Vector3.ZERO:
			d = last_dir
		else:
			d = pts[k + 1] - pts[k]
		if d.length_squared() < 1e-12:
			sk.set_bone_pose_rotation(b, rest_local.get_rotation_quaternion())
			pb = unposed
			continue
		d = d.normalized()
		var cur_y := (unposed * seg_local[k]).normalized()
		var swing := _arc(cur_y, d)
		var desired := Basis(swing) * unposed
		var local := pb.inverse() * desired
		sk.set_bone_pose_rotation(b, local.orthonormalized().get_rotation_quaternion())
		pb = desired


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	var dot := from.dot(to)
	if dot > 0.999999:
		return Quaternion.IDENTITY
	if dot < -0.999999:
		var ax := from.cross(Vector3.RIGHT)
		if ax.length_squared() < 1e-6:
			ax = from.cross(Vector3.UP)
		return Quaternion(ax.normalized(), PI)
	return Quaternion(from.cross(to).normalized(), acos(clampf(dot, -1.0, 1.0)))
