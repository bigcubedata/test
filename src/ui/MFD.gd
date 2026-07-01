extends Control
## Garmin G1000-style Multi-Function Display.
##
## Left third: engine indication system (EIS) vertical gauges.
## Right two-thirds: a heading-up moving map showing the aircraft over the
## runway, with range ring and a north pointer. Drawn procedurally from
## FlightData so it can be rendered into a SubViewport and mapped onto the
## 3D cockpit panel.

const C_BG := Color(0.04, 0.05, 0.06)
const C_TEXT := Color(0.92, 0.92, 0.95)
const C_GREEN := Color(0.2, 0.9, 0.2)
const C_AMBER := Color(1.0, 0.75, 0.1)
const C_RED := Color(0.95, 0.15, 0.15)
const C_CYAN := Color(0.3, 0.85, 1.0)
const C_MAG := Color(1.0, 0.3, 1.0)
const C_RUNWAY := Color(0.55, 0.55, 0.6)

# Runway geometry from World.tscn (centred at x=0, along Z).
const RWY_X := 0.0
const RWY_Z1 := -950.0
const RWY_Z2 := 550.0
const RWY_W := 45.0

const MAP_RANGE_M := 2200.0  # metres from centre to map edge

var _font: Font


func _ready() -> void:
	_font = UiFont.regular()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), C_BG)
	var split := s.x * 0.34
	_draw_engine(Rect2(0, 0, split, s.y))
	_draw_map(Rect2(split, 0, s.x - split, s.y))
	draw_line(Vector2(split, 0), Vector2(split, s.y), Color(0.3, 0.3, 0.35), 1.0)


# --------------------------------------------------------------------------
#  Engine indication (left column)
# --------------------------------------------------------------------------
func _draw_engine(r: Rect2) -> void:
	var x0 := r.position.x + 8
	var w := r.size.x - 16
	var y := r.position.y + 22
	_t(Vector2(x0, y - 6), "ENGINE", 15, C_TEXT)
	y += 10

	# RPM (big horizontal bar with redline).
	y = _bar(x0, y, w, "RPM", FlightData.engine_rpm, 0, 2700, 2700, "%d")
	y = _bar(x0, y, w, "MAP \"", FlightData.manifold_pressure_inhg, 10, 30, 99, "%.1f")
	y = _bar(x0, y, w, "FFLOW", FlightData.fuel_flow_gph, 0, 20, 99, "%.1f")
	y = _bar(x0, y, w, "OIL °F", FlightData.oil_temp_c * 1.8 + 32.0, 100, 250, 245, "%d")
	y = _bar(x0, y, w, "OIL P", lerpf(25, 60, clampf(FlightData.engine_rpm / 2700.0, 0, 1)), 0, 100, 100, "%d")
	y += 8

	# Fuel (US gallons; C172S holds 53 usable) + volts.
	_t(Vector2(x0, y), "FUEL  %d GAL" % roundi(FlightData.fuel_pct * 53.0), 14, C_GREEN)
	y += 20
	_t(Vector2(x0, y), "VOLTS %.1f" % FlightData.volts, 14, C_GREEN)
	y += 20
	_t(Vector2(x0, y), "FLAPS %d" % int(FlightData.flaps_deg), 14, C_TEXT)


func _bar(x: float, y: float, w: float, label: String, val: float,
		lo: float, hi: float, redline: float, fmt: String) -> float:
	_t(Vector2(x, y), label, 12, C_TEXT)
	var bar := Rect2(x, y + 4, w, 12)
	draw_rect(bar, Color(0.12, 0.12, 0.15))
	var frac := clampf((val - lo) / (hi - lo), 0.0, 1.0)
	var col := C_GREEN
	if val > redline:
		col = C_RED
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), col)
	draw_rect(bar, Color(0.4, 0.4, 0.45), false, 1.0)
	_t(Vector2(x + w - 52, y), fmt % val, 13, C_GREEN)
	return y + 30


