class_name SaveSystem
extends RefCounted
## Versioned, crash-safe persistence.
##
## Every file is an ENVELOPE: {format, kind, app_version, saved_at, checksum, data}
##   * atomic: written to "<path>.tmp", previous file kept as "<path>.bak",
##     then renamed — a crash never leaves a half-written save;
##   * verified: checksum of the data; corrupted files fall back to ".bak";
##   * forward compatible: `data` is plain JSON; readers use defaults for
##     missing keys and ignore unknown keys; `Migrations` upgrades old formats;
##   * large numeric grids are stored as base64 packed arrays (pack_f32).
## World saves are ZSTD-compressed; species/settings are readable JSON.

const FORMAT_VERSION := 1
const SPECIES_DIR := "user://species"
const WORLDS_DIR := "user://worlds"
const SETTINGS_PATH := "user://settings.json"
const CONTROLS_PATH := "user://controls.json"
const AUTOSAVE_SLOTS := 3


# --- Low level -----------------------------------------------------------------------

static func ensure_dir(path: String) -> void:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)


static func checksum(text: String) -> String:
	return text.md5_text()


static func write_envelope(path: String, kind: String, data: Dictionary, compressed: bool = false) -> Error:
	ensure_dir(path)
	var body := JSON.stringify(data)
	var env := {
		"format": FORMAT_VERSION, "kind": kind, "app_version": ProjectSettings.get_setting("application/config/version", "0"),
		"saved_at": Time.get_datetime_string_from_system(true), "checksum": checksum(body),
	}
	# The data is embedded as a raw JSON fragment to keep the checksum exact.
	var text := JSON.stringify(env).trim_suffix("}") + ",\"data\":" + body + "}"
	var tmp := path + ".tmp"
	var f: FileAccess
	if compressed:
		f = FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	else:
		f = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		var err := FileAccess.get_open_error()
		push_error("SaveSystem: cannot write %s (%s)" % [tmp, error_string(err)])
		return err
	f.store_string(text)
	f.close()
	if FileAccess.file_exists(path):
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(path, bak)
	var rerr := DirAccess.rename_absolute(tmp, path)
	if rerr != OK:
		push_error("SaveSystem: rename failed for %s (%s)" % [path, error_string(rerr)])
	return rerr


## Returns {ok: bool, data: Dictionary, error: String, from_backup: bool, format: int}.
static func read_envelope(path: String, expected_kind: String = "", compressed: bool = false) -> Dictionary:
	var res := _read_one(path, expected_kind, compressed)
	if not res["ok"] and FileAccess.file_exists(path + ".bak"):
		var bak := _read_one(path + ".bak", expected_kind, compressed)
		if bak["ok"]:
			bak["from_backup"] = true
			push_warning("SaveSystem: %s damaged, restored from backup (%s)" % [path, res["error"]])
			return bak
	return res


static func _read_one(path: String, expected_kind: String, compressed: bool) -> Dictionary:
	var out := {"ok": false, "data": {}, "error": "", "from_backup": false, "format": 0}
	if not FileAccess.file_exists(path):
		out["error"] = "file not found"
		return out
	var f: FileAccess
	if compressed:
		f = FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	else:
		f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		out["error"] = error_string(FileAccess.get_open_error())
		return out
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		out["error"] = "parse error: %s" % json.get_error_message()
		return out
	var env: Dictionary = json.data
	if expected_kind != "" and str(env.get("kind", "")) != expected_kind:
		out["error"] = "wrong kind %s" % env.get("kind", "")
		return out
	var data = env.get("data", {})
	if not (data is Dictionary):
		out["error"] = "no data"
		return out
	var stored := str(env.get("checksum", ""))
	if stored != "" and stored != checksum(JSON.stringify(data)):
		# JSON re-serialisation can differ in float formatting; verify by
		# extracting the raw fragment instead.
		var idx := text.find("\"data\":")
		if idx < 0 or checksum(text.substr(idx + 7, text.length() - idx - 8)) != stored:
			out["error"] = "checksum mismatch"
			return out
	var fmt := int(env.get("format", 1))
	out["format"] = fmt
	out["data"] = Migrations.upgrade(str(env.get("kind", expected_kind)), fmt, data)
	out["ok"] = true
	return out


