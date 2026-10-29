class_name Migrations
extends RefCounted
## Upgrades data written by older format versions.
## To change a format: bump SaveSystem.FORMAT_VERSION to N and add a function
## `_<kind>_to_N(data) -> Dictionary` registered in STEPS[kind][N].
## Readers must ALSO stay tolerant (defaults for missing keys), so most new
## parameters need no migration at all.

const STEPS := {
	# "species": {2: "_species_to_2"},
}


static func upgrade(kind: String, from_format: int, data: Dictionary) -> Dictionary:
	var steps: Dictionary = STEPS.get(kind, {})
	var d := data
	for v in range(from_format + 1, SaveSystem.FORMAT_VERSION + 1):
		if steps.has(v):
			d = Callable(Migrations, steps[v]).call(d)
	return d
