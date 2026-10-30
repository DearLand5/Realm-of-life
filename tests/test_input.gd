extends TestCase
## Input kit: gesture classification from synthesized touch sequences,
## joystick maths, touch buttons, control layouts, input actions.


# --- Helpers ------------------------------------------------------------------------------

func _rec() -> GestureRecognizer:
	var g := GestureRecognizer.new()
	g.scale_thresholds = false
	return g


func _log(g: GestureRecognizer) -> Dictionary:
	var log := {"tap": [], "double_tap": [], "long_press": [], "drag_started": [], "drag": [], "drag_ended": [],
		"pinch": [], "two_finger_drag": [], "two_finger_rotate": [], "orbit_drag": [], "secondary_tap": []}
	g.tap.connect(func(p: Vector2) -> void: log["tap"].append(p))
	g.double_tap.connect(func(p: Vector2) -> void: log["double_tap"].append(p))
	g.long_press.connect(func(p: Vector2) -> void: log["long_press"].append(p))
	g.drag_started.connect(func(p: Vector2, h: bool) -> void: log["drag_started"].append([p, h]))
	g.drag.connect(func(_p: Vector2, r: Vector2) -> void: log["drag"].append(r))
	g.drag_ended.connect(func(p: Vector2, v: Vector2) -> void: log["drag_ended"].append([p, v]))
	g.pinch.connect(func(f: float, _c: Vector2) -> void: log["pinch"].append(f))
	g.two_finger_drag.connect(func(r: Vector2, _c: Vector2) -> void: log["two_finger_drag"].append(r))
	g.two_finger_rotate.connect(func(a: float, _c: Vector2) -> void: log["two_finger_rotate"].append(a))
	g.orbit_drag.connect(func(r: Vector2, _p: Vector2) -> void: log["orbit_drag"].append(r))
	g.secondary_tap.connect(func(p: Vector2) -> void: log["secondary_tap"].append(p))
	return log


func _touch(g: GestureRecognizer, idx: int, pos: Vector2, pressed: bool, t: float) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	g.handle_event(e, t)


func _drag(g: GestureRecognizer, idx: int, pos: Vector2, t: float) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	g.handle_event(e, t)


func _count(log: Dictionary, key: String) -> int:
	return (log[key] as Array).size()


func _product(arr: Array) -> float:
	var p := 1.0
	for f in arr:
		p *= float(f)
	return p


# --- Gestures ----------------------------------------------------------------------------------

func test_tap_with_small_jitter() -> void:
	var g := _rec()
	var log := _log(g)
	_touch(g, 0, Vector2(100, 100), true, 10.0)
	_drag(g, 0, Vector2(104, 103), 10.05)  # finger wobble below the threshold
	g.update(10.08)
	_touch(g, 0, Vector2(104, 103), false, 10.12)
	check(_count(log, "tap") == 1, "one tap")
	check(_count(log, "drag_started") == 0 and _count(log, "long_press") == 0, "no drag / long press")
	check((log["tap"][0] as Vector2) == Vector2(100, 100), "tap reported at touch-down point")
	g.free()


func test_drag_is_not_a_tap() -> void:
	var g := _rec()
	var log := _log(g)
	_touch(g, 0, Vector2(100, 100), true, 1.0)
	for i in range(1, 6):
		_drag(g, 0, Vector2(100 + i * 10, 100), 1.0 + i * 0.016)
	_touch(g, 0, Vector2(150, 100), false, 1.1)
	check(_count(log, "tap") == 0, "drag produced no tap")
	check(_count(log, "drag_started") == 1, "drag started once")
	check(_count(log, "drag_ended") == 1, "drag ended once")
	var total := Vector2.ZERO
	for r in log["drag"]:
		total += r
	near(total.x, 50.0, 0.01, "drag relatives add up to the finger motion")
	var vel: Vector2 = log["drag_ended"][0][1]
	check(vel.x > 100.0, "release velocity measured (%s)" % vel)
	g.free()


