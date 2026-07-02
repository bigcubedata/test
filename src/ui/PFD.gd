extends Control
## Garmin G1000-style Primary Flight Display (faithful restyle).
##
## Drawn procedurally from the FlightData blackboard. Styling follows the real
## G1000: gradient sky/ground, anti-aliased scales, white digital readouts in
## black chevron boxes, cyan selection bugs, a magenta airspeed-trend vector,
## and a bottom HSI. Scales to any display size via `_u`.

# --- Palette (Garmin-ish) -------------------------------------------------
const SKY_TOP := Color(0.05, 0.30, 0.66)
const SKY_HZN := Color(0.22, 0.56, 0.86)
const GND_HZN := Color(0.55, 0.38, 0.15)
const GND_BOT := Color(0.28, 0.18, 0.07)
const C_WHITE := Color(1, 1, 1)
const C_BLACK := Color(0, 0, 0)
const C_TAPE := Color(0.04, 0.04, 0.05, 1.0)
const C_GREEN := Color(0.25, 0.95, 0.30)
const C_AMBER := Color(1.0, 0.72, 0.08)
const C_RED := Color(0.95, 0.16, 0.16)
const C_CYAN := Color(0.10, 0.85, 1.0)
const C_MAG := Color(1.0, 0.18, 0.92)
const C_ORANGE := Color(1.0, 0.78, 0.0)

const REF_H := 480.0
var _u := 1.0
var _pd := 6.5
var _pk := 4.2
var _pa := 0.62   # px per ft
var _font: Font
var _bold: Font
var _trend := 0.0
var _prev_ias := 0.0


func _ready() -> void:
	_font = UiFont.regular()
	_bold = UiFont.bold()
	set_process(true)


func _process(delta: float) -> void:
	var ias: float = FlightData.indicated_airspeed_kt
	if delta > 0.0:
		_trend = lerpf(_trend, (ias - _prev_ias) / delta, clampf(delta * 3.0, 0.0, 1.0))
	_prev_ias = ias
	queue_redraw()


func _draw() -> void:
	var s := size
	_u = s.y / REF_H
	_pd = 6.6 * _u
	_pk = 4.4 * _u
	_pa = 0.66 * _u
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.02, 0.03))

	var top := 4.0 * _u
	var att_h := s.y * 0.60
	# Attitude sits BETWEEN the tapes so nothing bleeds through.
	var att := Rect2(s.x * 0.145, top, s.x * 0.645, att_h)
	_draw_attitude(att)

	var tape_h := att_h
	_draw_airspeed(Rect2(6 * _u, top, s.x * 0.135, tape_h))
	_draw_altitude(Rect2(s.x * 0.79, top, s.x * 0.135, tape_h))
	_draw_vsi(Rect2(s.x * 0.925 + 2, top, s.x * 0.07, tape_h))
	# HSI kept clear of the very bottom edge so it isn't clipped on the panel.
	_draw_hsi(Vector2(s.x * 0.5, s.y * 0.80), s.y * 0.135)
	_draw_wind(s)
	_draw_annunciations(s)


