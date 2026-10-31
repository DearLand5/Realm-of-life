class_name AndroidImmersive
extends Node
## Keeps the Android status and navigation bars hidden ("sticky" immersive
## mode: a swipe from the edge shows them briefly, then they hide again).
##
## Godot's own fullscreen mode skips re-applying immersive mode once it thinks
## it is on, so on some devices the bars came back on every touch and stayed.
## This node talks to the activity window directly through AndroidRuntime
## (on the UI thread) and re-applies the mode at start, on focus / resume and
## after touches. No-op on other platforms.

## Minimum time between two re-applications triggered by touches (s).
const TOUCH_REAPPLY_INTERVAL := 2.0
## View.SYSTEM_UI_FLAG_*: LAYOUT_STABLE | LAYOUT_HIDE_NAVIGATION |
## LAYOUT_FULLSCREEN | HIDE_NAVIGATION | FULLSCREEN | IMMERSIVE_STICKY.
const LEGACY_FLAGS := 0x100 | 0x200 | 0x400 | 0x2 | 0x4 | 0x1000
## WindowInsets.Type.statusBars() | navigationBars() | captionBar().
const SYSTEM_BARS := 1 | 2 | 4
## WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE.
const BEHAVIOR_TRANSIENT_BY_SWIPE := 2

var _runtime: Object
var _activity: Object
var _runnable: Object
var _last_apply := -100.0


func _ready() -> void:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		set_process_input(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_runtime = Engine.get_singleton("AndroidRuntime")
	_activity = _runtime.call("getActivity") if _runtime != null else null
	if _activity != null:
		_runnable = _runtime.call("createRunnableFromGodotCallable", _hide_bars_on_ui_thread)
	# Once now and once after the first frames (the window may not be ready yet).
	apply()
	get_tree().create_timer(0.5).timeout.connect(apply)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN \
			or what == NOTIFICATION_WM_SIZE_CHANGED:
		apply()


func _input(event: InputEvent) -> void:
	var t := event as InputEventScreenTouch
	if t != null and not t.pressed and _now() - _last_apply > TOUCH_REAPPLY_INTERVAL:
		apply()


## Hides the system bars (posted to the Android UI thread).
func apply() -> void:
	if _activity == null or _runnable == null:
		return
	_last_apply = _now()
	_activity.call("runOnUiThread", _runnable)


func _hide_bars_on_ui_thread() -> void:
	var window: Object = _activity.call("getWindow")
	if window == null:
		return
	var decor: Object = window.call("getDecorView")
	if decor != null:
		decor.call("setSystemUiVisibility", LEGACY_FLAGS)
	if _api_level() >= 30:
		var ctrl: Object = window.call("getInsetsController")
		if ctrl != null:
			ctrl.call("setSystemBarsBehavior", BEHAVIOR_TRANSIENT_BY_SWIPE)
			ctrl.call("hide", SYSTEM_BARS)


## Android 11 (API 30) introduced WindowInsetsController.
static func _api_level() -> int:
	var major := int(OS.get_version().get_slice(".", 0))
	return 30 if major >= 11 else 0


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
