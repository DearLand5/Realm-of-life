class_name SpeciesLibrary
extends RefCounted
## The player's personal library of designed species (persists across worlds).
## One JSON envelope per species: user://species/<uid>.json
##   data: {uid, name, description, created, modified, tags, favorite, genome}
## Species are transferable between worlds: a world stores its own copy and
## keeps `library_uid` as a link.


static func new_uid() -> String:
	return "%x%04x" % [int(Time.get_unix_time_from_system()), randi() % 0xFFFF]


static func path_of(uid: String) -> String:
	return SaveSystem.SPECIES_DIR.path_join(uid.validate_filename() + ".json")


## Saves (creates or overwrites). Returns the uid.
static func save_species(genome: Genome, name: String, uid: String = "", extra: Dictionary = {}) -> String:
	if uid == "":
		uid = new_uid()
	var now := Time.get_datetime_string_from_system(true)
	var created := now
	var existing := load_entry(uid)
	if existing["ok"]:
		created = str(existing["data"].get("created", now))
	var data := {
		"uid": uid, "name": name, "description": extra.get("description", ""),
		"created": created, "modified": now, "tags": extra.get("tags", []),
		"favorite": extra.get("favorite", false), "genome": genome.to_dict(),
	}
	var err := SaveSystem.write_envelope(path_of(uid), "species", data)
	if err != OK:
		return ""
	return uid


static func load_entry(uid: String) -> Dictionary:
	return SaveSystem.read_envelope(path_of(uid), "species")


static func load_genome(uid: String) -> Genome:
	var r := load_entry(uid)
	if not r["ok"]:
		return null
	return Genome.from_dict(Serial.dict(r["data"], "genome"))


## [{uid, name, modified, favorite, description}] sorted: favourites, then newest.
static func list_entries() -> Array:
	var out := []
	for path in SaveSystem.list_files(SaveSystem.SPECIES_DIR, ".json"):
		var r := SaveSystem.read_envelope(path, "species")
		if not r["ok"]:
			continue
		var d: Dictionary = r["data"]
		out.append({"uid": d.get("uid", path.get_file().get_basename()), "name": d.get("name", "?"),
			"modified": d.get("modified", ""), "favorite": d.get("favorite", false), "description": d.get("description", "")})
	out.sort_custom(func(a, b):
		if bool(a["favorite"]) != bool(b["favorite"]):
			return bool(a["favorite"])
		return str(a["modified"]) > str(b["modified"]))
	return out


static func delete_species(uid: String) -> void:
	for p in [path_of(uid), path_of(uid) + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


static func duplicate_species(uid: String) -> String:
	var r := load_entry(uid)
	if not r["ok"]:
		return ""
	var g := Genome.from_dict(Serial.dict(r["data"], "genome"))
	return save_species(g, str(r["data"].get("name", "Вид")) + " (копия)", "", r["data"])
