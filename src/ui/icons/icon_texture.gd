class_name IconTexture
extends Texture2D
## Vector icon as a Texture2D: draws through `Icons` whenever a Control draws
## the texture, so it stays crisp at any size and works in every texture slot
## that uses `draw_texture*` (Button.icon, TabBar, ItemList, PopupMenu...).
## Buttons tint it with their theme icon colours (`icon_normal_color` etc.), so
## keep `color` white for themed buttons.
##
##   var t := IconTexture.make(&"save", 28)

## Icon id (see `Icons.names()`).
var icon: StringName = &"info":
	set(v):
		icon = v
		emit_changed()
## Nominal size in pixels (the size controls see via get_size()).
var size_px: int = 24:
	set(v):
		size_px = maxi(v, 1)
		emit_changed()
var color: Color = Color.WHITE:
	set(v):
		color = v
		emit_changed()
## Stroke weight multiplier (1 = default).
var stroke: float = 1.0:
	set(v):
		stroke = v
		emit_changed()


static func make(icon_name: StringName, px: int = 24, col: Color = Color.WHITE) -> IconTexture:
	var t := IconTexture.new()
	t.icon = icon_name
	t.size_px = px
	t.color = col
	return t


func _get_width() -> int:
	return size_px


func _get_height() -> int:
	return size_px


func _has_alpha() -> bool:
	return true


func _is_pixel_opaque(_x: int, _y: int) -> bool:
	return true


func _draw(to_canvas_item: RID, pos: Vector2, modulate: Color, _transpose: bool) -> void:
	Icons.draw_rid(to_canvas_item, icon, Rect2(pos, Vector2(size_px, size_px)), color * modulate, stroke)


func _draw_rect(to_canvas_item: RID, rect: Rect2, _tile: bool, modulate: Color, _transpose: bool) -> void:
	Icons.draw_rid(to_canvas_item, icon, rect, color * modulate, stroke)


func _draw_rect_region(to_canvas_item: RID, rect: Rect2, _src_rect: Rect2, modulate: Color, _transpose: bool, _clip_uv: bool) -> void:
	Icons.draw_rid(to_canvas_item, icon, rect, color * modulate, stroke)
