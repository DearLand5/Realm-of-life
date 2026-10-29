class_name MathUtil
extends RefCounted
## Small, dependency-free math helpers shared by all systems.


static func clamp01(x: float) -> float:
	return clampf(x, 0.0, 1.0)


static func remap_clamped(x: float, a: float, b: float, c: float, d: float) -> float:
	if is_equal_approx(a, b):
		return c
	return lerpf(c, d, clamp01((x - a) / (b - a)))


## Frame-rate independent exponential smoothing factor.
static func damp_factor(rate: float, dt: float) -> float:
	return 1.0 - exp(-rate * dt)


static func damp(current: float, target: float, rate: float, dt: float) -> float:
	return lerpf(current, target, damp_factor(rate, dt))


static func damp_v3(current: Vector3, target: Vector3, rate: float, dt: float) -> Vector3:
	return current.lerp(target, damp_factor(rate, dt))


## Polynomial smooth minimum (k = blend radius).
static func smin(a: float, b: float, k: float) -> float:
	if k <= 0.0:
		return minf(a, b)
	var h := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25


## Gaussian-shaped tolerance curve: 1 at optimum, falls with distance/width.
static func tolerance(value: float, optimum: float, width: float) -> float:
	if width <= 0.0:
		return 1.0 if is_equal_approx(value, optimum) else 0.0
	var d := (value - optimum) / width
	return exp(-0.5 * d * d)


## Logistic function.
static func sigmoid(x: float) -> float:
	return 1.0 / (1.0 + exp(-x))


## Builds an orthonormal basis whose Y axis points along `dir`.
static func basis_from_y(dir: Vector3, hint_z: Vector3 = Vector3.BACK) -> Basis:
	var y := dir.normalized()
	if y.length_squared() < 1e-8:
		y = Vector3.UP
	var z := hint_z - y * hint_z.dot(y)
	if z.length_squared() < 1e-6:
		z = Vector3.RIGHT - y * y.x
		if z.length_squared() < 1e-6:
			z = Vector3.FORWARD - y * (-y.z)
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


## Mirrors a basis across the YZ plane (x -> -x) keeping it a proper rotation.
static func mirror_basis_x(b: Basis) -> Basis:
	var m := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	return m * b * m


static func mirror_point_x(p: Vector3) -> Vector3:
	return Vector3(-p.x, p.y, p.z)


## Distance from point p to segment ab, also returns parameter via out array.
static func point_segment_t(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-12:
		return 0.0
	return clampf((p - a).dot(ab) / l2, 0.0, 1.0)


static func wrap_angle(a: float) -> float:
	return wrapf(a, -PI, PI)


## Stable string hash (FNV-1a 32-bit) for cache keys.
static func fnv1a(s: String) -> int:
	var h := 2166136261
	for c in s.to_utf8_buffer():
		h = ((h ^ c) * 16777619) & 0xFFFFFFFF
	return h
