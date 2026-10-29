class_name SenseProfile
extends RefCounted
## Perceptual capabilities derived from sensory organs + sense traits.
## Ranges are in metres (real units) under ideal conditions; Perception
## scales them by light level, wind, medium and occlusion at runtime.

const EYE_TYPE_MULT := {"camera": 1.0, "compound": 0.55, "simple": 0.35, "pit": 0.15, "ocellus": 0.08}
const EAR_TYPE_MULT := {"external": 1.0, "tympanum": 0.7, "pit": 0.4}

var eye_count: int = 0
var vision_range: float = 0.0
var vision_fov: float = 0.0        # degrees, combined horizontal field
var binocular: float = 0.0         # degrees of binocular overlap
var acuity: float = 0.0            # 0..1
var night_vision: float = 0.0      # 0..1
var color_vision: float = 0.0      # 0..1
var compound_eyes := false
var light_only := false            # only light/dark perception (ocelli/pits)
var smell_range: float = 3.0
var hearing_range: float = 4.0
var touch_range: float = 0.3
var vibration_range: float = 1.0
var electro_range: float = 0.0     # water only
var thermal_range: float = 0.0     # detects warm bodies, light independent
var magnetic := false
var polarized := false
var head_bone: int = 0             # bone used for gaze / first-person camera
var eye_point := Vector3.ZERO      # geometry space
var eye_forward := Vector3.FORWARD # geometry space mean gaze direction
var eye_dirs: Array[Vector3] = []  # geometry space


func max_range() -> float:
	return maxf(maxf(vision_range, smell_range), maxf(hearing_range, maxf(thermal_range, electro_range)))


## Effective vision range at a light level 0..1 (0 = moonless night).
func vision_at_light(light: float) -> float:
	if eye_count == 0:
		return 0.0
	var k := lerpf(0.08 + 0.85 * night_vision, 1.0, clampf(light, 0.0, 1.0))
	return vision_range * k


