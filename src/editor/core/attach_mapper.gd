class_name AttachMapper
extends RefCounted
## Converts between geometry-space points on a compiled AnatomyModel and the
## attachment parameters of BodyPart (attach_t / attach_angle / attach_depth).
## Exact inverse of AnatomyCompiler.attach_frame for mid attachments (the
## frames themselves are computed by the compiler's own function, so the
## editor and the compiler never disagree).
##
## Mirroring: a compiled chain of a mirrored instance is the reflection
## (x → −x) of its "raw" chain; parameters always live in raw space, so a
## point on a mirrored copy is reflected before inversion.
##
##   var raw := AttachMapper.instance_raw(model, inst)            # compiler-compatible chain
##   var a := AttachMapper.params_on_instance(model, inst, hit)   # {ok, t, angle, depth, cap}
##   var d := AttachMapper.params_for_drag(model, plan, child_inst, hit)  # for a dragged copy
##   var tf := AttachMapper.frame(model, inst, t, angle, depth)   # geometry-space attach frame

## Mid attachments are kept away from the chain ends (t ≤ 0.001 / ≥ 0.999
## means "continue the chain" in the compiler).
const T_EDGE := 0.002
const CAP_ATTACH_MAX_DEPTH := 1.0


## Raw (unmirrored) chain of a compiled spine instance, or null for point parts.
static func instance_raw(m: AnatomyModel, inst_idx: int) -> AnatomyCompiler._Raw:
	if inst_idx < 0 or inst_idx >= m.instances.size():
		return null
	var inst := m.instances[inst_idx]
	if inst.bones.is_empty():
		return null
	var raw := AnatomyCompiler._Raw.new()
	for bi in inst.bones:
		var b := m.bones[bi]
		var st := b.start
		var en := b.end
		var bs := b.basis
		if inst.mirrored:
			st = MathUtil.mirror_point_x(st)
			en = MathUtil.mirror_point_x(en)
			bs = MathUtil.mirror_basis_x(bs)
		raw.starts.append(st)
		raw.ends.append(en)
		raw.bases.append(bs)
		raw.r0s.append(b.r0)
		raw.r1s.append(b.r1)
		raw.flats.append(b.flatten)
		raw.lengths.append(b.length)
		raw.total += b.length
		raw.bone_indices.append(bi)
	return raw


## Attach frame (geometry space) on a compiled spine instance.
static func frame(m: AnatomyModel, inst_idx: int, t: float, angle: float, depth: float) -> Transform3D:
	var raw := instance_raw(m, inst_idx)
	if raw == null:
		return Transform3D.IDENTITY
	var tf := AnatomyCompiler.attach_frame(raw, t, angle, depth)
	if m.instances[inst_idx].mirrored:
		tf = Transform3D(MathUtil.mirror_basis_x(tf.basis), MathUtil.mirror_point_x(tf.origin))
	return tf


## Attachment parameters that put a child's anchor at geometry point `p` on
## spine instance `inst_idx`. Returns {ok, t, angle, depth, cap, segment}.
## cap: 0 = mid attachment, 1 = front end cap (t = 1), -1 = rear cap (t = 0).
static func params_on_instance(m: AnatomyModel, inst_idx: int, p: Vector3) -> Dictionary:
	var raw := instance_raw(m, inst_idx)
	if raw == null or raw.total <= 0.0:
		return {"ok": false}
	var q := MathUtil.mirror_point_x(p) if m.instances[inst_idx].mirrored else p
	return params_on_raw(raw, q)


## Inversion on a raw chain (q in raw space).
static func params_on_raw(raw: AnatomyCompiler._Raw, q: Vector3) -> Dictionary:
	var n := raw.starts.size()
	var best := 0
	var best_u := 0.0
	var best_u_raw := 0.0
	var best_d := INF
	for k in n:
		var a: Vector3 = raw.starts[k]
		var b: Vector3 = raw.ends[k]
		var ab := b - a
		var l2 := maxf(ab.length_squared(), 1e-12)
		var u_raw := (q - a).dot(ab) / l2
		var u := clampf(u_raw, 0.0, 1.0)
		var d := q.distance_to(a + ab * u)
		if d < best_d - 1e-9:
			best_d = d
			best = k
			best_u = u
			best_u_raw = u_raw
	# End caps: the point lies beyond the first/last segment along the axis.
	if best == n - 1 and best_u_raw > 1.0:
		var r := _cap_params(raw, q, true)
		if r["ok"]:
			return r
	if best == 0 and best_u_raw < 0.0:
		var r2 := _cap_params(raw, q, false)
		if r2["ok"]:
			return r2
	var acc := 0.0
	for k in best:
		acc += raw.lengths[k]
	var t := clampf((acc + best_u * raw.lengths[best]) / raw.total, T_EDGE, 1.0 - T_EDGE)
	# Re-evaluate the axis point at the clamped t (exact inverse of attach_frame).
	var seg_u := best_u
	var target := t * raw.total
	if absf(target - (acc + best_u * raw.lengths[best])) > 1e-7:
		seg_u = clampf((target - acc) / maxf(raw.lengths[best], 1e-6), 0.0, 1.0)
	var bs: Basis = raw.bases[best]
	var axis_p: Vector3 = (raw.starts[best] as Vector3).lerp(raw.ends[best], seg_u)
	var r_loc := maxf(lerpf(raw.r0s[best], raw.r1s[best], seg_u), 1e-6)
	var fl := maxf(raw.flats[best], 1e-3)
	var local := q - axis_p
	var x := local.dot(bs.x) / r_loc
	var z := local.dot(bs.z) / (r_loc * fl)
	var depth := sqrt(x * x + z * z)
	var angle := wrapf(rad_to_deg(atan2(z, x)), 0.0, 360.0) if depth > 1e-6 else 0.0
	return {"ok": true, "t": t, "angle": angle, "depth": depth, "cap": 0, "segment": best}