# --------------------------------------------------------------------------
#  Attitude
# --------------------------------------------------------------------------
func _draw_attitude(rect: Rect2) -> void:
	var c := rect.position + rect.size * 0.5
	var pitch: float = FlightData.pitch_deg
	var roll: float = FlightData.roll_deg

	draw_set_transform(c, deg_to_rad(-roll), Vector2.ONE)
	var off := pitch * _pd
	var big := maxf(rect.size.x, rect.size.y) * 2.2
	# Gradient sky and ground.
	draw_polygon(PackedVector2Array([
		Vector2(-big, -big + off), Vector2(big, -big + off), Vector2(big, off), Vector2(-big, off)]),
		PackedColorArray([SKY_TOP, SKY_TOP, SKY_HZN, SKY_HZN]))
	draw_polygon(PackedVector2Array([
		Vector2(-big, off), Vector2(big, off), Vector2(big, off + big), Vector2(-big, off + big)]),
		PackedColorArray([GND_HZN, GND_HZN, GND_BOT, GND_BOT]))
	draw_line(Vector2(-big, off), Vector2(big, off), C_WHITE, maxf(1.5, 2.0 * _u), true)

	# Pitch ladder.
	for deg in range(-90, 91, 5):
		if deg == 0:
			continue
		var y := -deg * _pd + off
		if absf(y - off) > rect.size.y * 0.62:
			continue
		var major := deg % 10 == 0
		var half := (52.0 if major else 26.0) * _u
		draw_line(Vector2(-half, y), Vector2(half, y), C_WHITE, maxf(1.0, 1.6 * _u), true)
		if major:
			var lbl := str(absi(deg))
			_text(Vector2(-half - 30 * _u, y + 6 * _u), lbl, 15, C_WHITE)
			_text(Vector2(half + 8 * _u, y + 6 * _u), lbl, 15, C_WHITE)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	_mask_outside(rect)

	_roll_scale(c, rect.size.y * 0.47)
	_roll_pointer(c, rect.size.y * 0.47, roll)

	# Fixed aircraft reference (G1000 split-wing boresight).
	var w := 4.0 * _u
	var L := 64.0 * _u
	var g := 16.0 * _u
	draw_line(Vector2(c.x - L, c.y), Vector2(c.x - g, c.y), C_ORANGE, w, true)
	draw_line(Vector2(c.x - g, c.y), Vector2(c.x - g, c.y + 11 * _u), C_ORANGE, w, true)
	draw_line(Vector2(c.x + g, c.y), Vector2(c.x + L, c.y), C_ORANGE, w, true)
	draw_line(Vector2(c.x + g, c.y), Vector2(c.x + g, c.y + 11 * _u), C_ORANGE, w, true)
	draw_rect(Rect2(c.x - 2.5 * _u, c.y - 2.5 * _u, 5 * _u, 5 * _u), C_ORANGE)

	draw_rect(rect, Color(0.35, 0.35, 0.4), false, 1.0)


func _roll_scale(c: Vector2, radius: float) -> void:
	for m in [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]:
		var ang := deg_to_rad(m - 90)
		var dir := Vector2(cos(ang), sin(ang))
		var tl := (13.0 if (m % 30 == 0 or m == 0) else 8.0) * _u
		draw_line(c + dir * (radius - tl), c + dir * radius, C_WHITE, maxf(1.0, 1.6 * _u), true)
	var top := c + Vector2(0, -radius)
	draw_colored_polygon(PackedVector2Array([
		top, top + Vector2(-8 * _u, -14 * _u), top + Vector2(8 * _u, -14 * _u)]), C_WHITE)


func _roll_pointer(c: Vector2, radius: float, roll: float) -> void:
	var ang := deg_to_rad(roll - 90)
	var dir := Vector2(cos(ang), sin(ang))
	var tip := c + dir * (radius - 1)
	var b1 := c + dir.rotated(0.055) * (radius - 15 * _u)
	var b2 := c + dir.rotated(-0.055) * (radius - 15 * _u)
	draw_colored_polygon(PackedVector2Array([tip, b1, b2]), C_WHITE)
	# Slip/skid bar just under the pointer.
	var slip: float = FlightData.slip_skid * 26.0 * _u
	var by := c.y - radius + 20 * _u
	draw_rect(Rect2(c.x - 13 * _u + slip, by, 26 * _u, 6 * _u), C_WHITE)