func test_long_press_fires_while_holding() -> void:
	var g := _rec()
	var log := _log(g)
	_touch(g, 0, Vector2(50, 50), true, 2.0)
	g.update(2.3)
	check(_count(log, "long_press") == 0, "not yet")
	g.update(2.55)
	check(_count(log, "long_press") == 1, "long press after 0.5 s")
	_touch(g, 0, Vector2(50, 50), false, 2.8)
	check(_count(log, "tap") == 0, "no tap after long press")
	# Long press then move → drag flagged as after_long_press.
	_touch(g, 0, Vector2(50, 50), true, 5.0)
	g.update(5.6)
	_drag(g, 0, Vector2(90, 50), 5.7)
	check(_count(log, "drag_started") == 1 and bool(log["drag_started"][0][1]), "drag after hold is flagged")
	_touch(g, 0, Vector2(90, 50), false, 5.8)
	g.free()


func test_long_press_detected_on_release_without_update() -> void:
	var g := _rec()
	var log := _log(g)
	_touch(g, 0, Vector2(10, 10), true, 0.0)
	_touch(g, 0, Vector2(10, 10), false, 0.9)
	check(_count(log, "long_press") == 1 and _count(log, "tap") == 0, "slow release classified as long press")
	g.free()


func test_double_tap() -> void:
	var g := _rec()
	var log := _log(g)
	_touch(g, 0, Vector2(200, 200), true, 1.0)
	_touch(g, 0, Vector2(200, 200), false, 1.08)
	_touch(g, 0, Vector2(206, 204), true, 1.2)
	_touch(g, 0, Vector2(206, 204), false, 1.26)
	check(_count(log, "double_tap") == 1, "double tap detected")
	check(_count(log, "tap") == 1, "first tap still reported (non-exclusive)")
	# Too slow → two taps.
	_touch(g, 0, Vector2(200, 200), true, 3.0)
	_touch(g, 0, Vector2(200, 200), false, 3.05)
	_touch(g, 0, Vector2(200, 200), true, 3.6)
	_touch(g, 0, Vector2(200, 200), false, 3.65)
	check(_count(log, "double_tap") == 1 and _count(log, "tap") == 3, "slow taps are separate")
	g.free()


func test_exclusive_double_tap_defers_single_tap() -> void:
	var g := _rec()
	g.exclusive_double_tap = true
	var log := _log(g)
	_touch(g, 0, Vector2(5, 5), true, 1.0)
	_touch(g, 0, Vector2(5, 5), false, 1.05)
	check(_count(log, "tap") == 0, "tap deferred")
	g.update(1.2)
	check(_count(log, "tap") == 0, "still inside the double-tap window")
	g.update(1.5)
	check(_count(log, "tap") == 1, "tap delivered after the window")
	_touch(g, 0, Vector2(5, 5), true, 2.0)
	_touch(g, 0, Vector2(5, 5), false, 2.05)
	_touch(g, 0, Vector2(5, 5), true, 2.15)
	_touch(g, 0, Vector2(5, 5), false, 2.2)
	g.update(2.8)
	check(_count(log, "double_tap") == 1 and _count(log, "tap") == 1, "double tap suppresses its single tap")
	g.free()


func test_pinch_zoom() -> void:
	var g := _rec()
	var log := _log(g)
	var c := Vector2(400, 300)
	_touch(g, 0, c - Vector2(50, 0), true, 1.0)
	_touch(g, 1, c + Vector2(50, 0), true, 1.01)
	for i in range(1, 11):
		var half := 50.0 + i * 5.0
		_drag(g, 0, c - Vector2(half, 0), 1.0 + i * 0.016)
		_drag(g, 1, c + Vector2(half, 0), 1.0 + i * 0.016 + 0.001)
	near(_product(log["pinch"]), 2.0, 0.01, "pinch factors multiply to the spread ratio")
	check(_count(log, "two_finger_drag") == 0, "symmetric pinch does not pan")
	check(_count(log, "two_finger_rotate") == 0, "no rotation")
	_touch(g, 0, c - Vector2(100, 0), false, 1.3)
	_touch(g, 1, c + Vector2(100, 0), false, 1.31)
	check(_count(log, "tap") == 0 and _count(log, "drag_started") == 0, "no single-finger gestures")
	g.free()


