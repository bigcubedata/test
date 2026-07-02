extends Node
## Instructional traffic-pattern demo pilot ("五边起落" lesson).
##
## Flies a textbook left-hand pattern for runway 36 with the by-the-book
## C172S numbers — full power, rotate 55, Vy 74 climb, 1000 ft AGL pattern,
## abeam-the-numbers power/flap reduction, 73 KIAS base, 65 KIAS stabilised
## final, idle flare, mains-first touchdown, centreline rollout — while a
## lesson HUD narrates each leg (Chinese + English) with live data, and the
## camera cuts between the instructional viewpoints.
##
## Not autoloaded in normal play. Add to autoloads to record the lesson:
## in a window it drives the normal renderer (use Movie Maker to record);
## headless it auto-runs 8x fast and prints PAT: telemetry for validation.

enum Leg { ROLL, UPWIND, XWIND_TURN, XWIND, DWN_TURN, DOWNWIND, ABEAM, BASE_TURN, BASE, FINAL_TURN, FINAL, FLARE, ROLLOUT, DONE }

const LEG_TEXT := {
	Leg.ROLL: ["起飞滑跑  TAKEOFF ROLL", "全油门 · 方向舵保持中线 · 55 KIAS 抬前轮"],
	Leg.UPWIND: ["一边·离场  UPWIND", "Vy 74 KIAS 直线爬升 · 保持跑道延长线"],
	Leg.XWIND_TURN: ["转二边  TURNING CROSSWIND", "500 ft AGL 以上 · 左坡度 20° · 继续爬升"],
	Leg.XWIND: ["二边  CROSSWIND", "保持 74 KIAS 爬升 · 建立侧风边"],
	Leg.DWN_TURN: ["转三边  TURNING DOWNWIND", "左转对正下风边 · 接近起落航线高度"],
	Leg.DOWNWIND: ["三边  DOWNWIND", "1000 ft AGL 平飞 · ~90 KIAS · 与跑道平行"],
	Leg.ABEAM: ["正切接地点  ABEAM", "收油门 · 白弧内放襟翼 10° · 建立 ~500 fpm 下降"],
	Leg.BASE_TURN: ["转四边  TURNING BASE", "左转 90° · 继续下降 · 检查间距"],
	Leg.BASE: ["四边  BASE", "襟翼 20° · 73 KIAS · 500 fpm 下降"],
	Leg.FINAL_TURN: ["转五边  TURNING FINAL", "对正跑道中线 · 不要带内侧坡度过大"],
	Leg.FINAL: ["五边  FINAL", "襟翼 30° · 65 KIAS · 稳定进近 · 瞄准接地点"],
	Leg.FLARE: ["拉平  FLARE", "收光油门 · 视线放远 · 带杆保持 · 主轮先接地"],
	Leg.ROLLOUT: ["着陆滑跑  ROLLOUT", "前轮轻放 · 刹车 · 方向舵保持中线"],
	Leg.DONE: ["完成  FULL STOP", "标准左起落航线完成 · 高度 1000 ft · 五边全程稳定"],
}

# Pattern geometry (runway 36: threshold z=530, centreline x=0, north = -Z).
const PATTERN_ALT_FT := 1000.0
const DOWNWIND_X := -1050.0     # left-hand pattern, west of the runway
const BASE_TURN_Z := 1690.0     # start the base turn here on downwind
const FINAL_TURN_X := -390.0    # start the final turn here on base
const AIM_Z := 490.0            # aim point: the runway numbers
const GLIDE_SLOPE := 0.066      # ~3.8 deg visual approach path

var leg: int = Leg.ROLL
var t := 0.0
var leg_t := 0.0
var ac: Aircraft
var cam: Node
var _hud: Control
var _headless := false
var _td_reported := false


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	if _headless:
		Engine.physics_ticks_per_second = 960
		Engine.time_scale = 8.0
		Engine.max_physics_steps_per_frame = 64
	else:
		# Recording: MSAA is very costly under software GL and the lesson
		# doesn't need it.
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		var layer := CanvasLayer.new()
		layer.layer = 5
		add_child(layer)
		_hud = LessonHud.new()
		_hud.pilot = self
		layer.add_child(_hud)


func _set_leg(l: int) -> void:
	leg = l
	leg_t = 0.0
	if _headless:
		print("PAT: t=%.0f leg=%s alt=%.0f ias=%.0f x=%.0f z=%.0f" % [t,
			Leg.keys()[l], FlightData.altitude_ft, FlightData.indicated_airspeed_kt,
			FlightData.pos_x, FlightData.pos_z])


