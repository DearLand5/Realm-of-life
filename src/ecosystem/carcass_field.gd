class_name CarcassField
extends RefCounted
## Dead bodies lying in the world (owned by EcoGrid). Carcasses close to
## each other merge (pools add their dead at sector centres). They rot with
## temperature (Q10) — the decayed mass becomes detritus — and become more
## toxic with age (scavengers need a high carrion tolerance).

const MERGE_RADIUS := 4.0
const DECAY_RATE := 0.35 / Units.SECONDS_PER_DAY   # fraction/s at 20 °C
const Q10 := 2.2
const TOXIC_AGE := 2.0 * Units.SECONDS_PER_DAY      # age of maximal toxicity
const MAX_TOXICITY := 0.8
const MIN_KG := 0.01

var ids := PackedInt32Array()
var positions := PackedVector3Array()
var kg := PackedFloat32Array()
var ages := PackedFloat32Array()
var species := PackedInt32Array()
var next_id: int = 1


func count() -> int:
	return ids.size()


func total_kg() -> float:
	var t := 0.0
	for v in kg:
		t += v
	return t


func add(pos: Vector3, mass: float, species_id: int) -> int:
	if mass <= MIN_KG:
		return -1
	var r2 := MERGE_RADIUS * MERGE_RADIUS
	for i in ids.size():
		var d := positions[i] - pos
		if d.x * d.x + d.z * d.z <= r2:
			# Mixed piles keep the larger contributor's species; age is mass-weighted.
			var total := kg[i] + mass
			ages[i] = ages[i] * kg[i] / total
			if mass > kg[i]:
				species[i] = species_id
			kg[i] = total
			return ids[i]
	ids.append(next_id)
	positions.append(pos)
	kg.append(mass)
	ages.append(0.0)
	species.append(species_id)
	next_id += 1
	return next_id - 1


func index_of(id: int) -> int:
	return ids.find(id)


func toxicity_at(i: int) -> float:
	return clampf(ages[i] / TOXIC_AGE, 0.0, 1.0) * MAX_TOXICITY


func info(i: int) -> Dictionary:
	return {"id": ids[i], "pos": positions[i], "kg": kg[i], "species_id": species[i], "age": ages[i], "toxicity": toxicity_at(i)}


func nearest(pos: Vector3, radius: float) -> int:
	var best := -1
	var best_d := radius * radius
	for i in ids.size():
		var d := positions[i] - pos
		var dd := d.x * d.x + d.z * d.z
		if dd <= best_d:
			best_d = dd
			best = i
	return best


## Removes up to `amount` kg from carcass index i. Returns kg taken.
func take(i: int, amount: float) -> float:
	var t := clampf(amount, 0.0, kg[i])
	kg[i] -= t
	return t


func kg_in_rect(x0: float, z0: float, x1: float, z1: float) -> float:
	var t := 0.0
	for i in ids.size():
		var p := positions[i]
		if p.x >= x0 and p.x < x1 and p.z >= z0 and p.z < z1:
			t += kg[i]
	return t


## Takes `amount` kg spread over the carcasses of a rectangle. Returns
## [kg taken, mean toxicity].
func take_in_rect(x0: float, z0: float, x1: float, z1: float, amount: float) -> Vector2:
	var avail := kg_in_rect(x0, z0, x1, z1)
	if avail <= 0.0 or amount <= 0.0:
		return Vector2.ZERO
	var f := clampf(amount / avail, 0.0, 1.0)
	var taken := 0.0
	var tox := 0.0
	for i in ids.size():
		var p := positions[i]
		if p.x >= x0 and p.x < x1 and p.z >= z0 and p.z < z1:
			var t := kg[i] * f
			kg[i] -= t
			taken += t
			tox += t * toxicity_at(i)
	return Vector2(taken, tox / maxf(taken, 1e-9))


## Ages and rots carcasses. `temp_at` gives the air temperature at a
## position; `to_detritus` receives (pos, kg) of decayed matter.
func step(dt: float, temp_at: Callable, to_detritus: Callable) -> void:
	var i := 0
	while i < ids.size():
		var t: float = temp_at.call(positions[i])
		var rate := DECAY_RATE * pow(Q10, clampf(t - 20.0, -30.0, 25.0) / 10.0)
		var lost := kg[i] * (1.0 - exp(-rate * dt))
		kg[i] -= lost
		ages[i] += dt
		to_detritus.call(positions[i], lost)
		if kg[i] < MIN_KG:
			to_detritus.call(positions[i], kg[i])
			_remove(i)
		else:
			i += 1


func _remove(i: int) -> void:
	ids.remove_at(i)
	positions.remove_at(i)
	kg.remove_at(i)
	ages.remove_at(i)
	species.remove_at(i)


func clear() -> void:
	ids.clear()
	positions.clear()
	kg.clear()
	ages.clear()
	species.clear()


func to_dict() -> Dictionary:
	var list := []
	for i in ids.size():
		list.append([ids[i], snappedf(positions[i].x, 0.01), snappedf(positions[i].y, 0.01), snappedf(positions[i].z, 0.01), kg[i], ages[i], species[i]])
	return {"next_id": next_id, "list": list}


func from_dict(d: Dictionary) -> void:
	clear()
	next_id = Serial.i(d, "next_id", 1)
	for e in Serial.arr(d, "list"):
		if e is Array and e.size() >= 7:
			ids.append(int(e[0]))
			positions.append(Vector3(float(e[1]), float(e[2]), float(e[3])))
			kg.append(float(e[4]))
			ages.append(float(e[5]))
			species.append(int(e[6]))
			next_id = maxi(next_id, int(e[0]) + 1)
