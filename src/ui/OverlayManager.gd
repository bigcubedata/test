extends CanvasLayer
## Keeps the 2D corner instruments (PFD bottom-left, MFD bottom-right) up in
## every view — cockpit, external and replay alike. They are the primary
## instruments now, so unlike a simulated 3D panel they are always readable,
## including while hand-flying from the cockpit eye-point.

@export var camera_path: NodePath
## Overlays this manager keeps visible (kept under the old name so the scene
## binding still resolves).
@export var hide_in_cockpit: Array[NodePath] = []


func _process(_delta: float) -> void:
	for p in hide_in_cockpit:
		var n := get_node_or_null(p)
		if n and not n.visible:
			n.visible = true