func _physics_process(dt: float) -> void:
	t += dt
	leg_t += dt
	if ac == null:
		ac = Replay.aircraft
		if ac == null:
			return
		ac.control_override = true
		Wind.preset = 0   # calm for the reference lesson
		cam = get_tree().get_first_node_in_group("flight_camera")
	if _headless and t > 700.0:
		print("PAT: TIMEOUT in leg ", Leg.keys()[leg])
		get_tree().quit()
	if _headless and Engine.get_physics_frames() % 1800 == 0:   # every 15 s sim
		print("PAT: stat t=%.0f leg=%s alt=%.0f agl=%.0f ias=%.0f vs=%.0f hdg=%.0f x=%.0f z=%.0f" %
			[t, Leg.keys()[leg], FlightData.altitude_ft, FlightData.altitude_agl_ft,
			FlightData.indicated_airspeed_kt, FlightData.vertical_speed_fpm,
			FlightData.heading_deg, FlightData.pos_x, FlightData.pos_z])

	var ias: float = FlightData.indicated_airspeed_kt
	var alt: float = FlightData.altitude_ft
	var agl: float = FlightData.altitude_agl_ft
	var vs: float = FlightData.vertical_speed_fpm
	var x: float = FlightData.pos_x
	var z: float = FlightData.pos_z
	var av: Vector3 = ac.angular_velocity
	var omega: Vector3 = ac.global_transform.basis.inverse() * av
	var vx: float = ac.linear_velocity.x

	match leg:
		Leg.ROLL:
			ac.engine.throttle = 1.0
			_yaw_track(0.0, x, vx, av)
			_wings_level(omega)
			ac.input_pitch = 0.45 if ias >= 55.0 else 0.0
			if not FlightData.on_ground and agl > 20.0:
				_set_leg(Leg.UPWIND)
		Leg.UPWIND:
			ac.engine.throttle = 1.0
			_hold_track_hdg(0.0, 0.0, x, vx, omega)
			_pitch_att(_climb_att(ias, FlightData.VY), omega)
			_yaw_coord(omega)
			if agl >= 500.0:
				_set_leg(Leg.XWIND_TURN)
		Leg.XWIND_TURN:
			ac.engine.throttle = 1.0
			_bank_to_heading(270.0, omega, 20.0)
			_pitch_att(_climb_att(ias, FlightData.VY) - 1.0, omega)
			_yaw_coord(omega)
			if _hdg_err(270.0) < 8.0:
				_set_leg(Leg.XWIND)
		Leg.XWIND:
			ac.engine.throttle = 1.0
			_bank_to_heading(270.0, omega, 20.0)
			_pitch_att(_climb_att(ias, FlightData.VY), omega)
			_yaw_coord(omega)
			if x <= DOWNWIND_X + 400.0:
				_set_leg(Leg.DWN_TURN)
		Leg.DWN_TURN:
			ac.engine.throttle = 1.0
			_bank_to_heading(180.0, omega, 22.0)
			_pitch_att(_climb_att(ias, 76.0) - 1.5, omega)
			_yaw_coord(omega)
			if _hdg_err(180.0) < 8.0:
				_set_leg(Leg.DOWNWIND)
		Leg.DOWNWIND:
			# Climb the last bit if needed, then level at pattern altitude with
			# power for ~90 KIAS.
			if alt < PATTERN_ALT_FT - 80.0:
				ac.engine.throttle = 1.0
				_pitch_att(_climb_att(ias, 78.0), omega)
			else:
				ac.engine.throttle = clampf(0.62 + (90.0 - ias) * 0.025, 0.35, 0.85)
				_pitch_alt(PATTERN_ALT_FT, alt, vs, omega)
			_hold_track_hdg(180.0, DOWNWIND_X, x, vx, omega)
			_yaw_coord(omega)
			if z >= AIM_Z:
				FlightData.flaps_setting = 1
				_set_leg(Leg.ABEAM)
		Leg.ABEAM:
			# Abeam the numbers: power back, flaps 10, begin the descent.
			ac.engine.throttle = 0.36
			_hold_track_hdg(180.0, DOWNWIND_X, x, vx, omega)
			_pitch_att(0.0 + _spd_trim(ias, 80.0), omega)
			_yaw_coord(omega)
			if z >= BASE_TURN_Z:
				_set_leg(Leg.BASE_TURN)
		Leg.BASE_TURN:
			ac.engine.throttle = 0.32
			_bank_to_heading(90.0, omega, 22.0)
			_pitch_att(-0.5 + _spd_trim(ias, 75.0), omega)
			_yaw_coord(omega)
			if _hdg_err(90.0) < 8.0:
				FlightData.flaps_setting = 2
				_set_leg(Leg.BASE)
		Leg.BASE:
			ac.engine.throttle = 0.30
			_bank_to_heading(90.0, omega, 22.0)
			_pitch_att(-0.5 + _spd_trim(ias, 73.0), omega)
			_yaw_coord(omega)
			if x >= FINAL_TURN_X:
				_set_leg(Leg.FINAL_TURN)
		Leg.FINAL_TURN:
			ac.engine.throttle = 0.30
			_bank_to_heading(0.0, omega, 20.0)
			_pitch_att(-1.0 + _spd_trim(ias, 70.0), omega)
			_yaw_coord(omega)
			if _hdg_err(0.0) < 10.0:
				FlightData.flaps_setting = 3
				_set_leg(Leg.FINAL)
		Leg.FINAL:
			# Attitude for 65 KIAS, power for the glidepath to the aim point.
			var dist := maxf(z - AIM_Z, 1.0)
			var tgt_agl_ft := dist * GLIDE_SLOPE * 3.281
			ac.engine.throttle = clampf(0.28 + (agl - tgt_agl_ft) * -0.004
				+ (65.0 - ias) * 0.014, 0.05, 0.60)
			_hold_track_hdg(0.0, 0.0, x, vx, omega, 0.0, 0.10)
			_pitch_att(-2.0 + _spd_trim(ias, 65.0), omega)
			_yaw_coord(omega)
			if agl < 22.0 and z > AIM_Z - 80.0:
				_set_leg(Leg.FLARE)
		Leg.FLARE:
			ac.engine.throttle = 0.0
			_hold_track_hdg(0.0, 0.0, x, vx, omega, 0.0, 0.06)
			# Arrest the sink and hold off: target a gentle -100 fpm.
			ac.input_pitch = clampf(ac.input_pitch + ((-100.0 - vs) * 0.00030
				- omega.x * 1.5) * 1.0, 0.0, 0.75)
			if FlightData.on_ground:
				if _headless and not _td_reported:
					_td_reported = true
					print("PAT: TOUCHDOWN vs=%.0ffpm pitch=%.1f x=%.1f z=%.0f ias=%.0f" %
						[vs, FlightData.pitch_deg, x, z, ias])
				_set_leg(Leg.ROLLOUT)
		Leg.ROLLOUT:
			ac.engine.throttle = 0.0
			ac.input_pitch = maxf(0.30 - leg_t * 0.12, 0.0)  # ease the nose down
			_yaw_track(0.0, x, vx, av)
			_wings_level(omega)
			ac.brakes_on = leg_t > 2.5
			if FlightData.ground_speed_kt < 2.0:
				if _headless:
					print("PAT: STOPPED z=%.0f  (threshold 530)" % z)
					print("PAT: done")
					get_tree().quit()
				_set_leg(Leg.DONE)
		Leg.DONE:
			ac.engine.throttle = 0.0
			ac.brakes_on = true
			if not _headless and leg_t > 8.0:
				get_tree().quit()   # end of lesson: finalise the recording

	_update_camera(agl)


