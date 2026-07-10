extends Node3D
## Exterior model for the C172.
##
## Preferred path: load the FlightGear c172p exterior (assets/models/c172.glb,
## GPL-2.0 — see assets/models/LICENSE.md) at runtime via GLTFDocument. The
## GLB carries the control surfaces, propeller, spinner and nose gear as
## separate named nodes whose origins sit on the real hinge lines, so this
## script can articulate them directly.
##
## Fallback path (GLB missing/unreadable): the original procedurally-built
## exterior — a lofted fuselage, shaped planforms, struts and faired gear —
## so the project still runs with zero external assets.
##
## Body frame: forward = -Z, up = +Y, right = +X.

const SEG := 24  # cross-section resolution

# ---- GLTF exterior (FlightGear c172p conversion) --------------------------
const GLB_PATH := "res://assets/models/c172.glb"
# Hinge axes in body frame, from the FlightGear animation definitions
# (converted to Godot axes). Node origins already sit on the hinge lines.
const AIL_L_AXIS := Vector3(0.9937, -0.0426, 0.1033)
const AIL_R_AXIS := Vector3(0.9937, 0.0426, -0.1033)
const RUD_AXIS := Vector3(-0.0082, 0.8294, 0.5586)
const NOSE_AXIS := Vector3(0.0, -0.9579, -0.2870)   # raked steering axis
const FLAP_TRAVEL := Vector3(0.0, -0.10, 0.08)      # Fowler-style slide at full flaps
const PROP_BLUR_RPM := 900.0    # above this the textured blur disc takes over
const VISUAL_MAX_RPS := 4.0     # capped visual prop rate (avoids strobing)

var _gltf := false
var _anim := {}                 # group name -> [{node, base}] (GLB mode)
var _prop_angle := 0.0
var _proc_prop: Node3D          # procedural prop, kept for the cockpit view

var _white: StandardMaterial3D
var _blue: StandardMaterial3D
var _glass: StandardMaterial3D
var _metal: StandardMaterial3D
var _tire: StandardMaterial3D

# Animated control-surface pivots (flaps follow FlightData; the rest follow
# the parent Aircraft's live surface deflections).
var _aircraft: Node
var _flaps: Array = []
var _ail_r: Node3D
var _ail_l: Node3D
var _elev: Node3D
var _rud: Node3D


func _ready() -> void:
	_aircraft = get_parent()
	if _load_gltf():
		return
	_white = _mat(Color(0.80, 0.81, 0.84), 0.55, 0.0)
	_blue = _mat(Color(0.12, 0.34, 0.62), 0.4, 0.1)
	# Windshield: nearly clear and non-metallic so you can see the runway
	# through it from the cockpit (a shiny windshield mirrors the sky white).
	_glass = _mat(Color(0.6, 0.7, 0.82, 0.13), 0.35, 0.0)
	_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_metal = _mat(Color(0.32, 0.33, 0.36), 0.4, 0.6)
	_tire = _mat(Color(0.06, 0.06, 0.07), 0.7, 0.0)

	_build_fuselage()
	_build_wings()
	_build_struts()
	_build_tail()
	_build_gear()
	_build_windows()
	_build_stripe()
	_build_cowl_details()
	_build_registration()
	_build_details()


func _process(_delta: float) -> void:
	if _gltf:
		_animate_gltf(_delta)
		return
	# Animate control surfaces. Flaps track FlightData (so they replay too);
	# ailerons/elevator/rudder track the live deflections on the Aircraft.
	var fl := deg_to_rad(FlightData.flaps_deg)
	for p in _flaps:
		p.rotation.x = fl
	if _aircraft == null:
		return
	var ail: float = _aircraft.aileron
	if _ail_r:
		_ail_r.rotation.x = -ail          # right aileron up on right-roll input
	if _ail_l:
		_ail_l.rotation.x = ail
	if _elev:
		_elev.rotation.x = -_aircraft.elevator * 1.2
	if _rud:
		_rud.rotation.y = _aircraft.rudder * 1.3


# --------------------------------------------------------------------------
#  GLTF exterior (FlightGear c172p conversion)
# --------------------------------------------------------------------------

