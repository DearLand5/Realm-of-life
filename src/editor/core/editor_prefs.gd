class_name EditorPrefs
extends RefCounted
## Small persistent editor preferences (favourite catalogue entries, recent
## entries, snapping). Stored as JSON in user://editor_prefs.json; every
## access is tolerant of a missing or damaged file.

const PATH := "user://editor_prefs.json"
const MAX_RECENT := 8

var favorites: Array[String] = []
var recent: Array[String] = []
var angle_step: float = 15.0
var snapping: bool = true
var seen_hint: bool = false


static func load_prefs() -> EditorPrefs:
	var p := EditorPrefs.new()
	if not FileAccess.file_exists(PATH):
		return p
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return p
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		var d: Dictionary = parsed
		for v in Serial.arr(d, "favorites"):
			p.favorites.append(str(v))
		for v in Serial.arr(d, "recent"):
			p.recent.append(str(v))
		p.angle_step = clampf(Serial.f(d, "angle_step", 15.0), 0.0, 90.0)
		p.snapping = Serial.b(d, "snapping", true)
		p.seen_hint = Serial.b(d, "seen_hint", false)
	return p


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"favorites": favorites, "recent": recent, "angle_step": angle_step,
		"snapping": snapping, "seen_hint": seen_hint}))


func is_favorite(id: String) -> bool:
	return favorites.has(id)


func set_favorite(id: String, on: bool) -> void:
	if on and not favorites.has(id):
		favorites.append(id)
	elif not on:
		favorites.erase(id)
	save()


func push_recent(id: String) -> void:
	recent.erase(id)
	recent.push_front(id)
	while recent.size() > MAX_RECENT:
		recent.pop_back()
	save()
