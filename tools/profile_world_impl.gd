extends Node
## Opens a new world, waits for agents, then prints render and script costs.

func _ready() -> void:
	Game.pending = {"new_world": {"seed": 777, "size": 256.0, "procedural_species": 6, "name": "Профиль"}}
	get_tree().change_scene_to_file("res://scenes/world.tscn")
	var w: Node = null
	for i in 900:
		await get_tree().process_frame
		w = Game.service(&"world")
		if w != null and i > 200:
			break
	if w == null:
		print("no world")
		get_tree().quit()
		return
	for i in 120:
		await get_tree().process_frame
	await _report("overview", w)
	if w.agents.live_count() > 0:
		var a: Node3D = w.agents.agents[0]
		w.cam.focus(a.global_position, 12.0, true)
		for i in 120:
			await get_tree().process_frame
		await _report("close", w)
	get_tree().quit()


func _report(label: String, w: Node) -> void:
	w.profile.clear()
	var f0 := Engine.get_process_frames()
	var t0 := Time.get_ticks_usec()
	for i in 60:
		await get_tree().process_frame
	var frames := float(Engine.get_process_frames() - f0)
	print("[%s] frame %.1f ms" % [label, (Time.get_ticks_usec() - t0) / 1000.0 / frames])
	for k in w.profile:
		print("   %-14s %.2f ms/frame" % [k, w.profile[k] / 1000.0 / frames])
	await _nodes(w)
	print("[%s] agents %d  draws %d  objs %d  prims %d  process %.1f ms  physics %.1f ms  fps %d  quality %s" % [label,
		w.agents.live_count(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_FPS), str(w.perf.get("tier_name") if w.perf.get("tier_name") != null else "")])


## Frame time with each processing script type switched off in turn.
func _nodes(w: Node) -> void:
	var groups := {}
	for n in get_tree().root.find_children("*", "", true, false):
		if n.is_processing() or n.is_physics_processing():
			var sc: Script = n.get_script()
			var k: String = sc.resource_path.get_file() if sc != null else n.get_class()
			if not groups.has(k):
				groups[k] = []
			groups[k].append(n)
	var base := await _avg(30)
	print("   base %.1f ms" % base)
	for k in groups:
		for n in groups[k]:
			n.set_process(false)
			n.set_physics_process(false)
		var t := await _avg(30)
		for n in groups[k]:
			if is_instance_valid(n):
				n.set_process(true)
				n.set_physics_process(true)
		if base - t > 1.0:
			print("   without %-28s x%-3d saves %.1f ms" % [k, groups[k].size(), base - t])


func _avg(n: int) -> float:
	var t := Time.get_ticks_usec()
	for i in n:
		await get_tree().process_frame
	return (Time.get_ticks_usec() - t) / 1000.0 / n
