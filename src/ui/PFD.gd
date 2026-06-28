extends Control
## Garmin G1000-style Primary Flight Display.
##
## Everything is drawn procedurally in _draw() from the shared FlightData
## blackboard, so the display has no scene dependencies and scales to any
## panel size. Layout mirrors a real G1000 PFD:
##   * Centre: attitude indicator with pitch ladder, roll scale, slip/skid.
##   * Left:   airspeed tape with V-speed colour arcs.
##   * Right:  altitude tape + vertical-speed indicator.
##   * Bottom: HSI compass rose with heading bug.
##
## Colours follow the Garmin convention (sky blue / ground brown, magenta
## bugs, white scales, green/amber/red speed arcs).

# --- Palette --------------------------------------------------------------
const C_SKY := Color(0.16, 0.55, 0.85)
const C_GROUND := Color(0.45, 0.30, 0.12)
const C_HORIZON := Color(1, 1, 1)
const C_TAPE_BG := Color(0.10, 0.10, 0.12, 0.78)
const C_TEXT := Color(1, 1, 1)
const C_MAGENTA := Color(1.0, 0.2, 1.0)
const C_GREEN := Color(0.2, 0.9, 0.2)
const C_AMBER := Color(1.0, 0.75, 0.1)
const C_RED := Color(0.95, 0.15, 0.15)
const C_WHITE := Color(1, 1, 1)
const C_BLACK := Color(0, 0, 0)
const C_YELLOW := Color(1.0, 0.85, 0.0)

const PX_PER_DEG := 6.5    # pitch ladder scale
const PX_PER_KT := 4.2     # airspeed tape scale
const PX_PER_100FT := 62.0 # altitude tape scale

var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()  # instruments update every frame


func _draw() -> void:
	var s := size
	# Overall PFD background.
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.04, 0.04, 0.05))

	var att_rect := Rect2(s.x * 0.18, 8, s.x * 0.64, s.y * 0.55)
	_draw_attitude(att_rect)
	_draw_airspeed_tape(Rect2(8, att_rect.position.y, s.x * 0.16 - 12, att_rect.size.y))
	_draw_altitude_tape(Rect2(s.x * 0.82 + 4, att_rect.position.y, s.x * 0.12, att_rect.size.y))
	_draw_vsi(Rect2(s.x * 0.94 + 6, att_rect.position.y, s.x * 0.05, att_rect.size.y))
	_draw_hsi(Vector2(s.x * 0.5, s.y * 0.80), s.y * 0.135)
	_draw_annunciations(s)


# --------------------------------------------------------------------------
#  Attitude indicator
# --------------------------------------------------------------------------
func _draw_attitude(rect: Rect2) -> void:
	var center := rect.position + rect.size * 0.5
	var pitch := FlightData.pitch_deg
	var roll := FlightData.roll_deg

	draw_set_transform(center, deg_to_rad(-roll), Vector2.ONE)
	var pitch_offset := pitch * PX_PER_DEG
	var big := maxf(rect.size.x, rect.size.y) * 2.0

	# Sky and ground halves (oversized so they fill when banked).
	draw_rect(Rect2(-big, -big + pitch_offset, big * 2, big), C_SKY)
	draw_rect(Rect2(-big, pitch_offset, big * 2, big), C_GROUND)
	draw_line(Vector2(-big, pitch_offset), Vector2(big, pitch_offset), C_HORIZON, 2.0)

	# Pitch ladder.
	for deg in range(-90, 91, 10):
		if deg == 0:
			continue
		var y := -deg * PX_PER_DEG + pitch_offset
		if absf(y - pitch_offset) > rect.size.y:
			continue
		var half := 46.0 if absi(deg) % 20 == 0 else 26.0
		draw_line(Vector2(-half, y), Vector2(half, y), C_HORIZON, 1.5)
		var label := str(absi(deg))
		_text(Vector2(-half - 34, y + 6), label, 16, C_WHITE)
		_text(Vector2(half + 6, y + 6), label, 16, C_WHITE)
	# Minor 5-degree ticks.
	for deg in range(-85, 86, 10):
		var y := -deg * PX_PER_DEG + pitch_offset
		if absf(y - pitch_offset) > rect.size.y:
			continue
		draw_line(Vector2(-14, y), Vector2(14, y), C_HORIZON, 1.0)

	draw_set_transform_matrix(Transform2D.IDENTITY)

	# Mask the spill outside the attitude window.
	_mask_outside(rect)

	# Roll scale arc with tick marks (fixed to the bezel).
	_draw_roll_scale(center, rect.size.y * 0.46)
	# Bank pointer (rotates with roll, points to current bank on the arc).
	_draw_bank_pointer(center, rect.size.y * 0.46, roll)
	# Slip/skid trapezoid under the pointer.
	_draw_slip_skid(center, rect.size.y * 0.46)

	# Fixed aircraft reference symbol (yellow wings + dot).
	draw_line(Vector2(center.x - 70, center.y), Vector2(center.x - 20, center.y), C_YELLOW, 4.0)
	draw_line(Vector2(center.x + 20, center.y), Vector2(center.x + 70, center.y), C_YELLOW, 4.0)
	draw_line(Vector2(center.x - 20, center.y), Vector2(center.x - 20, center.y + 12), C_YELLOW, 4.0)
	draw_line(Vector2(center.x + 20, center.y), Vector2(center.x + 20, center.y + 12), C_YELLOW, 4.0)
	draw_rect(Rect2(center.x - 4, center.y - 4, 8, 8), C_YELLOW)

	draw_rect(rect, Color(0.6, 0.6, 0.6), false, 2.0)


