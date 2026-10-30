class_name EditorCrashGuard
extends RefCounted
## Detects an editor that crashed while opening: a flag file is written when
## the editor starts loading and removed once the first creature mesh is on
## screen. A flag left over from the previous launch means that load never
## finished, so the editor opens in safe mode (lighter idle mesh LOD).

const FLAG_PATH := "user://editor_loading.flag"
## Idle mesh LOD in safe mode (normal: EditorStage.IDLE_LOD).
const SAFE_IDLE_LOD := 1


## Marks the start of a load; returns true when the previous load crashed.
static func begin() -> bool:
	var crashed := FileAccess.file_exists(FLAG_PATH)
	var f := FileAccess.open(FLAG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(Time.get_datetime_string_from_system())
		f.close()
	return crashed


## The editor finished loading: clears the flag.
static func done() -> void:
	if FileAccess.file_exists(FLAG_PATH):
		DirAccess.remove_absolute(FLAG_PATH)
