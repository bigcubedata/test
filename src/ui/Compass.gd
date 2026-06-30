extends Control
## Wet magnetic compass card, mounted on top of the glareshield. A vertical
## card whose numbers slide past a fixed lubber line as heading changes.

var _font: Font


func _ready() -> void:
	_font = UiFont.regular()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.12, 0.13, 0.16))
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.5, 0.5, 0.55), false, 3.0)
	var hdg: float = FlightData.heading_deg
	var cx := s.x * 0.5
	var cy := s.y * 0.5
	var ppd := s.x / 50.0  # pixels per degree of heading shown

	# The card: marks every 10 deg, cardinal letters, sliding under the lubber.
	for d in range(-30, 31, 10):
		var hd := snappedf(hdg, 10.0) + d
		var x := cx + (hd - hdg) * ppd
		if x < 6 or x > s.x - 6:
			continue
		var hh := int(fposmod(hd, 360.0))
		draw_line(Vector2(x, 4), Vector2(x, s.y * 0.32), Color(0.95, 0.95, 1.0), 2.0)
		var lbl := ""
		match hh:
			0: lbl = "N"
			90: lbl = "E"
			180: lbl = "S"
			270: lbl = "W"
			_: lbl = str(hh / 10)
		var col := Color(1.0, 0.5, 0.5) if hh % 90 == 0 else Color(0.95, 0.95, 1.0)
		draw_string(_font, Vector2(x - s.x * 0.05, s.y * 0.85), lbl,
			HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(s.y * 0.5), col)

	# Fixed lubber line.
	draw_line(Vector2(cx, 2), Vector2(cx, s.y - 2), Color(1.0, 0.65, 0.2), 3.0)