func _draw_roll_scale(center: Vector2, radius: float) -> void:
	var marks := [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]
	for m in marks:
		var ang := deg_to_rad(m - 90)  # 0 deg bank at top
		var dir := Vector2(cos(ang), sin(ang))
		var outer := center + dir * radius
		var tick_len := 14.0 if m % 30 == 0 or m == 0 else 9.0
		var inner := center + dir * (radius - tick_len)
		var col := C_WHITE
		draw_line(inner, outer, col, 2.0)
	# Sky-pointer triangle at the top (the fixed zero index).
	var top := center + Vector2(0, -radius)
	draw_colored_polygon(PackedVector2Array([
		top + Vector2(0, -2), top + Vector2(-8, -16), top + Vector2(8, -16)
	]), C_WHITE)


func _draw_bank_pointer(center: Vector2, radius: float, roll: float) -> void:
	# The pointer rides the fixed roll scale; tick for bank m sits at screen
	# angle (m - 90) deg, so the pointer for the current roll uses the same.
	var ang := deg_to_rad(roll - 90)
	var dir := Vector2(cos(ang), sin(ang))
	var tip := center + dir * (radius - 16)
	var left := center + (dir.rotated(0.06)) * (radius - 30)
	var right := center + (dir.rotated(-0.06)) * (radius - 30)
	draw_colored_polygon(PackedVector2Array([tip, left, right]), C_AMBER)


func _draw_slip_skid(center: Vector2, radius: float) -> void:
	# Trapezoid box just below the bank pointer; the gap slides with slip.
	var base_y := center.y - radius + 34
	var slip := FlightData.slip_skid * 22.0
	var w := 12.0
	draw_line(Vector2(center.x - 16, base_y), Vector2(center.x + 16, base_y), C_WHITE, 2.0)
	draw_rect(Rect2(center.x - w * 0.5 + slip, base_y + 3, w, 7), C_AMBER)


