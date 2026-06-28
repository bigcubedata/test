extends Camera3D
## Follows the aircraft with several selectable views.
##
## Views cycle with the "toggle_view" action (C):
##   0  Chase     - smoothed third-person trailing camera
##   1  Cockpit   - pilot eye point looking forward
##   2  Wing      - external view from off the left wing
##   3  Tower     - fixed runway-tower view that tracks the aircraft

@export var target_path: NodePath
var target: Node3D

enum View { CHASE, COCKPIT, WING, TOWER }
var view: int = View.CHASE

const CHASE_OFFSET := Vector3(0.0, 3.5, 13.0)   # behind & above (in body space)
const COCKPIT_OFFSET := Vector3(0.0, 0.9, -1.4) # pilot eye point
const WING_OFFSET := Vector3(-8.0, 1.5, 0.0)
var _tower_pos := Vector3(40.0, 12.0, 60.0)
var _chase_pos: Vector3


func _ready() -> void:
	if target_path:
		target = get_node(target_path)
	current = true
	if target:
		_chase_pos = target.global_position + target.global_transform.basis * CHASE_OFFSET


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("toggle_view"):
		view = (view + 1) % View.size()


func _physics_process(delta: float) -> void:
	if not target:
		return
	var tx := target.global_transform
	match view:
		View.CHASE:
			# Critically-damped follow so the camera lags gently in turns.
			var desired := tx.origin + tx.basis * CHASE_OFFSET
			_chase_pos = _chase_pos.lerp(desired, clampf(6.0 * delta, 0.0, 1.0))
			global_position = _chase_pos
			look_at(tx.origin + tx.basis * Vector3(0, 0.5, -4.0), tx.basis.y)
		View.COCKPIT:
			global_transform = tx
			global_position = tx * COCKPIT_OFFSET
			# Look forward along the nose with a slight down angle.
			look_at(tx * Vector3(0, 0.7, -30.0), tx.basis.y)
		View.WING:
			global_position = tx * WING_OFFSET
			look_at(tx.origin, Vector3.UP)
		View.TOWER:
			global_position = _tower_pos
			if global_position.distance_to(tx.origin) > 5.0:
				look_at(tx.origin, Vector3.UP)
