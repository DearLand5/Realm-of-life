extends SceneTree
## Editor stress test: opens a preset and feeds synthetic touch gestures
## (one-finger orbit/drag, two-finger pinch/pan) for many frames, printing
## frame timings. Used to hunt device crashes when moving the camera.
##   tools/shot.sh tools/stress_editor.gd -- [preset] [frames]

var _t := 0


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var preset := args[0] if args.size() > 0 else "predator"
	var frames := int(args[1]) if args.size() > 1 else 600
	UIOverlay.ensure()
	await process_frame
	UIApp.game().set("pending", {"preset": preset})
	var ed: Node = load("res://scenes/creature_editor.tscn").instantiate()
	get_root().add_child(ed)
	current_scene = ed
	for i in 30:
		await process_frame
	var vp := get_root().get_visible_rect().size
	var c := vp * Vector2(0.4, 0.5)
	var worst := 0.0
	var t0 := Time.get_ticks_usec()
	var last := t0
	for f in frames:
		var phase := (f / 60) % 4
		match phase:
			0:
				_one_finger(c, f % 60, Vector2(9, 2))
			1:
				_two_finger(c, f % 60, 3.0, Vector2(2, 1))
			2:
				_one_finger(c + Vector2(40, 30), f % 60, Vector2(-6, 5))
			3:
				_two_finger(c, f % 60, -3.0, Vector2(-2, 0))
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
	print("stress done: %d frames, avg %.1f ms, worst %.1f ms, visual %s" % [frames,
		(Time.get_ticks_usec() - t0) / 1000.0 / frames, worst, str(ed.get("stage").get("visual"))])
	quit()


func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	e.relative = rel
	e.screen_relative = rel
	e.velocity = rel * 60.0
	Input.parse_input_event(e)


func _one_finger(c: Vector2, k: int, step: Vector2) -> void:
	if k == 0:
		_touch(0, c, true)
	elif k == 59:
		_touch(0, c + step * 58.0, false)
	else:
		_drag(0, c + step * float(k), step)


func _two_finger(c: Vector2, k: int, spread: float, pan: Vector2) -> void:
	var a := c + Vector2(-80 - spread * k, 0) + pan * k
	var b := c + Vector2(80 + spread * k, 0) + pan * k
	if k == 0:
		_touch(0, a, true)
		_touch(1, b, true)
	elif k == 59:
		_touch(0, a, false)
		_touch(1, b, false)
	else:
		_drag(0, a, Vector2(-spread, 0) + pan)
		_drag(1, b, Vector2(spread, 0) + pan)
