extends Camera3D
## Follows the aircraft with several selectable views (cycle with C).
##   0  Cockpit - pilot eye point with mouse free-look (default for flying)
##   1  Chase   - smoothed third-person trailing camera
##   2  Wing    - external view from off the left wing
##   3  Tower   - fixed runway-tower view that tracks the aircraft
##
## Cockpit free-look: hold the RIGHT mouse button and move the mouse to look
## around the cabin (down at the panel, up and out the windshield, to the side
## windows) — like turning your head in a real cockpit. Release to free the
## cursor. Switching view recentres the look.
##
## During instant replay the view modes are bypassed: the camera orbits the
## aircraft so you can inspect its attitude from any angle. Hold the LEFT mouse
## button and drag to rotate around it; the mouse wheel zooms in/out.

@export var target_path: NodePath
var target: Node3D
var _airframe: Node3D

enum View { COCKPIT, CHASE, WING, TOWER }
## Cockpit is the primary view for hand-flying; cycle with C through
## Cockpit -> Chase -> Wing -> Tower and back.
var view: int = View.COCKPIT
const CYCLE := [View.COCKPIT, View.CHASE, View.WING, View.TOWER]

const CHASE_OFFSET := Vector3(0.0, 3.5, 13.0)
const COCKPIT_OFFSET := Vector3(-0.22, 0.57, -1.05) # pilot eye point (raised to see over the nose)
const WING_OFFSET := Vector3(-8.0, 1.5, 0.0)
const COCKPIT_FOV := 74.0
const EXTERNAL_FOV := 65.0
const BASE_PITCH := -10.0    # default look favours outside; free-look down for panel
const LOOK_SENS := 0.18
const ORBIT_SENS := 0.30

var _tower_pos := Vector3(40.0, 12.0, 60.0)
var _chase_pos: Vector3
var _look_yaw := 0.0
var _look_pitch := 0.0

# Replay orbit state.
var _orbit_yaw := 24.0
var _orbit_pitch := 16.0
var _orbit_dist := 14.0
var _was_replaying := false


func _ready() -> void:
	if target_path:
		target = get_node(target_path)
	current = true
	add_to_group("flight_camera")
	if target:
		_chase_pos = target.global_position + target.global_transform.basis * CHASE_OFFSET
		_airframe = target.get_node_or_null("Airframe")


func _process(_delta: float) -> void:
	if Replay.is_replaying():
		return  # view selection is suspended while orbiting a replay
	if Input.is_action_just_pressed("toggle_view"):
		var i := CYCLE.find(view)
		view = CYCLE[(i + 1) % CYCLE.size()]
		_look_yaw = 0.0
		_look_pitch = 0.0
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if Replay.is_replaying():
		_orbit_input(event)
		return
	if view != View.COCKPIT:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_yaw = clampf(_look_yaw - event.relative.x * LOOK_SENS, -150.0, 150.0)
		_look_pitch = clampf(_look_pitch - event.relative.y * LOOK_SENS, -85.0, 55.0)


func _orbit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
			MOUSE_BUTTON_WHEEL_UP:
				_orbit_dist = clampf(_orbit_dist - 1.5, 5.0, 60.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				_orbit_dist = clampf(_orbit_dist + 1.5, 5.0, 60.0)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_orbit_yaw = wrapf(_orbit_yaw - event.relative.x * ORBIT_SENS, -180.0, 180.0)
		_orbit_pitch = clampf(_orbit_pitch + event.relative.y * ORBIT_SENS, -85.0, 85.0)


func _physics_process(delta: float) -> void:
	if not target:
		return
	var replaying := Replay.is_replaying()
	# On entering replay, drop into a pleasant 3/4 rear vantage and free the cursor.
	if replaying and not _was_replaying:
		_orbit_yaw = 24.0
		_orbit_pitch = 16.0
		_orbit_dist = 14.0
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_was_replaying = replaying

	# Hide the exterior fuselage only from the cockpit eye-point while flying;
	# during replay we're orbiting outside, so the airframe must be visible.
	if _airframe:
		_airframe.visible = replaying or view != View.COCKPIT

	if replaying:
		_orbit_camera()
		return

	var tx := target.global_transform
	match view:
		View.COCKPIT:
			fov = COCKPIT_FOV
			global_position = tx * COCKPIT_OFFSET
			# Head orientation = aircraft basis * (yaw then pitch), so free-look
			# is relative to the cabin and the view banks with the aircraft.
			var look := Basis(Vector3.UP, deg_to_rad(_look_yaw)) \
				* Basis(Vector3.RIGHT, deg_to_rad(BASE_PITCH + _look_pitch))
			global_transform = Transform3D((tx.basis * look).orthonormalized(), tx * COCKPIT_OFFSET)
		View.CHASE:
			fov = EXTERNAL_FOV
			var desired := tx.origin + tx.basis * CHASE_OFFSET
			_chase_pos = _chase_pos.lerp(desired, clampf(6.0 * delta, 0.0, 1.0))
			global_position = _chase_pos
			look_at(tx.origin + tx.basis * Vector3(0, 0.5, -4.0), tx.basis.y)
		View.WING:
			fov = EXTERNAL_FOV
			global_position = tx * WING_OFFSET
			look_at(tx.origin, Vector3.UP)
		View.TOWER:
			fov = EXTERNAL_FOV
			global_position = _tower_pos
			if global_position.distance_to(tx.origin) > 5.0:
				look_at(tx.origin, Vector3.UP)


## Orbit the aircraft for replay inspection. The camera sits on a sphere around
## the model so its pitch and bank are clearly readable from any angle.
func _orbit_camera() -> void:
	fov = EXTERNAL_FOV
	var center := target.global_position + Vector3.UP * 1.0
	var cy := deg_to_rad(_orbit_yaw)
	var cp := deg_to_rad(_orbit_pitch)
	var dir := Vector3(sin(cy) * cos(cp), sin(cp), cos(cy) * cos(cp))
	global_position = center + dir * _orbit_dist
	look_at(center, Vector3.UP)
