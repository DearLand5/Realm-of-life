class_name Flocking
extends RefCounted
## Boids-style group steering from the conspecifics a creature currently
## perceives or remembers: cohesion, alignment, separation. Weights follow
## sociality; schooling in water and flocking in air use the vertical axis too.

const RANGE := 28.0


## Steering vector (length 0..1) to add to the heading. `centroid_out[0]` receives
## the group centre (Vector3.INF if no group) and `count_out[0]` the group size.
static func pull(a: CreatureAgent, centroid_out: Array = [], count_out: Array = []) -> Vector3:
	var soc := a.personality.sociality
	var mem := a.perception.memory
	var pos := a.mover.pos
	var sum_pos := Vector3.ZERO
	var sum_dir := Vector3.ZERO
	var sep := Vector3.ZERO
	var n := 0
	var sep_r := maxf(a.body_length() * 2.2, 1.2)
	for k in mem.short:
		var p: Percept = mem.short[k]
		if p.kind != Percept.Kind.AGENT or p.role != Percept.ROLE_CONSPECIFIC or p.confidence < 0.35:
			continue
		if p.agent == null or not is_instance_valid(p.agent):
			continue
		var d := p.pos - pos
		if d.length() > RANGE:
			continue
		var sd: CreatureAgent = p.agent as CreatureAgent
		if sd != null and sd.individual.stage == &"egg":
			continue
		n += 1
		sum_pos += p.pos
		if p.moving and p.vel.length_squared() > 0.04:
			sum_dir += p.vel.normalized()
		var dist := d.length()
		if dist < sep_r and dist > 0.01:
			sep -= d / (dist * dist) * sep_r
		if n >= 10:
			break
	if not count_out.is_empty():
		count_out[0] = n
	if n == 0:
		if not centroid_out.is_empty():
			centroid_out[0] = Vector3.INF
		return Vector3.ZERO
	var centre := sum_pos / float(n)
	if not centroid_out.is_empty():
		centroid_out[0] = centre
	var to_c := centre - pos
	var dist_c := to_c.length()
	var coh := to_c / maxf(dist_c, 0.01) * clampf((dist_c - sep_r * 1.5) / 15.0, 0.0, 1.0)
	var ali := sum_dir.normalized() * 0.5 if sum_dir.length_squared() > 0.01 else Vector3.ZERO
	var v := coh * 1.0 + ali * 0.8 + sep * 1.4
	if a.mover.medium == &"land":
		v.y = 0.0
	return v.limit_length(1.0) * clampf(soc * 1.2, 0.0, 0.9)