func test_two_finger_pan() -> void:
	var g := _rec()
	var log := _log(g)
	_touch(g, 0, Vector2(100, 300), true, 1.0)
	_touch(g, 1, Vector2(200, 300), true, 1.0)
	for i in range(1, 11):
		_drag(g, 0, Vector2(100 + i * 6, 300), 1.0 + i * 0.016)
		_drag(g, 1, Vector2(200 + i * 6, 300), 1.0 + i * 0.016)
	var total := Vector2.ZERO
	for r in log["two_finger_drag"]:
		total += r
	near(total.x, 60.0, 0.5, "pan follows the finger centre")
	check(_count(log, "pinch") == 0, "parallel fingers do not pinch")
	# The finger left after lifting one must not start an orbit drag.
	_touch(g, 0, Vector2(160, 300), false, 1.3)
	_drag(g, 1, Vector2(320, 300), 1.35)
	_drag(g, 1, Vector2(360, 300), 1.4)
	check(_count(log, "drag_started") == 0, "remaining finger ignored until all lift")
	_touch(g, 1, Vector2(360, 300), false, 1.5)
	check(g.state == GestureRecognizer.State.IDLE, "back to idle")
	g.free()


func test_two_finger_rotate() -> void:
	var g := _rec()
	var log := _log(g)
	var c := Vector2(300, 300)
	_touch(g, 0, c + Vector2(-80, 0), true, 1.0)
	_touch(g, 1, c + Vector2(80, 0), true, 1.0)
	for i in range(1, 13):
		var a := deg_to_rad(float(i) * 3.0)
		_drag(g, 0, c + Vector2(-80, 0).rotated(a), 1.0 + i * 0.016)
		_drag(g, 1, c + Vector2(80, 0).rotated(a), 1.0 + i * 0.016)
	var total := 0.0
	for a2 in log["two_finger_rotate"]:
		total += float(a2)
	near(rad_to_deg(total), 36.0, 0.5, "rotation sums to the twist (clockwise positive)")
	check(_count(log, "pinch") == 0, "rigid twist does not pinch")
	g.free()


func test_mouse_left_ignored_wheel_and_right_drag_used() -> void:
	var g := _rec()
	var log := _log(g)
	var lmb := InputEventMouseButton.new()
	lmb.button_index = MOUSE_BUTTON_LEFT
	lmb.pressed = true
	check(not g.handle_event(lmb), "left button not consumed")
	var mm := InputEventMouseMotion.new()
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	mm.relative = Vector2(30, 0)
	check(not g.handle_event(mm), "left-drag motion not consumed")
	check(_count(log, "drag") == 0 and _count(log, "orbit_drag") == 0, "no gestures from left mouse")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	g.handle_event(wheel)
	check(_count(log, "pinch") == 1 and float(log["pinch"][0]) > 1.0, "wheel up zooms in")
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	rmb.position = Vector2(10, 10)
	g.handle_event(rmb)
	var rm := InputEventMouseMotion.new()
	rm.button_mask = MOUSE_BUTTON_MASK_RIGHT
	rm.relative = Vector2(25, -5)
	rm.position = Vector2(35, 5)
	g.handle_event(rm)
	rmb.pressed = false
	g.handle_event(rmb)
	check(_count(log, "orbit_drag") == 1, "right drag orbits")
	check(_count(log, "secondary_tap") == 0, "dragged right button is not a click")
	rmb.pressed = true
	g.handle_event(rmb)
	rmb.pressed = false
	g.handle_event(rmb)
	check(_count(log, "secondary_tap") == 1, "right click without motion")
	g.free()


# --- Joystick & touch button ------------------------------------------------------------------

func test_joystick_math_and_dead_zone() -> void:
	var o := Vector2(100, 100)
	check(TouchJoystick.compute(o + Vector2(5, 0), o, 50.0, 0.15) == Vector2.ZERO, "inside dead zone → zero")
	near(TouchJoystick.compute(o + Vector2(50, 0), o, 50.0, 0.15).length(), 1.0, 1e-4, "rim → full")
	near(TouchJoystick.compute(o + Vector2(0, -200), o, 50.0, 0.15).y, -1.0, 1e-4, "beyond rim clamps, up is −y")
	var mid := TouchJoystick.compute(o + Vector2(0.575 * 50.0, 0), o, 50.0, 0.15)
	near(mid.x, 0.5, 1e-3, "rescaled ramp: halfway between dead zone and rim = 0.5")
	var diag := TouchJoystick.compute(o + Vector2(30, 30), o, 50.0, 0.1)
	near(diag.angle(), PI / 4.0, 1e-4, "direction preserved")


