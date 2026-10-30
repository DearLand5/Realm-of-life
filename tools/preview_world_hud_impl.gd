extends Node

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix := args[0] if args.size() > 0 else "res://screenshots/tmp/world_hud"
	var page := args[1] if args.size() > 1 else ""
	Game.pending = {"new_world": {"seed": 777, "size": 256.0, "procedural_species": 6, "name": "Превью"}}
	get_tree().change_scene_to_file("res://scenes/world.tscn")
	for i in 30:
		await get_tree().process_frame
	var w: Node = Game.service(&"world")
	var t := 0
	while w == null and t < 600:
		await get_tree().process_frame
		w = Game.service(&"world")
		t += 1
	for i in 90:
		await get_tree().process_frame
	await ShotUtil.save_viewport(get_tree().root, ProjectSettings.globalize_path(prefix + "_main.png"))
	if page != "":
		w.hud.open_page(StringName(page))
		for i in 20:
			await get_tree().process_frame
		await ShotUtil.save_viewport(get_tree().root, ProjectSettings.globalize_path(prefix + "_" + page + ".png"))
	get_tree().quit()
