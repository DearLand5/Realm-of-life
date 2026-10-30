class_name IconView
extends Control
## A Control that shows one vector icon, centred and scaled to fit.
## Colour defaults to the theme text colour (follows live theme changes).
##
##   var v := IconView.make(&"leaf", 32)
##   v.color_role = &"accent"      # any UIPalette token name

## Icon id (see `Icons.names()`).
@export var icon: StringName = &"info":
	set(v):
		icon = v
		queue_redraw()
## Explicit colour; used when `color_role` is empty.
@export var color: Color = Color.WHITE:
	set(v):
		color = v
		color_role = &""
		queue_redraw()
## Theme colour token (type "Realm"), e.g. &"text", &"accent", &"text_dim".
@export var color_role: StringName = &"text":
	set(v):
		color_role = v
		queue_redraw()
## Stroke weight multiplier.
@export var stroke: float = 1.0:
	set(v):
		stroke = v
		queue_redraw()


static func make(icon_name: StringName, size_px: float = 24.0, role: StringName = &"text") -> IconView:
	var v := IconView.new()
	v.icon = icon_name
	v.color_role = role
	v.custom_minimum_size = Vector2(size_px, size_px)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func resolved_color() -> Color:
	if color_role != &"" and has_theme_color(color_role, UITheme.TYPE):
		return get_theme_color(color_role, UITheme.TYPE)
	return color


func _draw() -> void:
	Icons.draw(self, icon, Rect2(Vector2.ZERO, size), resolved_color(), stroke)
