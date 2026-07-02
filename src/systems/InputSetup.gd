extends Node
## Registers the control bindings in code so they are guaranteed to exist
## regardless of how project.godot's input map is (re)serialized across Godot
## versions. Uses physical keycodes (layout-independent) and adds Mac-friendly
## throttle keys ("="/"-") alongside Page Up/Down (which need Fn on laptops).

func _ready() -> void:
	_bind("pitch_up", [KEY_UP])
	_bind("pitch_down", [KEY_DOWN])
	_bind("roll_left", [KEY_LEFT])
	_bind("roll_right", [KEY_RIGHT])
	_bind("yaw_left", [KEY_Z])
	_bind("yaw_right", [KEY_X])
	_bind("throttle_up", [KEY_PAGEUP, KEY_EQUAL, KEY_W])
	_bind("throttle_down", [KEY_PAGEDOWN, KEY_MINUS, KEY_S])
	_bind("trim_up", [KEY_COMMA])
	_bind("trim_down", [KEY_PERIOD])
	_bind("flaps_down", [KEY_F])
	_bind("flaps_up", [KEY_G])
	_bind("toggle_brakes", [KEY_B])
	_bind("toggle_view", [KEY_C])
	_bind("reset_aircraft", [KEY_R])
	_bind("replay_toggle", [KEY_TAB])
	_bind("replay_pause", [KEY_SPACE])
	_bind("cycle_wind", [KEY_V])


func _bind(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