# --------------------------------------------------------------------------
#  Airspeed tape
# --------------------------------------------------------------------------
func _draw_airspeed(r: Rect2) -> void:
	_tape_bg(r)
	var cx := r.position.x + r.size.x
	var cy := r.position.y + r.size.y * 0.5
	var ias: float = FlightData.indicated_airspeed_kt

	# V-speed colour strip along the inner edge.
	var stripx := cx - 6 * _u
	_band(stripx, FlightData.VS0, FlightData.VFE, C_WHITE, ias, cy, r, 3.0)
	_band(stripx, FlightData.VS1, FlightData.VNO, C_GREEN, ias, cy, r, 6.0)
	_band(stripx, FlightData.VNO, FlightData.VNE, C_AMBER, ias, cy, r, 6.0)
	_band(stripx, FlightData.VNE, FlightData.VNE + 40, C_RED, ias, cy, r, 6.0)

	var per := (r.size.y * 0.5) / _pk
	var v := int(floor((ias - per) / 10.0) * 10)
	while v <= int(ias + per) + 10:
		if v >= 20:
			var y := cy - (v - ias) * _pk
			if y > r.position.y + 4 and y < r.position.y + r.size.y - 4:
				draw_line(Vector2(cx - 11 * _u, y), Vector2(cx - 2, y), C_WHITE, maxf(1.0, 1.4 * _u), true)
				_text(Vector2(r.position.x + 6 * _u, y + 6 * _u), str(v), 16, C_WHITE)
		v += 10

	# Trend vector (magenta), clipped to the tape.
	var pred := clampf(_trend * 6.0, -60.0, 60.0)
	if absf(pred) > 1.0:
		var ytip := clampf(cy - pred * _pk, r.position.y + 4.0, r.position.y + r.size.y - 4.0)
		draw_line(Vector2(cx - 3 * _u, cy), Vector2(cx - 3 * _u, ytip), C_MAG, maxf(2.0, 3.0 * _u), true)

	_value_box(Rect2(r.position.x, cy - 19 * _u, r.size.x + 9 * _u, 38 * _u), 1, "%d" % roundi(ias), 24)
	_text(Vector2(r.position.x + 4 * _u, r.position.y - 4 * _u), "KIAS", 13, C_CYAN)
	_text(Vector2(r.position.x, r.position.y + r.size.y + 18 * _u),
		"TAS %dKT" % roundi(FlightData.true_airspeed_kt), 14, C_WHITE)


func _band(x: float, lo: float, hi: float, col: Color, ias: float, cy: float, r: Rect2, w: float) -> void:
	var y0 := clampf(cy - (lo - ias) * _pk, r.position.y, r.position.y + r.size.y)
	var y1 := clampf(cy - (hi - ias) * _pk, r.position.y, r.position.y + r.size.y)
	var top := minf(y0, y1)
	var bot := maxf(y0, y1)
	if bot - top > 0.5:
		draw_rect(Rect2(x, top, w * _u, bot - top), col)


# --------------------------------------------------------------------------
#  Altitude tape
# --------------------------------------------------------------------------
func _draw_altitude(r: Rect2) -> void:
	_tape_bg(r)
	var cx := r.position.x
	var cy := r.position.y + r.size.y * 0.5
	var alt: float = FlightData.altitude_ft

	# Selected altitude bug + readout (cyan) at the top.
	_text(Vector2(cx + 4 * _u, r.position.y - 4 * _u), "ALT", 13, C_CYAN)

	var per := (r.size.y * 0.5) / _pa
	var a := int(floor((alt - per) / 100.0) * 100)
	while a <= int(alt + per) + 100:
		var y := cy - (a - alt) * _pa
		if y > r.position.y + 4 and y < r.position.y + r.size.y - 4:
			draw_line(Vector2(cx + 2, y), Vector2(cx + 11 * _u, y), C_WHITE, maxf(1.0, 1.4 * _u), true)
			if a % 500 == 0:
				_text(Vector2(cx + 15 * _u, y + 6 * _u), str(a), 15, C_WHITE)
		a += 100

	_value_box(Rect2(cx - 9 * _u, cy - 19 * _u, r.size.x + 9 * _u, 38 * _u), -1, "%d" % roundi(alt), 22)
	# Baro setting box.
	_text(Vector2(cx, r.position.y + r.size.y + 18 * _u), "29.92IN", 14, C_CYAN)


