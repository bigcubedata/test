extends Node3D
## Top-level scene controller: positions the aircraft on the runway, wires the
## camera to it, and keeps a couple of helper overlays in sync.

@onready var aircraft: Aircraft = $Aircraft


func _ready() -> void:
	# Spawn on the south end of the runway, lined up to depart to the north.
	# Height is the gear's static equilibrium so it settles without a bounce.
	var spawn := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.12, 480.0))
	aircraft.global_transform = spawn
	aircraft.set_spawn(spawn, Vector3.ZERO)
