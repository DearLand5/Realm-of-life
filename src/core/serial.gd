class_name Serial
extends RefCounted
## JSON-safe conversion helpers. All save data is plain Dictionary/Array/
## float/int/String/bool so it survives JSON round-trips and old saves can be
## migrated by key (see SaveSystem / Migrations).


static func v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


static func to_v3(a, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	if a is Vector3:
		return a
	return fallback


static func v2(v: Vector2) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001)]


static func to_v2(a, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return fallback


static func color(c: Color) -> Array:
	return [snappedf(c.r, 0.001), snappedf(c.g, 0.001), snappedf(c.b, 0.001), snappedf(c.a, 0.001)]


static func to_color(a, fallback: Color = Color.WHITE) -> Color:
	if a is Array and a.size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)
	if a is String:
		return Color.from_string(a, fallback)
	return fallback


static func f(d: Dictionary, key: String, fallback: float = 0.0) -> float:
	var v = d.get(key, fallback)
	if v is float or v is int:
		return float(v)
	return fallback


static func i(d: Dictionary, key: String, fallback: int = 0) -> int:
	var v = d.get(key, fallback)
	if v is float or v is int:
		return int(v)
	return fallback


static func s(d: Dictionary, key: String, fallback: String = "") -> String:
	var v = d.get(key, fallback)
	return str(v) if v != null else fallback


static func b(d: Dictionary, key: String, fallback: bool = false) -> bool:
	var v = d.get(key, fallback)
	if v is bool:
		return v
	if v is float or v is int:
		return v != 0
	return fallback


static func sn(d: Dictionary, key: String, fallback: StringName = &"") -> StringName:
	var v = d.get(key, null)
	return StringName(str(v)) if v != null else fallback


static func arr(d: Dictionary, key: String) -> Array:
	var v = d.get(key, [])
	return v if v is Array else []


static func dict(d: Dictionary, key: String) -> Dictionary:
	var v = d.get(key, {})
	return v if v is Dictionary else {}


## Deep copy of a JSON-like structure.
static func deep_copy(v):
	if v is Dictionary:
		return (v as Dictionary).duplicate(true)
	if v is Array:
		return (v as Array).duplicate(true)
	return v


## Converts JSON-parsed numbers inside a params dictionary back to proper types
## according to a template (ints stay ints, StringNames from strings).
static func coerce_like(value, template):
	if template is int:
		return int(value) if (value is float or value is int) else template
	if template is float:
		return float(value) if (value is float or value is int) else template
	if template is bool:
		return bool(value) if (value is bool or value is float or value is int) else template
	if template is StringName:
		return StringName(str(value))
	if template is String:
		return str(value)
	if template is Color:
		return to_color(value, template)
	return value