# --------------------------------------------------------------------------
#  Vertical speed
# --------------------------------------------------------------------------
func _draw_vsi(r: Rect2) -> void:
	draw_rect(r, C_TAPE)
	var cx := r.position.x
	var cy := r.position.y + r.size.y * 0.5
	var maxf_ := 2000.0
	var ppf := (r.size.y * 0.46) / maxf_
	for f in [-2000, -1000, 1000, 2000]:
		var y: float = cy - f * ppf
		draw_line(Vector2(cx, y), Vector2(cx + 7 * _u, y), C_WHITE, maxf(1.0, 1.2 * _u), true)
		_text(Vector2(cx + 8 * _u, y + 4 * _u), str(absi(f) / 1000), 11, C_WHITE)
	draw_line(Vector2(cx, cy), Vector2(cx + 5 * _u, cy), Color(0.5, 0.5, 0.55), 1.0, true)
	var vs: float = clampf(FlightData.vertical_speed_fpm, -maxf_, maxf_)
	var yv := cy - vs * ppf
	var ptr := PackedVector2Array([
		Vector2(cx, yv), Vector2(cx + 14 * _u, yv - 9 * _u), Vector2(cx + 36 * _u, yv - 9 * _u),
		Vector2(cx + 36 * _u, yv + 9 * _u), Vector2(cx + 14 * _u, yv + 9 * _u)])
	draw_colored_polygon(ptr, C_MAG)
	if absf(FlightData.vertical_speed_fpm) > 50:
		_text(Vector2(cx + 14 * _u, yv + 4 * _u), "%d" % (roundi(FlightData.vertical_speed_fpm / 50.0) * 50), 10, C_WHITE)
	_text(Vector2(r.position.x, r.position.y - 4 * _u), "VS", 12, C_CYAN)


# --------------------------------------------------------------------------
#  HSI
# --------------------------------------------------------------------------
func _draw_hsi(c: Vector2, radius: float) -> void:
	var hdg: float = FlightData.heading_deg
	draw_circle(c, radius + 8 * _u, Color(0.02, 0.02, 0.03))
	draw_arc(c, radius, 0, TAU, 72, Color(0.5, 0.5, 0.55), maxf(1.0, 1.4 * _u), true)
	for deg in range(0, 360, 5):
		var a := deg_to_rad(deg - hdg - 90)
		var dir := Vector2(cos(a), sin(a))
		var major := deg % 30 == 0
		var tl := (13.0 if major else 7.0) * _u
		draw_line(c + dir * (radius - tl), c + dir * radius, C_WHITE, maxf(1.0, 1.3 * _u), true)
		if major:
			var lbl := ""
			match deg:
				0: lbl = "N"
				90: lbl = "E"
				180: lbl = "S"
				270: lbl = "W"
				_: lbl = str(deg / 10)
			var tp := c + dir * (radius - 26 * _u)
			_text_centered(tp, lbl, 15, C_WHITE)
	# Aircraft symbol.
	draw_line(c + Vector2(0, -15 * _u), c + Vector2(0, 15 * _u), C_WHITE, maxf(2.0, 3.0 * _u), true)
	draw_line(c + Vector2(-13 * _u, 0), c + Vector2(13 * _u, 0), C_WHITE, maxf(2.0, 3.0 * _u), true)
	# Lubber + heading box.
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -radius - 3 * _u), c + Vector2(-8 * _u, -radius - 16 * _u),
		c + Vector2(8 * _u, -radius - 16 * _u)]), C_WHITE)
	var bx := Rect2(c.x - 30 * _u, c.y - radius - 46 * _u, 60 * _u, 26 * _u)
	draw_rect(bx, C_BLACK)
	draw_rect(bx, C_WHITE, false, maxf(1.0, 1.3 * _u))
	_text_centered(Vector2(c.x, c.y - radius - 26 * _u), "%03d°" % roundi(hdg), 18, C_WHITE)


# --------------------------------------------------------------------------
#  Wind data box (G1000 option 2: relative arrow + direction/speed)
# --------------------------------------------------------------------------
func _draw_wind(s: Vector2) -> void:
	var ox := s.x * 0.075
	var oy := s.y * 0.715
	_text(Vector2(ox, oy), "WIND", 13, C_CYAN)
	var spd: float = FlightData.wind_speed_kt
	if spd < 0.8:
		_text(Vector2(ox, oy + 18 * _u), "CALM", 14, C_WHITE)
		return
	# Arrow shows where the wind blows TO, relative to the aircraft heading —
	# an arrow from the left means wind from the left.
	var rel := deg_to_rad(FlightData.wind_dir_deg + 180.0 - FlightData.heading_deg)
	var c := Vector2(ox + 14 * _u, oy + 32 * _u)
	var dir := Vector2(sin(rel), -cos(rel))
	var arm := 12.0 * _u
	draw_line(c - dir * arm, c + dir * arm, C_WHITE, maxf(1.5, 2.0 * _u), true)
	var tip := c + dir * (arm + 5 * _u)
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([
		tip, c + dir * arm - side * 4.5 * _u, c + dir * arm + side * 4.5 * _u]), C_WHITE)
	_text(Vector2(ox + 34 * _u, oy + 28 * _u), "%03d°" % roundi(FlightData.wind_dir_deg), 13, C_WHITE)
	_text(Vector2(ox + 34 * _u, oy + 44 * _u), "%d KT" % roundi(spd), 13, C_WHITE)
	# Active preset (cycled with V), so the pilot sees what V just selected.
	_text(Vector2(ox, oy + 60 * _u), Wind.preset_name(), 11, Color(0.6, 0.65, 0.7))


