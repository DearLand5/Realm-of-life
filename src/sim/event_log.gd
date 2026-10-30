class_name EventLog
extends RefCounted
## World journal: life events, species history, weather extremes, mutations
## and every player intervention (the "experiment history"). Entries are
## plain dictionaries {bio_time, day, category, text, data} so they save as
## JSON and the UI can filter them.

const MAX_ENTRIES := 3000
const CATEGORIES := {
	&"life": "Жизнь", &"species": "Виды", &"evolution": "Эволюция", &"weather": "Погода",
	&"intervention": "Вмешательства", &"record": "Рекорды", &"system": "Система",
}

var entries: Array = []
var _clock: Callable  # () -> Vector2(bio_time, day)


func setup(clock: Callable) -> void:
	_clock = clock


func add(category: StringName, text: String, data: Dictionary = {}) -> Dictionary:
	var t := Vector2.ZERO
	if _clock.is_valid():
		t = _clock.call()
	var e := {"bio_time": t.x, "day": int(t.y), "category": str(category), "text": text, "data": data}
	entries.append(e)
	if entries.size() > MAX_ENTRIES:
		# Keep interventions forever-ish: drop the oldest non-intervention entry.
		var drop := 0
		for i in entries.size():
			if entries[i]["category"] != "intervention":
				drop = i
				break
		entries.remove_at(drop)
	Bus.emit(&"sim_event_logged", [e])
	return e


func filtered(categories: Array = [], limit: int = 200) -> Array:
	var out := []
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		if categories.is_empty() or categories.has(StringName(e["category"])) or categories.has(e["category"]):
			out.append(e)
			if out.size() >= limit:
				break
	return out


func interventions() -> Array:
	return filtered([&"intervention"], MAX_ENTRIES)


func to_dict() -> Dictionary:
	return {"entries": entries.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	entries = Serial.arr(d, "entries").duplicate(true)
