extends Node
## Wind, gusts and turbulence (autoload).
##
## The mean wind follows a boundary-layer profile (calmer right at the
## surface, building with height), slow gusts and a little direction wander
## ride on top, and high-frequency turbulence is sampled as a spatio-temporal
## noise field — the aircraft samples it at several points (wingtips, tail),
## so uneven gusts across the span produce real rolling/pitching bumps.
##
## Press V to cycle presets, from calm through crosswind-landing practice to
## a gusty, turbulent day. Direction is where the wind blows FROM, runway
## 36/18 points north/south, so 090/270 are direct crosswinds.

const PRESETS := [
	{"name": "CALM", "dir": 0.0, "kt": 0.0, "gust": 0.0, "turb": 0.0},
	{"name": "330/08", "dir": 330.0, "kt": 8.0, "gust": 4.0, "turb": 0.3},
	{"name": "090/12", "dir": 90.0, "kt": 12.0, "gust": 5.0, "turb": 0.5},
	{"name": "270/15G25", "dir": 270.0, "kt": 15.0, "gust": 10.0, "turb": 0.7},
	{"name": "300/18G30", "dir": 300.0, "kt": 18.0, "gust": 12.0, "turb": 1.0},
]
const KT_TO_MS := 0.514444

var preset := 0
var _t := 0.0
var _gust_n := FastNoiseLite.new()
var _turb: Array = [FastNoiseLite.new(), FastNoiseLite.new(), FastNoiseLite.new()]


func _ready() -> void:
	# frequency = 1.0 so the hand-tuned time/space scales in sample() act as
	# written (FastNoiseLite's default of 0.01 would slow them all 100x and
	# freeze the gusts).
	_gust_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_gust_n.seed = 7
	_gust_n.frequency = 1.0
	for i in range(3):
		_turb[i].noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_turb[i].seed = 100 + i * 37
		_turb[i].frequency = 1.0


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("cycle_wind"):
		preset = (preset + 1) % PRESETS.size()


func _physics_process(dt: float) -> void:
	_t += dt
	# Publish the wind at the aircraft's position for the PFD data box.
	var pos := Vector3(FlightData.pos_x,
		FlightData.altitude_ft / FlightData.M_TO_FEET, FlightData.pos_z)
	var w := sample(pos)
	FlightData.wind_speed_kt = Vector2(w.x, w.z).length() / KT_TO_MS
	if FlightData.wind_speed_kt > 0.3:
		# Direction the wind comes FROM (0 = north = -Z).
		FlightData.wind_dir_deg = fposmod(rad_to_deg(atan2(-w.x, w.z)), 360.0)


## World-space wind vector [m/s] at a position. Deterministic in (pos, _t),
## so nearby points (wingtips) see coherent but different gusts.
func sample(pos: Vector3) -> Vector3:
	var p: Dictionary = PRESETS[preset]
	var out := Vector3.ZERO
	var base_kt: float = p["kt"]
	var turb: float = p["turb"]
	if base_kt > 0.01:
		# Slow gust factor (only ever adds) + small direction wander.
		var gust_kt: float = p["gust"] * clampf(_gust_n.get_noise_1d(_t * 0.07) * 1.8, 0.0, 1.0)
		var from_deg: float = p["dir"] + _gust_n.get_noise_1d(_t * 0.03 + 50.0) * 12.0
		var to_rad := deg_to_rad(from_deg + 180.0)
		# Boundary layer: mean wind builds with height above the surface.
		var h := maxf(pos.y, 2.0)
		var profile := clampf(pow(h / 10.0, 0.14), 0.7, 1.35)
		var spd := (base_kt + gust_kt) * KT_TO_MS * profile
		out = Vector3(sin(to_rad), 0.0, -cos(to_rad)) * spd
	if turb > 0.01:
		# Spatio-temporal turbulence, fading with altitude; the vertical
		# component is what the wings feel most.
		var s := 0.06
		var amp := turb * 1.9 * clampf(1.2 - pos.y / 2500.0, 0.5, 1.2)
		out.x += amp * _turb[0].get_noise_3d(pos.x * s + _t * 1.9, pos.y * s, pos.z * s)
		out.y += amp * 0.9 * _turb[1].get_noise_3d(pos.x * s, pos.y * s + _t * 2.3, pos.z * s)
		out.z += amp * _turb[2].get_noise_3d(pos.x * s + _t * 1.4, pos.y * s, pos.z * s + _t * 1.7)
	return out


func turbulence() -> float:
	return PRESETS[preset]["turb"]


func preset_name() -> String:
	return PRESETS[preset]["name"]
