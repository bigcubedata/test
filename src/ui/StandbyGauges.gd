extends Control
## Standby (backup) steam gauges for the C172 G1000 panel: airspeed indicator,
## attitude indicator and altimeter, stacked vertically. Rendered into a tall
## SubViewport and mounted left of the PFD. Mechanical-instrument style to
## contrast with the glass displays.

const C_BG := Color(0.03, 0.03, 0.035)
const C_FACE := Color(0.07, 0.07, 0.08)
const C_RIM := Color(0.25, 0.25, 0.28)
const C_TICK := Color(0.9, 0.9, 0.92)
const C_NEEDLE := Color(0.95, 0.95, 0.95)
const C_SKY := Color(0.16, 0.5, 0.82)
const C_GND := Color(0.42, 0.28, 0.12)
const C_YELLOW := Color(1.0, 0.85, 0.0)

var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), C_BG)
	var r := s.x * 0.42
	var cx := s.x * 0.5
	_asi(Vector2(cx, s.y * 0.18), r)
	_attitude(Vector2(cx, s.y * 0.5), r)
	_altimeter(Vector2(cx, s.y * 0.82), r)


func _dial(c: Vector2, r: float) -> void:
	draw_circle(c, r + r * 0.08, Color(0.02, 0.02, 0.02))
	draw_circle(c, r, C_FACE)
	draw_arc(c, r, 0, TAU, 48, C_RIM, maxf(2.0, r * 0.06))


func _label(c: Vector2, txt: String, r: float) -> void:
	draw_string(_font, c + Vector2(-r * 0.5, r * 0.42), txt,
		HORIZONTAL_ALIGNMENT_CENTER, r, roundi(r * 0.26), Color(0.7, 0.7, 0.75))


func _asi(c: Vector2, r: float) -> void:
	_dial(c, r)
	# Scale 40..160 kt across 300 degrees (start lower-left).
	var lo := 40.0
	var hi := 160.0
	var a0 := deg_to_rad(150.0)
	var span := deg_to_rad(240.0)
	for kt in range(int(lo), int(hi) + 1, 20):
		var f := (kt - lo) / (hi - lo)
		var ang := a0 + f * span
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(c + dir * (r * 0.82), c + dir * r, C_TICK, maxf(1.0, r * 0.03))
		draw_string(_font, c + dir * (r * 0.62) + Vector2(-r * 0.16, r * 0.1),
			str(kt / 10), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(r * 0.2), C_TICK)
	var ias: float = clampf(FlightData.indicated_airspeed_kt, 0.0, hi)
	var fa := a0 + clampf((ias - lo) / (hi - lo), -0.1, 1.05) * span
	var nd := Vector2(cos(fa), sin(fa))
	draw_line(c, c + nd * (r * 0.85), C_NEEDLE, maxf(2.0, r * 0.06))
	draw_circle(c, r * 0.08, C_NEEDLE)
	_label(c, "AIRSPEED", r)


func _attitude(c: Vector2, r: float) -> void:
	draw_circle(c, r + r * 0.08, Color(0.02, 0.02, 0.02))
	# Sky/ground, rotated by roll and shifted by pitch, then mask to a disc.
	var roll := FlightData.roll_deg
	var pitch := FlightData.pitch_deg
	var ppd := r / 25.0  # pixels per degree
	draw_set_transform(c, deg_to_rad(-roll), Vector2.ONE)
	var off := pitch * ppd
	var big := r * 2.5
	draw_rect(Rect2(-big, -big + off, big * 2, big), C_SKY)
	draw_rect(Rect2(-big, off, big * 2, big), C_GND)
	draw_line(Vector2(-big, off), Vector2(big, off), Color(1, 1, 1), maxf(1.0, r * 0.03))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# Mask the square corners outside the dial with a thick bg ring.
	draw_arc(c, r + r * 0.45, 0, TAU, 48, C_BG, r * 0.9)
	draw_arc(c, r, 0, TAU, 48, C_RIM, maxf(2.0, r * 0.06))
	# Fixed miniature aircraft.
	draw_line(c + Vector2(-r * 0.5, 0), c + Vector2(-r * 0.15, 0), C_YELLOW, maxf(2.0, r * 0.05))
	draw_line(c + Vector2(r * 0.15, 0), c + Vector2(r * 0.5, 0), C_YELLOW, maxf(2.0, r * 0.05))
	draw_circle(c, r * 0.04, C_YELLOW)
	# Roll pointer.
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(-r * 0.1, -r * 0.82), c + Vector2(r * 0.1, -r * 0.82)]), C_YELLOW)


func _altimeter(c: Vector2, r: float) -> void:
	_dial(c, r)
	for i in range(10):
		var ang := deg_to_rad(-90.0 + i * 36.0)
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(c + dir * (r * 0.82), c + dir * r, C_TICK, maxf(1.0, r * 0.03))
		draw_string(_font, c + dir * (r * 0.62) + Vector2(-r * 0.1, r * 0.1),
			str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(r * 0.2), C_TICK)
	var alt: float = FlightData.altitude_ft
	# Hundreds hand (long) and thousands hand (short).
	var h100 := fposmod(alt, 1000.0) / 1000.0
	var h1000 := fposmod(alt, 10000.0) / 10000.0
	var a100 := deg_to_rad(-90.0) + h100 * TAU
	var a1000 := deg_to_rad(-90.0) + h1000 * TAU
	draw_line(c, c + Vector2(cos(a1000), sin(a1000)) * (r * 0.55), C_NEEDLE, maxf(3.0, r * 0.09))
	draw_line(c, c + Vector2(cos(a100), sin(a100)) * (r * 0.85), C_NEEDLE, maxf(2.0, r * 0.05))
	draw_circle(c, r * 0.08, C_NEEDLE)
	_label(c, "ALT", r)
