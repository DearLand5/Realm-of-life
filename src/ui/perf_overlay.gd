class_name PerfOverlay
extends Label
## On-device performance readout (Settings → «Показывать FPS»): FPS, CPU and
## GPU frame time, draw calls and primitives, refreshed twice a second.
## GPU time comes from the render-time measurement of the root viewport.

const INTERVAL := 0.5

var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 13)
	add_theme_color_override("font_color", Color(1, 1, 0.6))
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 4)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(delta: float) -> void:
	_t += delta
	if _t < INTERVAL:
		return
	_t = 0.0
	var rid := get_viewport().get_viewport_rid()
	text = "%d FPS · ЦП %.1f мс · ГП %.1f мс · отрисовок %d · треуг. %dk" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		RenderingServer.viewport_get_measured_render_time_gpu(rid),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)]
