class_name LogDialog
extends ModalDialog
## «Журнал»: the tail of the engine log of the previous and the current launch
## (user://logs, written on the device), with a copy button so a player can
## send it in a bug report. Opened from Settings and after an editor crash.

const LOG_DIR := "user://logs"
const TAIL_LINES := 80

## Shown above the log (e.g. why the dialog opened).
var intro: String = ""
## Shows this text instead of the log (other reports, e.g. the benchmark).
var report: String = ""


static func show_report(title_text: String, text: String) -> LogDialog:
	var d := LogDialog.new()
	d.report = text
	d.title = title_text
	d.open()
	return d


static func show_log(intro_text: String = "") -> LogDialog:
	var d := LogDialog.new()
	d.intro = intro_text
	d.open()
	return d


func _ready() -> void:
	if title == "":
		title = tr("Журнал")
	icon_name = &"info"
	size_class = SizeClass.LARGE
	expand_content = true
	if intro != "":
		var l := Label.new()
		l.text = intro
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(l)
	var text := report if report != "" else report_text()
	var box := TextEdit.new()
	box.text = text
	box.editable = false
	box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.custom_minimum_size.y = 320
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(box)
	var copy := add_button(&"copy", tr("Скопировать"), &"AccentButton", &"copy", false)
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(text)
		UIApp.notify(tr("Журнал скопирован"), &"success"))
	add_button(&"cancel", tr("Закрыть"))
	super()
	# The end of the log (what happened last) matters most.
	(func() -> void: box.scroll_vertical = box.get_line_count()).call_deferred()


## Device info plus the tails of the previous and the current log.
static func report_text() -> String:
	var parts := PackedStringArray()
	parts.append("Realm of Life %s · %s %s · %s · %s · %d ядер" % [
		str(ProjectSettings.get_setting("application/config/version", "?")), OS.get_name(), OS.get_version(),
		OS.get_model_name(), RenderingServer.get_video_adapter_name(), OS.get_processor_count()])
	parts.append("Рендерер: %s, %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_api_version()])
	var prev := previous_log_path()
	if prev != "":
		parts.append("\n=== Прошлый запуск (%s) ===" % prev.get_file())
		parts.append(_tail(prev))
	parts.append("\n=== Текущий запуск ===")
	parts.append(_tail(LOG_DIR + "/godot.log"))
	return "\n".join(parts)


## Newest rotated log (the launch before this one), or "".
static func previous_log_path() -> String:
	var d := DirAccess.open(LOG_DIR)
	if d == null:
		return ""
	var best := ""
	var best_t := -1
	for f in d.get_files():
		if f == "godot.log" or not f.ends_with(".log"):
			continue
		var p := LOG_DIR + "/" + f
		var t := FileAccess.get_modified_time(p)
		if t > best_t:
			best_t = t
			best = p
	return best


static func _tail(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "(нет файла)"
	var lines := f.get_as_text().split("\n")
	var start := maxi(0, lines.size() - TAIL_LINES)
	return "\n".join(lines.slice(start))
