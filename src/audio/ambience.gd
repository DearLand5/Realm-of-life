class_name Ambience
extends Node
## Procedural ambient soundscape (no audio files): wind (filtered noise ∝ wind
## speed), rain (bright noise ∝ precipitation), thunder after lightning,
## daytime bird chirps near vegetation, night crickets when warm. Synthesised
## into an AudioStreamGenerator at a low mix rate to stay cheap on phones.

const MIX_RATE := 16000.0
const BUFFER_SEC := 0.25

var climate: ClimateState
var focus := Vector3.ZERO
var enabled := true
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _rng := RandomNumberGenerator.new()
var _wind_lp := 0.0
var _wind_lp2 := 0.0
var _rain_hp_prev := 0.0
var _rain_lp := 0.0
var _thunder := 0.0
var _thunder_lp := 0.0
var _chirp_t := -1.0
var _chirp_len := 0.0
var _chirp_f0 := 0.0
var _chirp_f1 := 0.0
var _chirp_phase := 0.0
var _next_chirp := 2.0
var _cricket_phase := 0.0
var _time := 0.0
var _volume := 0.8


func setup(shared: ClimateState, weather: Node = null) -> void:
	climate = shared
	_rng.seed = 1234
	_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = BUFFER_SEC
	_player.stream = gen
	_player.volume_db = -6.0
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()
	if weather != null and weather.has_signal("lightning"):
		weather.lightning.connect(func(_p: Vector3) -> void: _thunder = 1.0)
	_volume = float(UIApp.setting("sfx_volume", 0.8))


func _process(delta: float) -> void:
	if _playback == null or climate == null or not enabled:
		return
	_time += delta
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var wind := clampf(climate.wind.length() / 12.0, 0.0, 1.0)
	var rain := clampf(climate.precipitation, 0.0, 1.0) * (0.3 if climate.precipitation_is_snow(focus) else 1.0)
	var day := climate.daylight
	var temp := climate.temperature_at(focus)
	var birds := day * clampf((temp - 2.0) / 12.0, 0.0, 1.0) * (1.0 - rain) * 0.9
	var crickets := (1.0 - day) * clampf((temp - 12.0) / 10.0, 0.0, 1.0) * (1.0 - rain)
	_next_chirp -= delta
	if _next_chirp <= 0.0 and birds > 0.05 and _chirp_t < 0.0:
		_chirp_t = 0.0
		_chirp_len = _rng.randf_range(0.08, 0.28)
		_chirp_f0 = _rng.randf_range(2200.0, 3800.0)
		_chirp_f1 = _chirp_f0 * _rng.randf_range(0.6, 1.5)
		_next_chirp = _rng.randf_range(0.2, 2.5) / maxf(birds, 0.1)
	var vol := _volume
	var dt := 1.0 / MIX_RATE
	var wind_a := 0.015 + 0.05 * wind
	for i in frames:
		var n := _rng.randf() * 2.0 - 1.0
		# Wind: double low-pass with slow gust modulation.
		_wind_lp += (n - _wind_lp) * wind_a
		_wind_lp2 += (_wind_lp - _wind_lp2) * wind_a
		var gust := 0.6 + 0.4 * sin(_time * 0.7 + float(i) * dt * 0.7)
		var s := _wind_lp2 * wind * gust * 3.5
		# Rain: high-passed noise with random drop clicks.
		var hp := n - _rain_hp_prev
		_rain_hp_prev = n
		_rain_lp += (hp - _rain_lp) * 0.5
		s += _rain_lp * rain * 0.35
		if rain > 0.0 and _rng.randf() < rain * 0.002:
			s += _rng.randf_range(-0.4, 0.4) * rain
		# Thunder rumble.
		if _thunder > 0.001:
			_thunder_lp += (n - _thunder_lp) * 0.01
			s += _thunder_lp * _thunder * 4.0
			_thunder *= 0.99993
		# Bird chirp (frequency sweep with an envelope).
		if _chirp_t >= 0.0:
			var u := _chirp_t / _chirp_len
			var f := lerpf(_chirp_f0, _chirp_f1, u)
			_chirp_phase += f * dt * TAU
			s += sin(_chirp_phase) * sin(u * PI) * 0.12 * birds
			_chirp_t += dt
			if _chirp_t >= _chirp_len:
				_chirp_t = -1.0
		# Crickets: AM-pulsed high tone.
		if crickets > 0.01:
			_cricket_phase += 4300.0 * dt * TAU
			var pulse := 1.0 if fmod(_time * 1000.0 + float(i) * dt * 1000.0, 450.0) < 90.0 else 0.0
			s += sin(_cricket_phase) * pulse * 0.04 * crickets
		s = clampf(s * vol, -1.0, 1.0)
		_playback.push_frame(Vector2(s, s))
