extends Control
## Compact engine-indication strip (a slice of the G1000 EIS).
## Shows RPM as an arc gauge plus fuel flow, oil temp and throttle.

var _font: Font

const C_TEXT := Color(1, 1, 1)
const C_GREEN := Color(0.2, 0.9, 0.2)
const C_AMBER := Color(1.0, 0.75, 0.1)
const C_RED := Color(0.95, 0.15, 0.15)


func _ready() -> void:
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.06, 0.06, 0.08, 0.85))
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.4, 0.4, 0.45), false, 1.0)

	# --- RPM bar gauge ----
	var rpm: float = FlightData.engine_rpm
	var frac := clampf(rpm / 2700.0, 0.0, 1.0)
	var bar := Rect2(12, 24, s.x - 24, 18)
	draw_rect(bar, Color(0.15, 0.15, 0.18))
	# Green normal band up to 2700, red past 2700 (redline).
	var fill_col := C_GREEN
	if rpm > 2700.0:
		fill_col = C_RED
	elif rpm < 800.0:
		fill_col = C_AMBER
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), fill_col)
	draw_rect(bar, Color(0.5, 0.5, 0.5), false, 1.0)
	_text(Vector2(12, 18), "RPM", 13, C_TEXT)
	_text(Vector2(s.x - 70, 18), "%d" % roundi(rpm), 15, C_GREEN)

	# --- Numeric readouts ----
	var y := 56
	_row("MAP", "%.1f inHg" % FlightData.manifold_pressure_inhg, y); y += 20
	_row("FFLOW", "%.1f gph" % FlightData.fuel_flow_gph, y); y += 20
	_row("OIL T", "%d C" % roundi(FlightData.oil_temp_c), y); y += 20
	_row("THR", "%d %%" % roundi(FlightData.throttle_pct), y); y += 20


func _row(label: String, value: String, y: int) -> void:
	_text(Vector2(12, y), label, 13, C_TEXT)
	_text(Vector2(size.x * 0.5, y), value, 13, C_GREEN)


func _text(pos: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
