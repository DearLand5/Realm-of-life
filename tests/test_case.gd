class_name TestCase
extends RefCounted
## Minimal test base. Subclasses define `test_*` methods and call check().

var failures: Array[String] = []
var checks: int = 0
var current: String = ""


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append("%s: %s" % [current, msg])


func near(a: float, b: float, eps: float, msg: String) -> void:
	check(absf(a - b) <= eps, "%s (got %s, expected %s ± %s)" % [msg, a, b, eps])


func finite(x: float, msg: String) -> void:
	check(not is_nan(x) and not is_inf(x), "%s is not finite (%s)" % [msg, x])
