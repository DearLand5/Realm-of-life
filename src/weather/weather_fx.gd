class_name WeatherFX
extends Node3D
## Weather visuals around the camera: rain streaks and snowflakes as
## GPUParticles3D (amounts scaled by WorldQuality and precipitation), and
## lightning flashes during storms (WeatherSystem.lightning_flash, read by
## DayNightCycle to light the sky and scene).

const RAIN_AMOUNT: Array[int] = [500, 1200, 2400]
const SNOW_AMOUNT: Array[int] = [350, 900, 1800]
const BOX := Vector3(22.0, 1.0, 22.0)
const HEIGHT := 14.0

var weather: WeatherSystem
## Storm lightning (off for still screenshots).
var lightning_enabled := true
var rain: GPUParticles3D
var snow: GPUParticles3D
var _rain_mat: ParticleProcessMaterial
var _snow_mat: ParticleProcessMaterial
var _flash_timer: float = 4.0
var _flash_t: float = -1.0
var _rng := RandomNumberGenerator.new()


func setup(ws: WeatherSystem) -> void:
	weather = ws
	_rng.seed = 7
	var q := WorldQuality.level()
	_rain_mat = _process_material(Vector3(0, -1, 0), 11.0, 0.06)
	rain = _particles("Rain", RAIN_AMOUNT[q], 1.3, _rain_mat, _rain_mesh())
	_snow_mat = _process_material(Vector3(0, -1, 0), 1.3, 0.6)
	_snow_mat.turbulence_enabled = q == WorldQuality.HIGH
	_snow_mat.turbulence_noise_strength = 0.8
	snow = _particles("Snow", SNOW_AMOUNT[q], 7.0, _snow_mat, _snow_mesh())


func _process_material(dir: Vector3, speed: float, spread: float) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = BOX
	m.direction = dir
	m.spread = spread * 45.0
	m.initial_velocity_min = speed * 0.85
	m.initial_velocity_max = speed * 1.15
	m.gravity = Vector3(0, -speed * 0.2, 0)
	m.particle_flag_align_y = speed > 5.0
	return m


func _particles(node_name: String, amount: int, lifetime: float, pm: ParticleProcessMaterial, mesh: Mesh) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.local_coords = false
	p.emitting = false
	p.visible = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	add_child(p)
	return p


func _rain_mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.7)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.8, 0.88, 0.5)
	# Drops right at the lens would be huge bars: fade them in from 2 to 5 m.
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 2.0
	m.distance_fade_max_distance = 5.0
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	q.material = m
	return q


func _snow_mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.albedo_color = Color(0.95, 0.97, 1.0, 1.0)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	return q


## Per-frame update with real (unscaled) delta.
func update_fx(delta: float) -> void:
	if weather == null or weather.climate == null:
		return
	var c := weather.climate
	var cam_pos := weather.focus
	var precip := clampf(c.precipitation, 0.0, 1.0)
	var is_snow := c.regional_temperature < 0.5 or c.weather == &"snow"
	var wind3 := Vector3(c.wind.x, 0.0, c.wind.y)
	# Emit upwind so drops drift through the view.
	global_position = cam_pos + Vector3(0, HEIGHT, 0) - wind3 * 0.8
	_set_active(rain, precip > 0.04 and not is_snow, precip)
	_set_active(snow, precip > 0.04 and is_snow, precip)
	_rain_mat.gravity = Vector3(c.wind.x * 1.5, -9.0, c.wind.y * 1.5)
	_snow_mat.gravity = Vector3(c.wind.x * 0.5, -0.25, c.wind.y * 0.5)
	_lightning(delta, c)


func _set_active(p: GPUParticles3D, on: bool, intensity: float) -> void:
	if p.emitting != on:
		p.emitting = on
		if on:
			p.visible = true
			p.restart()
	if not on and p.visible and not p.emitting:
		p.visible = false
	p.amount_ratio = clampf(0.25 + intensity * 0.75, 0.0, 1.0)


func _lightning(delta: float, c: ClimateState) -> void:
	var f := 0.0
	if _flash_t >= 0.0:
		_flash_t += delta
		# Two quick flickers then fade.
		f = maxf(0.0, 1.0 - _flash_t / 0.35) * (0.6 + 0.4 * sin(_flash_t * 60.0))
		if _flash_t > 0.4:
			_flash_t = -1.0
	if lightning_enabled and c.weather == &"storm" and c.precipitation > 0.5:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash_timer = _rng.randf_range(3.0, 11.0)
			_flash_t = 0.0
			var a := _rng.randf() * TAU
			weather.notify_lightning(weather.focus + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(60.0, 400.0))
	weather.lightning_flash = clampf(f, 0.0, 1.0)


## Fills particle systems immediately (previews / screenshots).
func prewarm() -> void:
	for p in [rain, snow]:
		var gp: GPUParticles3D = p
		if gp.emitting:
			gp.restart()
