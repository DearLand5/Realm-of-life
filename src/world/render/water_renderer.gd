class_name WaterRenderer
extends Node3D
## Ocean, lake and river surfaces (shaders/water.gdshader). Geometry is
## static (built once in setup); wind, sky reflection colour, daylight and
## rain are pushed into the shader from the shared ClimateState.
##   setup(world, climate = null)

const SHADER_PATH := "res://shaders/water.gdshader"
const OUTER_RADIUS := 3000.0

var world: WorldData
var climate: ClimateState
var material: ShaderMaterial
var river_material: ShaderMaterial
var _uniform_timer := 0.0


func setup(w: WorldData, shared_climate: ClimateState = null) -> void:
	world = w
	climate = shared_climate
	for ch in get_children():
		ch.queue_free()
	var shader: Shader = load(SHADER_PATH)
	material = ShaderMaterial.new()
	material.shader = shader
	material.render_priority = 0
	river_material = ShaderMaterial.new()
	river_material.shader = shader
	river_material.set_shader_parameter("river", true)
	river_material.render_priority = -1
	var cells := clampi(nearest_po2(int(round(32.0 / w.cell))), 8, 64)
	var count := int(ceil(float(w.res - 1) / float(cells)))
	for cz in count:
		for cx in count:
			var mesh := WaterMesher.build_chunk(w, cx * cells, cz * cells, cells)
			if mesh != null:
				_add(mesh, material, "Water_%d_%d" % [cx, cz])
	_add(WaterMesher.build_outer_ocean(w, OUTER_RADIUS), material, "OuterOcean")
	var rivers := WaterMesher.build_rivers(w)
	if rivers != null:
		_add(rivers, river_material, "Rivers")
	_apply_uniforms()


func _add(mesh: ArrayMesh, mat: Material, node_name: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _process(delta: float) -> void:
	_uniform_timer -= delta
	if _uniform_timer <= 0.0:
		_uniform_timer = 0.15
		_apply_uniforms()


func _apply_uniforms() -> void:
	if material == null:
		return
	var wind := Vector2(2.0, 0.5)
	var sky := Color(0.6, 0.74, 0.9)
	var day := 1.0
	var rain := 0.0
	if climate != null:
		wind = climate.wind
		var elev := climate.sun_elevation
		day = SunModel.daylight(elev)
		var zen := SkyPalette.sample_color(SkyPalette.ZENITH, elev)
		var hor := SkyPalette.sample_color(SkyPalette.HORIZON, elev)
		sky = SkyPalette.overcast(hor.lerp(zen, 0.35), climate.cloud_cover, climate.fog, day)
		rain = clampf(climate.precipitation, 0.0, 1.0) if climate.weather != &"snow" else 0.0
	for m in [material, river_material]:
		var sm: ShaderMaterial = m
		sm.set_shader_parameter("wind", wind)
		sm.set_shader_parameter("sky_color", sky)
		sm.set_shader_parameter("daylight", day)
		sm.set_shader_parameter("rain", rain)
