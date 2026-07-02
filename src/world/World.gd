extends Node3D
## Procedural scenery detail, built from primitives at load (no art assets):
##  - proper runway markings: numbers, threshold piano keys, aiming-point bars,
##    dashed centreline, edge lines
##  - a small GA airport east of the runway: taxiway, apron, hangar, FBO,
##    control tower, fuel farm, windsock
##  - countryside: farm-field patches, tree stands, two hamlets, a lake,
##    smooth distant hills and a few fair-weather clouds

const Z_SOUTH := 550.0     # runway 36 threshold (depart to the north)
const Z_NORTH := -950.0    # runway 18 threshold
const RWY_Y := 0.02        # top surface of the runway slab (flush with the
                           # physics ground plane at y=0 so wheels sit on it)

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 172
	_runway_markings()
	_airport()
	_fields()
	_trees()
	_hills_and_lake()
	_clouds()


# --------------------------------------------------------------------------
#  Helpers
# --------------------------------------------------------------------------
func _m(c: Color, rough := 0.9, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(sz: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO,
		shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _cyl(top_r: float, bot_r: float, h: float, pos: Vector3, mat: Material,
		rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = h
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi


# --------------------------------------------------------------------------
#  Runway markings
# --------------------------------------------------------------------------
func _runway_markings() -> void:
	var paint := _m(Color(0.88, 0.88, 0.86), 0.7)
	var yellow := _m(Color(0.85, 0.75, 0.15), 0.7)

	# Edge lines.
	for s in [1.0, -1.0]:
		_box(Vector3(0.9, 0.04, 1440.0), Vector3(s * 21.3, RWY_Y + 0.02, -200.0), paint, Vector3.ZERO, false)

	# Dashed centreline (real runways use dashes, not a solid stripe).
	var z := Z_NORTH + 95.0
	while z < Z_SOUTH - 95.0:
		_box(Vector3(0.9, 0.04, 30.0), Vector3(0.0, RWY_Y + 0.02, z + 15.0), paint, Vector3.ZERO, false)
		z += 60.0

	# Threshold piano keys, four each side of the centreline at both ends.
	for endsign in [1.0, -1.0]:
		var zk := (Z_SOUTH - 22.0) if endsign > 0.0 else (Z_NORTH + 22.0)
		for i in range(4):
			var x := 3.6 + i * 5.4
			_box(Vector3(1.8, 0.04, 26.0), Vector3(x, RWY_Y + 0.02, zk), paint, Vector3.ZERO, false)
			_box(Vector3(1.8, 0.04, 26.0), Vector3(-x, RWY_Y + 0.02, zk), paint, Vector3.ZERO, false)

	# Aiming-point bars ~300 m past each threshold.
	for endsign in [1.0, -1.0]:
		var za := (Z_SOUTH - 300.0) if endsign > 0.0 else (Z_NORTH + 300.0)
		for s in [1.0, -1.0]:
			_box(Vector3(3.0, 0.04, 45.0), Vector3(s * 8.5, RWY_Y + 0.02, za), paint, Vector3.ZERO, false)

	# Painted runway numbers, oriented for the pilot on approach.
	_number("36", Vector3(0.0, RWY_Y + 0.05, Z_SOUTH - 70.0), 0.0)
	_number("18", Vector3(0.0, RWY_Y + 0.05, Z_NORTH + 70.0), 180.0)

	# Taxiway centreline out to the apron.
	_box(Vector3(62.0, 0.03, 0.5), Vector3(56.0, 0.27, 420.0), yellow, Vector3.ZERO, false)


func _number(text: String, pos: Vector3, yaw_deg: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = UiFont.bold()
	l.font_size = 320
	l.pixel_size = 0.045
	l.modulate = Color(0.92, 0.92, 0.9)
	l.position = pos
	l.rotation_degrees = Vector3(-90.0, yaw_deg, 0.0)
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)


# --------------------------------------------------------------------------
#  Airport buildings (east of the runway, by the spawn point)
# --------------------------------------------------------------------------
func _airport() -> void:
	var asphalt := _m(Color(0.17, 0.17, 0.19), 0.9)
	var concrete := _m(Color(0.42, 0.42, 0.44), 0.9)
	var steel := _m(Color(0.60, 0.62, 0.66), 0.6)
	var roof := _m(Color(0.30, 0.32, 0.36), 0.7)
	var glassy := _m(Color(0.15, 0.22, 0.30), 0.3)

	# Taxiway + apron.
	_box(Vector3(70.0, 0.24, 16.0), Vector3(57.0, 0.12, 420.0), asphalt, Vector3.ZERO, false)
	_box(Vector3(130.0, 0.22, 150.0), Vector3(157.0, 0.11, 430.0), concrete, Vector3.ZERO, false)

	# Hangar with a shallow roof cap and a big door strip.
	_box(Vector3(42.0, 9.0, 30.0), Vector3(170.0, 4.5, 375.0), steel)
	_box(Vector3(44.0, 1.4, 32.0), Vector3(170.0, 9.7, 375.0), roof)
	_box(Vector3(32.0, 7.0, 0.5), Vector3(170.0, 3.5, 390.3), _m(Color(0.5, 0.52, 0.55), 0.6))

	# FBO building with a glass front.
	_box(Vector3(20.0, 6.0, 14.0), Vector3(126.0, 3.0, 478.0), _m(Color(0.72, 0.70, 0.66), 0.8))
	_box(Vector3(21.0, 0.8, 15.0), Vector3(126.0, 6.4, 478.0), roof)
	_box(Vector3(18.0, 1.8, 0.4), Vector3(126.0, 3.6, 485.2), glassy)

	# Control tower: shaft, glazed cab, roof, antenna.
	_cyl(2.4, 2.8, 16.0, Vector3(196.0, 8.0, 470.0), concrete)
	_box(Vector3(7.0, 3.4, 7.0), Vector3(196.0, 17.7, 470.0), glassy)
	_box(Vector3(8.0, 0.6, 8.0), Vector3(196.0, 19.7, 470.0), roof)
	_cyl(0.05, 0.05, 4.0, Vector3(196.0, 22.0, 470.0), steel)

	# Fuel farm.
	var tank := _m(Color(0.85, 0.86, 0.88), 0.4)
	_cyl(2.2, 2.2, 5.0, Vector3(150.0, 2.5, 490.0), tank)
	_cyl(2.2, 2.2, 5.0, Vector3(158.0, 2.5, 490.0), tank)

	# Windsock beside the runway.
	_cyl(0.06, 0.06, 5.0, Vector3(40.0, 2.5, 330.0), steel)
	_cyl(0.10, 0.34, 1.6, Vector3(40.9, 5.0, 330.0), _m(Color(0.95, 0.45, 0.08), 0.8),
		Vector3(0.0, 0.0, -PI * 0.5))


# --------------------------------------------------------------------------
#  Countryside: farm fields + hamlets
# --------------------------------------------------------------------------
func _fields() -> void:
	var palette := [
		Color(0.33, 0.42, 0.20), Color(0.45, 0.42, 0.22), Color(0.52, 0.47, 0.26),
		Color(0.29, 0.38, 0.19), Color(0.42, 0.37, 0.18), Color(0.37, 0.45, 0.23),
	]
	# One shared material per palette colour (46 patches, 6 materials).
	var mats: Array = []
	for c in palette:
		mats.append(_m(c, 0.95))
	for i in range(46):
		var x := _rng.randf_range(-4200.0, 4200.0)
		var z := _rng.randf_range(-4200.0, 4200.0)
		if absf(x) < 220.0 and z > -2400.0 and z < 2000.0:
			continue  # keep the runway corridor clear
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(_rng.randf_range(200.0, 480.0), _rng.randf_range(160.0, 420.0))
		mi.mesh = pm
		mi.material_override = mats[_rng.randi_range(0, mats.size() - 1)]
		mi.position = Vector3(x, 0.02 + 0.004 * i, z)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

	# Two hamlets: clusters of simple gabled houses.
	var wall := _m(Color(0.78, 0.74, 0.68), 0.8)
	var hroof := _m(Color(0.42, 0.28, 0.22), 0.8)
	for center in [Vector2(-1900.0, 1500.0), Vector2(2400.0, -1700.0)]:
		for i in range(8):
			var hx: float = center.x + _rng.randf_range(-220.0, 220.0)
			var hz: float = center.y + _rng.randf_range(-220.0, 220.0)
			var w := _rng.randf_range(9.0, 16.0)
			var d := _rng.randf_range(8.0, 14.0)
			var h := _rng.randf_range(4.0, 6.5)
			_box(Vector3(w, h, d), Vector3(hx, h * 0.5, hz), wall)
			_box(Vector3(w + 1.0, 1.0, d + 1.0), Vector3(hx, h + 0.5, hz), hroof)


# --------------------------------------------------------------------------
#  Tree stands (one MultiMesh of cone canopies)
# --------------------------------------------------------------------------
func _trees() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 2.6
	cone.height = 7.0
	mm.mesh = cone
	var count := 170
	mm.instance_count = count
	var placed := 0
	while placed < count:
		var x := _rng.randf_range(-3600.0, 3600.0)
		var z := _rng.randf_range(-3600.0, 3600.0)
		if absf(x) < 170.0 and z > -2300.0 and z < 1900.0:
			continue  # approach/departure corridor
		if x > 30.0 and x < 260.0 and z > 300.0 and z < 520.0:
			continue  # apron area
		var s := _rng.randf_range(0.8, 1.8)
		mm.set_instance_transform(placed,
			Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)), Vector3(x, 3.4 * s, z)))
		placed += 1
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _m(Color(0.14, 0.30, 0.13), 0.95)
	add_child(mi)


