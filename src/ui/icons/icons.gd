class_name Icons
extends RefCounted
## Procedural vector icon set (no image files; crisp at any size).
##
##   Icons.draw(self, &"play", Rect2(0, 0, 32, 32), Color.WHITE)   # inside _draw()
##   button.icon = Icons.texture(&"save")                           # any Texture2D slot
##   var v := IconView.make(&"leaf", 40)                            # standalone Control
##
## Icons are designed on a 24×24 grid with ~2-unit strokes; `stroke` scales the
## line weight (1.0 = default). Names: `Icons.names()`; aliases (flask → test,
## book → library, question → help, ...) resolve through `resolve()`.

const ALIASES := {
	&"flask": &"test", &"book": &"library", &"question": &"help", &"hamburger": &"menu",
	&"pencil": &"edit", &"first_person": &"person", &"third_person": &"follow", &"random": &"dice",
	&"delete": &"trash", &"ok": &"check", &"world": &"globe", &"fly": &"bird", &"rest": &"zzz",
	&"call": &"sound", &"attack": &"claw", &"mate": &"heart", &"interact": &"pointer", &"eat": &"leaf",
	&"drink": &"drop", &"ascend": &"chevron_up", &"descend": &"chevron_down", &"fly_toggle": &"bird",
	&"time": &"clock", &"stats": &"chart", &"temperature": &"thermometer", &"water": &"drop",
	&"vegetation": &"tree", &"relief": &"mountain", &"atom": &"experiment",
}

static var _names: Array[StringName] = []
static var _warned: Dictionary = {}
static var _painter := IconPainter.new()


static func names() -> Array[StringName]:
	if _names.is_empty():
		_names.append_array(IconSetUI.NAMES)
		_names.append_array(IconSetWorld.NAMES)
	return _names


static func resolve(icon_name: StringName) -> StringName:
	return ALIASES.get(icon_name, icon_name)


static func has(icon_name: StringName) -> bool:
	return names().has(resolve(icon_name))


## Draws an icon into a CanvasItem (call from its `_draw()`).
static func draw(canvas: CanvasItem, icon_name: StringName, rect: Rect2, color: Color, stroke: float = 1.0) -> void:
	draw_rid(canvas.get_canvas_item(), icon_name, rect, color, stroke)


## Draws into a canvas item RID. Returns false (and draws a placeholder) for unknown names.
static func draw_rid(rid: RID, icon_name: StringName, rect: Rect2, color: Color, stroke: float = 1.0) -> bool:
	if not rid.is_valid() or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	var id := resolve(icon_name)
	var side := minf(rect.size.x, rect.size.y)
	# Thin strokes look faint when tiny: keep at least ~1.3 px.
	var units := maxf(2.0 * stroke, 1.3 * IconPainter.GRID / maxf(side, 1.0))
	var p := _painter.setup(rid, rect, color, units)
	if IconSetUI.draw(p, id) or IconSetWorld.draw(p, id):
		return true
	if not _warned.has(id):
		_warned[id] = true
		push_warning("Icons: unknown icon '%s'" % id)
	p.rrect(Rect2(4, 4, 16, 16), 3.0)
	p.disc(Vector2(12, 12), 1.5)
	return false


## A Texture2D that renders the icon as vectors (usable in Button.icon, TabBar, ItemList...).
static func texture(icon_name: StringName, size_px: int = 24, color: Color = Color.WHITE) -> IconTexture:
	return IconTexture.make(icon_name, size_px, color)
