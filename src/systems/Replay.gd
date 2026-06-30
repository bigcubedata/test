extends Node
## Flight recorder + instant-replay system (autoload singleton).
##
## While flying (LIVE), every physics frame the aircraft's world transform and
## a snapshot of the instrument state (FlightData) are pushed into a fixed-size
## ring buffer — roughly the last two minutes of flight. Pressing Tab enters
## REPLAY: the aircraft is frozen and its transform + instruments are driven
## from the recorded samples, so the PFD/MFD show exactly what they showed at
## the time. The chase camera tracks the played-back aircraft. Pressing Tab
## again leaves replay and resumes live flight from where it was paused.
##
## Controls (REPLAY mode):
##   Tab          enter / leave replay
##   Space        play / pause
##   Left/Right   scrub backward / forward (hold)
##   Up/Down      slower / faster playback (steps through 0.25x .. 4x)

enum Mode { LIVE, REPLAY }
var mode: int = Mode.LIVE

# Ring buffer. 120 Hz physics * 120 s = 14400 samples (~2 minutes of history).
const CAPACITY := 14400
const PHYS_HZ := 120.0

# Instrument fields mirrored each frame so playback reproduces the displays.
const FIELDS := [
	"indicated_airspeed_kt", "true_airspeed_kt", "ground_speed_kt",
	"altitude_ft", "altitude_agl_ft", "vertical_speed_fpm",
	"pitch_deg", "roll_deg", "heading_deg", "slip_skid",
	"angle_of_attack_deg", "load_factor",
	"engine_rpm", "manifold_pressure_inhg", "fuel_flow_gph", "oil_temp_c",
	"throttle_pct", "flaps_deg", "flaps_setting", "on_ground",
	"stall_warning", "pos_x", "pos_z", "fuel_pct", "volts",
]

const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0]

var _xforms: Array[Transform3D] = []
var _snaps: Array = []
var _head: int = 0       # next write slot
var _count: int = 0      # number of valid samples

var aircraft: RigidBody3D
var _camera: Node

var _play_pos: float = 0.0     # fractional sample index [0, _count-1]
var paused: bool = false
var _speed_idx: int = 2        # index into SPEEDS (1.0x)

# Saved live state so we can resume flight exactly where replay was entered.
var _resume_xform: Transform3D
var _resume_linvel: Vector3
var _resume_angvel: Vector3


func register(ac: RigidBody3D) -> void:
	aircraft = ac


func _ready() -> void:
	_xforms.resize(CAPACITY)
	_snaps.resize(CAPACITY)


# Called by the aircraft every physics frame while flying.
func capture(xform: Transform3D) -> void:
	if mode != Mode.LIVE:
		return
	_xforms[_head] = xform
	_snaps[_head] = _snapshot()
	_head = (_head + 1) % CAPACITY
	_count = mini(_count + 1, CAPACITY)


func clear() -> void:
	_head = 0
	_count = 0


func is_replaying() -> bool:
	return mode == Mode.REPLAY


func playback_speed() -> float:
	return SPEEDS[_speed_idx]


# Position within the replay, 0..1, and elapsed/total seconds.
func progress() -> float:
	if _count <= 1:
		return 0.0
	return clampf(_play_pos / float(_count - 1), 0.0, 1.0)


func elapsed_sec() -> float:
	return _play_pos / PHYS_HZ


func total_sec() -> float:
	return maxf(0.0, (_count - 1)) / PHYS_HZ


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("replay_toggle"):
		if mode == Mode.LIVE:
			_enter_replay()
		else:
			_exit_replay()
	if mode != Mode.REPLAY:
		return
	if Input.is_action_just_pressed("replay_pause"):
		paused = not paused
	if Input.is_action_just_pressed("pitch_down"):      # Down arrow -> slower
		_speed_idx = maxi(_speed_idx - 1, 0)
	if Input.is_action_just_pressed("pitch_up"):        # Up arrow -> faster
		_speed_idx = mini(_speed_idx + 1, SPEEDS.size() - 1)


func _physics_process(_delta: float) -> void:
	if mode != Mode.REPLAY or _count == 0:
		return

	# Scrub with the roll keys; otherwise advance unless paused.
	var scrub := Input.get_axis("roll_left", "roll_right")
	if absf(scrub) > 0.01:
		_play_pos = clampf(_play_pos + scrub * 6.0, 0.0, float(_count - 1))
	elif not paused:
		_play_pos += playback_speed()
		if _play_pos >= float(_count - 1):
			_play_pos = float(_count - 1)
			paused = true     # hold on the last frame

	_apply_sample(_play_pos)


func _enter_replay() -> void:
	if _count == 0 or aircraft == null:
		return
	mode = Mode.REPLAY
	paused = false
	_play_pos = 0.0
	# Remember the live state so we can hand control back later.
	_resume_xform = aircraft.global_transform
	_resume_linvel = aircraft.linear_velocity
	_resume_angvel = aircraft.angular_velocity
	aircraft.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	aircraft.freeze = true
	# A good tracking shot: snap the chase camera onto the played-back aircraft.
	_camera = get_tree().get_first_node_in_group("flight_camera")
	if _camera and int(_camera.view) == 0:   # leave the cockpit for replays
		_camera.view = 1


func _exit_replay() -> void:
	mode = Mode.LIVE
	if aircraft:
		aircraft.freeze = false
		aircraft.global_transform = _resume_xform
		aircraft.linear_velocity = _resume_linvel
		aircraft.angular_velocity = _resume_angvel


func _apply_sample(pos: float) -> void:
	var i := int(floor(pos))
	var j := mini(i + 1, _count - 1)
	var f := pos - float(i)
	var xa := _read_xform(i)
	var xb := _read_xform(j)
	# Interpolate position and rotation for smooth slow-motion / scrubbing.
	var origin := xa.origin.lerp(xb.origin, f)
	var qa := xa.basis.get_rotation_quaternion()
	var qb := xb.basis.get_rotation_quaternion()
	var rot := qa.slerp(qb, f)
	aircraft.global_transform = Transform3D(Basis(rot), origin)
	_restore(_read_snap(i))


func _read_xform(i: int) -> Transform3D:
	var idx := (_head - _count + i + CAPACITY) % CAPACITY
	return _xforms[idx]


func _read_snap(i: int) -> Dictionary:
	var idx := (_head - _count + i + CAPACITY) % CAPACITY
	return _snaps[idx]


func _snapshot() -> Dictionary:
	var d := {}
	for field in FIELDS:
		d[field] = FlightData.get(field)
	return d


func _restore(d: Dictionary) -> void:
	for field in FIELDS:
		if d.has(field):
			FlightData.set(field, d[field])