## Load the converted FlightGear model at runtime. GLTFDocument works both in
## the editor and headless, and needs no import step. Returns false (-> the
## procedural fallback is built instead) if the file is absent or unreadable.
func _load_gltf() -> bool:
	if not FileAccess.file_exists(GLB_PATH):
		return false
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(GLB_PATH, state) != OK:
		push_warning("Airframe: failed to parse %s, using procedural model" % GLB_PATH)
		return false
	var model := doc.generate_scene(state)
	if model == null:
		push_warning("Airframe: failed to instance %s, using procedural model" % GLB_PATH)
		return false
	add_child(model)
	# Collect the articulated nodes; converter emits them as Group, Group_1, …
	# with identical origins, so every node in a group gets the same motion.
	for group in ["Flaps", "AileronL", "AileronR", "Elevator", "Rudder",
			"PropSlow", "PropFast", "Spinner", "NoseGear"]:
		_anim[group] = []
		_collect_group(model, group, _anim[group])
	_gltf = true
	# The GLB carries its own propeller + blur disc for the external views.
	# The procedural propeller stays alive for the cockpit eye-point, where
	# the whole exterior model is hidden but the prop must still be seen
	# through the windshield; _animate_gltf swaps them with our visibility.
	_proc_prop = get_parent().get_node_or_null("Propeller")
	return true


func _collect_group(root: Node, group: String, into: Array) -> void:
	for child in root.get_children():
		var n := child.name as String
		if n == group or n.begins_with(group + "_"):
			# Guard against prefix collisions (e.g. "Prop" vs "PropFast").
			into.append({"node": child, "base": (child as Node3D).position})
		_collect_group(child, group, into)


func _set_group(group: String, basis: Basis, offset: Vector3 = Vector3.ZERO) -> void:
	for e in _anim[group]:
		e.node.transform = Transform3D(basis, e.base + offset)


func _animate_gltf(delta: float) -> void:
	# Show the procedural prop exactly when the exterior model is hidden
	# (cockpit view while flying); external and replay views use the GLB prop.
	if _proc_prop and _proc_prop.visible == visible:
		_proc_prop.visible = not visible

	# Flaps: the real 172's flaps run aft and down on tracks while rotating,
	# so the slide (from the FlightGear animation) is applied with the hinge
	# rotation. Driven from FlightData so they animate in replay too.
	var fnorm: float = FlightData.flaps_deg / 30.0
	_set_group("Flaps", Basis(Vector3.RIGHT, deg_to_rad(30.0) * fnorm), FLAP_TRAVEL * fnorm)

	# Prop: spin at a capped visual rate; above ~900 rpm swap the geometric
	# blades for the textured blur disc (both spin about the crank axis).
	var rpm: float = FlightData.engine_rpm
	_prop_angle = wrapf(_prop_angle + TAU * minf(rpm / 60.0, VISUAL_MAX_RPS) * delta, 0.0, TAU)
	var spin := Basis(Vector3.BACK, _prop_angle)
	_set_group("Spinner", spin)
	_set_group("PropSlow", spin)
	_set_group("PropFast", spin)
	var blur := rpm > PROP_BLUR_RPM
	for e in _anim["PropSlow"]:
		e.node.visible = not blur
	for e in _anim["PropFast"]:
		e.node.visible = blur

	if _aircraft == null:
		return
	# Control surfaces follow the live deflections (radians) on the Aircraft;
	# signs match the procedural fallback (+X hinge rotation = trailing edge
	# down, checked against the FlightGear animation definitions).
	var ail: float = _aircraft.aileron
	_set_group("AileronL", Basis(AIL_L_AXIS, ail))
	_set_group("AileronR", Basis(AIL_R_AXIS, -ail))
	_set_group("Elevator", Basis(Vector3.RIGHT, -_aircraft.elevator * 1.2))
	_set_group("Rudder", Basis(RUD_AXIS, _aircraft.rudder * 1.3))
	# Nose wheel mirrors the physics steer angle about the raked strut axis.
	var steer: float = (_aircraft.rudder / _aircraft.MAX_RUDDER) * _aircraft.NOSE_STEER_ANGLE
	_set_group("NoseGear", Basis(NOSE_AXIS, steer))