static func _cap_params(raw: AnatomyCompiler._Raw, q: Vector3, front: bool) -> Dictionary:
	var n := raw.starts.size()
	var i := n - 1 if front else 0
	var b: Basis = raw.bases[i]
	var tang := b.y if front else -b.y
	var p_end: Vector3 = raw.ends[i] if front else raw.starts[i]
	var v := q - p_end
	var dist := v.length()
	if dist < 1e-7:
		return {"ok": true, "t": 1.0 if front else 0.0, "angle": 0.0, "depth": 0.0, "cap": 1 if front else -1, "segment": i}
	var dir := v / dist
	var along := dir.dot(tang)
	if along <= 0.05:
		return {"ok": false}
	var perp := dir - tang * along
	var ratio := perp.length() / along
	# attach_frame: out ∝ tang·(1−d) + normal·d·1.6  ⇒  |perp|/along = 1.6·d/(1−d)
	var depth := clampf(ratio / (1.6 + ratio), 0.0, CAP_ATTACH_MAX_DEPTH)
	var angle := 0.0
	if perp.length_squared() > 1e-10:
		var w := perp.normalized()
		var fl := maxf(raw.flats[i], 1e-3)
		angle = wrapf(rad_to_deg(atan2(w.dot(b.z), w.dot(b.x) / fl)), 0.0, 360.0)
	return {"ok": true, "t": 1.0 if front else 0.0, "angle": angle, "depth": depth, "cap": 1 if front else -1, "segment": i}


## Parameters for the BodyPart of compiled instance `child_inst` so that THIS
## copy (mirror / radial / repeat copy) lands at `p`. Returns
## {ok, t, angle, depth, cap} in the part's own (stored) terms.
static func params_for_drag(m: AnatomyModel, plan: BodyPlan, child_inst: int, p: Vector3) -> Dictionary:
	if child_inst < 0 or child_inst >= m.instances.size():
		return {"ok": false}
	var inst := m.instances[child_inst]
	var par := inst.parent_instance
	var part := plan.get_part(inst.part_id)
	if par < 0 or part == null:
		return {"ok": false}
	var pp := p
	if inst.mirrored != m.instances[par].mirrored:
		pp = MathUtil.mirror_point_x(p)
	var r := params_on_instance(m, par, pp)
	if not r["ok"]:
		return r
	if part.symmetry >= 3:
		r["angle"] = wrapf(float(r["angle"]) - 360.0 * float(inst.radial_index) / float(part.symmetry), 0.0, 360.0)
	var reps := maxi(1, part.repeat_count)
	if reps > 1 and int(r["cap"]) == 0:
		var u := float(inst.repeat_index) / float(reps - 1)
		r["t"] = clampf(float(r["t"]) - part.repeat_span * u, T_EDGE, 1.0 - T_EDGE)
	return r


## Geometry-space attach frame of a compiled instance (its own copy), or
## identity for the root.
static func instance_frame(m: AnatomyModel, plan: BodyPlan, inst_idx: int) -> Transform3D:
	if inst_idx < 0 or inst_idx >= m.instances.size():
		return Transform3D.IDENTITY
	var inst := m.instances[inst_idx]
	var part := plan.get_part(inst.part_id)
	var par := inst.parent_instance
	if part == null or par < 0 or instance_raw(m, par) == null:
		return Transform3D(Basis.IDENTITY, inst.anchor)
	var t := part.attach_t
	var reps := maxi(1, part.repeat_count)
	if reps > 1:
		t = clampf(t + part.repeat_span * float(inst.repeat_index) / float(reps - 1), 0.0, 1.0)
	var angle := part.attach_angle
	if part.symmetry >= 3:
		angle += 360.0 * float(inst.radial_index) / float(part.symmetry)
	var raw := instance_raw(m, par)
	var tf := AnatomyCompiler.attach_frame(raw, t, angle, part.attach_depth)
	# Raw space of the parent; mirror into this copy's space.
	if inst.mirrored:
		tf = Transform3D(MathUtil.mirror_basis_x(tf.basis), MathUtil.mirror_point_x(tf.origin))
	return tf


## Segment-joint parameters (0..1) of a spine part's chain (for snapping).
static func joint_ts(part: BodyPart) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var total := EditorCommands.chain_length(part)
	if total <= 0.0:
		return out
	var acc := 0.0
	for i in part.segments.size() - 1:
		acc += part.segments[i].length
		out.append(acc / total)
	return out


## Snaps attachment params: angle to `angle_step` (and the dorsal/ventral
## symmetry plane), t to segment joints of the parent and to `t_step`.
static func snap(params: Dictionary, parent: BodyPart, angle_step: float = 15.0, t_step: float = 0.05) -> Dictionary:
	var out := params.duplicate()
	if not out.get("ok", false):
		return out
	var a := float(out["angle"])
	for plane in [90.0, 270.0]:
		if absf(wrapf(a - plane, -180.0, 180.0)) < 8.0:
			a = plane
	if angle_step > 0.0:
		a = snappedf(a, angle_step)
	out["angle"] = wrapf(a, 0.0, 360.0)
	if int(out.get("cap", 0)) == 0:
		var t := float(out["t"])
		var snapped := false
		if parent != null:
			for jt in joint_ts(parent):
				if absf(t - jt) < 0.035:
					t = jt
					snapped = true
					break
		if not snapped and t_step > 0.0:
			t = snappedf(t, t_step)
		out["t"] = clampf(t, T_EDGE, 1.0 - T_EDGE)
	out["depth"] = snappedf(float(out["depth"]), 0.05)
	return out
