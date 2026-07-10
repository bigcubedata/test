extends Node
## Procedural cockpit audio (no sound assets required).
##
## Synthesises the whole soundscape in real time into one AudioStreamGenerator.
## Everything is driven from FlightData, so it works in replay too:
##
##   * Engine     - the Lycoming IO-360 fires twice per rev (4-cyl 4-stroke),
##                  modelled as a train of raised-cosine exhaust pulses plus a
##                  crankshaft-rate rumble. Pulses get random per-firing
##                  amplitude jitter that is strong at idle (the classic
##                  Lycoming idle lope) and fades out at speed. Throttle adds
##                  combustion noise and brightens the pulses.
##   * Propeller  - the two blades pass at the same 2-per-rev rate, heard as
##                  broadband noise chopped at the firing frequency; the chop
##                  deepens with rpm and airspeed (the "waah" of a flat-out
##                  prop).
##   * Wind       - two noise bands per ear (rumble + hiss) whose gain AND
##                  brightness rise with airspeed; sideslip adds the hiss of
##                  air hitting the fuselage side-on. Independent noise per
##                  ear gives a wide, natural image.
##   * Buffet     - near the stall the separated wake beats on the tail at
##                  ~12 Hz: low-passed noise amplitude-modulated at that rate.
##   * Stall horn - the 172's electric reed horn: a bright ~1.9 kHz squeal
##                  with a slow warble, ramping in as the warning trips.
##   * Ground     - deep rolling rumble proportional to ground speed with a
##                  slow "seams in the pavement" modulation, a touchdown
##                  thump scaled by sink rate, and a short tire chirp when
##                  touching down at speed.
##   * Flaps      - the electric flap motor's twin-tone whine while the
##                  surfaces are in transit.
##
## Registered as an autoload; one push_buffer per fill (never per sample).

const SR := 22050.0

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback

# --- oscillator / filter state ---------------------------------------------
var _eng_phase := 0.0
var _fire_jit := 1.0        # per-firing amplitude jitter (idle lope)
var _pulse_dc := 0.3        # slow DC tracker to centre the pulse train
var _exh_lp := 0.0          # combustion-noise low-pass
var _wind_lp_l := 0.0
var _wind_lp_r := 0.0
var _grd_lp := 0.0
var _bump_lp := 0.0         # very slow modulator: pavement seams
var _buf_lp := 0.0          # buffet noise band
var _buf_phase := 0.0       # buffet 12 Hz beat
var _horn_phase := 0.0
var _horn_warb := 0.0
var _horn_env := 0.0
var _flap_phase := 0.0
var _flap_env := 0.0
var _td_env := 0.0          # touchdown thump envelope
var _sq_env := 0.0          # tire-chirp envelope
var _sq_phase := 0.0

# --- smoothed drivers (avoid zipper noise) ----------------------------------
var _rpm_s := 700.0
var _thr_s := 0.0
var _wind_s := 0.0
var _grd_s := 0.0
var _prev_on_ground := true
var _prev_flaps := 0.0
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
	# Touchdown one-shots on the air->ground transition.
	var og: bool = FlightData.on_ground
	if og and not _prev_on_ground:
		_td_env = clampf(absf(FlightData.vertical_speed_fpm) / 500.0, 0.25, 1.0)
		if FlightData.ground_speed_kt > 25.0:
			_sq_env = clampf(FlightData.ground_speed_kt / 70.0, 0.4, 1.0)
	_prev_on_ground = og

	if _playback == null:
		return
	_fill()


