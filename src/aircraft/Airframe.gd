extends Node3D
## Procedurally-built refined exterior for the C172.
##
## Instead of crude boxes, the fuselage is a smooth lofted body (elliptical
## cross-sections from a rounded cabin to a tapered tail boom), the flight
## surfaces are shaped planforms (taper, rounded tips, swept fin + dorsal),
## and the aircraft has wing lift struts and faired fixed gear — the things
## that read as "a Cessna". Built in code so no art assets are needed.
##
## Body frame: forward = -Z, up = +Y, right = +X.

const SEG := 24  # cross-section resolution

var _white: StandardMaterial3D
var _blue: StandardMaterial3D
var _glass: StandardMaterial3D
var _metal: StandardMaterial3D
var _tire: StandardMaterial3D


func _ready() -> void:
	_white = _mat(Color(0.90, 0.90, 0.92), 0.45, 0.05)
	_blue = _mat(Color(0.12, 0.34, 0.62), 0.4, 0.1)
	_glass = _mat(Color(0.25, 0.4, 0.55, 0.55), 0.05, 0.5)
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


# --------------------------------------------------------------------------
#  Fuselage (lofted elliptical sections)
# --------------------------------------------------------------------------
func _build_fuselage() -> void:
	# stations: z (fwd -Z), half-width x, half-height y, vertical centre
	var st := [
		[-4.55, 0.06, 0.06, -0.02],
		[-4.30, 0.34, 0.33, -0.03],
		[-3.70, 0.50, 0.50, -0.02],
		[-3.00, 0.55, 0.60, 0.03],
		[-2.20, 0.57, 0.66, 0.07],
		[-1.40, 0.58, 0.70, 0.09],
		[-0.40, 0.56, 0.70, 0.09],
		[0.60, 0.48, 0.60, 0.07],
		[1.50, 0.34, 0.42, 0.10],
		[2.50, 0.20, 0.27, 0.14],
		[3.45, 0.10, 0.17, 0.20],
	]
	var rings: Array = []
	for s in st:
		rings.append(_ring(s[0], s[1], s[2], s[3]))
	# The fuselage is a closed tube, so cull back faces (avoids the near/far
	# wall z-fighting moire you get with double-sided rendering).
	var fuse_mat := _mat(Color(0.90, 0.90, 0.92), 0.45, 0.05)
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
	# Planform in (span = u/X, chord = v/Z); thickness along Y.
	var prof := PackedVector2Array([
		Vector2(0.45, -0.55), Vector2(3.9, -0.55), Vector2(5.05, -0.40),
		Vector2(5.30, 0.05), Vector2(5.05, 0.78), Vector2(3.9, 1.05),
		Vector2(0.45, 1.05),
	])
	var dih := 0.05  # dihedral (rad)
	for sign in [1.0, -1.0]:
		var m := _extrude(prof, Vector3(sign, 0, 0), Vector3(0, 0, 1), 0.17,
			Vector3(0, 0, -1.55), _white)
		m.rotation = Vector3(0, 0, dih * sign)  # tips up (dihedral)
		m.position.y = 0.66
		# Blue tip cap.
		var tip := PackedVector2Array([
			Vector2(4.55, -0.42), Vector2(5.05, -0.40), Vector2(5.30, 0.05),
			Vector2(5.05, 0.78), Vector2(4.55, 0.92)])
		var tm := _extrude(tip, Vector3(sign, 0, 0), Vector3(0, 0, 1), 0.21,
			Vector3(0, 0, -1.55), _blue)
		tm.rotation = Vector3(0, 0, dih * sign)
		tm.position.y = 0.66


func _build_struts() -> void:
	# Lift strut from lower fuselage to ~mid-wing underside, each side.
	for sign in [1.0, -1.0]:
		var top := Vector3(sign * 2.6, 0.62, -1.5)
		var bot := Vector3(sign * 0.45, -0.18, -1.35)
		_strut(top, bot, 0.05)
		# Small jury strut.
		_strut(Vector3(sign * 2.6, 0.62, -1.5), Vector3(sign * 2.2, 0.2, -1.65), 0.03)


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
	var fin := PackedVector2Array([
		Vector2(1.9, 0.30), Vector2(3.05, 1.45), Vector2(3.5, 1.45),
		Vector2(3.72, 0.34),
	])
	_add_mesh(_extrude_mesh(fin, Vector3(0, 0, 1), Vector3(0, 1, 0), 0.08), _blue)

	# Horizontal stabiliser (span=X, chord=Z; thin in Y), tapered with elevator.
	var stab := PackedVector2Array([
		Vector2(-1.75, 3.08), Vector2(1.75, 3.08), Vector2(1.45, 3.42),
		Vector2(1.45, 3.66), Vector2(-1.45, 3.66), Vector2(-1.45, 3.42),
	])
	_extrude(stab, Vector3(1, 0, 0), Vector3(0, 0, 1), 0.10, Vector3(0, 0.32, 0), _white)


# --------------------------------------------------------------------------
#  Fixed tricycle gear with wheel fairings
# --------------------------------------------------------------------------
func _build_gear() -> void:
	# Main gear: spring legs out to faired wheels.
	for sign in [1.0, -1.0]:
		_strut(Vector3(sign * 0.18, -0.30, -1.0), Vector3(sign * 1.05, -1.05, -1.0), 0.06)
		_wheel(Vector3(sign * 1.05, -1.18, -1.0))
	# Nose gear.
	_strut(Vector3(0.0, -0.45, -3.35), Vector3(0.0, -1.05, -3.55), 0.07)
	_wheel(Vector3(0.0, -1.18, -3.55))


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
	# Windshield (two angled panes meeting at the centre post).
	var wprof := PackedVector2Array([
		Vector2(-0.5, 0.0), Vector2(0.5, 0.0), Vector2(0.42, 0.62), Vector2(-0.42, 0.62)])
	var ws := _extrude(wprof, Vector3(1, 0, 0), Vector3(0, 0.7, -0.72).normalized(), 0.02,
		Vector3(0, 0.32, -2.15), _glass)
	# Side windows (cabin), left and right, sitting just proud of the skin.
	for sign in [1.0, -1.0]:
		var swin := PackedVector2Array([
			Vector2(-0.5, -0.16), Vector2(0.5, -0.16), Vector2(0.42, 0.18), Vector2(-0.42, 0.18)])
		var m := _extrude(swin, Vector3(0, 0, 1), Vector3(0, 1, 0), 0.02,
			Vector3(sign * 0.63, 0.30, -1.35), _glass)
		m.rotation = Vector3(0, sign * -0.05, 0)  # toe in to follow the body


func _build_stripe() -> void:
	# Cheatline along the fuselage sides.
	for sign in [1.0, -1.0]:
		var st := PackedVector2Array([
			Vector2(-3.4, 0.0), Vector2(2.6, 0.0), Vector2(2.6, 0.10), Vector2(-3.4, 0.10)])
		_extrude(st, Vector3(0, 0, 1), Vector3(0, 1, 0), 0.01,
			Vector3(sign * 0.585, -0.05, 0.0), _blue)


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
