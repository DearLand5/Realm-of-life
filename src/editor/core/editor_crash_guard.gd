class_name EditorCrashGuard
extends RefCounted
## Detects an editor session that crashed: a flag file exists while the editor
## is open in the foreground and is removed when it closes normally or the app
## goes to the background. A flag left over from the previous launch means the
## app died inside the editor, so the editor opens in safe mode (lighter mesh,
## no shadow map) and shows the log for a bug report.

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


## The editor closed normally (or the app was backgrounded): clears the flag.
static func done() -> void:
	if FileAccess.file_exists(FLAG_PATH):
		DirAccess.remove_absolute(FLAG_PATH)
