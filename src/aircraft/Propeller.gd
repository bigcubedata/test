extends Node3D
## Spinning two-blade propeller + spinner for the C172.
##
## Builds a hub, spinner cone, two blades and a translucent "prop arc" disc.
## The blades spin at a capped *visual* rate (real 2700 rpm would just strobe
## at the frame rate), while the arc disc fades in with rpm to sell the blur.
## Forward is -Z, so the propeller spins about the Z axis.

const VISUAL_MAX_RPS := 4.0   # capped visual revs/sec (avoids strobing)

var _blades: Node3D
var _arc_mat: StandardMaterial3D


func _ready() -> void:
	var dark := _mat(Color(0.06, 0.06, 0.07), 0.45, 0.1)
	var tip := _mat(Color(0.95, 0.78, 0.08), 0.4, 0.1)        # painted warning tip
	var alu := _mat(Color(0.78, 0.78, 0.81), 0.25, 0.85)      # polished spinner

	# Polished spinner cone (narrow end forward, -Z).
	var spinner := _cyl(0.02, 0.11, 0.24, alu, Vector3(-PI * 0.5, 0, 0))
	spinner.position = Vector3(0, 0, -0.12)

	_blades = Node3D.new()
	add_child(_blades)
	# Hub.
	_cyl(0.055, 0.055, 0.09, dark, Vector3(PI * 0.5, 0, 0), _blades)
	# Two slim, pitched blades with yellow tips (instead of one flat slab).
	for s in [1.0, -1.0]:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.075, 0.84, 0.02)
		b.mesh = bm
		b.material_override = dark
		b.position = Vector3(0, s * 0.50, 0)
		b.rotation = Vector3(0, 0.30, 0)                 # blade pitch/twist
		_blades.add_child(b)
		var t := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(0.075, 0.12, 0.02)
		t.mesh = tm
		t.material_override = tip
		t.position = Vector3(0, s * 0.92, 0)
		t.rotation = Vector3(0, 0.30, 0)
		_blades.add_child(t)

	# Translucent prop-arc disc that fades in with rpm to sell the blur.
	var arc := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.99
	disc.bottom_radius = 0.99
	disc.height = 0.006
	arc.mesh = disc
	arc.rotation = Vector3(PI * 0.5, 0, 0)
	_arc_mat = StandardMaterial3D.new()
	_arc_mat.albedo_color = Color(0.62, 0.62, 0.64, 0.0)
	_arc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arc.material_override = _arc_mat
	arc.position = Vector3(0, 0, -0.02)
	add_child(arc)


func _process(delta: float) -> void:
	var rpm: float = FlightData.engine_rpm
	var rps := minf(rpm / 60.0, VISUAL_MAX_RPS)
	if _blades:
		_blades.rotation.z += rps * TAU * delta
	if _arc_mat:
		# Blades visible at low rpm; arc disc takes over as it spools up.
		var a := clampf((rpm - 500.0) / 1100.0, 0.0, 1.0) * 0.34
		_arc_mat.albedo_color.a = a


func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _cyl(r: float, top: float, h: float, mat: StandardMaterial3D, rot: Vector3, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = top
	mesh.height = h
	mi.mesh = mesh
	mi.material_override = mat
	mi.rotation = rot
	(parent if parent else self).add_child(mi)
	return mi
