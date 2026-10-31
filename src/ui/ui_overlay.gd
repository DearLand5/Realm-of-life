class_name UIOverlay
extends CanvasLayer
## Persistent UI host that survives scene changes (child of the root window):
##   * themes the root Window, so every scene's Controls get UITheme
##     automatically and re-theme live when settings change;
##   * hosts the dialog layer (ModalDialog.open() default) and a ToastLayer
##     listening to EventBus.notify;
##   * orientation adapter: keeps the short screen side at 720 canvas units in
##     both landscape and portrait (project stretch base is 1280×720, which
##     would otherwise shrink the UI by ~45 % in portrait).
##
##   UIOverlay.ensure()            # call once from any scene's _ready (idempotent)
##   UIOverlay.toasts().show_toast(tr("Готово"), &"success")
##
## Controls placed under your own CanvasLayer do not inherit the Window theme:
## call `UITheme.attach(that_root_control)` for them.

const LAYER := 90

static var _instance: UIOverlay

## Swap content_scale_size with the orientation (see class doc).
var adapt_orientation: bool = true

var root_control: Control
var dialog_layer: Control
var toast_layer: ToastLayer
var _base := Vector2i(1280, 720)


## Returns the overlay, creating it under the root window if needed.
static func ensure() -> UIOverlay:
	if is_instance_valid(_instance):
		return _instance
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var o := UIOverlay.new()
	o.name = "UIOverlay"
	_instance = o
	tree.root.add_child.call_deferred(o)
	return o


static func instance() -> UIOverlay:
	return _instance if is_instance_valid(_instance) else null


## Where modal dialogs go by default (null if no overlay exists).
static func dialog_host() -> Control:
	var o := instance()
	return o.dialog_layer if o != null else null


static func toasts() -> ToastLayer:
	var o := instance()
	return o.toast_layer if o != null else null


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	root_control = Control.new()
	root_control.name = "Root"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)
	dialog_layer = Control.new()
	dialog_layer.name = "Dialogs"
	dialog_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(dialog_layer)
	toast_layer = ToastLayer.new()
	toast_layer.name = "Toasts"
	root_control.add_child(toast_layer)


func _ready() -> void:
	_base = Vector2i(int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))
	UITheme.attach(root_control)
	UITheme.attach(get_tree().root)
	get_tree().root.size_changed.connect(adapt_now)
	adapt_now()
	_sync_perf.call_deferred()
	var atlas := IconAtlas.ensure_built(self)
	if atlas != null:
		atlas.built.connect(_redraw_all)


var _perf: PerfOverlay
var _perf_poll := 0.0


func _process(delta: float) -> void:
	_perf_poll -= delta
	if _perf_poll <= 0.0:
		_perf_poll = 1.0
		_sync_perf()


## Shows / hides the FPS readout to match the "show_perf" setting.
func _sync_perf() -> void:
	var on := bool(UIApp.setting("show_perf", false))
	if on and _perf == null:
		_perf = PerfOverlay.new()
		root_control.add_child(_perf)
	elif not on and _perf != null:
		_perf.queue_free()
		_perf = null


## Icons already drawn as vectors switch to the atlas on their next redraw.
func _redraw_all() -> void:
	for n in get_tree().root.find_children("*", "CanvasItem", true, false):
		(n as CanvasItem).queue_redraw()


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


## Re-evaluates orientation scaling (called automatically on window resize).
func adapt_now() -> void:
	var win := get_tree().root
	if not adapt_orientation or win.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED:
		return
	var want := content_size_for(Vector2(win.size), _base)
	if win.content_scale_size != want:
		win.content_scale_size = want


## Base canvas size for a window: the project base, transposed in portrait.
static func content_size_for(window_size: Vector2, base: Vector2i) -> Vector2i:
	var long_side := maxi(base.x, base.y)
	var short_side := mini(base.x, base.y)
	if window_size.y > window_size.x:
		return Vector2i(short_side, long_side)
	return Vector2i(long_side, short_side)