# --------------------------------------------------------------------------
#  Fuselage (lofted elliptical sections)
# --------------------------------------------------------------------------
func _build_fuselage() -> void:
	# stations: z (fwd -Z), half-width x, half-height y, vertical centre.
	# Nose shortened to a true C172 cowl length (spinner ~-3.8); the long tail
	# boom and tall cabin are kept for the right proportions.
	var st := [
		[-3.70, 0.10, 0.11, -0.05],   # cowl front, flush with the spinner base
		[-3.35, 0.30, 0.28, -0.05],
		[-2.95, 0.48, 0.44, -0.01],
		[-2.55, 0.55, 0.58, 0.04],
		[-2.20, 0.57, 0.66, 0.07],    # windshield base
		[-1.40, 0.58, 0.70, 0.09],    # cabin (tallest)
		[-0.40, 0.56, 0.70, 0.09],
		[0.60, 0.48, 0.59, 0.08],
		[1.55, 0.33, 0.42, 0.11],
		[2.55, 0.19, 0.27, 0.16],
		[3.55, 0.09, 0.16, 0.22],     # tailcone
	]
	var rings: Array = []
	for s in st:
		rings.append(_ring(s[0], s[1], s[2], s[3]))
	# The fuselage is a closed tube, so cull back faces (avoids the near/far
	# wall z-fighting moire you get with double-sided rendering).
	var fuse_mat := _mat(Color(0.80, 0.81, 0.84), 0.55, 0.0)
	fuse_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_add_mesh(_loft_mesh(rings, true, true), fuse_mat)


func _ring(z: float, w: float, h: float, cy: float) -> PackedVector3Array:
	var r := PackedVector3Array()
	for i in range(SEG):
		var a := TAU * float(i) / float(SEG)
		r.append(Vector3(w * cos(a), cy + h * sin(a), z))
	return r


# --------------------------------------------------------------------------
#  Wings (tapered, rounded tip, dihedral) + struts
# --------------------------------------------------------------------------
func _build_wings() -> void:
	# Planform in (span = u/X, chord = v/Z); thickness along Y. The trailing
	# edge stops at v=0.70 — the last ~22% of chord is the separate flap and
	# aileron surfaces built below, which animate.
	# Root starts at the centreline (buried inside the hull) so there is no
	# gap where the wing meets the curved cabin roof.
	var prof := PackedVector2Array([
		Vector2(0.0, -0.55), Vector2(3.9, -0.55), Vector2(5.05, -0.40),
		Vector2(5.30, 0.05), Vector2(5.05, 0.55), Vector2(3.9, 0.70),
		Vector2(0.0, 0.70),
	])
	var dih := 0.05  # dihedral (rad)
	for sign in [1.0, -1.0]:
		var m := _extrude(prof, Vector3(sign, 0, 0), Vector3(0, 0, 1), 0.17,
			Vector3(0, 0, -1.55), _white)
		m.rotation = Vector3(0, 0, dih * sign)  # tips up (dihedral)
		m.position.y = 0.80                      # sunk onto the cabin roof
		# Blue tip cap — same thickness as the wing so it doesn't form a lip.
		var tip := PackedVector2Array([
			Vector2(4.55, -0.42), Vector2(5.05, -0.40), Vector2(5.30, 0.05),
			Vector2(5.05, 0.55), Vector2(4.55, 0.66)])
		var tm := _extrude(tip, Vector3(sign, 0, 0), Vector3(0, 0, 1), 0.175,
			Vector3(0, 0, -1.55), _blue)
		tm.rotation = Vector3(0, 0, dih * sign)
		tm.position.y = 0.80

		# Hinged trailing-edge surfaces (hinge line at z = -0.85), tucked well
		# under the trailing edge so no daylight shows at the hinge line.
		var surf := _mat(Color(0.72, 0.73, 0.76), 0.5, 0.0)
		var flap := _hinged_surface(Vector3(sign * 1.5, 0.78 + 0.05 * 1.5, -0.85),
			Vector3(1.9, 0.09, 0.40), dih * sign, surf)
		_flaps.append(flap)
		var ail := _hinged_surface(Vector3(sign * 3.7, 0.78 + 0.05 * 3.7, -0.85),
			Vector3(2.1, 0.08, 0.36), dih * sign, surf)
		if sign > 0.0:
			_ail_r = ail
		else:
			_ail_l = ail


