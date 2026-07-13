extends Node
## Physical joystick/throttle support (autoload), tuned for the Thrustmaster
## TCA Airbus set — the TCA Sidestick Airbus Edition and the TCA Quadrant
## Airbus Edition — but any HID stick works with the same axis constants.
##
## Detection is by device name ("TCA"/"Sidestick"/"Airbus" = stick,
## "Quadrant"/"Throttle" = throttle quadrant). When a stick is present its
## axes drive pitch/roll/yaw directly (analog, expo curve, no keyboard
## rate-shaping); when a quadrant is present the ENG levers drive the
## throttle absolutely, with the reverse range acting as wheel brakes.
## The stick's mini thrust slider is used when no quadrant is plugged in.
## Keyboard controls keep working whenever no device provides that input.
##
## Axis numbers differ between OSes/drivers: press J in-game to open the
## device monitor (live axis/button values) and adjust the constants below
## if your twist or levers land on different indices.

# --- TCA Sidestick Airbus (HID order: X, Y, Rz twist, mini slider) ---------
const STICK_AXIS_ROLL := 0
const STICK_AXIS_PITCH := 1
const STICK_AXIS_YAW := 2          # twist rudder
const STICK_AXIS_THROTTLE := 3     # grey mini thrust lever on the base
const STICK_DEADZONE := 0.04
const YAW_DEADZONE := 0.10
const EXPO := 1.6                  # response curve: fine near centre
const INVERT_PITCH := false        # pull back = nose up already
const USE_STICK_SLIDER := true     # mini lever as throttle w/o a quadrant
const STICK_SLIDER_INVERT := true  # Thrustmaster HID: pushed forward = -1

# Stick buttons -> actions, polled from the STICK device only. (These are
# deliberately not InputMap binds: those fire for every device, and the TCA
# Quadrant presses virtual buttons as its levers cross the detents.)
const STICK_BTN_ACTIONS := {
	JOY_BUTTON_A: &"toggle_brakes",           # trigger
	JOY_BUTTON_B: &"toggle_view",             # red button
	JOY_BUTTON_DPAD_UP: &"trim_down",         # hat forward = nose down
	JOY_BUTTON_DPAD_DOWN: &"trim_up",
	JOY_BUTTON_DPAD_LEFT: &"flaps_up",
	JOY_BUTTON_DPAD_RIGHT: &"flaps_down",
}

# Device-name fragments (upper-case). Quadrant is matched FIRST: the TCA
# Quadrant reports as "TCA Q-ENG 1&2", which would otherwise hit "TCA" in
# the stick list. The sidestick reports as "T.A320 Pilot" on some OSes.
const QUAD_NAMES: Array[String] = ["Q-ENG", "QUADRANT", "THROTTLE"]
const STICK_NAMES: Array[String] = ["SIDESTICK", "TCA", "AIRBUS", "STICK", "T.16000", "A320", "PILOT"]

# --- TCA Quadrant Airbus (two ENG levers) -----------------------------------
const QUAD_AXIS_ENG1 := 0
const QUAD_AXIS_ENG2 := 1
const QUAD_INVERT := true          # most report full-forward as -1; flip if reversed
const QUAD_IDLE := -0.45           # lever position of the IDLE detent (after invert)
const QUAD_REV_BRAKE := -0.55      # below this the reverse range brakes the wheels

var stick_dev := -1
var quad_dev := -1
var _monitor: CanvasLayer
var _monitor_label: Label
var _rescan_t := 0.0
var _btn_state := {}


func _ready() -> void:
	Input.joy_connection_changed.connect(func(_d, _c): _scan())
	_scan()


func _scan() -> void:
	stick_dev = -1
	quad_dev = -1
	var spare := -1
	for d in Input.get_connected_joypads():
		var n := Input.get_joy_name(d).to_upper()
		if quad_dev < 0 and _name_match(n, QUAD_NAMES):
			quad_dev = d
		elif stick_dev < 0 and _name_match(n, STICK_NAMES):
			stick_dev = d
		elif spare < 0 and not _name_match(n, QUAD_NAMES):
			spare = d       # any other joypad: candidate stick
	if stick_dev < 0:
		stick_dev = spare
	if stick_dev >= 0 or quad_dev >= 0:
		print("Joystick: stick=%s  quadrant=%s" % [
			Input.get_joy_name(stick_dev) if stick_dev >= 0 else "-",
			Input.get_joy_name(quad_dev) if quad_dev >= 0 else "-"])


func _name_match(name_upper: String, fragments: Array[String]) -> bool:
	for f in fragments:
		if f in name_upper:
			return true
	return false


## Edge-detect the stick's buttons and inject the mapped actions, so only
## the STICK device can trigger them (see STICK_BTN_ACTIONS).
func _poll_stick_buttons() -> void:
	for b in STICK_BTN_ACTIONS:
		var pressed := stick_dev >= 0 and Input.is_joy_button_pressed(stick_dev, b)
		if pressed == _btn_state.get(b, false):
			continue
		_btn_state[b] = pressed
		var ev := InputEventAction.new()
		ev.action = STICK_BTN_ACTIONS[b]
		ev.pressed = pressed
		Input.parse_input_event(ev)


func has_stick() -> bool:
	return stick_dev >= 0


