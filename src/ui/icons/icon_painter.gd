class_name IconPainter
extends RefCounted
## Immediate-mode vector painter used by `Icons` and `ShapeTexture`.
##
## Draws straight into a canvas item RID through RenderingServer, so it works
## both from a CanvasItem's `_draw()` and from a custom Texture2D's `_draw*`
## virtuals (which is what makes `IconTexture` usable in Buttons, tabs, lists).
## Coordinates are in a 24×24 design grid mapped into the target rect (or in
## pixels after `setup_pixels`). Strokes are anti-aliased; when the colour is
## opaque, strokes get round caps/joins and fills an anti-aliased rim.

const GRID := 24.0

var rid: RID
var origin := Vector2.ZERO
## Pixels per design unit.
var k: float = 1.0
var color := Color.WHITE
## Stroke width in design units.
var width: float = 2.0


## Maps the 24-unit grid into the largest centred square of `rect`.
func setup(target: RID, rect: Rect2, col: Color, stroke_units: float = 2.0) -> IconPainter:
	rid = target
	var side := minf(absf(rect.size.x), absf(rect.size.y))
	k = side / GRID
	origin = rect.position + (rect.size.abs() - Vector2(side, side)) * 0.5
	color = col
	width = stroke_units
	return self


## 1 unit = 1 pixel, origin at `pos`.
func setup_pixels(target: RID, pos: Vector2, col: Color, stroke_px: float = 2.0) -> IconPainter:
	rid = target
	k = 1.0
	origin = pos
	color = col
	width = stroke_px
	return self


func p(v: Vector2) -> Vector2:
	return origin + v * k


func stroke_px() -> float:
	return maxf(width * k, 1.0)


func _opaque() -> bool:
	return color.a >= 0.99


# --- Strokes -------------------------------------------------------------------

func line(a: Vector2, b: Vector2) -> void:
	var w := stroke_px()
	RenderingServer.canvas_item_add_line(rid, p(a), p(b), color, w, true)
	if _opaque() and w > 1.6:
		RenderingServer.canvas_item_add_circle(rid, p(a), w * 0.5, color, true)
		RenderingServer.canvas_item_add_circle(rid, p(b), w * 0.5, color, true)


## Polyline through `pts` (design units); `closed` joins the last point to the first.
func poly(pts: PackedVector2Array, closed: bool = false) -> void:
	if pts.size() < 2:
		return
	var w := stroke_px()
	var tp := PackedVector2Array()
	for v in pts:
		tp.append(p(v))
	if closed:
		tp.append(tp[0])
	RenderingServer.canvas_item_add_polyline(rid, tp, PackedColorArray([color]), w, true)
	if _opaque() and w > 1.6:
		var r := w * 0.5
		# Round joins only where the direction actually turns (cheap and clean).
		for i in tp.size():
			if closed or i == 0 or i == tp.size() - 1 or _is_corner(tp, i):
				RenderingServer.canvas_item_add_circle(rid, tp[i], r, color, true)


func _is_corner(tp: PackedVector2Array, i: int) -> bool:
	if i <= 0 or i >= tp.size() - 1:
		return true
	var d0 := (tp[i] - tp[i - 1]).normalized()
	var d1 := (tp[i + 1] - tp[i]).normalized()
	return d0.dot(d1) < 0.94


func ring(c: Vector2, r: float) -> void:
	poly(arc_points(c, r, 0.0, TAU), true)


## Arc from angle a0 to a1 (radians, screen space: 0 = +x, PI/2 = down).
func arc(c: Vector2, r: float, a0: float, a1: float) -> void:
	poly(arc_points(c, r, a0, a1))


func ellipse(c: Vector2, rx: float, ry: float, rot: float = 0.0) -> void:
	var pts := PackedVector2Array()
	var n := 40
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	poly(pts, true)


func rrect(r: Rect2, radius: float) -> void:
	poly(rrect_points(r, radius), true)


## Arrow head (two strokes) at `tip`, pointing along `dir`.
func arrow_head(tip: Vector2, dir: Vector2, size: float = 4.5, spread_deg: float = 42.0) -> void:
	var d := dir.normalized()
	var a := tip - d.rotated(deg_to_rad(spread_deg)) * size
	var b := tip - d.rotated(-deg_to_rad(spread_deg)) * size
	poly(PackedVector2Array([a, tip, b]))


func dashed_line(a: Vector2, b: Vector2, dash: float = 2.0, gap: float = 2.0) -> void:
	var len_total := a.distance_to(b)
	var d := (b - a) / maxf(len_total, 0.001)
	var t := 0.0
	while t < len_total:
		line(a + d * t, a + d * minf(t + dash, len_total))
		t += dash + gap


# --- Fills ------------------------------------------------------------------------

## Filled simple polygon (convex or concave, not self-intersecting).
func fill(pts: PackedVector2Array) -> void:
	if pts.size() < 3:
		return
	var tp := PackedVector2Array()
	for v in pts:
		tp.append(p(v))
	if Geometry2D.triangulate_polygon(tp).is_empty():
		return
	RenderingServer.canvas_item_add_polygon(rid, tp, PackedColorArray([color]))
	if _opaque():
		var rim := tp.duplicate()
		rim.append(tp[0])
		RenderingServer.canvas_item_add_polyline(rid, rim, PackedColorArray([color]), 1.0, true)


func disc(c: Vector2, r: float) -> void:
	RenderingServer.canvas_item_add_circle(rid, p(c), r * k, color, true)


func frrect(r: Rect2, radius: float) -> void:
	fill(rrect_points(r, radius))


# --- Geometry helpers (design units) ----------------------------------------------

static func arc_points(c: Vector2, r: float, a0: float, a1: float, n: int = -1) -> PackedVector2Array:
	if n < 0:
		n = clampi(int(absf(a1 - a0) / TAU * 40.0) + 2, 3, 48)
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / float(n))
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


static func rrect_points(r: Rect2, radius: float) -> PackedVector2Array:
	var rad := minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	if rad <= 0.01:
		pts.append_array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		return pts
	var corners := [
		[Vector2(r.end.x - rad, r.position.y + rad), -PI * 0.5],
		[Vector2(r.end.x - rad, r.end.y - rad), 0.0],
		[Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5],
		[Vector2(r.position.x + rad, r.position.y + rad), PI],
	]
	for cdef in corners:
		var a0: float = cdef[1]
		pts.append_array(arc_points(cdef[0], rad, a0, a0 + PI * 0.5, 6))
	return pts


static func quad_points(a: Vector2, ctrl: Vector2, b: Vector2, n: int = 12) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / float(n)
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	return pts


## Angles (relative to c1) of the two intersection points of two circles, or [] if none.
static func circle_intersection_angles(c1: Vector2, r1: float, c2: Vector2, r2: float) -> PackedFloat32Array:
	var d := c1.distance_to(c2)
	if d <= 0.0001 or d > r1 + r2 or d < absf(r1 - r2):
		return PackedFloat32Array()
	var a := (r1 * r1 - r2 * r2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(r1 * r1 - a * a, 0.0))
	var base := (c2 - c1).angle()
	var spread := atan2(h, a)
	return PackedFloat32Array([base - spread, base + spread])


static func star_points(c: Vector2, r_out: float, r_in: float, points: int = 5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var a := -PI * 0.5 + PI * float(i) / float(points)
		pts.append(c + Vector2(cos(a), sin(a)) * (r_out if i % 2 == 0 else r_in))
	return pts
