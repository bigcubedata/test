extends Node
## Shared flight-state blackboard (autoload singleton).
##
## The aircraft writes its current state here every physics frame and the
## glass-cockpit instruments (PFD/HSI) read from it. Decoupling the flight
## model from the UI this way keeps the instruments dumb and testable, and
## lets multiple displays share a single source of truth.

# --- Unit conversion helpers ---------------------------------------------
const MS_TO_KNOTS: float = 1.943844      # m/s -> knots
const M_TO_FEET: float = 3.280839895     # metres -> feet
const MS_TO_FPM: float = 196.850394      # m/s -> feet per minute

# --- Air data ------------------------------------------------------------
var indicated_airspeed_kt: float = 0.0   # KIAS
var true_airspeed_kt: float = 0.0        # KTAS
var ground_speed_kt: float = 0.0
var altitude_ft: float = 0.0             # MSL (here: above ground origin)
var altitude_agl_ft: float = 0.0
var vertical_speed_fpm: float = 0.0

# --- Attitude ------------------------------------------------------------
var pitch_deg: float = 0.0               # nose up positive
var roll_deg: float = 0.0                # right wing down positive
var heading_deg: float = 0.0             # 0-360, magnetic-ish (true here)
var track_deg: float = 0.0               # ground track (falls back to heading when slow)
var slip_skid: float = 0.0               # lateral g, drives the inclinometer ball
var angle_of_attack_deg: float = 0.0
var load_factor: float = 1.0             # g

# --- Powerplant ----------------------------------------------------------
var engine_rpm: float = 0.0
var manifold_pressure_inhg: float = 0.0
var fuel_flow_gph: float = 0.0
var oil_temp_c: float = 0.0
var throttle_pct: float = 0.0

# --- Configuration -------------------------------------------------------
var flaps_deg: float = 0.0
var flaps_setting: int = 0               # 0,1,2,3 -> 0/10/20/30 deg
var parking_brake: bool = false
var on_ground: bool = true
var stall_warning: bool = false

# --- World position (for the MFD moving map) ------------------------------
var pos_x: float = 0.0   # world X (east)  [m]
var pos_z: float = 0.0   # world Z (north = -Z) [m]
var fuel_pct: float = 0.85
var volts: float = 24.0

# --- Wind at the aircraft (for the PFD wind data box) ----------------------
var wind_dir_deg: float = 0.0    # direction the wind blows FROM
var wind_speed_kt: float = 0.0

# --- V-speeds for the C172S (KIAS): airspeed-tape arcs + pilot references -
const VS0: float = 40.0    # stall, full flaps (bottom of white arc)
const VS1: float = 48.0    # stall, clean (bottom of green arc)
const VFE: float = 85.0    # max flaps extended (top of white arc)
const VNO: float = 129.0   # max structural cruising (top of green arc)
const VNE: float = 163.0   # never exceed (red line)
const VY: float = 74.0     # best rate of climb (used by the demo pilots)

## Reset all derived readouts and pilot-set configuration. Called when the
## aircraft is respawned.
func reset_state() -> void:
	indicated_airspeed_kt = 0.0
	true_airspeed_kt = 0.0
	ground_speed_kt = 0.0
	vertical_speed_fpm = 0.0
	pitch_deg = 0.0
	roll_deg = 0.0
	slip_skid = 0.0
	angle_of_attack_deg = 0.0
	load_factor = 1.0
	stall_warning = false
	parking_brake = false
	flaps_setting = 0
	flaps_deg = 0.0
	track_deg = 0.0
