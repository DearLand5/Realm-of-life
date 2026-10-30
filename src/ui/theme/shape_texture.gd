class_name ShapeTexture
extends Texture2D
## Procedural vector textures for theme slots that need icons: slider
## grabbers, switch tracks, check boxes, radio buttons, drop-down arrows.
## Drawn through RenderingServer each time, so they scale with the UI.

enum Kind { GRABBER, SWITCH_ON, SWITCH_OFF, CHECK_ON, CHECK_OFF, RADIO_ON, RADIO_OFF, ARROW_DOWN, ARROW_RIGHT, CLOSE, BLANK }

var kind: Kind = Kind.GRABBER
var size_px := Vector2i(24, 24)
## Main fill (track / box / knob).
var fill_color := Color.WHITE
## Outline colour (alpha 0 = none).
var border_color := Color.TRANSPARENT
## Mark colour (knob, tick, dot).
var mark_color := Color.BLACK
var border_px: float = 2.0

static var _p := IconPainter.new()


static func make(k: Kind, sz: Vector2i, fill: Color, mark: Color = Color.BLACK, border: Color = Color.TRANSPARENT, border_w: float = 2.0) -> ShapeTexture:
	var t := ShapeTexture.new()
	t.kind = k
	t.size_px = sz
	t.fill_color = fill
	t.mark_color = mark
	t.border_color = border
	t.border_px = border_w
	return t


func _get_width() -> int:
	return size_px.x


func _get_height() -> int:
	return size_px.y


func _has_alpha() -> bool:
	return true


func _draw(rid: RID, pos: Vector2, modulate: Color, _transpose: bool) -> void:
	_paint(rid, Rect2(pos, Vector2(size_px)), modulate)


func _draw_rect(rid: RID, rect: Rect2, _tile: bool, modulate: Color, _transpose: bool) -> void:
	_paint(rid, rect, modulate)


func _draw_rect_region(rid: RID, rect: Rect2, _src: Rect2, modulate: Color, _transpose: bool, _clip: bool) -> void:
	_paint(rid, rect, modulate)


func _paint(rid: RID, r: Rect2, m: Color) -> void:
	var fill := fill_color * m
	var mark := mark_color * m
	var border := border_color * m
	var c := r.get_center()
	var h := minf(r.size.x, r.size.y)
	match kind:
		Kind.GRABBER:
			var rad := h * 0.5 - 1.0
			RenderingServer.canvas_item_add_circle(rid, c + Vector2(0, 1.5), rad, Color(0, 0, 0, 0.25 * m.a), true)
			RenderingServer.canvas_item_add_circle(rid, c, rad, fill, true)
			if border.a > 0.0:
				_p.setup_pixels(rid, Vector2.ZERO, border, border_px).ring(c, rad - border_px * 0.5)
			RenderingServer.canvas_item_add_circle(rid, c, rad * 0.32, mark, true)
		Kind.SWITCH_ON, Kind.SWITCH_OFF:
			var track := Rect2(r.position + Vector2(1, r.size.y * 0.5 - h * 0.42), Vector2(r.size.x - 2, h * 0.84))
			_p.setup_pixels(rid, Vector2.ZERO, fill, 1.0).frrect(track, track.size.y * 0.5)
			if border.a > 0.0:
				_p.setup_pixels(rid, Vector2.ZERO, border, border_px).rrect(track.grow(-border_px * 0.5), track.size.y * 0.5)
			var kr := track.size.y * 0.5 - maxf(3.0, h * 0.09)
			var kx := track.end.x - track.size.y * 0.5 if kind == Kind.SWITCH_ON else track.position.x + track.size.y * 0.5
			RenderingServer.canvas_item_add_circle(rid, Vector2(kx, c.y), kr, mark, true)
		Kind.CHECK_ON, Kind.CHECK_OFF:
			var box := Rect2(c - Vector2(h, h) * 0.42, Vector2(h, h) * 0.84)
			_p.setup_pixels(rid, Vector2.ZERO, fill, 1.0).frrect(box, h * 0.2)
			if border.a > 0.0:
				_p.setup_pixels(rid, Vector2.ZERO, border, border_px).rrect(box.grow(-border_px * 0.5), h * 0.2)
			if kind == Kind.CHECK_ON:
				var q := _p.setup(rid, box.grow(-h * 0.06), mark, 2.6)
				q.poly(PackedVector2Array([Vector2(5.5, 12.5), Vector2(10, 17), Vector2(18.5, 7.5)]))
		Kind.RADIO_ON, Kind.RADIO_OFF:
			var rad := h * 0.42
			RenderingServer.canvas_item_add_circle(rid, c, rad, fill, true)
			if border.a > 0.0:
				_p.setup_pixels(rid, Vector2.ZERO, border, border_px).ring(c, rad - border_px * 0.5)
			if kind == Kind.RADIO_ON:
				RenderingServer.canvas_item_add_circle(rid, c, rad * 0.45, mark, true)
		Kind.ARROW_DOWN:
			_p.setup(rid, r, fill, 2.4).poly(PackedVector2Array([Vector2(6, 9.5), Vector2(12, 15.5), Vector2(18, 9.5)]))
		Kind.ARROW_RIGHT:
			_p.setup(rid, r, fill, 2.4).poly(PackedVector2Array([Vector2(9.5, 6), Vector2(15.5, 12), Vector2(9.5, 18)]))
		Kind.CLOSE:
			var q2 := _p.setup(rid, r, fill, 2.2)
			q2.line(Vector2(7, 7), Vector2(17, 17))
			q2.line(Vector2(17, 7), Vector2(7, 17))
		Kind.BLANK:
			pass
