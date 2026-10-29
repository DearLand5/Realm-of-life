extends TestCase
## Envelope writing, backup recovery, species library.


func test_envelope_roundtrip_and_backup() -> void:
	var path := "user://test_tmp/env.json"
	var data := {"a": 1, "b": [1.5, 2.5], "c": {"x": "привет"}}
	check(SaveSystem.write_envelope(path, "test", data) == OK, "write ok")
	var r := SaveSystem.read_envelope(path, "test")
	check(r["ok"], "read ok: %s" % r["error"])
	check(str(r["data"]["c"]["x"]) == "привет", "unicode survives")
	# Second write keeps a backup; corrupt the main file and recover.
	data["a"] = 2
	SaveSystem.write_envelope(path, "test", data)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{broken")
	f.close()
	var r2 := SaveSystem.read_envelope(path, "test")
	check(r2["ok"] and r2["from_backup"], "recovered from backup")
	check(int(r2["data"]["a"]) == 1, "backup holds previous version")


func test_compressed_world_save() -> void:
	var big := PackedFloat32Array()
	for i in 10000:
		big.append(sin(i * 0.01))
	var data := {"name": "Тест", "day": 3, "grid": SaveSystem.pack_f32(big)}
	check(SaveSystem.save_world("unit_test_slot", data) == OK, "world saved")
	var r := SaveSystem.load_world("unit_test_slot")
	check(r["ok"], "world loaded: %s" % r["error"])
	var back := SaveSystem.unpack_f32(r["data"]["grid"])
	check(back.size() == big.size() and absf(back[500] - big[500]) < 1e-6, "packed grid restored")
	var listed := SaveSystem.list_world_saves()
	check(listed.any(func(e): return e["slot"] == "unit_test_slot"), "slot listed")
	SaveSystem.delete_world("unit_test_slot")


func test_species_library() -> void:
	var g := BodyPlanPresets.create(&"frog")
	var uid := SpeciesLibrary.save_species(g, "Тестовая лягушка")
	check(uid != "", "saved species")
	var back := SpeciesLibrary.load_genome(uid)
	check(back != null and Genetics.distance(g, back) < 0.001, "species genome restored")
	check(SpeciesLibrary.list_entries().any(func(e): return e["uid"] == uid), "listed")
	SpeciesLibrary.delete_species(uid)
	check(SpeciesLibrary.load_genome(uid) == null, "deleted")
