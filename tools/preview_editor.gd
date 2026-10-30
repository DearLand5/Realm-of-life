extends SceneTree
## Creature editor screenshots (software GL under Xvfb).
##   tools/shot.sh tools/preview_editor.gd -- <mode> <preset> <select_kind|-> <out.png> [extra]
##   SHOT_RES=720x1280 tools/shot.sh tools/preview_editor.gd -- limbs predator limb res://screenshots/tmp/ed.png
## mode: shape|anatomy|limbs|covering|senses|organs|biology|genetics|diagnostics
## extra: xray | edit | scroll=<px> | test | seg=<n> | collapse

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "shape"
	var preset := args[1] if args.size() > 1 else "predator"
	var kind := args[2] if args.size() > 2 else "-"
	var out := args[3] if args.size() > 3 else "res://screenshots/tmp/editor_%s.png" % mode
	var extra := args[4] if args.size() > 4 else ""
	UIOverlay.ensure()
	await process_frame
	var portrait := get_root().size.y > get_root().size.x
	if portrait:
		SafeArea.debug_insets = Vector4(0, 34, 0, 18)
	var game := UIApp.game()
	game.set("pending", {"preset": preset})
	var ed: CreatureEditor = load("res://scenes/creature_editor.tscn").instantiate()
	get_root().add_child(ed)
	current_scene = ed
	for i in 6:
		await process_frame
	ed.ctx.set_mode(StringName(mode))
	if kind != "-":
		var parts := ed.doc.plan().parts_of_kind(StringName(kind))
		if not parts.is_empty():
			ed.doc.select(parts[0].id)
	if extra == "xray":
		ed.ctx.set_xray(true)
	if extra == "edit":
		ed.ctx.set_edit_gesture(true)
	if extra == "test":
		ed.ctx.request(&"test")
	if extra == "collapse":
		ed._sheet_state = 2
		ed._layout()
	if extra.begins_with("seg="):
		ed.ctx.set_segment(int(extra.get_slice("=", 1)))
	for i in 40:
		await process_frame
	if extra.begins_with("scroll="):
		ed._scroll.scroll_vertical = int(extra.get_slice("=", 1))
		for i in 4:
			await process_frame
	if portrait:
		_fake_notch()
	for i in 6:
		await process_frame
	await ShotUtil.save_viewport(get_root(), ProjectSettings.globalize_path(out))
	quit()


func _fake_notch() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	get_root().add_child(layer)
	var notch := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.BLACK
	sb.set_corner_radius_all(14)
	notch.add_theme_stylebox_override("panel", sb)
	notch.position = Vector2(get_root().get_visible_rect().size.x * 0.5 - 60, 8)
	notch.size = Vector2(120, 26)
	layer.add_child(notch)