func test_joystick_tracks_its_own_finger() -> void:
	var j := TouchJoystick.new()
	j.mode = TouchJoystick.Mode.FIXED
	j.size = Vector2(200, 200)
	var changes := []
	j.changed.connect(func(v: Vector2) -> void: changes.append(v))
	var press := InputEventScreenTouch.new()
	press.index = 2
	press.pressed = true
	press.position = Vector2(100, 100)
	j._gui_input(press)
	var other := InputEventScreenDrag.new()
	other.index = 5
	other.position = Vector2(190, 100)
	j._gui_input(other)
	check(j.value == Vector2.ZERO, "other finger ignored")
	var mine := InputEventScreenDrag.new()
	mine.index = 2
	mine.position = Vector2(100 + j.radius_px(), 100)
	j._gui_input(mine)
	near(j.value.x, 1.0, 1e-3, "own finger drives the stick")
	var second := InputEventScreenTouch.new()
	second.index = 7
	second.pressed = true
	second.position = Vector2(20, 20)
	j._gui_input(second)
	check(j.is_active and j.value.x > 0.99, "second finger cannot steal the stick")
	press.pressed = false
	j._gui_input(press)
	check(j.value == Vector2.ZERO and not j.is_active, "release resets")
	check(changes.size() >= 2, "changed emitted")
	j.free()


func test_touch_button_tap_hold_toggle() -> void:
	var b := TouchButton.make(&"jump")
	b.toggle_mode = true
	var got := {"tapped": 0, "held": 0, "toggled": []}
	b.tapped.connect(func() -> void: got["tapped"] += 1)
	b.held.connect(func() -> void: got["held"] += 1)
	b.toggled.connect(func(on: bool) -> void: got["toggled"].append(on))
	var t := InputEventScreenTouch.new()
	t.index = 1
	t.pressed = true
	b._gui_input(t)
	check(b.is_pressed, "pressed")
	t.pressed = false
	b._gui_input(t)
	check(got["tapped"] == 1 and got["toggled"] == [true], "tap toggles on")
	t.pressed = true
	b._gui_input(t)
	b._process(0.6)
	t.pressed = false
	b._gui_input(t)
	check(got["held"] == 1 and got["tapped"] == 1, "hold is not a tap")
	b.free()


# --- Layouts & actions ------------------------------------------------------------------------

func test_control_layout_roundtrip_and_mirroring() -> void:
	var l := ControlLayout.new()
	var def := l.element(&"third_person", &"btn_jump")
	check(not def.is_empty() and (def["anchor"] as Vector2) == Vector2(1, 1), "default jump bottom-right")
	l.set_element(&"third_person", &"btn_jump", {"size": 1.4, "opacity": 0.5, "offset": Vector2(-120, -140)})
	l.set_element(&"observer", &"joy_move", {"visible": false})
	var d := l.to_dict()
	var json := JSON.stringify(d)
	var back := ControlLayout.from_dict(JSON.parse_string(json))
	var e := back.element(&"third_person", &"btn_jump")
	near(float(e["size"]), 1.4, 1e-4, "size survives JSON")
	near(float(e["opacity"]), 0.5, 1e-4, "opacity survives JSON")
	check((e["offset"] as Vector2).is_equal_approx(Vector2(-120, -140)), "offset survives JSON")
	check(not bool(back.element(&"observer", &"joy_move")["visible"]), "visibility survives JSON")
	# Mirroring.
	back.left_handed = true
	var m := back.element(&"third_person", &"btn_jump")
	check((m["anchor"] as Vector2).is_equal_approx(Vector2(0, 1)), "left-handed anchor mirrored")
	check((m["offset"] as Vector2).is_equal_approx(Vector2(120, -140)), "left-handed offset mirrored")
	var area := Rect2(0, 0, 1280, 720)
	var r_left := back.rect_for(&"third_person", &"btn_jump", area, 1.0)
	back.left_handed = false
	var r_right := back.rect_for(&"third_person", &"btn_jump", area, 1.0)
	near(r_left.get_center().x, 1280.0 - r_right.get_center().x, 0.01, "rects mirror across the screen")
	# Edits made while left-handed are stored right-handed.
	back.left_handed = true
	back.set_element(&"third_person", &"btn_attack", {"anchor": Vector2(0, 1), "offset": Vector2(100, -100)})
	back.left_handed = false
	var stored := back.element(&"third_person", &"btn_attack")
	check((stored["anchor"] as Vector2).is_equal_approx(Vector2(1, 1)) and (stored["offset"] as Vector2).is_equal_approx(Vector2(-100, -100)),
		"displayed edits un-mirrored for storage")
	check(ControlLayout.from_dict({"junk": 1, "schemes": {"x": 5}}).active_scheme == ControlLayout.DEFAULT_SCHEME, "tolerant of bad data")


