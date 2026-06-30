extends Control
## Thin status bar shown at the top-centre during instant replay: a REPLAY
## badge, a scrub bar with elapsed / total time, the playback speed, and a
## PAUSED flag. Also shows a small "REC" dot while flying so it's clear the
## flight is being recorded for playback.

const C_REC := Color(0.95, 0.2, 0.2)
const C_BAR_BG := Color(0.1, 0.11, 0.13, 0.85)
const C_BAR_FILL := Color(0.3, 0.85, 1.0)
const C_TEXT := Color(0.95, 0.96, 0.98)
const C_AMBER := Color(1.0, 0.75, 0.1)

var _font: Font
var _font_b: Font


func _ready() -> void:
	_font = UiFont.regular()
	_font_b = UiFont.bold()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if Replay.is_replaying():
		_draw_replay_bar()
	else:
		_draw_rec_dot()


func _draw_rec_dot() -> void:
	# Small recording indicator at top-left of this (top-centred) control.
	var c := Vector2(size.x * 0.5 - 70, 18)
	draw_circle(c, 6, C_REC)
	draw_string(_font, c + Vector2(14, 5), "REC", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_TEXT)


func _draw_replay_bar() -> void:
	var w := 460.0
	var x := size.x * 0.5 - w * 0.5
	var y := 12.0
	var bar := Rect2(x, y + 22, w, 8)
	draw_rect(Rect2(x - 12, y - 4, w + 24, 52), C_BAR_BG, true)

	draw_circle(Vector2(x + 6, y + 10), 6, C_REC)
	draw_string(_font_b, Vector2(x + 18, y + 15), "REPLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_TEXT)

	var spd := str(Replay.playback_speed()) + "x"
	draw_string(_font, Vector2(x + 96, y + 15), spd, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_AMBER)
	if Replay.paused:
		draw_string(_font_b, Vector2(x + 150, y + 15), "PAUSED", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_AMBER)

	var t := "%s / %s" % [_fmt(Replay.elapsed_sec()), _fmt(Replay.total_sec())]
	draw_string(_font, Vector2(x + w - 96, y + 15), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_TEXT)

	# Scrub bar.
	draw_rect(bar, Color(0.18, 0.19, 0.22), true)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * Replay.progress(), bar.size.y)), C_BAR_FILL, true)
	var px := bar.position.x + bar.size.x * Replay.progress()
	draw_circle(Vector2(px, bar.position.y + bar.size.y * 0.5), 5, Color.WHITE)

	draw_string(_font, Vector2(x, y + 48), "Space pause   ←/→ scrub   ↑/↓ speed   Tab exit",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.82, 0.86))


func _fmt(sec: float) -> String:
	var m := int(sec) / 60
	var s := int(sec) % 60
	return "%d:%02d" % [m, s]
