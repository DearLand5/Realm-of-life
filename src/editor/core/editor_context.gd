class_name EditorContext
extends RefCounted
## Shared state of one editor session: the document plus view state (mode,
## active segment, gesture mode, toggles). Mode pages, the stage and the
## gesture layer talk to each other only through this object, never directly.
##
## Requests that need the editor shell (dialogs, scene changes) go through
## `request(action, args)`; the editor root listens to `action_requested`.

signal mode_changed(mode: StringName)
signal segment_changed(index: int)
signal view_changed
signal action_requested(action: StringName, args: Dictionary)
signal tutorial_event(id: StringName)
signal toast(text: String, level: StringName)
## Ask the stage to frame a part.
signal stage_focus(part_id: int)

## id, icon, label, tooltip — order = tab order.
const MODES: Array[Dictionary] = [
	{"id": &"shape", "icon": &"scale", "label": "Форма", "tip": "Туловище, шея, голова, хвост, панцирь"},
	{"id": &"anatomy", "icon": &"skull", "label": "Скелет", "tip": "Суставы, мышцы, внутренние органы"},
	{"id": &"limbs", "icon": &"paw", "label": "Конечности", "short": "Лапы", "tip": "Ноги, плавники, крылья, щупальца"},
	{"id": &"covering", "icon": &"layers", "label": "Покровы", "tip": "Кожа, чешуя, шерсть, перья, окраска"},
	{"id": &"senses", "icon": &"eye", "label": "Чувства", "tip": "Глаза, уши, нос, усики, сенсоры"},
	{"id": &"organs", "icon": &"claw", "label": "Органы", "tip": "Рты, рога, шипы, когти, жабры, железы"},
	{"id": &"biology", "icon": &"leaf", "label": "Биология", "tip": "Среда, питание, размножение, обмен веществ"},
	{"id": &"genetics", "icon": &"dna", "label": "Гены", "tip": "Наследуемые признаки и аллели"},
	{"id": &"diagnostics", "icon": &"chart", "label": "Проверка", "tip": "Анатомическая диагностика"},
]

var doc: EditorDocument
var prefs: EditorPrefs
var mode: StringName = &"shape"
## Active segment of the selected spine part (per-segment editing, handles).
var segment: int = 0
## false: one finger orbits the camera; true: one finger drags parts.
var edit_gesture: bool = false
var xray: bool = false
var snapping: bool = true
var show_fov: bool = true
var show_handles: bool = true
## Show the explanation under every slider.
var hints: bool = false
## Compiled instance (index in AnatomyModel.instances) the user last touched
## for the selected part: handles and drags act on that copy (-1 = first).
var selected_instance: int = -1
## Part highlighted by a diagnostics row (-1 = none).
var hint_part: int = -1


func _init(d: EditorDocument = null, p: EditorPrefs = null) -> void:
	doc = d if d != null else EditorDocument.new()
	prefs = p if p != null else EditorPrefs.new()
	snapping = prefs.snapping


func set_mode(m: StringName) -> void:
	if m == mode:
		return
	mode = m
	mode_changed.emit(m)
	view_changed.emit()


func set_segment(i: int) -> void:
	var part := doc.selected_part()
	var n := part.segments.size() if part != null else 0
	var ni := clampi(i, 0, maxi(n - 1, 0))
	if ni == segment:
		return
	segment = ni
	segment_changed.emit(ni)


func set_edit_gesture(on: bool) -> void:
	edit_gesture = on
	view_changed.emit()


func set_xray(on: bool) -> void:
	xray = on
	view_changed.emit()


func set_snapping(on: bool) -> void:
	snapping = on
	prefs.snapping = on
	prefs.save()
	view_changed.emit()


func set_show_fov(on: bool) -> void:
	show_fov = on
	view_changed.emit()


func request(action: StringName, args: Dictionary = {}) -> void:
	action_requested.emit(action, args)


func notify(text: String, level: StringName = &"info") -> void:
	toast.emit(text, level)


## Active segment clamped to the selected part.
func active_segment() -> int:
	var part := doc.selected_part()
	if part == null or part.segments.is_empty():
		return 0
	return clampi(segment, 0, part.segments.size() - 1)


## Display name of a part ("Лапа" or its kind label).
static func part_name(p: BodyPart) -> String:
	if p == null:
		return "—"
	return p.label if p.label != "" else PartSchema.label(p.kind)


## Ids of the current selection (plain Array for closures).
func actions_selected() -> Array:
	var out: Array = []
	for id in doc.selection:
		out.append(id)
	return out
