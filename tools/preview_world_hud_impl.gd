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
	print("agents: ", w.agents.live_count(), " runtime: ", w.agents.has_runtime(), " focus ", w.cam.pivot, " stat ", w.perf.statistical_mode, " budget ", w.perf.agent_budget())
	var act := 0
	for s in w.state.pop.sectors:
		if w.agents.is_active_sector(s.index):
			act += 1
			if s.total_count() > 0: print(" active sector ", s.index, " count ", s.total_count())
	print("active ", act)
	if w.agents.live_count() > 0:
		var a: Node3D = w.agents.agents[0]
		w.cam.focus(a.global_position, 9.0, true)
		w.select(a)
		for i in 60:
			await get_tree().process_frame
		print("status: ", a.get_status())
	await ShotUtil.save_viewport(get_tree().root, ProjectSettings.globalize_path(prefix + "_main.png"))
	if page == "possess" or page == "first":
		w.possess(&"third_person" if page == "possess" else &"first_person")
		for i in 120:
			await get_tree().process_frame
		await ShotUtil.save_viewport(get_tree().root, ProjectSettings.globalize_path(prefix + "_" + page + ".png"))
		w.release_control()
		for i in 10:
			await get_tree().process_frame
		print("released ok, controller=", w.controller)
	elif page != "":
		w.hud.open_page(StringName(page))
		for i in 20:
			await get_tree().process_frame
		await ShotUtil.save_viewport(get_tree().root, ProjectSettings.globalize_path(prefix + "_" + page + ".png"))
	get_tree().quit()
