extends Node
## Opens a world at a typical ground-level view and measures the frame time
## with each visual part switched off in turn. With a software rasteriser the
## differences approximate the relative GPU cost of each part.

const SAMPLES := 12


func _ready() -> void:
	Game.pending = {"new_world": {"seed": 777, "size": 256.0, "procedural_species": 6, "name": "GPU"}}
	get_tree().change_scene_to_file("res://scenes/world.tscn")
	for i in 240:
		await get_tree().process_frame
	var w: Node = Game.service(&"world")
	w.perf.auto_quality = false
	w.time.set_scale_index(0)
	if w.agents.live_count() > 0:
		w.cam.focus((w.agents.agents[0] as Node3D).global_position, 14.0, true)
	for i in 90:
		await get_tree().process_frame
	var vp := get_viewport()
	var base := await _avg()
	print("base %.1f ms  (scale %.2f msaa %d)" % [base, vp.scaling_3d_scale, vp.msaa_3d])
	await _try("terrain", base, func(on: bool) -> void: w.terrain.visible = on)
	await _try("water", base, func(on: bool) -> void: w.water.visible = on)
	await _try("flora", base, func(on: bool) -> void: w.flora.visible = on)
	await _try("creatures", base, func(on: bool) -> void:
		for a in w.agents.agents:
			if is_instance_valid(a): (a as Node3D).visible = on)
	var prims := func() -> int: return int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	print("  primitives %d, draws %d" % [prims.call(), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	var plain := StandardMaterial3D.new()
	plain.vertex_color_use_as_albedo = true
	var tmat: Material = w.terrain.material
	await _try("terrain shader", base, func(on: bool) -> void:
		for mi in w.terrain.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = null if on else plain)
	for part in ["terrain", "flora", "water"]:
		var node: Node = w.get(part)
		var before: int = prims.call()
		node.visible = false
		await _avg()
		print("  %s primitives ≈ %d" % [part, before - prims.call()])
		node.visible = true
		await _avg()
	await _try("sun shadow", base, func(on: bool) -> void: w.day_night.sun.shadow_enabled = on)
	await _try("msaa", base, func(on: bool) -> void: vp.msaa_3d = Viewport.MSAA_2X if on else Viewport.MSAA_DISABLED)
	await _try("weather fx", base, func(on: bool) -> void:
		for n in w.find_children("*", "GPUParticles3D", true, false): (n as Node3D).visible = on
		for n in w.find_children("*", "CPUParticles3D", true, false): (n as Node3D).visible = on)
	await _try("ui", base, func(on: bool) -> void: w.hud.visible = on)
	vp.scaling_3d_scale = 0.7
	print("render scale 0.7: %.1f ms" % await _avg())
	get_tree().quit()


func _try(label: String, base: float, toggle: Callable) -> void:
	toggle.call(false)
	var t := await _avg()
	toggle.call(true)
	print("  without %-12s %.1f ms  (part ≈ %.0f%%)" % [label, t, 100.0 * (base - t) / base])


func _avg() -> float:
	for i in 3:
		await get_tree().process_frame
	var t := Time.get_ticks_usec()
	for i in SAMPLES:
		await get_tree().process_frame
	return (Time.get_ticks_usec() - t) / 1000.0 / SAMPLES
