extends Node3D
## Procedural 3D cockpit interior for the C172S G1000.
##
## Builds the instrument panel, glareshield, windshield posts, control yoke and
## throttle quadrant from primitives, and mounts the G1000 PFD and MFD as real
## 3D screens: each instrument Control is rendered into a SubViewport whose
## texture is mapped onto a quad in the panel (so the glass cockpit is part of
## the 3D world, not a flat overlay). The node is a child of the Aircraft, so
## the whole cockpit moves and banks rigidly with the airframe.
##
## Local frame: origin = pilot eye point, forward = -Z, up = +Y, right = +X.

const PFD_SCRIPT := preload("res://src/ui/PFD.gd")
const MFD_SCRIPT := preload("res://src/ui/MFD.gd")
const STANDBY_SCRIPT := preload("res://src/ui/StandbyGauges.gd")
const COMPASS_SCRIPT := preload("res://src/ui/Compass.gd")

var _aircraft: Node
var _yoke: Node3D
var _yoke_l: Node3D
var _panel_normal: Texture2D
var _leather_normal: Texture2D
var _screens: Array = []
var _rebind_frames := 8


func _ready() -> void:
	_aircraft = get_parent()
	_panel_normal = _noise_normal(0.08, 5.0)    # fine moulded-plastic grain
	_leather_normal = _noise_normal(0.025, 11.0) # coarse padded-leather grain
	_build_structure()
	_build_panel()
	_build_screens()
	_build_yokes()
	_build_pedestal()
	_build_controls()
	_build_lighting()