func _fill() -> void:
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return

	# ---- per-block parameter update ----------------------------------------
	_rpm_s = lerpf(_rpm_s, FlightData.engine_rpm, 0.25)
	_thr_s = lerpf(_thr_s, FlightData.throttle_pct / 100.0, 0.25)
	var ias: float = FlightData.indicated_airspeed_kt
	_wind_s = lerpf(_wind_s, clampf((ias - 20.0) / 140.0, 0.0, 1.0), 0.2)
	var gs_target := 0.0
	if FlightData.on_ground:
		gs_target = clampf(FlightData.ground_speed_kt / 55.0, 0.0, 1.0)
	_grd_s = lerpf(_grd_s, gs_target, 0.2)

	var f0 := maxf(_rpm_s, 250.0) / 30.0            # firing rate: 2 per rev
	var rough := lerpf(0.30, 0.04, clampf((_rpm_s - 650.0) / 1400.0, 0.0, 1.0))
	var eng_amp := 0.14 + 0.46 * _thr_s
	var chop := clampf((_rpm_s - 1500.0) / 1300.0, 0.0, 1.0) \
		* (0.35 + 0.65 * _wind_s)                    # prop chop depth
	var exh_noise_amp := 0.05 + 0.30 * _thr_s

	# Wind: gain grows ~quadratically, brightness (filter k) with speed too.
	var wind_amp := 0.36 * _wind_s * _wind_s + 0.05 * _wind_s
	var slip_hiss := clampf(absf(FlightData.slip_skid) * 2.0, 0.0, 1.0) \
		* _wind_s * 0.15
	var k_wind := 0.05 + 0.28 * _wind_s

	var stalling: bool = FlightData.stall_warning
	var buffeting := stalling and not FlightData.on_ground
	_horn_env = move_toward(_horn_env, 1.0 if stalling else 0.0, 0.08)

	# Electric flap motor: whines while the surfaces are moving.
	var flaps: float = FlightData.flaps_deg
	var flap_moving := absf(flaps - _prev_flaps) > 0.005
	_prev_flaps = flaps
	_flap_env = move_toward(_flap_env, 1.0 if flap_moving else 0.0, 0.15)

	var horn_on := _horn_env > 0.001
	var flap_on := _flap_env > 0.001
	var grd_on := _grd_s > 0.001

	if _buf.size() != frames:
		_buf.resize(frames)
	for i in range(frames):
		# --- Engine: exhaust pulse train + crank rumble + prop chop --------
		_eng_phase += f0 / SR
		if _eng_phase >= 1.0:
			_eng_phase -= 1.0
			_fire_jit = 1.0 + rough * (randf() * 2.0 - 1.0)
		# Raised-cosine pulse, cubed to sharpen: bright "pop" per firing.
		var c := 0.5 + 0.5 * cos(TAU * (_eng_phase - 0.5))
		var pulse := c * c * c
		_pulse_dc += (pulse - _pulse_dc) * 0.002
		var noise := randf() * 2.0 - 1.0
		_exh_lp += (noise - _exh_lp) * (0.10 + 0.20 * _thr_s)
		var e := (pulse - _pulse_dc) * 1.5 * _fire_jit    # exhaust pulses
		e += 0.35 * sin(TAU * _eng_phase * 0.5)           # crankshaft rumble
		e += _exh_lp * exh_noise_amp                      # combustion noise
		e += noise * (0.30 + 0.70 * c) * chop * 0.35      # prop blade chop
		e *= eng_amp * 0.42

		# --- Wind: independent rumble+hiss per ear -------------------------
		var nl := randf() * 2.0 - 1.0
		var nr := randf() * 2.0 - 1.0
		_wind_lp_l += (nl - _wind_lp_l) * k_wind
		_wind_lp_r += (nr - _wind_lp_r) * k_wind
		var wl := _wind_lp_l * wind_amp + (nl - _wind_lp_l) * (wind_amp * 0.22 + slip_hiss)
		var wr := _wind_lp_r * wind_amp + (nr - _wind_lp_r) * (wind_amp * 0.22 + slip_hiss)

		# --- Mono extras ----------------------------------------------------
		var m := 0.0

		# Pre-stall buffet: low noise band beating at ~12 Hz on the airframe.
		if buffeting:
			_buf_phase += 12.0 / SR
			if _buf_phase >= 1.0:
				_buf_phase -= 1.0
			_buf_lp += (nl - _buf_lp) * 0.03
			m += _buf_lp * (0.55 + 0.45 * sin(TAU * _buf_phase)) * 0.9

		# Stall horn: bright reed squeal with a slow warble.
		if horn_on:
			_horn_warb += 5.5 / SR
			if _horn_warb >= 1.0:
				_horn_warb -= 1.0
			_horn_phase += (1900.0 + 60.0 * sin(TAU * _horn_warb)) / SR
			if _horn_phase >= 1.0:
				_horn_phase -= 1.0
			var h := sin(TAU * _horn_phase) + 0.55 * sin(TAU * _horn_phase * 2.0)
			m += clampf(h * 1.6, -1.0, 1.0) * 0.11 * _horn_env

		# Ground roll: deep rumble + slow seam bumps, only on the wheels.
		if grd_on:
			_grd_lp += (nr - _grd_lp) * 0.045
			_bump_lp += (nl - _bump_lp) * 0.0025
			m += _grd_lp * (0.8 + 1.6 * absf(_bump_lp)) * _grd_s * 0.5

		# Touchdown thump (filtered burst) and tire chirp.
		if _td_env > 0.0001:
			m += _grd_lp * _td_env * 2.2 + nl * _td_env * 0.18
			_td_env *= 0.9993
		if _sq_env > 0.0001:
			_sq_phase += (1150.0 + 250.0 * _sq_env) / SR
			if _sq_phase >= 1.0:
				_sq_phase -= 1.0
			m += sin(TAU * _sq_phase) * _sq_env * 0.16
			_sq_env *= 0.9990

		# Flap motor: twin-tone electric whine.
		if flap_on:
			_flap_phase += 410.0 / SR
			if _flap_phase >= 1.0:
				_flap_phase -= 1.0
			m += (0.6 * sin(TAU * _flap_phase) + 0.4 * sin(TAU * _flap_phase * 2.0)) \
				* _flap_env * 0.045

		# --- Mix with a gentle soft-knee ------------------------------------
		var l := (e + m + wl) * 0.75
		var r := (e + m + wr) * 0.75
		_buf[i] = Vector2(clampf(l - l * l * l * 0.15, -1.0, 1.0),
				clampf(r - r * r * r * 0.15, -1.0, 1.0))
	# One native call per block instead of one per sample (~22k/sec).
	_playback.push_buffer(_buf)