# --------------------------------------------------------------------------
#  Airspeed tape
# --------------------------------------------------------------------------
func _draw_airspeed_tape(rect: Rect2) -> void:
	draw_rect(rect, C_TAPE_BG)
	var cx := rect.position.x + rect.size.x
	var cy := rect.position.y + rect.size.y * 0.5
	var ias: float = FlightData.indicated_airspeed_kt

	# V-speed colour bands along the tape edge.
	_speed_band(rect, FlightData.VS0, FlightData.VFE, C_WHITE, ias, cy, 4.0)   # white arc
	_speed_band(rect, FlightData.VS1, FlightData.VNO, C_GREEN, ias, cy, 7.0)   # green arc
	_speed_band(rect, FlightData.VNO, FlightData.VNE, C_AMBER, ias, cy, 7.0)   # amber arc
	_speed_band(rect, FlightData.VNE, FlightData.VNE + 30, C_RED, ias, cy, 7.0) # red line region

	# Moving scale: a tick + label every 10 kt.
	var top_speed := ias + (rect.size.y * 0.5) / PX_PER_KT
	var low_speed := ias - (rect.size.y * 0.5) / PX_PER_KT
	var v := int(floor(low_speed / 10.0) * 10)
	while v <= int(top_speed) + 10:
		if v >= 20:
			var y := cy - (v - ias) * PX_PER_KT
			if y > rect.position.y and y < rect.position.y + rect.size.y:
				draw_line(Vector2(cx - 12, y), Vector2(cx, y), C_WHITE, 1.5)
				_text(Vector2(rect.position.x + 6, y + 6), str(v), 17, C_WHITE)
		v += 10

	# Centre readout box (current IAS).
	var box := Rect2(rect.position.x, cy - 18, rect.size.x + 14, 36)
	draw_rect(box, C_BLACK)
	draw_rect(box, C_WHITE, false, 1.5)
	_text(Vector2(box.position.x + 6, cy + 8), "%d" % roundi(ias), 26, C_GREEN)
	# Trend/label.
	_text(Vector2(rect.position.x + 4, rect.position.y - 6), "KIAS", 15, C_WHITE)
	# TAS readout at the bottom.
	_text(Vector2(rect.position.x + 2, rect.position.y + rect.size.y + 20),
		"TAS %d" % roundi(FlightData.true_airspeed_kt), 15, C_WHITE)


func _speed_band(rect: Rect2, lo: float, hi: float, col: Color, ias: float, cy: float, w: float) -> void:
	var x := rect.position.x + rect.size.x - w
	var y_lo := cy - (lo - ias) * PX_PER_KT
	var y_hi := cy - (hi - ias) * PX_PER_KT
	var top := clampf(minf(y_lo, y_hi), rect.position.y, rect.position.y + rect.size.y)
	var bot := clampf(maxf(y_lo, y_hi), rect.position.y, rect.position.y + rect.size.y)
	if bot - top > 0.5:
		draw_rect(Rect2(x, top, w, bot - top), col)


# --------------------------------------------------------------------------
#  Altitude tape
# --------------------------------------------------------------------------
func _draw_altitude_tape(rect: Rect2) -> void:
	draw_rect(rect, C_TAPE_BG)
	var cx := rect.position.x
	var cy := rect.position.y + rect.size.y * 0.5
	var alt: float = FlightData.altitude_ft

	var span_ft := (rect.size.y * 0.5) / PX_PER_100FT * 100.0
	var top_alt := alt + span_ft
	var a := int(floor((alt - span_ft) / 100.0) * 100)
	while a <= int(top_alt) + 100:
		var y := cy - (a - alt) * (PX_PER_100FT / 100.0)
		if y > rect.position.y and y < rect.position.y + rect.size.y:
			draw_line(Vector2(cx, y), Vector2(cx + 12, y), C_WHITE, 1.5)
			if a % 500 == 0:
				_text(Vector2(cx + 16, y + 6), str(a), 16, C_WHITE)
		a += 100

	# Centre readout box.
	var box := Rect2(cx - 8, cy - 18, rect.size.x + 8, 36)
	draw_rect(box, C_BLACK)
	draw_rect(box, C_WHITE, false, 1.5)
	_text(Vector2(box.position.x + 4, cy + 8), "%d" % roundi(alt), 22, C_GREEN)
	_text(Vector2(cx + 4, rect.position.y - 6), "ALT", 15, C_WHITE)
	# AGL readout.
	_text(Vector2(cx, rect.position.y + rect.size.y + 20),
		"AGL %d" % roundi(FlightData.altitude_agl_ft), 15, C_WHITE)


