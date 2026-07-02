extends Node
## Procedural cockpit audio (no sound assets required).
##
## Synthesises the soundscape in real time into a single AudioStreamGenerator:
##   * Engine    - harmonic tone at the cylinder firing frequency, rising in
##                 pitch and volume with RPM/throttle.
##   * Wind/slip - filtered noise scaled by airspeed.
##   * Stall horn - a steady reed-horn tone whenever the stall warning is on.
##   * Touchdown - a short thump triggered on landing, scaled by sink rate.
## Registered as an autoload so it follows the aircraft state in FlightData.

const SR := 22050.0

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback

var _eng_phase := 0.0
var _wind_lp := 0.0
var _stall_phase := 0.0
var _td_env := 0.0          # touchdown thump envelope
var _prev_on_ground := true
var _rpm_s := 700.0         # smoothed values to avoid zipper noise
var _thr_s := 0.0
var _wind_s := 0.0
var _buf := PackedVector2Array()   # reused block buffer (one push per fill)


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SR
	gen.buffer_length = 0.12
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.autoplay = false
	add_child(_player)
	_player.play()
	var pb := _player.get_stream_playback()
	if pb is AudioStreamGeneratorPlayback:
		_playback = pb


func _process(_delta: float) -> void:
	# Trigger a touchdown thump on the air->ground transition.
	var og: bool = FlightData.on_ground
	if og and not _prev_on_ground:
		_td_env = clampf(absf(FlightData.vertical_speed_fpm) / 500.0, 0.25, 1.0)
	_prev_on_ground = og

	if _playback == null:
		return
	_fill()


func _fill() -> void:
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return

	# Smooth the driving parameters once per block.
	_rpm_s = lerpf(_rpm_s, FlightData.engine_rpm, 0.25)
	_thr_s = lerpf(_thr_s, FlightData.throttle_pct / 100.0, 0.25)
	var ias: float = FlightData.indicated_airspeed_kt
	_wind_s = lerpf(_wind_s, clampf((ias - 25.0) / 130.0, 0.0, 1.0), 0.2)

	var f0 := maxf(_rpm_s, 250.0) / 60.0 * 2.0     # 4-cyl, 2 firings/rev
	var eng_amp := 0.10 + 0.42 * _thr_s
	var wind_amp := _wind_s * 0.30
	var stalling: bool = FlightData.stall_warning

	if _buf.size() != frames:
		_buf.resize(frames)
	for i in range(frames):
		# --- Engine: fundamental + harmonics + a sub for the lope ---
		_eng_phase += f0 / SR
		if _eng_phase >= 1.0:
			_eng_phase -= 1.0
		var e := sin(TAU * _eng_phase)
		e += 0.5 * sin(TAU * _eng_phase * 2.0)
		e += 0.3 * sin(TAU * _eng_phase * 3.0)
		e += 0.4 * sin(TAU * _eng_phase * 0.5)
		e *= eng_amp * 0.38

		# --- Wind: one-pole low-passed noise ---
		var noise := randf() * 2.0 - 1.0
		_wind_lp += (noise - _wind_lp) * 0.18
		var w := _wind_lp * wind_amp

		# --- Stall horn ---
		var s := 0.0
		if stalling:
			_stall_phase += 410.0 / SR
			if _stall_phase >= 1.0:
				_stall_phase -= 1.0
			s = 0.18 * sin(TAU * _stall_phase)

		# --- Touchdown thump ---
		var td := 0.0
		if _td_env > 0.0001:
			td = (randf() * 2.0 - 1.0) * _td_env * 0.45
			_td_env *= 0.9994

		var smp := clampf((e + w + s + td) * 0.7, -1.0, 1.0)
		_buf[i] = Vector2(smp, smp)
	# One native call per block instead of one per sample (~22k/sec).
	_playback.push_buffer(_buf)
