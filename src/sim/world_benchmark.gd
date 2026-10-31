class_name WorldBenchmark
extends Node
## On-device frame-cost breakdown of the world (world menu → «Тест
## производительности»): measures CPU and GPU frame time with each visual part
## switched off in turn, then restores everything and returns a text report.

signal finished(report: String)

const WARMUP := 20
const SAMPLES := 40

var world: Node


func run() -> void:
	var vp := get_viewport()
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	var lines := PackedStringArray()
	lines.append("Тест производительности · %s · %s" % [OS.get_model_name(), RenderingServer.get_video_adapter_name()])
	lines.append("Рендерер %s, масштаб 3D %.2f, особей %d, качество %s" % [RenderingServer.get_current_rendering_method(),
		vp.scaling_3d_scale, world.agents.live_count(), str(world.perf.profile.level)])
	var base := await _measure()
	lines.append("Всё включено: %s" % _fmt(base))
	var parts := [
		["рельеф", func(on: bool) -> void: world.terrain.visible = on],
		["вода", func(on: bool) -> void: world.water.visible = on],
		["растения", func(on: bool) -> void: world.flora.visible = on],
		["существа", func(on: bool) -> void:
			for a in world.agents.agents:
				if is_instance_valid(a): (a as Node3D).visible = on],
		["тени солнца", func(on: bool) -> void: world.day_night.sun.shadow_enabled = on],
		["интерфейс", func(on: bool) -> void: world.hud.visible = on],
		["симуляция", func(on: bool) -> void: world.set_process(on)],
	]
	for p in parts:
		(p[1] as Callable).call(false)
		var r := await _measure()
		(p[1] as Callable).call(true)
		lines.append("  без «%s»: %s  (экономия ЦП %.1f, ГП %.1f мс)" % [p[0], _fmt(r), base.x - r.x, base.y - r.y])
	var sc := vp.scaling_3d_scale
	vp.scaling_3d_scale = 0.5
	lines.append("  масштаб 3D 0.5: %s" % _fmt(await _measure()))
	vp.scaling_3d_scale = sc
	finished.emit("\n".join(lines))


## Vector3(cpu_ms, gpu_ms, frame_ms) averaged over SAMPLES frames.
func _measure() -> Vector3:
	var rid := get_viewport().get_viewport_rid()
	for i in WARMUP:
		await get_tree().process_frame
	var cpu := 0.0
	var gpu := 0.0
	var t := Time.get_ticks_usec()
	for i in SAMPLES:
		await get_tree().process_frame
		cpu += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var frame := (Time.get_ticks_usec() - t) / 1000.0 / SAMPLES
	return Vector3(cpu / SAMPLES, gpu / SAMPLES, frame)


static func _fmt(v: Vector3) -> String:
	return "кадр %.1f мс (%d FPS), ЦП %.1f мс, ГП %.1f мс" % [v.z, int(1000.0 / maxf(v.z, 0.1)), v.x, v.y]
