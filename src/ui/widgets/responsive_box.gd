class_name ResponsiveBox
extends BoxContainer
## Box that lays its children out in a row in landscape and in a column in
## portrait (or below a width breakpoint).
##
##   var rb := ResponsiveBox.new()          # row when the viewport is landscape
##   rb.break_width = 720.0                  # or: row only when own width ≥ 720 (× ui scale)
##   rb.layout_changed.connect(func(vertical): ...)
##
## Signals: layout_changed(vertical: bool)

signal layout_changed(vertical: bool)

## > 0: vertical when the available width is below this (canvas px at ui scale 1).
## 0: follow viewport orientation (portrait → vertical).
@export var break_width: float = 0.0
## Swap the rule (column in landscape, row in portrait).
@export var invert: bool = false


func _ready() -> void:
	get_viewport().size_changed.connect(_update)
	_update()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
		_update.call_deferred()


## True if the given sizes call for a vertical layout (pure; used by _update and tests).
static func wants_vertical(viewport_size: Vector2, available_width: float, bp: float, inverted: bool) -> bool:
	var v := viewport_size.y > viewport_size.x if bp <= 0.0 else available_width < bp
	return v != inverted


func _update() -> void:
	if not is_inside_tree():
		return
	var avail := size.x
	var p := get_parent() as Control
	if avail <= 0.0 and p != null:
		avail = p.size.x
	var v := wants_vertical(get_viewport_rect().size, avail, break_width * UITheme.scale_of(self), invert)
	if v != vertical:
		vertical = v
		layout_changed.emit(v)