# --------------------------------------------------------------------------
#  Helpers
# --------------------------------------------------------------------------
func _mat(color: Color, rough := 0.6, metal := 0.0, normal: Texture2D = null, normal_scale := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if normal:
		m.normal_enabled = true
		m.normal_texture = normal
		m.normal_scale = normal_scale
	return m

## Procedural tiling normal map from value noise, for surface relief/texture.
func _noise_normal(freq: float, strength: float) -> Texture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = strength
	t.noise = n
	return t

func _box(sz: Vector3, pos: Vector3, mat: StandardMaterial3D, rot := Vector3.ZERO, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = sz
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	(parent if parent else self).add_child(mi)
	return mi

func _cyl(radius: float, height: float, pos: Vector3, mat: StandardMaterial3D, rot := Vector3.ZERO, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	(parent if parent else self).add_child(mi)
	return mi


# --------------------------------------------------------------------------
#  Cabin shell: posts, window frames, side walls
# --------------------------------------------------------------------------
func _build_structure() -> void:
	# Warm "Royalite" cabin plastic instead of stark white, with a soft headliner
	# and slightly darker side trim — closer to a real C172 interior.
	var frame := _mat(Color(0.63, 0.61, 0.57), 0.85, 0.0, _panel_normal, 0.25)
	var head := _mat(Color(0.79, 0.78, 0.74), 0.9, 0.0, _leather_normal, 0.3)
	var trim := _mat(Color(0.44, 0.43, 0.41), 0.85, 0.0, _leather_normal, 0.45)

	# Slim A-pillars (windshield posts), leaning forward and outboard.
	_box(Vector3(0.034, 0.84, 0.045), Vector3(-0.6, 0.22, -0.74), frame, Vector3(-0.45, 0.0, 0.18))
	_box(Vector3(0.034, 0.84, 0.045), Vector3(0.9, 0.22, -0.74), frame, Vector3(-0.45, 0.0, -0.18))
	# Thin windshield header.
	_box(Vector3(1.62, 0.045, 0.055), Vector3(0.15, 0.55, -0.92), frame, Vector3(-0.35, 0.0, 0.0))
	# Slim centre divider between the windshield halves.
	_box(Vector3(0.022, 0.72, 0.03), Vector3(0.15, 0.26, -0.86), frame, Vector3(-0.4, 0.0, 0.0))
	# Side cabin walls / door frames (lower, slimmer).
	_box(Vector3(0.05, 0.6, 1.5), Vector3(-0.64, -0.2, -0.1), trim)
	_box(Vector3(0.05, 0.6, 1.5), Vector3(0.94, -0.2, -0.1), trim)
	# Window sills.
	_box(Vector3(0.05, 0.05, 1.3), Vector3(-0.62, -0.02, -0.15), frame)
	_box(Vector3(0.05, 0.05, 1.3), Vector3(0.92, -0.02, -0.15), frame)
	# Headliner / cabin roof, gently sloped forward.
	_box(Vector3(1.64, 0.045, 0.82), Vector3(0.15, 0.6, -0.18), head, Vector3(0.05, 0.0, 0.0))


# --------------------------------------------------------------------------
#  Instrument panel + glareshield
# --------------------------------------------------------------------------
func _build_panel() -> void:
	var panel_mat := _mat(Color(0.10, 0.10, 0.11), 0.7, 0.0, _panel_normal, 0.4)
	var coam := _mat(Color(0.05, 0.05, 0.055), 0.95, 0.0, _leather_normal, 0.8)
	var tilt := Vector3(-0.10, 0.0, 0.0)  # top tilts away from pilot

	# Main panel slab.
	_box(Vector3(1.5, 0.5, 0.04), Vector3(0.15, -0.34, -0.66), panel_mat, tilt)
	# Lower sub-panel (switches / kneeboard area) — kept in the panel plane so
	# it doesn't poke forward and occlude the bottom of the G1000 screens.
	_box(Vector3(1.5, 0.22, 0.06), Vector3(0.15, -0.66, -0.64), panel_mat)
	# Glareshield (padded coaming) overhanging the top of the panel. Kept low
	# so the pilot can see the horizon and runway over the nose.
	_box(Vector3(1.55, 0.07, 0.40), Vector3(0.15, -0.18, -0.62), coam, Vector3(-0.05, 0.0, 0.0))
	# Glareshield front lip.
	_box(Vector3(1.55, 0.04, 0.05), Vector3(0.15, -0.21, -0.82), coam)


# --------------------------------------------------------------------------
#  G1000 screens via SubViewports
# --------------------------------------------------------------------------
func _build_screens() -> void:
	# Gentle tilt; screens sit proud of the panel so their (tilted) bottom edge
	# stays in front of the slab and the HSI isn't clipped.
	var tilt := Vector3(-0.10, 0.0, 0.0)
	# PFD in front of the pilot, MFD to its right (centre stack).
	_make_screen(PFD_SCRIPT, Vector3(-0.07, -0.30, -0.565), 0.34, 0.27, tilt)
	_make_screen(MFD_SCRIPT, Vector3(0.37, -0.30, -0.565), 0.34, 0.27, tilt)
	# Standby steam gauges (ASI/AI/ALT) to the left of the PFD.
	_make_screen(STANDBY_SCRIPT, Vector3(-0.31, -0.30, -0.565), 0.10, 0.28, tilt, Vector2i(384, 1024))
	# Wet magnetic compass hung from the top of the windshield, centred so it
	# stays clear of the glareshield and panel instead of being occluded.
	_make_screen(COMPASS_SCRIPT, Vector3(0.15, 0.40, -0.80), 0.17, 0.085, Vector3(0.34, 0, 0), Vector2i(512, 256))
	# Avionics / radio stack between and below the screens.
	var stack := _mat(Color(0.07, 0.07, 0.08), 0.6)
	_box(Vector3(0.10, 0.36, 0.03), Vector3(0.15, -0.32, -0.632), stack, tilt)
	for i in range(5):
		var btn := _mat(Color(0.2, 0.5, 0.2) if i % 2 == 0 else Color(0.3, 0.3, 0.32), 0.5)
		_box(Vector3(0.07, 0.016, 0.01), Vector3(0.15, -0.22 - i * 0.04, -0.648), btn, tilt)


func _make_screen(ui_script: Script, pos: Vector3, w: float, h: float, rot: Vector3, vp_size := Vector2i(1024, 768)) -> void:
	# Bezel sits BEHIND the glass quad (toward the panel) so it frames, not
	# occludes, the display.
	var bezel := _mat(Color(0.02, 0.02, 0.02), 0.5)
	_box(Vector3(w + 0.03, h + 0.03, 0.02), pos + Vector3(0, 0, -0.025), bezel, rot)

	# SubViewport rendering the instrument Control.
	var sv := SubViewport.new()
	sv.size = vp_size
	sv.disable_3d = true
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	add_child(sv)
	var ui := Control.new()
	ui.set_script(ui_script)
	# Pin to the top-left and set the exact pixel size. (Do NOT use a full-rect
	# anchor: with the project's canvas_items stretch it picks up a 2x content
	# scale, making the Control 2048x1536 so the SubViewport clips it.)
	ui.anchor_left = 0.0
	ui.anchor_top = 0.0
	ui.anchor_right = 0.0
	ui.anchor_bottom = 0.0
	ui.position = Vector2.ZERO
	ui.size = Vector2(vp_size)
	sv.add_child(ui)

	# Quad textured by the viewport, self-lit like a real display.
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(w, h)
	mi.mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = sv.get_texture()  # albedo_color stays white (it multiplies the texture)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	# On some backends (Forward+/MoltenVK on macOS) a ViewportTexture bound on
	# the first frame comes back blank; re-bind it for a few frames to be safe.
	_screens.append({"m": m, "sv": sv})


# --------------------------------------------------------------------------
#  Control yokes
# --------------------------------------------------------------------------
func _build_yokes() -> void:
	_yoke = _make_yoke(Vector3(-0.04, -0.46, -0.40))
	_yoke_l = _make_yoke(Vector3(0.5, -0.46, -0.40))


func _make_yoke(base: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = base
	add_child(pivot)
	var dark := _mat(Color(0.05, 0.05, 0.06), 0.45)
	# Column shaft toward the pilot (along +Z).
	_cyl(0.016, 0.30, Vector3(0, 0, 0.13), dark, Vector3(PI * 0.5, 0, 0), pivot)
	# Handwheel cross-bar + grips (ram's-horn look).
	var wheel := Node3D.new()
	wheel.position = Vector3(0, 0, 0.28)
	pivot.add_child(wheel)
	_box(Vector3(0.26, 0.025, 0.03), Vector3.ZERO, dark, Vector3.ZERO, wheel)
	_box(Vector3(0.03, 0.10, 0.03), Vector3(-0.12, 0.045, 0), dark, Vector3(0, 0, 0.5), wheel)
	_box(Vector3(0.03, 0.10, 0.03), Vector3(0.12, 0.045, 0), dark, Vector3(0, 0, -0.5), wheel)
	pivot.set_meta("wheel", wheel)
	return pivot


# --------------------------------------------------------------------------
#  Throttle / mixture quadrant
# --------------------------------------------------------------------------
func _build_pedestal() -> void:
	var dark := _mat(Color(0.09, 0.09, 0.10), 0.6)
	_box(Vector3(0.18, 0.12, 0.20), Vector3(0.23, -0.55, -0.42), dark)
	# Throttle (black) and mixture (red) knobs.
	var black := _mat(Color(0.02, 0.02, 0.02), 0.4)
	var red := _mat(Color(0.6, 0.05, 0.05), 0.4)
	_cyl(0.018, 0.12, Vector3(0.18, -0.46, -0.36), black, Vector3(0.5, 0, 0))
	_cyl(0.016, 0.10, Vector3(0.27, -0.47, -0.36), red, Vector3(0.5, 0, 0))


func _build_controls() -> void:
	# Flap selector lever (right of the pedestal, with detent gate).
	var metal := _mat(Color(0.3, 0.3, 0.33), 0.4, 0.6)
	var white := _mat(Color(0.85, 0.85, 0.88), 0.5)
	_box(Vector3(0.03, 0.12, 0.06), Vector3(0.48, -0.58, -0.46), metal)  # gate plate
	var flap_lever := _box(Vector3(0.014, 0.11, 0.014), Vector3(0.48, -0.52, -0.44), metal, Vector3(-0.3, 0, 0))
	_box(Vector3(0.03, 0.03, 0.03), Vector3(0, 0.06, 0.0), white, Vector3.ZERO, flap_lever)  # knob

	# Row of toggle switches along the lower sub-panel.
	var sw_base := _mat(Color(0.06, 0.06, 0.07), 0.6)
	var sw := _mat(Color(0.7, 0.7, 0.72), 0.4, 0.5)
	for i in range(6):
		var x := -0.12 + i * 0.05
		_box(Vector3(0.02, 0.02, 0.012), Vector3(x, -0.60, -0.55), sw_base)
		_box(Vector3(0.008, 0.03, 0.008), Vector3(x, -0.585, -0.555), sw, Vector3(-0.4, 0, 0))

	# Ignition / magneto key barrel on the far left.
	var black := _mat(Color(0.03, 0.03, 0.035), 0.5, 0.3)
	_cyl(0.018, 0.03, Vector3(-0.36, -0.60, -0.52), black, Vector3(0.4, 0, 0))


func _build_lighting() -> void:
	# Soft cabin fill light so the interior reads even with the sun outside.
	var omni := OmniLight3D.new()
	omni.position = Vector3(0.15, 0.25, -0.2)
	omni.light_energy = 1.2
	omni.omni_range = 3.0
	omni.light_color = Color(1.0, 0.96, 0.9)
	add_child(omni)


func _process(_delta: float) -> void:
	# Re-bind the panel-screen viewport textures for the first few frames, in
	# case the initial bind came back blank on this graphics backend.
	if _rebind_frames > 0:
		_rebind_frames -= 1
		for s in _screens:
			s.m.albedo_texture = s.sv.get_texture()

	# Animate the yokes from the live control inputs.
	if _aircraft == null:
		return
	var ail: float = _aircraft.aileron
	var elev: float = _aircraft.elevator
	for y in [_yoke, _yoke_l]:
		if y == null:
			continue
		var wheel: Node3D = y.get_meta("wheel")
		if wheel:
			wheel.rotation.z = -ail * 2.2          # turn the wheel with roll
		y.rotation.x = elev * 0.25                 # push/pull with pitch
		y.position.z = -0.40 - elev * 0.04
