class_name DayNightCycle
extends Node3D
## Sun & moon lights, procedural sky (shaders/sky.gdshader), ambient light
## and distance fog driven by the shared ClimateState (time of day, season,
## clouds, fog, precipitation). Mobile: one shadowed light with a short
## shadow distance, sky not used for radiance (ambient from colour).
##   setup(climate, weather_system = null, time_controller = null)

const SKY_SHADER := "res://shaders/sky.gdshader"

var climate: ClimateState
## Optional WeatherSystem (reads `lightning_flash`).
var weather: Node
## Optional clock: clouds drift faster when time is accelerated.
var time: TimeController
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var world_environment: WorldEnvironment
var environment: Environment
var sky_material: ShaderMaterial
## Clear-weather fog density (atmospheric perspective).
var base_fog_density: float = 0.0007
var _cloud_offset := Vector2.ZERO


func _init() -> void:
	process_priority = -80


func setup(shared: ClimateState, weather_system: Node = null, clock: TimeController = null) -> void:
	climate = shared
	weather = weather_system
	time = clock
	if sun == null:
		_build()
	update_now()


func _build() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_angular_distance = 0.6
	var q := WorldQuality.level()
	sun.shadow_enabled = q > WorldQuality.LOW
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q < WorldQuality.HIGH else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = [40.0, 70.0, 140.0][q]
	sun.directional_shadow_blend_splits = q == WorldQuality.HIGH
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = false
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_specular = 0.3
	add_child(moon)
	sky_material = ShaderMaterial.new()
	sky_material.shader = load(SKY_SHADER)
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.15
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_density = base_fog_density
	environment.fog_sky_affect = 0.25
	environment.fog_aerial_perspective = 0.0
	world_environment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)


func _process(delta: float) -> void:
	if climate == null:
		return
	# Clouds drift with the wind; acceleration speeds them up (capped ×16).
	var dt := delta
	if time != null:
		dt = minf(time.phys_dt, delta * 16.0)
	_cloud_offset += climate.wind * dt * 0.0015
	_cloud_offset = Vector2(fposmod(_cloud_offset.x, 1000.0), fposmod(_cloud_offset.y, 1000.0))
	update_now()


## Recomputes lights, sky and fog from the climate immediately.
func update_now() -> void:
	if climate == null or sun == null:
		return
	var c := climate
	var sun_dir := c.sun_direction.normalized()
	var elev := c.sun_elevation
	var cloud := clampf(c.cloud_cover, 0.0, 1.0)
	var fog := clampf(c.fog, 0.0, 1.0)
	var day := SunModel.daylight(elev)
	var night := 1.0 - smoothstep(-10.0, -2.0, elev)
	var flash := 0.0
	if weather != null and "lightning_flash" in weather:
		flash = float(weather.get("lightning_flash"))

	var zenith := SkyPalette.overcast(SkyPalette.sample_color(SkyPalette.ZENITH, elev), cloud, fog, day)
	var horizon := SkyPalette.overcast(SkyPalette.sample_color(SkyPalette.HORIZON, elev), cloud * 0.9, fog, day)
	var sun_col := SkyPalette.sample_color(SkyPalette.SUN, elev)
	var glow := SkyPalette.sample_float(SkyPalette.GLOW, elev) * (1.0 - cloud * 0.8) * (1.0 - fog)

	# Sun.
	var sun_vis := smoothstep(-2.0, 3.0, elev)
	sun.visible = sun_vis > 0.001
	_orient(sun, sun_dir)
	sun.light_color = sun_col.lerp(Color(0.85, 0.88, 0.92), cloud * 0.6)
	sun.light_energy = sun_vis * lerpf(1.2, 1.6, smoothstep(5.0, 35.0, elev)) * (1.0 - 0.68 * cloud) * (1.0 - 0.45 * fog)
	# Grazing sun → long aliased shadows; fade them while the light is soft anyway.
	sun.shadow_opacity = clampf(1.0 - cloud * 0.75 - fog * 0.6, 0.15, 1.0) * lerpf(0.35, 1.0, smoothstep(3.0, 14.0, elev))
	# Moon.
	var moon_dir := SunModel.moon_direction(sun_dir, c.year_phase)
	moon.visible = night > 0.01
	_orient(moon, moon_dir)
	moon.light_energy = night * 0.65 * (1.0 - 0.7 * cloud) + flash * 2.5

	# Sky shader.
	var sm := sky_material
	sm.set_shader_parameter("zenith_color", zenith)
	sm.set_shader_parameter("horizon_color", horizon)
	sm.set_shader_parameter("ground_color", horizon.lerp(Color(0.2, 0.22, 0.22) * maxf(day, 0.1), 0.5))
	sm.set_shader_parameter("sun_color", sun_col)
	sm.set_shader_parameter("glow_color", Color(1.0, 0.5, 0.25).lerp(sun_col, 0.3))
	sm.set_shader_parameter("glow_strength", glow * 0.9)
	sm.set_shader_parameter("sun_dir", sun_dir)
	sm.set_shader_parameter("moon_dir", moon_dir)
	sm.set_shader_parameter("star_intensity", night * (1.0 - cloud) * (1.0 - fog))
	sm.set_shader_parameter("moon_intensity", night)
	sm.set_shader_parameter("cloud_cover", cloud)
	sm.set_shader_parameter("cloud_darkness", clampf(c.precipitation * 0.7 + (0.35 if c.weather == &"storm" else 0.0), 0.0, 0.9))
	var cl := Color(1.0, 1.0, 1.0).lerp(sun_col * 1.1, 1.0 - smoothstep(2.0, 20.0, elev))
	sm.set_shader_parameter("cloud_light", cl * lerpf(0.06, 1.0, day))
	sm.set_shader_parameter("cloud_shadow", Color(0.5, 0.55, 0.63) * lerpf(0.04, 0.95, day))
	sm.set_shader_parameter("cloud_offset", _cloud_offset)
	sm.set_shader_parameter("flash", flash)

	# Ambient + fog.
	var amb := horizon.lerp(zenith, 0.4)
	# Less saturated than the sky itself (ground bounce light mixes in).
	var grey := (amb.r + amb.g + amb.b) / 3.0
	amb = amb.lerp(Color(grey * 1.05, grey, grey * 0.92), 0.45)
	var amb_floor := Color(0.1, 0.13, 0.24)
	amb = Color(maxf(amb.r, amb_floor.r), maxf(amb.g, amb_floor.g), maxf(amb.b, amb_floor.b))
	environment.ambient_light_color = amb
	environment.ambient_light_energy = lerpf(1.0, 0.8, day) + cloud * 0.25 * day + flash * 1.5
	environment.fog_light_color = horizon.lerp(amb, 0.25)
	environment.fog_density = base_fog_density + fog * 0.03 + clampf(c.precipitation, 0.0, 1.0) * 0.005
	environment.fog_sky_affect = 0.2 + fog * 0.8


static func _orient(light: DirectionalLight3D, towards: Vector3) -> void:
	var d := -towards.normalized()
	var up := Vector3.UP if absf(d.y) < 0.99 else Vector3.FORWARD
	light.basis = Basis.looking_at(d, up)