func has_throttle() -> bool:
	return quad_dev >= 0 or (stick_dev >= 0 and USE_STICK_SLIDER)


func roll() -> float:
	return _curve(Input.get_joy_axis(stick_dev, STICK_AXIS_ROLL), STICK_DEADZONE)


func pitch() -> float:
	# Our convention: positive input = nose UP (stick pulled back = HID +1).
	var v := _curve(Input.get_joy_axis(stick_dev, STICK_AXIS_PITCH), STICK_DEADZONE)
	return -v if INVERT_PITCH else v


func yaw() -> float:
	return _curve(Input.get_joy_axis(stick_dev, STICK_AXIS_YAW), YAW_DEADZONE)


## Absolute throttle 0..1 from the quadrant levers (averaged so either or
## both work) or, failing that, the sidestick's mini slider.
func throttle() -> float:
	var lever := _lever()
	if quad_dev >= 0:
		return clampf((lever - QUAD_IDLE) / (1.0 - QUAD_IDLE), 0.0, 1.0)
	return clampf((lever + 1.0) * 0.5, 0.0, 1.0)   # slider: full range


## True while the quadrant levers are lifted into the reverse range.
func reverse_braking() -> bool:
	return quad_dev >= 0 and _lever() < QUAD_REV_BRAKE


func _lever() -> float:
	if quad_dev >= 0:
		var a := Input.get_joy_axis(quad_dev, QUAD_AXIS_ENG1)
		var b := Input.get_joy_axis(quad_dev, QUAD_AXIS_ENG2)
		var v := (a + b) * 0.5
		return -v if QUAD_INVERT else v
	var s := Input.get_joy_axis(stick_dev, STICK_AXIS_THROTTLE)
	return -s if STICK_SLIDER_INVERT else s


func _curve(v: float, dz: float) -> float:
	if absf(v) < dz:
		return 0.0
	var t := (absf(v) - dz) / (1.0 - dz)
	return signf(v) * pow(t, EXPO)


# --------------------------------------------------------------------------
#  Device monitor (J): live axis/button readout for verifying the mapping.
# --------------------------------------------------------------------------
func _process(_delta: float) -> void:
	# Belt and braces: joy_connection_changed is not always delivered on every
	# platform (macOS in particular), so while no device is mapped keep
	# rescanning every couple of seconds.
	if stick_dev < 0 and quad_dev < 0:
		_rescan_t += _delta
		if _rescan_t > 2.0:
			_rescan_t = 0.0
			_scan()
	_poll_stick_buttons()
	if Input.is_action_just_pressed("joy_debug"):
		_toggle_monitor()
	if _monitor and _monitor.visible:
		_monitor_label.text = _monitor_text()


func _toggle_monitor() -> void:
	if _monitor == null:
		_monitor = CanvasLayer.new()
		_monitor.layer = 10
		add_child(_monitor)
		var panel := ColorRect.new()
		panel.color = Color(0.02, 0.04, 0.07, 0.88)
		panel.position = Vector2(280, 200)
		panel.size = Vector2(720, 380)
		_monitor.add_child(panel)
		_monitor_label = Label.new()
		_monitor_label.position = Vector2(16, 10)
		_monitor_label.size = Vector2(688, 360)
		_monitor_label.add_theme_font_size_override("font_size", 14)
		panel.add_child(_monitor_label)
	else:
		_monitor.visible = not _monitor.visible


func _monitor_text() -> String:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		var msg := "JOYSTICK MONITOR (J to close)\n\nNo devices connected. (rescanning every 2 s)\n"
		if OS.get_name() == "macOS":
			msg += """
macOS notes / macOS 排查:
 1. Unplug and replug the USB cable with this app running.
    先启动本程序，再拔插一次 USB。
 2. System Settings -> Privacy & Security -> Input Monitoring:
    allow this app, then restart it.
    系统设置 -> 隐私与安全性 -> 输入监控: 允许本程序后重启。
 3. Generic HID sticks need a build exported with Godot 4.5+
    (4.3/4.4 have a macOS controller-detection regression).
    通用 HID 摇杆需要 Godot 4.5+ 导出的版本
    (4.3/4.4 在 macOS 上有手柄检测回归)。"""
		return msg
	var out := "JOYSTICK MONITOR (J to close)  —  edit src/systems/JoystickInput.gd to remap\n"
	for d in pads:
		var role := "stick" if d == stick_dev else ("quadrant" if d == quad_dev else "unused")
		out += "\n[%d] %s   (%s)\n  axes: " % [d, Input.get_joy_name(d), role]
		for a in range(8):
			out += "%d:%+.2f  " % [a, Input.get_joy_axis(d, a)]
		var btns := ""
		for b in range(24):
			if Input.is_joy_button_pressed(d, b):
				btns += "%d " % b
		out += "\n  buttons down: %s\n" % (btns if btns != "" else "-")
	if stick_dev >= 0:
		out += "\nmapped: roll %+.2f  pitch %+.2f  yaw %+.2f  throttle %d%%%s" % [
			roll(), pitch(), yaw(), roundi(throttle() * 100.0),
			"  [REVERSE=BRAKE]" if reverse_braking() else ""]
	out += "\ncheck: full-forward lever should read throttle 100% — if reversed,"
	out += "\nflip QUAD_INVERT (quadrant) or STICK_SLIDER_INVERT (stick slider)."
	return out
