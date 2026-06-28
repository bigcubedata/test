extends CanvasLayer
## Shows the flat 2D instrument overlay only for external camera views. In the
## cockpit view the instruments are already on the 3D panel, so the overlay is
## hidden for an unobstructed out-the-window picture.

@export var camera_path: NodePath
@export var hide_in_cockpit: Array[NodePath] = []

var _cam: Node


func _ready() -> void:
	_cam = get_node_or_null(camera_path)


func _process(_delta: float) -> void:
	if _cam == null:
		return
	# View.COCKPIT == 0 in CameraController's enum.
	var in_cockpit: bool = int(_cam.view) == 0
	for p in hide_in_cockpit:
		var n := get_node_or_null(p)
		if n:
			n.visible = not in_cockpit