# --------------------------------------------------------------------------
#  Moving map (right)
# --------------------------------------------------------------------------
func _draw_map(r: Rect2) -> void:
	var center := r.position + r.size * 0.5
	var radius := minf(r.size.x, r.size.y) * 0.46
	var scale := radius / MAP_RANGE_M
	var hdg := deg_to_rad(FlightData.heading_deg)
	var sinh := sin(hdg)
	var cosh := cos(hdg)
	var ac := Vector2(FlightData.pos_x, FlightData.pos_z)

	# Convert a world point (x = east, z; north = -z) to heading-up screen pos.
	var to_screen := func(wx: float, wz: float) -> Vector2:
		var east := wx - ac.x
		var north := -(wz - ac.y)
		var fwd := east * sinh + north * cosh
		var right := east * cosh - north * sinh
		return center + Vector2(right, -fwd) * scale

	# Extended runway centreline (dashed) for final-approach guidance.
	_dash(to_screen.call(RWY_X, RWY_Z2), to_screen.call(RWY_X, RWY_Z2 + 1100.0), Color(0.9, 0.9, 0.3, 0.7), 1.0)
	_dash(to_screen.call(RWY_X, RWY_Z1), to_screen.call(RWY_X, RWY_Z1 - 1100.0), Color(0.9, 0.9, 0.3, 0.7), 1.0)

	# Left-hand traffic pattern for runway 36 (downwind to the west).
	const OFF := -850.0   # downwind offset (west, -X)
	const EXT := 380.0    # legs extend past the thresholds
	var p_final: Vector2 = to_screen.call(RWY_X, RWY_Z2 + EXT)
	var p_base: Vector2 = to_screen.call(OFF, RWY_Z2 + EXT)
	var p_dnwn: Vector2 = to_screen.call(OFF, RWY_Z1 - EXT)
	var p_cros: Vector2 = to_screen.call(RWY_X, RWY_Z1 - EXT)
	_dash(p_final, p_base, C_CYAN, 1.0)   # base
	_dash(p_base, p_dnwn, C_CYAN, 1.0)    # downwind
	_dash(p_dnwn, p_cros, C_CYAN, 1.0)    # crosswind
	_dash(p_cros, p_final, C_CYAN, 1.0)   # upwind/final

	# Runway as a filled strip + solid centreline.
	var a: Vector2 = to_screen.call(RWY_X - RWY_W * 0.5, RWY_Z1)
	var b: Vector2 = to_screen.call(RWY_X + RWY_W * 0.5, RWY_Z1)
	var c: Vector2 = to_screen.call(RWY_X + RWY_W * 0.5, RWY_Z2)
	var d: Vector2 = to_screen.call(RWY_X - RWY_W * 0.5, RWY_Z2)
	draw_colored_polygon(PackedVector2Array([a, b, c, d]), C_RUNWAY)
	draw_line(to_screen.call(RWY_X, RWY_Z1), to_screen.call(RWY_X, RWY_Z2), Color(0.95, 0.95, 0.3), 1.5)

	# Runway end designators: 36 at the south threshold, 18 at the north.
	var e36: Vector2 = to_screen.call(RWY_X, RWY_Z2)
	var e18: Vector2 = to_screen.call(RWY_X, RWY_Z1)
	_t(e36 - Vector2(8, -2), "36", 13, Color.WHITE)
	_t(e18 - Vector2(8, 2), "18", 13, Color.WHITE)

	# Range ring + label.
	draw_arc(center, radius, 0, TAU, 64, Color(0.4, 0.4, 0.45), 1.0)
	draw_arc(center, radius * 0.5, 0, TAU, 64, Color(0.25, 0.25, 0.3), 1.0)
	_t(Vector2(center.x + 4, center.y - radius + 14), "%.1f nm" % (MAP_RANGE_M / 1852.0), 12, C_TEXT)

	# North pointer (rotates opposite heading).
	var npos := center + Vector2(-sinh, -cosh) * (radius - 6)
	_t(npos - Vector2(5, -5), "N", 14, C_CYAN)

	# Track line ahead.
	draw_line(center, center - Vector2(0, radius * 0.6), C_MAG, 2.0)

	# Aircraft symbol (always centre, pointing up).
	var sym := PackedVector2Array([
		center + Vector2(0, -10), center + Vector2(-7, 8), center + Vector2(0, 4), center + Vector2(7, 8)])
	draw_colored_polygon(sym, Color.WHITE)

	# Distance to the runway-36 threshold.
	var d36 := Vector2(FlightData.pos_x - RWY_X, FlightData.pos_z - RWY_Z2).length() / 1852.0

	# Data readouts.
	_t(Vector2(r.position.x + 8, r.position.y + r.size.y - 42),
		"GS %d kt" % roundi(FlightData.ground_speed_kt), 14, C_GREEN)
	_t(Vector2(r.position.x + 8, r.position.y + r.size.y - 26),
		"TRK %03d" % roundi(FlightData.heading_deg), 14, C_GREEN)
	_t(Vector2(r.position.x + 8, r.position.y + r.size.y - 10),
		"RW36 %.1f nm" % d36, 14, C_CYAN)
	_t(Vector2(r.position.x + r.size.x - 90, r.position.y + r.size.y - 10),
		"ALT %d" % roundi(FlightData.altitude_ft), 14, C_GREEN)


func _dash(a: Vector2, b: Vector2, col: Color, w: float, dash := 9.0, gap := 6.0) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.5:
		return
	var dir := d / l
	var t := 0.0
	while t < l:
		var t2 := minf(t + dash, l)
		draw_line(a + dir * t, a + dir * t2, col, w)
		t += dash + gap


func _t(pos: Vector2, text: String, fs: int, col: Color) -> void:
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
