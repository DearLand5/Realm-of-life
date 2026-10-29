extends SceneTree
## UI previews → screenshots (software GL under Xvfb).
##   tools/shot.sh tools/preview_ui.gd -- <what> [out.png]
##   SHOT_RES=720x1280 tools/shot.sh tools/preview_ui.gd -- menu res://screenshots/tmp/menu_portrait.png
## what: menu | new_world | load | library | presets | settings | help | layout | widgets | icons
## Dialogs get sample data (no saves are written).

var _what := "menu"


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	_what = args[0] if args.size() > 0 else "menu"
	var out := args[1] if args.size() > 1 else "res://screenshots/tmp/ui_%s.png" % _what
	var overlay := UIOverlay.ensure()
	if _what in ["widgets", "icons"]:
		overlay.adapt_orientation = false
		get_root().content_scale_size = get_root().size
	await process_frame
	await process_frame
	var portrait := get_root().size.y > get_root().size.x
	if portrait and _what != "icons" and _what != "widgets":
		SafeArea.debug_insets = Vector4(0, 34, 0, 18)
	match _what:
		"widgets":
			_scene(UIGallery.build_widgets())
		"icons":
			_scene(UIGallery.build_icons())
		_:
			var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
			_scene(menu)
			await process_frame
			_open(_what)
	if portrait and _what != "icons" and _what != "widgets":
		_fake_notch()
	for i in 12:
		await process_frame
	if _what == "widgets":
		UIGallery.after_layout(current_scene)
		for i in 4:
			await process_frame
	await ShotUtil.save_viewport(get_root(), ProjectSettings.globalize_path(out))
	quit()


func _scene(n: Node) -> void:
	get_root().add_child(n)
	current_scene = n


func _open(what: String) -> void:
	match what:
		"new_world":
			var d := NewWorldDialog.new()
			d.library_entries = UIGallery.sample_species()
			d.config["seed"] = 482913
			d.dry_run = true
			d.open()
		"load":
			var d2 := LoadDialog.new()
			d2.entries = UIGallery.sample_saves()
			d2.dry_run = true
			d2.open()
		"library", "presets":
			var d3 := SpeciesLibraryDialog.new()
			d3.entries = UIGallery.sample_species()
			d3.start_with_presets = what == "presets"
			d3.dry_run = true
			d3.open()
		"settings":
			SettingsDialog.new().open()
		"help":
			HelpPopup.show_term("число фруда")
		"layout":
			var l := ControlLayout.new()
			LayoutEditor.open_for(l, &"third_person")
		"toasts":
			UIApp.notify("Мир сохранён", &"success")
			UIApp.notify("Мало воды: вид «Лягушка» под угрозой", &"warning")


func _fake_notch() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	get_root().add_child(layer)
	var notch := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.BLACK
	sb.set_corner_radius_all(14)
	notch.add_theme_stylebox_override("panel", sb)
	var w := get_root().get_visible_rect().size.x
	notch.position = Vector2(w * 0.5 - 60, 8)
	notch.size = Vector2(120, 26)
	layer.add_child(notch)
