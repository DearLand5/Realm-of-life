class_name CreatureMemory
extends RefCounted
## Short-term memory of perceived things (decaying confidence, last known
## position) plus long-term spatial memory (good food areas, water spots, danger
## zones, shelter, home). The span scales with the `learning` trait and brain size.

const SPOT_FOOD := &"food"
const SPOT_WATER := &"water"
const SPOT_DANGER := &"danger"
const SPOT_SHELTER := &"shelter"
const SPOT_HOME := &"home"
const MERGE_RADIUS := 7.0
const FORGET_BELOW := 0.06

## key -> Percept (maintained by Perception, decayed here).
var short: Dictionary = {}
## Long-term spots: [{type, pos, strength 0..1, t}].
var spots: Array[Dictionary] = []
var span: float = 40.0           # s until a short-term percept fades to ~37 %
var capacity: int = 8
var spot_half_life: float = 600.0
var home := Vector3.INF


func configure(learning: float, brain: float) -> void:
	var l := clampf(learning, 0.0, 1.0)
	var b := clampf(brain, 0.0, 1.5)
	span = lerpf(15.0, 120.0, l) * (0.6 + 0.5 * minf(b, 1.0))
	capacity = 4 + int(round(16.0 * l * minf(0.4 + b, 1.2)))
	spot_half_life = lerpf(120.0, 2400.0, l) * (0.5 + 0.5 * minf(b + 0.3, 1.0))


## Decays confidence by age; drops what is no longer worth remembering.
func decay(now: float) -> void:
	var drop: Array[int] = []
	for k in short:
		var p: Percept = short[k]
		if not p.fresh:
			p.confidence = exp(-(now - p.t_seen) / span)
			if p.confidence < FORGET_BELOW or ((p.kind == Percept.Kind.AGENT or p.kind == Percept.Kind.EGG) and not is_instance_valid(p.agent)):
				drop.append(k)
	for k in drop:
		short.erase(k)


func get_or_make(key: int) -> Percept:
	var p: Percept = short.get(key)
	if p == null:
		p = Percept.new()
		p.key = key
		short[key] = p
	return p


func forget(key: int) -> void:
	short.erase(key)


func clear_short() -> void:
	short.clear()


# --- Long-term spots ----------------------------------------------------------------

## Remembers (or reinforces) a place. `strength` 0..1 is its value.
func note(type: StringName, p: Vector3, strength: float, now: float) -> void:
	for s in spots:
		if s["type"] == type and (s["pos"] as Vector3).distance_to(p) < MERGE_RADIUS:
			s["pos"] = (s["pos"] as Vector3).lerp(p, 0.25)
			s["strength"] = clampf(maxf(float(s["strength"]), strength) * 0.5 + float(s["strength"]) * 0.5 + 0.15, 0.0, 1.0)
			s["t"] = now
			return
	if spots.size() >= capacity:
		var worst := 0
		var worst_v := INF
		for i in spots.size():
			var v := float(spots[i]["strength"]) - 0.002 * (now - float(spots[i]["t"])) + (0.5 if spots[i]["type"] == SPOT_HOME else 0.0)
			if v < worst_v:
				worst_v = v
				worst = i
		spots.remove_at(worst)
	spots.append({"type": type, "pos": p, "strength": clampf(strength, 0.0, 1.0), "t": now})
	if type == SPOT_HOME:
		home = p


## Weakens a spot (e.g. a food place found empty, a danger that turned out safe).
func penalize(type: StringName, p: Vector3, amount: float) -> void:
	for i in range(spots.size() - 1, -1, -1):
		var s := spots[i]
		if s["type"] == type and (s["pos"] as Vector3).distance_to(p) < MERGE_RADIUS * 1.3:
			s["strength"] = float(s["strength"]) - amount
			if float(s["strength"]) <= 0.05:
				spots.remove_at(i)


func decay_spots(dt: float) -> void:
	var f := pow(0.5, dt / spot_half_life)
	for i in range(spots.size() - 1, -1, -1):
		var s := spots[i]
		if s["type"] == SPOT_HOME:
			continue
		s["strength"] = float(s["strength"]) * f
		if float(s["strength"]) < 0.04:
			spots.remove_at(i)


## Best remembered spot of a type for an agent at `from`: strength / (1 + distance/60).
## Returns Vector3.INF when none.
func recall(type: StringName, from: Vector3, min_strength: float = 0.1, exclude_near: Vector3 = Vector3.INF, exclude_r: float = 0.0) -> Vector3:
	var best := Vector3.INF
	var best_v := 0.0
	for s in spots:
		if s["type"] != type or float(s["strength"]) < min_strength:
			continue
		var sp: Vector3 = s["pos"]
		if exclude_near != Vector3.INF and sp.distance_to(exclude_near) < exclude_r:
			continue
		var v := float(s["strength"]) / (1.0 + sp.distance_to(from) / 60.0)
		if v > best_v:
			best_v = v
			best = sp
	return best


## Danger strength near a point (sum over remembered danger zones, 0..1).
func danger_at(p: Vector3, radius: float = 18.0) -> float:
	var d := 0.0
	for s in spots:
		if s["type"] == SPOT_DANGER:
			var dist := (s["pos"] as Vector3).distance_to(p)
			if dist < radius:
				d += float(s["strength"]) * (1.0 - dist / radius)
	return clampf(d, 0.0, 1.0)


func to_dict() -> Dictionary:
	var out := []
	for s in spots:
		out.append({"type": str(s["type"]), "pos": Serial.v3(s["pos"]), "strength": s["strength"], "t": s["t"]})
	return {"spots": out, "home": Serial.v3(home) if home != Vector3.INF else []}


func from_dict(d: Dictionary) -> void:
	spots.clear()
	for e in Serial.arr(d, "spots"):
		if e is Dictionary:
			spots.append({"type": StringName(Serial.s(e, "type", "food")), "pos": Serial.to_v3(e.get("pos")),
				"strength": Serial.f(e, "strength", 0.5), "t": Serial.f(e, "t", 0.0)})
	var h: Variant = d.get("home")
	home = Serial.to_v3(h, Vector3.INF) if h is Array and not (h as Array).is_empty() else Vector3.INF