# ---------------------------------------------------------------- control --
func _hdg_err(tgt: float) -> float:
	return absf(wrapf(tgt - FlightData.heading_deg + 180.0, 0.0, 360.0) - 180.0)


func _bank_to_heading(tgt_hdg: float, omega: Vector3, max_bank: float) -> void:
	var e := wrapf(tgt_hdg - FlightData.heading_deg + 180.0, 0.0, 360.0) - 180.0
	var tgt_roll := clampf(e * 1.3, -max_bank, max_bank)
	ac.input_roll = clampf(-(FlightData.roll_deg - tgt_roll) * 0.055 + omega.z * 1.4, -1.0, 1.0)


## Track a north/south line (or plain heading hold when gain is 0).
func _hold_track_hdg(base_hdg: float, line_x: float, x: float, vx: float,
		omega: Vector3, _z := 0.0, gain := 0.12) -> void:
	var corr := 0.0
	if gain > 0.0:
		var err := x - line_x
		if base_hdg > 90.0 and base_hdg < 270.0:   # southbound: sign flips
			corr = clampf(err * gain + vx * 1.0, -25.0, 25.0)
		else:
			corr = -clampf(err * gain + vx * 1.0, -25.0, 25.0)
	_bank_to_heading(base_hdg + corr, omega, 25.0)


func _wings_level(omega: Vector3) -> void:
	ac.input_roll = clampf(-FlightData.roll_deg * 0.06 + omega.z * 1.5, -1.0, 1.0)


