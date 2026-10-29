class_name CreatureMeshCache
extends RefCounted
## Process-wide cache of CreatureMeshSets keyed by morph key + LOD
## (size is not part of the key: it is node scale). Autoload-free singleton:
## the static API forwards to one hidden state object.
##
##   build_now(model, lod)            synchronous (editor, tests)
##   request(model, lod, callback)    asynchronous: pure mesh data is built on the
##                                    WorkerThreadPool, Godot resources are created
##                                    and callbacks run on the main thread
##                                    (call_deferred); concurrent requests for the
##                                    same key share one task
##   get_cached(morph_key, lod)       cached set or null
## Memory is bounded by an LRU cap on the estimated vertex/index bytes.
## Evicted sets stay alive while CreatureVisuals still reference them.

const DEFAULT_MEMORY_CAP := 64 * 1024 * 1024

static var _state: _State = null


class _State:
	extends RefCounted
	var memory_cap: int = DEFAULT_MEMORY_CAP
	var entries := {}             # key -> CreatureMeshSet
	var lru := PackedStringArray()  # least recent first
	var bytes: int = 0
	var pending := {}             # key -> {"task": int, "callbacks": Array[Callable]}
	var hits: int = 0
	var misses: int = 0
	var builds: int = 0

	func touch(key: String) -> void:
		var i := lru.find(key)
		if i >= 0:
			lru.remove_at(i)
		lru.append(key)

	func store(s: CreatureMeshSet) -> CreatureMeshSet:
		if entries.has(s.key):
			touch(s.key)
			return entries[s.key]
		entries[s.key] = s
		bytes += s.byte_size
		touch(s.key)
		builds += 1
		while bytes > memory_cap and lru.size() > 1:
			var old := lru[0]
			lru.remove_at(0)
			var e: CreatureMeshSet = entries.get(old)
			if e != null:
				bytes -= e.byte_size
				entries.erase(old)
		return s

	func task(model: AnatomyModel, lod: int, key: String) -> void:
		# Worker thread: pure data only.
		var data := CreatureMeshBuilder.build_data(model, lod)
		deliver.call_deferred(key, data)

	func deliver(key: String, data: CreatureMeshData) -> void:
		var p: Dictionary = pending.get(key, {})
		pending.erase(key)
		if p.has("task"):
			WorkerThreadPool.wait_for_task_completion(int(p["task"]))
		var s: CreatureMeshSet = entries.get(key)
		if s == null:
			s = store(CreatureMeshSet.from_data(data))
		for cb in p.get("callbacks", []):
			var c: Callable = cb
			if c.is_valid():
				c.call(s)


static func _st() -> _State:
	if _state == null:
		_state = _State.new()
	return _state


static func key_for(model: AnatomyModel, lod: int) -> String:
	return CreatureMeshBuilder.cache_key(model, lod)


static func get_cached(morph_key: String, lod: int) -> CreatureMeshSet:
	var st := _st()
	var key := "%s#%d" % [morph_key, MeshLod.clamp_lod(lod)]
	var s: CreatureMeshSet = st.entries.get(key)
	if s != null:
		st.touch(key)
		st.hits += 1
	return s


static func _get_key(key: String) -> CreatureMeshSet:
	var st := _st()
	var s: CreatureMeshSet = st.entries.get(key)
	if s != null:
		st.touch(key)
		st.hits += 1
	return s


## Synchronous build (or cache hit). Main thread.
static func build_now(model: AnatomyModel, lod: int) -> CreatureMeshSet:
	var key := key_for(model, lod)
	var s := _get_key(key)
	if s != null:
		return s
	_st().misses += 1
	return _st().store(CreatureMeshSet.from_data(CreatureMeshBuilder.build_data(model, lod)))


## Asynchronous build; `callback(meshes: CreatureMeshSet)` always runs on the
## main thread (deferred, also on cache hits). Main thread.
static func request(model: AnatomyModel, lod: int, callback: Callable) -> void:
	var st := _st()
	var key := key_for(model, lod)
	var s := _get_key(key)
	if s != null:
		if callback.is_valid():
			callback.call_deferred(s)
		return
	if st.pending.has(key):
		var p: Dictionary = st.pending[key]
		(p["callbacks"] as Array).append(callback)
		return
	st.misses += 1
	var cbs: Array[Callable] = [callback]
	var entry := {"callbacks": cbs}
	st.pending[key] = entry
	entry["task"] = WorkerThreadPool.add_task(st.task.bind(model, MeshLod.clamp_lod(lod), key), false, "CreatureMeshBuild")


static func is_pending(model: AnatomyModel, lod: int) -> bool:
	return _st().pending.has(key_for(model, lod))


static func set_memory_cap(bytes: int) -> void:
	_st().memory_cap = maxi(bytes, 1024 * 1024)


static func clear() -> void:
	var st := _st()
	st.entries.clear()
	st.lru = PackedStringArray()
	st.bytes = 0


static func stats() -> Dictionary:
	var st := _st()
	return {"entries": st.entries.size(), "bytes": st.bytes, "cap": st.memory_cap, "pending": st.pending.size(),
		"hits": st.hits, "misses": st.misses, "builds": st.builds}
