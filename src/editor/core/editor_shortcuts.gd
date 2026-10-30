class_name EditorShortcuts
extends RefCounted
## Desktop keyboard shortcuts of the editor (Ctrl+Z/Y undo/redo, Ctrl+C/V/D,
## Ctrl+S, Delete, F = fit, Esc = clear selection). Returns true when handled.


static func handle(ctx: EditorContext, event: InputEvent) -> bool:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return false
	var ctrl := k.ctrl_pressed or k.meta_pressed
	match k.keycode:
		KEY_Z:
			if not ctrl:
				return false
			if k.shift_pressed:
				ctx.doc.redo()
			else:
				ctx.doc.undo()
		KEY_Y:
			if not ctrl:
				return false
			ctx.doc.redo()
		KEY_C:
			if not ctrl:
				return false
			ctx.request(&"copy")
		KEY_V:
			if not ctrl:
				return false
			ctx.request(&"paste")
		KEY_D:
			if not ctrl:
				return false
			ctx.request(&"duplicate")
		KEY_S:
			if not ctrl:
				return false
			ctx.request(&"save")
		KEY_DELETE, KEY_BACKSPACE:
			ctx.request(&"delete")
		KEY_F:
			ctx.request(&"fit")
		KEY_ESCAPE:
			ctx.doc.select(-1)
		_:
			return false
	return true