## A control surface hanging aft (+Z) of its hinge-line pivot, overlapping
## the fixed surface by ~7 cm so the hinge never shows a gap when deflected.
func _hinged_surface(pivot_pos: Vector3, sz: Vector3, roll: float,
		mat: StandardMaterial3D) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	pivot.rotation.z = roll
	add_child(pivot)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = Vector3(0, 0, sz.z * 0.5 - 0.07)
	pivot.add_child(mi)
	return pivot


func _build_struts() -> void:
	# Lift strut from the lower fuselage to the wing underside at mid-span. The
	# wing sits at y=0.66 with dihedral, so its underside at span ~2.5 is near
	# y=0.70 — the strut top must reach there or it visibly floats below the wing.
	for sign in [1.0, -1.0]:
		var top := Vector3(sign * 2.5, 0.88, -1.55)
		var bot := Vector3(sign * 0.42, -0.39, -1.42)
		_strut(top, bot, 0.05)
		# Small jury strut bracing the main strut to the wing near the attach.
		_strut(Vector3(sign * 2.12, 0.55, -1.5), Vector3(sign * 2.45, 0.87, -1.62), 0.03)


func _strut(a: Vector3, b: Vector3, thick: float) -> void:
	var mid := (a + b) * 0.5
	var length := a.distance_to(b)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thick, length, thick * 2.4)  # long axis = local Y
	mi.mesh = bm
	mi.material_override = _white
	# Build a basis whose +Y points along the strut.
	var y := (a - b).normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y, z), mid)
	add_child(mi)


# --------------------------------------------------------------------------
#  Empennage: swept fin + dorsal, tapered stabiliser
# --------------------------------------------------------------------------
func _build_tail() -> void:
	# Vertical fin (planform in chord=Z, height=Y; thin in X) with dorsal fin.
	# The trailing part is a separate rudder hinged at z = 3.30.
	var fin := PackedVector2Array([
		Vector2(1.9, 0.30), Vector2(3.05, 1.45), Vector2(3.28, 1.45),
		Vector2(3.30, 0.32),
	])
	_add_mesh(_extrude_mesh(fin, Vector3(0, 0, 1), Vector3(0, 1, 0), 0.08), _blue)

	_rud = Node3D.new()
	_rud.position = Vector3(0, 0, 3.30)
	add_child(_rud)
	# Rudder profile starts 6 cm AHEAD of its hinge so it tucks into the fin
	# (same thickness as the fin: no lip, no slot).
	var rud_prof := PackedVector2Array([
		Vector2(-0.06, 0.31), Vector2(0.42, 0.36), Vector2(0.26, 1.44), Vector2(-0.06, 1.44),
	])
	var rud_mi := MeshInstance3D.new()
	rud_mi.mesh = _extrude_mesh(rud_prof, Vector3(0, 0, 1), Vector3(0, 1, 0), 0.08)
	rud_mi.material_override = _blue
	_rud.add_child(rud_mi)

	# Horizontal stabiliser (span=X, chord=Z; thin in Y); the elevator hangs
	# from a hinge at z = 3.40.
	var stab := PackedVector2Array([
		Vector2(-1.75, 3.08), Vector2(1.75, 3.08), Vector2(1.5, 3.40), Vector2(-1.5, 3.40),
	])
	_extrude(stab, Vector3(1, 0, 0), Vector3(0, 0, 1), 0.10, Vector3(0, 0.32, 0), _white)

	_elev = Node3D.new()
	_elev.position = Vector3(0, 0.32, 3.40)
	add_child(_elev)
	var ele_mi := MeshInstance3D.new()
	var ele_bm := BoxMesh.new()
	# Matches the stab's trailing-edge width/thickness; overlaps the hinge.
	ele_bm.size = Vector3(3.0, 0.09, 0.34)
	ele_mi.mesh = ele_bm
	ele_mi.material_override = _white
	ele_mi.position = Vector3(0, 0, 0.10)
	_elev.add_child(ele_mi)


