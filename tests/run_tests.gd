extends SceneTree
## Headless test runner:
##   godot --headless --path . -s tests/run_tests.gd [-- filter]
## Runs every tests/**/test_*.gd (TestCase subclasses). Exit code 1 on failure.

func _initialize() -> void:
	# Wait one frame so autoloads are ready.
	await process_frame
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var files := _collect("res://tests")
	files.sort()
	var total_fail := 0
	var total_checks := 0
	var t0 := Time.get_ticks_msec()
	for path in files:
		if filter != "" and not path.contains(filter):
			continue
		var script: GDScript = load(path)
		if script == null:
			print("[LOAD FAIL] ", path)
			total_fail += 1
			continue
		var inst = script.new()
		if not (inst is TestCase):
			continue
		var methods := []
		for m in inst.get_method_list():
			if str(m["name"]).begins_with("test_"):
				methods.append(str(m["name"]))
		methods.sort()
		for mname in methods:
			inst.current = "%s::%s" % [path.get_file(), mname]
			var before: int = inst.failures.size()
			var ts := Time.get_ticks_msec()
			var r = inst.call(mname)
			if r is Object and r.has_method("is_valid"):
				pass
			var dt := Time.get_ticks_msec() - ts
			var ok: bool = inst.failures.size() == before
			print("%s %s (%d ms)" % ["  ok  " if ok else "[FAIL]", inst.current, dt])
		for f in inst.failures:
			print("    ✗ ", f)
		total_fail += inst.failures.size()
		total_checks += inst.checks
	print("\n%d checks, %d failures, %.1f s" % [total_checks, total_fail, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if total_fail > 0 else 0)


func _collect(dir_path: String) -> Array:
	var out := []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for sub in d.get_directories():
		out.append_array(_collect(dir_path.path_join(sub)))
	return out
