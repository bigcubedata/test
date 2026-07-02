extends Node
## Flight recorder + instant-replay system (autoload singleton).
##
## While flying (LIVE) the aircraft's world transform and a snapshot of the
## instrument state are sampled at 30 Hz into a fixed ring buffer that holds
## about eleven minutes of flight — enough for a full local pattern/flight, so
## a replay covers the whole trip rather than just the last stretch. Pressing
## Tab enters REPLAY: the aircraft is frozen and driven from the samples, so the
## PFD/MFD replay faithfully. Samples are stored in flat packed arrays (not
## per-frame dictionaries) to keep the long buffer cheap.
##
## Controls (REPLAY mode):
##   Tab          enter / leave replay
##   Space        play / pause
##   Left/Right   scrub backward / forward (hold)
##   Up/Down      slower / faster playback

enum Mode { LIVE, REPLAY }
var mode: int = Mode.LIVE

const PHYS_HZ := 120.0
const STRIDE := 4                 # sample every 4th physics frame -> 30 Hz
const SAMPLE_HZ := PHYS_HZ / STRIDE
const CAPACITY := 20000           # ~11 minutes at 30 Hz

# Instrument fields mirrored each sample so playback reproduces the displays.
const FIELDS := [
	"indicated_airspeed_kt", "true_airspeed_kt", "ground_speed_kt",
	"altitude_ft", "altitude_agl_ft", "vertical_speed_fpm",
	"pitch_deg", "roll_deg", "heading_deg", "slip_skid",
	"angle_of_attack_deg", "load_factor",
	"engine_rpm", "manifold_pressure_inhg", "fuel_flow_gph", "oil_temp_c",
	"throttle_pct", "flaps_deg", "flaps_setting", "on_ground",
	"stall_warning", "pos_x", "pos_z", "fuel_pct", "volts",
	"wind_dir_deg", "wind_speed_kt", "track_deg",
]
# Fields that must be restored as bool / int rather than float.
const BOOL_FIELDS := ["on_ground", "stall_warning"]
const INT_FIELDS := ["flaps_setting"]

const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0]

var _nf := 0
var _origin: PackedVector3Array = PackedVector3Array()
var _quat: PackedFloat32Array = PackedFloat32Array()
var _data: PackedFloat32Array = PackedFloat32Array()
var _head: int = 0        # next write slot
var _count: int = 0       # valid samples
var _phase: int = 0       # physics-frame counter for the stride

var aircraft: RigidBody3D

var _play_pos: float = 0.0     # fractional sample index [0, _count-1]
var paused: bool = false
var _speed_idx: int = 2        # index into SPEEDS (1.0x)

var _resume_xform: Transform3D
var _resume_linvel: Vector3
var _resume_angvel: Vector3
# Control-authoritative state that playback overwrites and live flight reads.
var _resume_flaps: int = 0
var _resume_flaps_deg: float = 0.0
var _resume_brake: bool = false


func register(ac: RigidBody3D) -> void:
	aircraft = ac


func _ready() -> void:
	_nf = FIELDS.size()
	_origin.resize(CAPACITY)
	_quat.resize(CAPACITY * 4)
	_data.resize(CAPACITY * _nf)


func clear() -> void:
	_head = 0
	_count = 0
	_phase = 0


# Called by the aircraft every physics frame while flying; strides to 30 Hz.
func capture(xform: Transform3D) -> void:
	if mode != Mode.LIVE:
		return
	_phase += 1
	if _phase < STRIDE:
		return
	_phase = 0
	var i := _head
	_origin[i] = xform.origin
	var q := xform.basis.get_rotation_quaternion()
	_quat[i * 4 + 0] = q.x
	_quat[i * 4 + 1] = q.y
	_quat[i * 4 + 2] = q.z
	_quat[i * 4 + 3] = q.w
	var base := i * _nf
	for k in range(_nf):
		_data[base + k] = float(FlightData.get(FIELDS[k]))
	_head = (_head + 1) % CAPACITY
	_count = mini(_count + 1, CAPACITY)


func is_replaying() -> bool:
	return mode == Mode.REPLAY


func playback_speed() -> float:
	return SPEEDS[_speed_idx]


func progress() -> float:
	if _count <= 1:
		return 0.0
	return clampf(_play_pos / float(_count - 1), 0.0, 1.0)


func elapsed_sec() -> float:
	return _play_pos / SAMPLE_HZ


func total_sec() -> float:
	return maxf(0.0, (_count - 1)) / SAMPLE_HZ


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
	# Advance in sample units: SAMPLE_HZ/PHYS_HZ samples per physics tick = 1x.
	var step := SAMPLE_HZ / PHYS_HZ
	var scrub := Input.get_axis("roll_left", "roll_right")
	if absf(scrub) > 0.01:
		_play_pos = clampf(_play_pos + scrub * 2.0, 0.0, float(_count - 1))
	elif not paused:
		_play_pos += playback_speed() * step
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
	_resume_xform = aircraft.global_transform
	_resume_linvel = aircraft.linear_velocity
	_resume_angvel = aircraft.angular_velocity
	_resume_flaps = FlightData.flaps_setting
	_resume_flaps_deg = FlightData.flaps_deg
	_resume_brake = FlightData.parking_brake
	aircraft.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	aircraft.freeze = true
	# The camera switches itself to an orbit while is_replaying() is true.


func _exit_replay() -> void:
	mode = Mode.LIVE
	if aircraft:
		aircraft.freeze = false
		aircraft.global_transform = _resume_xform
		aircraft.linear_velocity = _resume_linvel
		aircraft.angular_velocity = _resume_angvel
	# Playback overwrote the pilot's configuration via _restore(); hand back
	# the flaps/brake the aircraft actually had when replay was entered.
	FlightData.flaps_setting = _resume_flaps
	FlightData.flaps_deg = _resume_flaps_deg
	FlightData.parking_brake = _resume_brake


func _apply_sample(pos: float) -> void:
	var i := int(floor(pos))
	var j := mini(i + 1, _count - 1)
	var f := pos - float(i)
	var xa := _read_xform(i)
	var xb := _read_xform(j)
	var origin := xa.origin.lerp(xb.origin, f)
	var rot := xa.basis.get_rotation_quaternion().slerp(xb.basis.get_rotation_quaternion(), f)
	aircraft.global_transform = Transform3D(Basis(rot), origin)
	_restore(i)


func _slot(i: int) -> int:
	return (_head - _count + i + CAPACITY) % CAPACITY


func _read_xform(i: int) -> Transform3D:
	var idx := _slot(i)
	var q := Quaternion(_quat[idx * 4], _quat[idx * 4 + 1], _quat[idx * 4 + 2], _quat[idx * 4 + 3])
	return Transform3D(Basis(q), _origin[idx])


func _restore(i: int) -> void:
	var base := _slot(i) * _nf
	for k in range(_nf):
		var field: String = FIELDS[k]
		var v := _data[base + k]
		if field in BOOL_FIELDS:
			FlightData.set(field, v > 0.5)
		elif field in INT_FIELDS:
			FlightData.set(field, int(round(v)))
		else:
			FlightData.set(field, v)