static func list_files(dir_path: String, ext: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(ext):
			out.append(dir_path.path_join(f))
	return out


# --- Packed arrays ----------------------------------------------------------------------

static func pack_f32(a: PackedFloat32Array) -> String:
	return Marshalls.raw_to_base64(a.to_byte_array())


static func unpack_f32(s, expected_size: int = -1) -> PackedFloat32Array:
	if not (s is String) or s == "":
		var empty := PackedFloat32Array()
		if expected_size > 0:
			empty.resize(expected_size)
		return empty
	var a := Marshalls.base64_to_raw(s).to_float32_array()
	if expected_size > 0 and a.size() != expected_size:
		a.resize(expected_size)
	return a


static func pack_bytes(a: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(a)


static func unpack_bytes(s) -> PackedByteArray:
	if not (s is String) or s == "":
		return PackedByteArray()
	return Marshalls.base64_to_raw(s)


# --- Settings & controls -------------------------------------------------------------

static func load_settings() -> Dictionary:
	var r := read_envelope(SETTINGS_PATH, "settings")
	return r["data"] if r["ok"] else {}


static func save_settings(s: Dictionary) -> void:
	write_envelope(SETTINGS_PATH, "settings", s)


static func load_controls() -> Dictionary:
	var r := read_envelope(CONTROLS_PATH, "controls")
	return r["data"] if r["ok"] else {}


static func save_controls(c: Dictionary) -> void:
	write_envelope(CONTROLS_PATH, "controls", c)


# --- Worlds ----------------------------------------------------------------------------------

static func world_dir(slot: String) -> String:
	return WORLDS_DIR.path_join(slot.validate_filename())


## kind: "manual" | "autosave" | "checkpoint:<name>"
static func save_world(slot: String, data: Dictionary, kind: String = "manual") -> Error:
	var dir := world_dir(slot)
	var file := "world.sav"
	if kind == "autosave":
		_rotate_autosaves(dir)
		file = "autosave_1.sav"
	elif kind.begins_with("checkpoint:"):
		file = "cp_%s.sav" % kind.substr(11).validate_filename()
	var meta := {"slot": slot, "kind": kind, "day": data.get("day", 0), "name": data.get("name", slot),
		"species": data.get("species_count", 0), "population": data.get("population", 0),
		"saved_at": Time.get_datetime_string_from_system(true)}
	var err := write_envelope(dir.path_join(file), "world", data, true)
	if err == OK:
		write_envelope(dir.path_join(file.get_basename() + ".meta"), "world_meta", meta)
	return err


static func _rotate_autosaves(dir: String) -> void:
	for i in range(AUTOSAVE_SLOTS, 1, -1):
		var src := dir.path_join("autosave_%d.sav" % (i - 1))
		var dst := dir.path_join("autosave_%d.sav" % i)
		if FileAccess.file_exists(src):
			if FileAccess.file_exists(dst):
				DirAccess.remove_absolute(dst)
			DirAccess.rename_absolute(src, dst)
			var ms := src.get_basename() + ".meta"
			var md := dst.get_basename() + ".meta"
			if FileAccess.file_exists(ms):
				if FileAccess.file_exists(md):
					DirAccess.remove_absolute(md)
				DirAccess.rename_absolute(ms, md)


static func load_world(slot: String, file: String = "world.sav") -> Dictionary:
	return read_envelope(world_dir(slot).path_join(file), "world", true)


## [{slot, file, meta}], newest first.
static func list_world_saves() -> Array:
	var out := []
	var d := DirAccess.open(WORLDS_DIR)
	if d == null:
		return out
	for slot in d.get_directories():
		for meta_path in list_files(WORLDS_DIR.path_join(slot), ".meta"):
			var r := read_envelope(meta_path, "world_meta")
			if r["ok"]:
				out.append({"slot": slot, "file": meta_path.get_file().get_basename() + ".sav", "meta": r["data"]})
	out.sort_custom(func(a, b): return str(a["meta"].get("saved_at", "")) > str(b["meta"].get("saved_at", "")))
	return out


static func delete_world(slot: String) -> void:
	var dir := world_dir(slot)
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
