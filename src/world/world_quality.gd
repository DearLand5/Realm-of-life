class_name WorldQuality
extends RefCounted
## Rendering quality level for world visuals (terrain LOD, flora density,
## shadows, particles). Reads Game.setting("quality") when the Game autoload
## exists: "low" | "medium" | "high" | "auto" (auto → medium).

enum { LOW, MEDIUM, HIGH }

## Tools/tests can force a level (−1 = use the user setting).
static var override_level: int = -1


static func level() -> int:
	if override_level >= 0:
		return clampi(override_level, LOW, HIGH)
	var q := "auto"
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var game := (loop as SceneTree).root.get_node_or_null("Game")
		if game != null and game.has_method("setting"):
			q = str(game.call("setting", "quality"))
	match q:
		"low":
			return LOW
		"high":
			return HIGH
		_:
			return MEDIUM


## Picks a value by quality: pick([low, medium, high]).
static func pick(values: Array):
	return values[clampi(level(), 0, values.size() - 1)]