# --------------------------------------------------------------------------
#  Vertical speed indicator
# --------------------------------------------------------------------------
func _draw_vsi(rect: Rect2) -> void:
	draw_rect(rect, C_TAPE_BG)
	var cx := rect.position.x + 2
	var cy := rect.position.y + rect.size.y * 0.5
	var max_fpm := 2000.0
	var px_per_fpm := (rect.size.y * 0.5) / max_fpm

	for f in [-2000, -1000, 0, 1000, 2000]:
		var y: float = cy - f * px_per_fpm
		draw_line(Vector2(cx, y), Vector2(cx + 8, y), C_WHITE, 1.0)
		if f != 0:
			_text(Vector2(cx + 2, y - 3), str(absi(f) / 1000.0), 11, C_WHITE)

	var vs: float = clampf(FlightData.vertical_speed_fpm, -max_fpm, max_fpm)
	var y_now := cy - vs * px_per_fpm
	# Pointer.
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, y_now), Vector2(cx + 16, y_now - 8), Vector2(cx + 16, y_now + 8)
	]), C_MAGENTA)
	_text(Vector2(rect.position.x, rect.position.y - 6), "VS", 14, C_WHITE)


# --------------------------------------------------------------------------
#  Horizontal situation indicator (compass rose)
# --------------------------------------------------------------------------
func _draw_hsi(center: Vector2, radius: float) -> void:
	var hdg := FlightData.heading_deg
	draw_circle(center, radius + 6, Color(0.05, 0.05, 0.06))
	# Rotating compass card.
	for deg in range(0, 360, 5):
		var a := deg_to_rad(deg - hdg - 90)
		var dir := Vector2(cos(a), sin(a))
		var is_major := deg % 30 == 0
		var tick := 12.0 if is_major else 6.0
		draw_line(center + dir * (radius - tick), center + dir * radius, C_WHITE, 1.5 if is_major else 1.0)
		if is_major:
			var lbl := ""
			match deg:
				0: lbl = "N"
				90: lbl = "E"
				180: lbl = "S"
				270: lbl = "W"
				_: lbl = str(deg / 10)
			var tp := center + dir * (radius - 28)
			_text(tp - Vector2(7, -6), lbl, 16, C_WHITE)

	# Aircraft symbol at centre.
	draw_line(center + Vector2(0, -14), center + Vector2(0, 14), C_YELLOW, 3.0)
	draw_line(center + Vector2(-12, 0), center + Vector2(12, 0), C_YELLOW, 3.0)
	# Lubber line + heading bug at top.
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -radius - 2),
		center + Vector2(-7, -radius - 14),
		center + Vector2(7, -radius - 14)
	]), C_WHITE)
	# Digital heading box.
	var box := Rect2(center.x - 26, center.y - radius - 40, 52, 24)
	draw_rect(box, C_BLACK)
	draw_rect(box, C_WHITE, false, 1.0)
	_text(box.position + Vector2(8, 18), "%03d" % roundi(hdg), 18, C_GREEN)


# --------------------------------------------------------------------------
#  Annunciations (stall, brakes, flaps)
# --------------------------------------------------------------------------
func _draw_annunciations(s: Vector2) -> void:
	if FlightData.stall_warning:
		var r := Rect2(s.x * 0.5 - 60, 14, 120, 26)
		draw_rect(r, C_RED)
		_text(r.position + Vector2(20, 19), "STALL", 18, C_BLACK)

	# Flaps indicator.
	var flap_txt := "FLAPS %d" % int(FlightData.flaps_deg)
	_text(Vector2(s.x * 0.5 - 40, s.y - 14), flap_txt, 15, C_WHITE)
	if FlightData.parking_brake:
		_text(Vector2(s.x * 0.5 - 40, s.y - 32), "PARK BRK", 15, C_AMBER)


# --------------------------------------------------------------------------
#  Helpers
# --------------------------------------------------------------------------
func _text(pos: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _mask_outside(rect: Rect2) -> void:
	# Paint opaque borders so the oversized attitude ball doesn't spill past
	# the attitude window (cheap substitute for true clipping).
	var s := size
	draw_rect(Rect2(0, 0, s.x, rect.position.y), Color(0.04, 0.04, 0.05))
	draw_rect(Rect2(0, rect.position.y + rect.size.y, s.x, s.y - (rect.position.y + rect.size.y)), Color(0.04, 0.04, 0.05))
	draw_rect(Rect2(0, 0, rect.position.x, s.y), Color(0.04, 0.04, 0.05))
	draw_rect(Rect2(rect.position.x + rect.size.x, 0, s.x - (rect.position.x + rect.size.x), s.y), Color(0.04, 0.04, 0.05))
