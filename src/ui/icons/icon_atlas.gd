class_name IconAtlas
extends Node
## Rasterises every vector icon once into a mipmapped texture atlas, after
## which `Icons.draw_rid` draws an icon as one textured quad instead of dozens
## of antialiased lines and arcs. Vector icons cost thousands of draw calls per
## frame on a full screen of UI — the main frame-time cost on phones.
##
##   IconAtlas.ensure_built(parent)   # once, from UIOverlay; redraws the UI when done
##   IconAtlas.region(id)             # atlas pixel rect of an icon, or an empty Rect2

signal built

## Cell size in atlas pixels; the icon fills the cell minus PAD on each side.
const CELL := 96
const PAD := 8
const COLUMNS := 12

static var texture: Texture2D = null
static var _regions: Dictionary = {}
static var _building := false


static func ready() -> bool:
	return texture != null


static func region(id: StringName) -> Rect2:
	return _regions.get(id, Rect2())


## Starts the one-time build under `parent` (no-op headless or when done).
static func ensure_built(parent: Node) -> IconAtlas:
	if texture != null or _building or DisplayServer.get_name() == "headless":
		return null
	_building = true
	var a := IconAtlas.new()
	a.name = "IconAtlas"
	parent.add_child(a)
	return a


func _ready() -> void:
	var ids := Icons.names()
	var rows := int(ceil(float(ids.size()) / COLUMNS))
	var vp := SubViewport.new()
	vp.size = Vector2i(COLUMNS * CELL, rows * CELL)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var canvas := _Sheet.new()
	canvas.ids = ids
	vp.add_child(canvas)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img != null and not img.is_empty():
		img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		texture = ImageTexture.create_from_image(img)
		for i in ids.size():
			var cell := Vector2(i % COLUMNS, i / COLUMNS) * CELL
			_regions[ids[i]] = Rect2(cell + Vector2(PAD, PAD), Vector2(CELL - PAD * 2, CELL - PAD * 2))
	_building = false
	built.emit()
	queue_free()


class _Sheet:
	extends Node2D
	var ids: Array[StringName] = []

	func _draw() -> void:
		for i in ids.size():
			var cell := Vector2(i % IconAtlas.COLUMNS, i / IconAtlas.COLUMNS) * IconAtlas.CELL
			var r := Rect2(cell + Vector2(IconAtlas.PAD, IconAtlas.PAD), Vector2.ONE * (IconAtlas.CELL - IconAtlas.PAD * 2))
			Icons.draw_vector(get_canvas_item(), ids[i], r, Color.WHITE)