## Attitude hold — far more stable than chasing airspeed with pitch (no
## phugoid); the airspeed target trims the attitude a few degrees instead.
## A slow integral term removes the steady-state error (elevator trim).
var _pitch_i := 0.0

func _pitch_att(tgt_deg: float, omega: Vector3) -> void:
	var err := tgt_deg - FlightData.pitch_deg
	_pitch_i = clampf(_pitch_i + err * 0.25 / 120.0, -0.35, 0.55)
	ac.input_pitch = clampf(err * 0.12 + _pitch_i - omega.x * 2.5, -0.5, 0.75)


## Climb attitude around ~7.5 deg, trimmed by airspeed error — but never so
## low that the nose drops right after liftoff while speed is still building.
func _climb_att(ias: float, tgt_kt: float) -> float:
	return clampf(7.5 + (ias - tgt_kt) * 0.30, 6.5, 10.5)


## Descent attitude trim: fast -> raise the nose a little, slow -> lower it.
func _spd_trim(ias: float, tgt_kt: float) -> float:
	return clampf((ias - tgt_kt) * 0.30, -3.0, 3.0)


func _pitch_alt(tgt_ft: float, alt: float, vs: float, omega: Vector3) -> void:
	ac.input_pitch = clampf((tgt_ft - alt) * 0.004 - vs * 0.0005 - omega.x * 2.0, -0.8, 0.8)


## Rudder: hold the centreline on the ground.
func _yaw_track(line_x: float, x: float, vx: float, av: Vector3) -> void:
	var hdg_err := wrapf(FlightData.heading_deg + 180.0, 0.0, 360.0) - 180.0
	ac.input_yaw = clampf(-hdg_err * 0.08 - (x - line_x) * 0.02 - vx * 0.05 + av.y * 1.5, -1.0, 1.0)


## Rudder in flight: "step on the ball" — ball right means right rudder. This
## both counters the full-power left yaw and coordinates the turns.
func _yaw_coord(_omega: Vector3) -> void:
	ac.input_yaw = clampf(FlightData.slip_skid * 3.5, -1.0, 1.0)


# ----------------------------------------------------------------- camera --
func _update_camera(agl: float) -> void:
	if cam == null:
		return
	var v := 1   # chase by default
	match leg:
		Leg.ROLL:
			v = 0                       # cockpit: rotation sight picture
		Leg.UPWIND:
			v = 0 if leg_t < 4.0 else 1 # hold the liftoff view a beat
		Leg.XWIND_TURN, Leg.XWIND:
			v = 2                       # wing view shows the bank
		Leg.DWN_TURN, Leg.DOWNWIND:
			v = 1
		Leg.BASE_TURN, Leg.BASE:
			v = 2
		Leg.FINAL_TURN:
			v = 1
		Leg.FINAL:
			v = 0 if agl < 320.0 else 1 # cockpit for the stabilised approach
		Leg.FLARE:
			v = 0                       # the flare sight picture
		Leg.ROLLOUT, Leg.DONE:
			v = 0 if leg_t < 3.0 else 1
	if int(cam.view) != v:
		cam.view = v


# --------------------------------------------------------------- lesson HUD --
class LessonHud extends Control:
	var pilot: Node
	var _font: Font
	var _bold: Font

	func _ready() -> void:
		_font = UiFont.regular()
		_bold = UiFont.bold()
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		# Under a CanvasLayer the Control itself has zero size; draw in the
		# canvas coordinate space of the viewport instead.
		var s := get_viewport_rect().size
		var texts: Array = pilot.LEG_TEXT[pilot.leg]
		var w := 780.0
		var xx := s.x * 0.5 - w * 0.5
		var y := 120.0
		draw_rect(Rect2(xx, y, w, 96), Color(0.03, 0.05, 0.08, 0.82))
		draw_rect(Rect2(xx, y, 6, 96), Color(0.1, 0.85, 1.0))
		draw_string(_bold, Vector2(xx + 22, y + 36), texts[0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1))
		draw_string(_font, Vector2(xx + 22, y + 66), texts[1],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 0.92, 1.0))
		var live := "IAS %d kt   AGL %d ft   VS %+d fpm   HDG %03d°   襟翼 %d°" % [
			roundi(FlightData.indicated_airspeed_kt), roundi(FlightData.altitude_agl_ft),
			roundi(FlightData.vertical_speed_fpm / 10.0) * 10,
			roundi(FlightData.heading_deg), int(FlightData.flaps_deg)]
		draw_string(_font, Vector2(xx + 22, y + 88), live,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.55, 0.95, 0.55))