func test_control_layout_rects_and_schemes() -> void:
	var l := ControlLayout.new()
	var portrait := Rect2(0, 40, 720, 1200)
	for mode in ControlLayout.MODES:
		for id in l.element_ids(mode):
			var r := l.rect_for(mode, id, portrait, 1.0)
			check(portrait.encloses(r), "%s/%s inside portrait safe area" % [mode, id])
	l.place_at(&"third_person", &"btn_eat", Vector2(100, 640), portrait, 1.0)
	var e := l.element(&"third_person", &"btn_eat")
	check((e["anchor"] as Vector2).is_equal_approx(Vector2(0, 0.5)), "re-anchored to nearest anchor point")
	near(l.rect_for(&"third_person", &"btn_eat", portrait, 1.0).get_center().x, 100.0, 1.0, "placed where dropped")
	check(l.new_scheme("Мой"), "new scheme")
	check(l.active_scheme == "Мой", "new scheme active")
	l.set_element(&"third_person", &"btn_jump", {"size": 0.7})
	l.set_active(ControlLayout.DEFAULT_SCHEME)
	near(float(l.element(&"third_person", &"btn_jump")["size"]), 1.0, 1e-4, "schemes are independent")
	check(l.rename_scheme("Мой", "Левая рука"), "rename")
	l.delete_scheme("Левая рука")
	check(not l.scheme_names().has("Левая рука"), "deleted")
	l.set_element(&"third_person", &"btn_jump", {"size": 9.0})
	near(float(l.element(&"third_person", &"btn_jump")["size"]), ControlLayout.MAX_SIZE, 1e-4, "size clamped")
	l.reset_element(&"third_person", &"btn_jump")
	near(float(l.element(&"third_person", &"btn_jump")["size"]), 1.0, 1e-4, "reset element")


func test_control_layout_persists_via_save_system() -> void:
	var before := SaveSystem.load_controls()
	var l := ControlLayout.new()
	l.new_scheme("Тест")
	l.set_element(&"first_person", &"btn_sprint", {"opacity": 0.33})
	l.save()
	var back := ControlLayout.load_saved()
	check(back.active_scheme == "Тест", "active scheme restored")
	near(float(back.element(&"first_person", &"btn_sprint")["opacity"]), 0.33, 1e-4, "override restored")
	SaveSystem.save_controls(before)


func test_input_actions_registration_and_remap() -> void:
	InputActions.register_defaults(false)
	for a in InputActions.CONTEXT:
		check(InputMap.has_action(a), "action %s registered" % a)
	check(InputActions.key_text(&"jump").contains("Space"), "jump on Space")
	check(InputActions.label(&"eat") == "Есть", "Russian label")
	InputActions.rebind(&"jump", InputActions.key_event(KEY_J))
	var d := InputActions.to_dict()
	check(d.has("jump") and d["jump"] == [KEY_J], "remap exported")
	InputActions.reset(&"jump")
	check(not InputActions.to_dict().has("jump"), "reset restores defaults")
	InputActions.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(InputActions.key_text(&"jump").contains("J"), "remap imported from JSON")
	InputActions.reset_all()
