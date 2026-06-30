extends Camera3D
## Follows the aircraft with several selectable views (cycle with C).
##   0  Cockpit - pilot eye point with mouse free-look
##   1  Chase   - smoothed third-person trailing camera
##   2  Wing    - external view from off the left wing
##   3  Tower   - fixed runway-tower view that tracks the aircraft
##
## Cockpit free-look: hold the RIGHT mouse button and move the mouse to look
## around the cabin (down at the panel, up and out the windshield, to the side
## windows) — like turning your head in a real cockpit. Release to free the
## cursor. Switching view recentres the look.

@export var target_path: NodePath
var target: Node3D
var _airframe: Node3D

enum View { COCKPIT, CHASE, WING, TOWER }
var view: int = View.COCKPIT

const CHASE_OFFSET := Vector3(0.0, 3.5, 13.0)
const COCKPIT_OFFSET := Vector3(-0.22, 0.57, -1.05) # pilot eye point (raised to see over the nose)
const WING_OFFSET := Vector3(-8.0, 1.5, 0.0)
const COCKPIT_FOV := 74.0
const EXTERNAL_FOV := 65.0
const BASE_PITCH := -10.0    # default look favours outside; free-look down for panel
const LOOK_SENS := 0.18

var _tower_pos := Vector3(40.0, 12.0, 60.0)
var _chase_pos: Vector3
var _look_yaw := 0.0
var _look_pitch := 0.0


func _ready() -> void:
	if target_path:
		target = get_node(target_path)
	current = true
	if target:
		_chase_pos = target.global_position + target.global_transform.basis * CHASE_OFFSET
		_airframe = target.get_node_or_null("Airframe")


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("toggle_view"):
		view = (view + 1) % View.size()
		_look_yaw = 0.0
		_look_pitch = 0.0
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if view != View.COCKPIT:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_yaw = clampf(_look_yaw - event.relative.x * LOOK_SENS, -150.0, 150.0)
		_look_pitch = clampf(_look_pitch - event.relative.y * LOOK_SENS, -85.0, 55.0)


func _physics_process(delta: float) -> void:
	if not target:
		return
	# Hide the exterior fuselage from the cockpit (you're inside it); the
	# cockpit interior + propeller provide the in-cabin visuals, and the
	# windshield view stays clear for visual approaches.
	if _airframe:
		_airframe.visible = view != View.COCKPIT
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