# --------------------------------------------------------------------------
#  Fixed tricycle gear with wheel fairings
# --------------------------------------------------------------------------
func _build_gear() -> void:
	# Wheel heights/stations follow the physics gear (contact plane ~1.1 m
	# below the CG at rest) so the tires roll on the runway surface instead of
	# sinking into it.
	for sign in [1.0, -1.0]:
		_strut(Vector3(sign * 0.18, -0.30, -0.45), Vector3(sign * 1.05, -0.72, -0.45), 0.06)
		_wheel(Vector3(sign * 1.05, -0.85, -0.45))
	# Nose gear under the cowl.
	_strut(Vector3(0.0, -0.40, -2.45), Vector3(0.0, -0.72, -2.60), 0.07)
	_wheel(Vector3(0.0, -0.85, -2.60))


func _wheel(pos: Vector3) -> void:
	# Tyre (cylinder, axis along X).
	var tyre := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.26
	cm.bottom_radius = 0.26
	cm.height = 0.13
	tyre.mesh = cm
	tyre.material_override = _tire
	tyre.rotation = Vector3(0, 0, PI * 0.5)
	tyre.position = pos
	add_child(tyre)
	# Wheel fairing (pant): a flattened teardrop.
	var pant := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	pant.mesh = sm
	pant.scale = Vector3(0.45, 0.7, 1.15)
	pant.material_override = _white
	pant.position = pos + Vector3(0, 0.02, 0.05)
	add_child(pant)


# --------------------------------------------------------------------------
#  Glass: windshield + side windows
# --------------------------------------------------------------------------
func _build_windows() -> void:
	# Big Cessna glazing: a wide windshield raked AFT (base at the cowl, top at
	# the wing leading edge), tall door windows, rear windows and small
	# rear-quarter lights — the 172's greenhouse look.
	var wprof := PackedVector2Array([
		Vector2(-0.56, 0.0), Vector2(0.56, 0.0), Vector2(0.46, 0.68), Vector2(-0.46, 0.68)])
	_extrude(wprof, Vector3(1, 0, 0), Vector3(0, 0.75, 0.55).normalized(), 0.02,
		Vector3(0, 0.24, -2.42), _glass)
	for sign in [1.0, -1.0]:
		# Door window.
		var door := PackedVector2Array([
			Vector2(-0.52, -0.20), Vector2(0.52, -0.20), Vector2(0.44, 0.24), Vector2(-0.44, 0.24)])
		var m := _extrude(door, Vector3(0, 0, 1), Vector3(0, 1, 0), 0.02,
			Vector3(sign * 0.615, 0.30, -1.42), _glass)
		m.rotation = Vector3(0, sign * -0.04, 0)  # toe in to follow the body
		# Rear cabin window.
		var rear := PackedVector2Array([
			Vector2(-0.46, -0.16), Vector2(0.46, -0.16), Vector2(0.38, 0.22), Vector2(-0.38, 0.22)])
		var r := _extrude(rear, Vector3(0, 0, 1), Vector3(0, 1, 0), 0.02,
			Vector3(sign * 0.575, 0.30, -0.40), _glass)
		r.rotation = Vector3(0, sign * -0.09, 0)
		# Rear-quarter light on the tapering aft cabin.
		var qtr := PackedVector2Array([
			Vector2(-0.30, -0.10), Vector2(0.30, -0.10), Vector2(0.22, 0.16), Vector2(-0.22, 0.16)])
		var q := _extrude(qtr, Vector3(0, 0, 1), Vector3(0, 1, 0), 0.02,
			Vector3(sign * 0.50, 0.30, 0.42), _glass)
		q.rotation = Vector3(0, sign * -0.14, 0)


