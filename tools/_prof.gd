extends SceneTree
func _initialize():
	await process_frame
	var st := WorldBuilder.create({"seed": 4242, "size": 256.0, "procedural_species": 6})
	st.pop.sector_budget = 0
	print("start pop ", st.total_population(), " sectors ", st.pop.sectors.size(), " eco dim ", st.eco.dim)
	var te := 0; var tp := 0; var td := 0
	for i in 20:
		var t0 := Time.get_ticks_usec()
		st.eco.step_all(21600.0)
		var t1 := Time.get_ticks_usec()
		st.pop.step(21600.0)
		var t2 := Time.get_ticks_usec()
		if i % 4 == 3: st.evo.daily(float(i/4))
		var t3 := Time.get_ticks_usec()
		te += t1-t0; tp += t2-t1; td += t3-t2
	print("eco %.1f ms/step  pop %.1f ms/step  daily %.1f ms/day" % [te/20000.0, tp/20000.0, td/5000.0])
	var n := 0
	for s in st.pop.sectors: n += s.pools.size()
	print("pools ", n, " pop ", st.total_population())
	quit()