static func build(model: AnatomyModel, genome: Genome) -> SenseProfile:
	var sp := SenseProfile.new()
	var plan := genome.body_plan
	var s := model.size_scale
	var acuity_t := genome.value(&"vision_acuity")
	var night_t := genome.value(&"night_vision")
	var smell_t := genome.value(&"smell_acuity")
	var hear_t := genome.value(&"hearing_acuity")
	var fov_max := 0.0
	var best_range := 0.0
	var eye_sum := Vector3.ZERO
	var eye_pos := Vector3.ZERO
	var night := 0.0
	var colour := 0.0
	var acc_sum := 0.0
	var only_light := true
	for a in model.accessories:
		var part := plan.get_part(a.part_id)
		if part == null:
			continue
		match a.type:
			&"eye":
				sp.eye_count += 1
				var et := str(part.get_param("eye_type", "camera"))
				var mult := float(EYE_TYPE_MULT.get(et, 0.5))
				if et != "ocellus" and et != "pit":
					only_light = false
				if et == "compound":
					sp.compound_eyes = true
				var eye_r := a.size * s
				var ac := float(part.get_param("acuity", 0.6)) * acuity_t
				var rng := (12.0 + 260.0 * sqrt(maxf(eye_r, 0.0005))) * clampf(ac, 0.05, 1.4) * mult
				best_range = maxf(best_range, rng)
				fov_max = maxf(fov_max, float(part.get_param("fov", 120.0)))
				night = maxf(night, float(part.get_param("night_vision", 0.3)))
				colour = maxf(colour, float(part.get_param("color_vision", 0.6)))
				acc_sum += ac
				var dir := a.transform.basis.y.normalized()
				sp.eye_dirs.append(dir)
				eye_sum += dir
				eye_pos += a.transform.origin
	if sp.eye_count > 0:
		sp.vision_range = minf(best_range * (1.0 + 0.08 * float(mini(sp.eye_count, 8) - 1)), 160.0)
		sp.acuity = clampf(acc_sum / float(sp.eye_count), 0.0, 1.0)
		sp.night_vision = clampf(night * 0.6 + night_t * 0.6, 0.0, 1.0)
		sp.color_vision = colour
		sp.light_only = only_light
		if only_light:
			sp.vision_range = minf(sp.vision_range, 6.0)
		sp.eye_point = eye_pos / float(sp.eye_count)
		sp.eye_forward = eye_sum.normalized() if eye_sum.length_squared() > 1e-6 else Vector3.FORWARD
		# Horizontal spread of gaze directions widens the combined field.
		var spread := 0.0
		for i in sp.eye_dirs.size():
			for j in range(i + 1, sp.eye_dirs.size()):
				var a2 := Vector2(sp.eye_dirs[i].x, sp.eye_dirs[i].z)
				var b2 := Vector2(sp.eye_dirs[j].x, sp.eye_dirs[j].z)
				if a2.length_squared() > 1e-6 and b2.length_squared() > 1e-6:
					spread = maxf(spread, rad_to_deg(absf(a2.angle_to(b2))))
		sp.vision_fov = minf(360.0, fov_max + spread)
		sp.binocular = maxf(0.0, fov_max - spread) if sp.eye_count >= 2 else 0.0
	var smell := 0.0
	var hearing := 0.0
	var touch := 0.0
	for inst in model.instances:
		var part := plan.get_part(inst.part_id)
		if part == null:
			continue
		match part.kind:
			&"nose":
				smell += float(part.get_param("sensitivity", 0.6)) * (0.6 + float(part.get_param("size", 0.3)))
			&"antenna":
				smell += float(part.get_param("chemo", 0.6)) * 0.7
				touch = maxf(touch, part.total_length() * s * float(part.get_param("tactile", 0.6)) * 1.2)
			&"ear":
				var et := str(part.get_param("ear_type", "external"))
				hearing += float(part.get_param("sensitivity", 0.6)) * float(EAR_TYPE_MULT.get(et, 0.5)) * (0.6 + 0.4 * float(part.get_param("size", 0.5)))
			&"whisker":
				var acc_i := inst.accessories[0] if not inst.accessories.is_empty() else -1
				if acc_i >= 0:
					touch = maxf(touch, model.accessories[acc_i].size * s * 1.2 * float(part.get_param("sensitivity", 0.7)))
			&"mouth":
				smell += 0.1
			&"sensor":
				var sens := float(part.get_param("sensitivity", 0.6))
				match str(part.get_param("sensor_type", "electro")):
					"electro":
						sp.electro_range = maxf(sp.electro_range, 2.0 + 18.0 * sens)
					"thermal":
						sp.thermal_range = maxf(sp.thermal_range, 2.0 + 22.0 * sens)
					"magnetic":
						sp.magnetic = true
					"vibration":
						sp.vibration_range = maxf(sp.vibration_range, 3.0 + 30.0 * sens)
					"polarized":
						sp.polarized = true
	sp.smell_range = (3.0 + 60.0 * pow(smell, 0.7)) * smell_t
	sp.hearing_range = 4.0 + 80.0 * pow(hearing, 0.8) * hear_t if hearing > 0.0 else 4.0
	var body_r := maxf(float(model.stats.get("width", 0.2)), float(model.stats.get("height", 0.2))) * 0.5
	sp.touch_range = maxf(touch, body_r * 1.1)
	var n_sup := int(model.stats.get("support_count", 0))
	sp.vibration_range = maxf(sp.vibration_range, 1.0 + 0.6 * float(n_sup))
	# Head bone: first bone of the largest head, else front of the root chain.
	var best_head := -1
	var best_r := -1.0
	for b in model.bones:
		if b.kind == &"head" and b.r1 > best_r:
			best_r = b.r1
			best_head = b.index
	if best_head < 0:
		for b in model.bones:
			if b.parent == 0 and b.part_id == plan.root_id:
				best_head = b.index
		var cur := best_head
		while cur >= 0:
			var kids := model.children_of_bone(cur)
			var next := -1
			for k in kids:
				if model.bones[k].instance == model.bones[cur].instance:
					next = k
			if next < 0:
				break
			cur = next
		best_head = maxi(cur, 0)
	sp.head_bone = best_head
	if sp.eye_count == 0 and best_head >= 0 and best_head < model.bones.size():
		sp.eye_point = model.bones[best_head].end
		sp.eye_forward = model.bones[best_head].basis.y
	return sp
