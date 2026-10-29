class_name Rng
extends RefCounted
## Deterministic random helper wrapping RandomNumberGenerator.
## Every simulation subsystem owns its own Rng seeded from the world seed so
## results are reproducible and independent of call order between systems.

var _r := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	_r.seed = seed_value if seed_value != 0 else randi()


func set_seed(seed_value: int) -> void:
	_r.seed = seed_value


func get_state() -> int:
	return _r.state


func set_state(state: int) -> void:
	_r.state = state


func randf() -> float:
	return _r.randf()


func range_f(a: float, b: float) -> float:
	return _r.randf_range(a, b)


func range_i(a: int, b: int) -> int:
	return _r.randi_range(a, b)


func chance(p: float) -> bool:
	return _r.randf() < p


## Standard normal sample scaled by sigma.
func gauss(mean: float = 0.0, sigma: float = 1.0) -> float:
	return _r.randfn(mean, sigma)


func pick(arr: Array):
	if arr.is_empty():
		return null
	return arr[_r.randi_range(0, arr.size() - 1)]


## Picks an index with probability proportional to weights.
func weighted_index(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return -1
	var x := _r.randf() * total
	for i in weights.size():
		x -= maxf(0.0, float(weights[i]))
		if x <= 0.0:
			return i
	return weights.size() - 1


func unit_vector3() -> Vector3:
	var v := Vector3(gauss(), gauss(), gauss())
	return v.normalized() if v.length_squared() > 1e-8 else Vector3.UP


func unit_vector2() -> Vector2:
	var a := _r.randf() * TAU
	return Vector2(cos(a), sin(a))


## Poisson-distributed integer (Knuth for small lambda, normal approx for large).
func poisson(lambda: float) -> int:
	if lambda <= 0.0:
		return 0
	if lambda > 30.0:
		return maxi(0, int(round(gauss(lambda, sqrt(lambda)))))
	var l := exp(-lambda)
	var k := 0
	var p := 1.0
	while true:
		p *= _r.randf()
		if p <= l:
			break
		k += 1
	return k


## Stateless hash → [0,1). Used for stable procedural placement.
static func hash01(a: int, b: int = 0, c: int = 0) -> float:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0x1000000)