# --------------------------------------------------------------------------
#  Distant hills + a lake
# --------------------------------------------------------------------------
func _hills_and_lake() -> void:
	var specs := [
		[5200.0, -7000.0, 2400.0, 620.0, Color(0.30, 0.36, 0.33)],
		[-6200.0, -8200.0, 3200.0, 780.0, Color(0.27, 0.33, 0.31)],
		[-2600.0, -9500.0, 2600.0, 520.0, Color(0.33, 0.39, 0.34)],
		[7800.0, -2600.0, 2800.0, 660.0, Color(0.31, 0.37, 0.33)],
		[-8400.0, 1800.0, 3000.0, 700.0, Color(0.29, 0.35, 0.32)],
		[6800.0, 6200.0, 2600.0, 560.0, Color(0.32, 0.38, 0.34)],
	]
	for s in specs:
		_cyl(0.0, s[2], s[3], Vector3(s[0], s[3] * 0.5 - 40.0, s[1]), _m(s[4], 1.0))

	var lake := _cyl(430.0, 450.0, 0.06, Vector3(2600.0, 0.03, 2300.0), _m(Color(0.15, 0.30, 0.42), 0.15))
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --------------------------------------------------------------------------
#  Fair-weather clouds (flattened unshaded spheres)
# --------------------------------------------------------------------------
func _clouds() -> void:
	var cm := _m(Color(1.0, 1.0, 1.0, 0.88), 1.0, true)
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in range(9):
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 130.0
		sm.height = 80.0
		mi.mesh = sm
		mi.material_override = cm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(_rng.randf_range(-6000.0, 6000.0),
			_rng.randf_range(1200.0, 2100.0), _rng.randf_range(-7000.0, 5000.0))
		mi.scale = Vector3(_rng.randf_range(1.6, 3.4), 1.0, _rng.randf_range(1.6, 3.4))
		add_child(mi)