func _build_stripe() -> void:
	# Blue cheatline along the fuselage sides, segmented so it follows the
	# hull's taper (a single flat plane would bury itself or float).
	var pts := [
		[-2.90, 0.46], [-2.40, 0.555], [-1.60, 0.585], [-0.60, 0.575],
		[0.40, 0.51], [1.30, 0.38], [2.20, 0.24], [2.90, 0.15],
	]
	for side in [1.0, -1.0]:
		for i in range(pts.size() - 1):
			var z0: float = pts[i][0]
			var w0: float = pts[i][1]
			var z1: float = pts[i + 1][0]
			var w1: float = pts[i + 1][1]
			var length := z1 - z0
			var seg := _box(Vector3(0.02, 0.15, length + 0.06),
				Vector3(side * ((w0 + w1) * 0.5 + 0.012), -0.10, (z0 + z1) * 0.5), _blue)
			seg.rotation.y = side * atan2(w0 - w1, length)


func _build_cowl_details() -> void:
	# Air-intake scoops each side of the spinner, a landing light between them
	# and an exhaust stub under the right cowl cheek.
	var dark := _mat(Color(0.05, 0.05, 0.06), 0.7, 0.0)
	for s in [1.0, -1.0]:
		_box(Vector3(0.16, 0.11, 0.10), Vector3(s * 0.15, -0.14, -3.40), dark)
	_box(Vector3(0.12, 0.07, 0.06), Vector3(0.0, -0.24, -3.44),
		_mat(Color(0.9, 0.92, 0.82), 0.2, 0.4))
	var pipe := _box(Vector3(0.07, 0.07, 0.30), Vector3(0.16, -0.47, -2.95),
		_mat(Color(0.25, 0.25, 0.27), 0.5, 0.6))
	pipe.rotation.x = 0.25


func _build_registration() -> void:
	# N-number on both sides of the aft fuselage, rotated to follow the taper.
	for s in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = "N172SG"
		l.font = UiFont.bold()
		l.font_size = 120
		l.pixel_size = 0.0032
		l.modulate = Color(0.10, 0.22, 0.45)
		l.position = Vector3(s * 0.40, 0.16, 1.15)
		l.rotation.y = s * (PI * 0.5 - 0.14)
		add_child(l)


func _build_details() -> void:
	# Navigation lights: red left wingtip, green right, white on the tailcone.
	var red := _unlit(Color(0.95, 0.1, 0.1))
	var grn := _unlit(Color(0.1, 0.9, 0.2))
	var wht := _unlit(Color(1.0, 1.0, 0.95))
	_box(Vector3(0.05, 0.05, 0.09), Vector3(-5.28, 1.062, -1.93), red)
	_box(Vector3(0.05, 0.05, 0.09), Vector3(5.28, 1.062, -1.93), grn)
	_box(Vector3(0.05, 0.05, 0.05), Vector3(0.0, 0.24, 3.58), wht)

	# Pitot tube under the left wing.
	var metal := _mat(Color(0.6, 0.6, 0.62), 0.35, 0.7)
	var pitot := _box(Vector3(0.025, 0.025, 0.30), Vector3(-2.1, 0.72, -2.05), metal)
	pitot.rotation.x = 0.12
	_box(Vector3(0.02, 0.10, 0.02), Vector3(-2.1, 0.78, -1.95), metal)

	# Comm/nav blade antennas on the cabin roof and spine.
	var ant := _mat(Color(0.85, 0.85, 0.87), 0.5, 0.1)
	var a1 := _box(Vector3(0.02, 0.16, 0.22), Vector3(0.0, 0.86, 0.15), ant)
	a1.rotation.x = -0.35
	var a2 := _box(Vector3(0.02, 0.12, 0.18), Vector3(0.0, 0.55, 1.4), ant)
	a2.rotation.x = -0.35