# --------------------------------------------------------------------------
#  Annunciations
# --------------------------------------------------------------------------
func _draw_annunciations(s: Vector2) -> void:
	if FlightData.stall_warning:
		var r := Rect2(s.x * 0.5 - 64 * _u, 8 * _u, 128 * _u, 28 * _u)
		draw_rect(r, C_RED)
		draw_rect(r, C_WHITE, false, 1.5)
		_text_centered(Vector2(s.x * 0.5, 28 * _u), "STALL", 18, C_WHITE)
	_text(Vector2(8 * _u, s.y - 10 * _u), "FLAPS %d°" % int(FlightData.flaps_deg), 14, C_WHITE)
	if FlightData.parking_brake:
		_text(Vector2(8 * _u, s.y - 28 * _u), "PARK BRK", 14, C_AMBER)


# --------------------------------------------------------------------------
#  Helpers
# --------------------------------------------------------------------------
func _tape_bg(r: Rect2) -> void:
	draw_rect(r, C_TAPE)
	draw_line(Vector2(r.position.x + r.size.x, r.position.y),
		Vector2(r.position.x + r.size.x, r.position.y + r.size.y), Color(0.4, 0.4, 0.45), 1.0, true)


## A digital-readout box with a chevron pointing toward the attitude.
## dir = 1 -> chevron on the right (airspeed); dir = -1 -> left (altitude).
func _value_box(box: Rect2, dir: int, text: String, fsize: int) -> void:
	var yc := box.position.y + box.size.y * 0.5
	var ch := 9.0 * _u
	var pts: PackedVector2Array
	if dir == 1:
		var xr := box.position.x + box.size.x
		pts = PackedVector2Array([
			Vector2(box.position.x, box.position.y), Vector2(xr - ch, box.position.y),
			Vector2(xr, yc), Vector2(xr - ch, box.position.y + box.size.y),
			Vector2(box.position.x, box.position.y + box.size.y)])
	else:
		var xl := box.position.x
		pts = PackedVector2Array([
			Vector2(xl + ch, box.position.y), Vector2(box.position.x + box.size.x, box.position.y),
			Vector2(box.position.x + box.size.x, box.position.y + box.size.y),
			Vector2(xl + ch, box.position.y + box.size.y), Vector2(xl, yc)])
	draw_colored_polygon(pts, C_BLACK)
	draw_polyline(pts + PackedVector2Array([pts[0]]), C_WHITE, maxf(1.0, 1.5 * _u), true)
	var off_x := (10.0 if dir == 1 else 6.0) * _u
	draw_string(_bold, Vector2(box.position.x + off_x, yc + fsize * 0.36 * _u),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(fsize * _u), C_WHITE)


func _text(pos: Vector2, text: String, fs: int, col: Color) -> void:
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(fs * _u), col)


func _text_centered(pos: Vector2, text: String, fs: int, col: Color) -> void:
	var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(fs * _u))
	draw_string(_font, pos - Vector2(sz.x * 0.5, -sz.y * 0.3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(fs * _u), col)


func _mask_outside(rect: Rect2) -> void:
	var s := size
	var bg := Color(0.02, 0.02, 0.03)
	draw_rect(Rect2(0, 0, s.x, rect.position.y), bg)
	draw_rect(Rect2(0, rect.position.y + rect.size.y, s.x, s.y - (rect.position.y + rect.size.y)), bg)
	draw_rect(Rect2(0, 0, rect.position.x, s.y), bg)
	draw_rect(Rect2(rect.position.x + rect.size.x, 0, s.x - (rect.position.x + rect.size.x), s.y), bg)
