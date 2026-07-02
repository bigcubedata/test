extends Label3D
## Floating tag that hovers above the aircraft during instant replay, calling
## out the flight-path (glide) angle and height above ground. Hidden in live
## flight; billboarded and fixed-size so it stays readable as the chase camera
## moves. Driven from the replayed FlightData so it matches the instruments.

const C_TEXT := Color(0.96, 0.97, 1.0)
const C_DESC := Color(1.0, 0.62, 0.2)   # amber when descending
const C_CLIMB := Color(0.4, 0.95, 0.5)  # green when climbing
const HEIGHT := 3.2                      # metres above the aircraft

var _ac: Node3D


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fixed_size = true
	no_depth_test = true
	pixel_size = 0.00042
	font_size = 64
	outline_size = 16
	outline_modulate = Color(0, 0, 0, 0.85)
	modulate = C_TEXT
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_level = true          # ignore the aircraft's roll/pitch; we place it ourselves
	visible = false


func _process(_delta: float) -> void:
	if not Replay.is_replaying() or Replay.aircraft == null:
		visible = false
		return
	visible = true
	_ac = Replay.aircraft
	global_position = _ac.global_position + Vector3.UP * HEIGHT

	# Flight-path angle from the recorded vertical/horizontal speed.
	var gs_ms: float = FlightData.ground_speed_kt / FlightData.MS_TO_KNOTS
	var vs_ms: float = FlightData.vertical_speed_fpm / FlightData.MS_TO_FPM
	var fpa: float = rad_to_deg(atan2(vs_ms, maxf(gs_ms, 0.1)))
	var agl: int = roundi(FlightData.altitude_agl_ft)

	modulate = C_DESC if fpa < -0.2 else (C_CLIMB if fpa > 0.2 else C_TEXT)
	text = "GLIDE %+.1f°\nAGL %d ft\nG %.1f" % [fpa, agl, FlightData.load_factor]