func _unlit(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(sz: Vector3, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


# --------------------------------------------------------------------------
#  Mesh helpers
# --------------------------------------------------------------------------
func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	# Solid parts are closed prisms/tubes, so cull back faces to avoid the
	# double-sided z-fighting moire seen edge-on. (Glass is made double-sided
	# explicitly below.)
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


func _add_mesh(mesh: ArrayMesh, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	return mi


## Loft a tube through rings (each a PackedVector3Array of equal length).
func _loft_mesh(rings: Array, cap_front: bool, cap_back: bool) -> ArrayMesh:
	var n := SEG
	var verts := PackedVector3Array()
	for ring in rings:
		for p in ring:
			verts.append(p)
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for k in range(normals.size()):
		normals[k] = Vector3.ZERO
	var idx := PackedInt32Array()
	for r in range(rings.size() - 1):
		for i in range(n):
			var a := r * n + i
			var b := r * n + (i + 1) % n
			var c := (r + 1) * n + (i + 1) % n
			var d := (r + 1) * n + i
			idx.append_array([a, b, c, a, c, d])
	# Accumulate face normals.
	for t in range(0, idx.size(), 3):
		var ia := idx[t]
		var ib := idx[t + 1]
		var ic := idx[t + 2]
		var fn := (verts[ib] - verts[ia]).cross(verts[ic] - verts[ia])
		normals[ia] += fn
		normals[ib] += fn
		normals[ic] += fn
	# Orient outward (radial from the body axis).
	for k in range(verts.size()):
		var v := verts[k]
		var radial := Vector3(v.x, v.y - 0.05, 0.0)
		var nrm := normals[k].normalized()
		if nrm.dot(radial) < 0.0:
			nrm = -nrm
		normals[k] = nrm
	# End caps to a centre point.
	if cap_front:
		_cap(verts, normals, idx, 0, rings[0], true)
	if cap_back:
		_cap(verts, normals, idx, (rings.size() - 1) * n, rings[rings.size() - 1], false)

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


func _cap(verts: PackedVector3Array, normals: PackedVector3Array, idx: PackedInt32Array,
		base: int, ring: PackedVector3Array, front: bool) -> void:
	var center := Vector3.ZERO
	for p in ring:
		center += p
	center /= ring.size()
	var dir := Vector3(0, 0, -0.18) if front else Vector3(0, 0, 0.18)
	var ci := verts.size()
	verts.append(center + dir)
	normals.append(Vector3(0, 0, -1) if front else Vector3(0, 0, 1))
	for i in range(SEG):
		var a := base + i
		var b := base + (i + 1) % SEG
		if front:
			idx.append_array([ci, b, a])
		else:
			idx.append_array([ci, a, b])


## Extrude a 2D polygon (in the u/v plane) by `thickness` along u x v.
func _extrude(profile: PackedVector2Array, uaxis: Vector3, vaxis: Vector3,
		thickness: float, origin: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	return _add_mesh(_extrude_mesh(profile, uaxis, vaxis, thickness), mat)


func _extrude_mesh(profile: PackedVector2Array, uaxis: Vector3, vaxis: Vector3,
		thickness: float) -> ArrayMesh:
	var naxis := uaxis.cross(vaxis).normalized()
	var half := naxis * (thickness * 0.5)
	var tris := Geometry2D.triangulate_polygon(profile)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var to3 := func(p: Vector2, off: Vector3) -> Vector3:
		return uaxis * p.x + vaxis * p.y + off
	# Front + back caps.
	for k in range(0, tris.size(), 3):
		var p0: Vector2 = profile[tris[k]]
		var p1: Vector2 = profile[tris[k + 1]]
		var p2: Vector2 = profile[tris[k + 2]]
		verts.append(to3.call(p0, half)); verts.append(to3.call(p1, half)); verts.append(to3.call(p2, half))
		for _i in range(3): normals.append(naxis)
		verts.append(to3.call(p2, -half)); verts.append(to3.call(p1, -half)); verts.append(to3.call(p0, -half))
		for _i in range(3): normals.append(-naxis)
	# Side walls.
	var m := profile.size()
	for i in range(m):
		var a2: Vector2 = profile[i]
		var b2: Vector2 = profile[(i + 1) % m]
		var af: Vector3 = to3.call(a2, half)
		var bf: Vector3 = to3.call(b2, half)
		var ab: Vector3 = to3.call(a2, -half)
		var bb: Vector3 = to3.call(b2, -half)
		var sn := (bf - af).cross(naxis).normalized()
		verts.append(af); verts.append(bf); verts.append(bb)
		verts.append(af); verts.append(bb); verts.append(ab)
		for _i in range(6): normals.append(sn)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am
