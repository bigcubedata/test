class_name Aircraft
extends RigidBody3D
## Cessna 172S Skyhawk flight-dynamics model.
##
## A lumped-parameter, body-axis aerodynamic model tuned to the C172S POH.
## Forces are integrated through Godot's rigid-body solver in
## _integrate_forces so the simulation is stable at the 120 Hz physics tick.
##
## Aerodynamic conventions (Godot axes):
##   forward = -basis.z, up = +basis.y, right = +basis.x
##   alpha (angle of attack) positive = nose-up relative wind
##   beta  (sideslip)       positive = relative wind from the right
##
## Reference data (C172S, 2550 lb gross):
##   wing area S = 16.17 m^2, span b = 11.0 m, AR = 7.32
##   empty ~ 800 kg, gross 1157 kg; we model ~1110 kg (pilot + half fuel)
##   Vs1 48 KCAS, Vs0 40, Vno 129, Vne 163, cruise ~124 KTAS

# --- Mass / geometry ------------------------------------------------------
const WING_AREA: float = 16.17       # m^2
const WING_SPAN: float = 11.0        # m
const MEAN_CHORD: float = 1.47       # m
const ASPECT_RATIO: float = 7.32
const OSWALD_E: float = 0.75

# --- Lift -----------------------------------------------------------------
const CL0: float = 0.30              # CL at zero alpha (cambered wing + incidence)
const CL_ALPHA: float = 5.7          # per radian (finite-wing lift slope)
const ALPHA_STALL: float = 0.2793    # 16 deg, clean stall AoA
const CL_MAX: float = 1.6            # clean max lift coefficient

# --- Drag -----------------------------------------------------------------
const CD0: float = 0.032            # parasite drag (gear down, fixed prop)

# --- Stability & control (moment coefficients, per radian unless noted) ---
# Signs are chosen for Godot's body frame (forward = -Z, up = +Y, right = +X)
# where +pitch_moment = nose-up, +roll_moment = left roll, +yaw_moment = nose-left.
const CM0: float = 0.04             # zero-alpha pitching moment (slightly nose-up)
const CM_ALPHA: float = -1.2        # longitudinal static stability (restoring)
const CM_Q: float = -12.0           # pitch damping
const CM_ELEVATOR: float = 1.1      # elevator power (up input -> nose up)
const CL_BETA: float = 0.10         # dihedral effect (slip right -> roll left)
const CL_P: float = -0.45           # roll damping
const CL_AILERON: float = -0.28     # aileron roll power (right input -> roll right)
const CN_BETA: float = -0.12        # weathercock stability (slip right -> yaw right)
const CN_R: float = -0.15           # yaw damping
const CN_RUDDER: float = -0.10      # rudder yaw power (right input -> yaw right)

# --- Control authority / rates -------------------------------------------
const MAX_ELEVATOR: float = 0.35    # rad of effective deflection
const MAX_AILERON: float = 0.40
const MAX_RUDDER: float = 0.30
const CONTROL_RATE: float = 2.5     # how fast surfaces move toward command
const TRIM_RATE: float = 0.15       # elevator trim slew (per second)

# --- Ground handling ------------------------------------------------------
const GEAR_HEIGHT: float = 1.2      # wheel contact below CG [m]
const GEAR_STIFFNESS: float = 90000.0
const GEAR_DAMPING: float = 9000.0
const ROLLING_FRICTION: float = 0.04
const BRAKE_FRICTION: float = 0.5

# --- Runtime state --------------------------------------------------------
var engine := C172Engine.new()
var elevator: float = 0.0
var aileron: float = 0.0
var rudder: float = 0.0
var elevator_trim: float = 0.06     # slight nose-up trim for level cruise

var input_pitch: float = 0.0
var input_roll: float = 0.0
var input_yaw: float = 0.0
var brakes_on: bool = false

var _spawn_transform: Transform3D
var _spawn_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	# Mass & inertia. The inertia tensor strongly shapes how the aircraft
	# rotates; values are order-of-magnitude correct for a light single.
	mass = 1110.0
	# Inertia tensor in Godot body axes: x = pitch (lateral) axis,
	# y = yaw (vertical) axis, z = roll (longitudinal) axis. Values from the
	# C172 (Ixx~1742, Iyy~2475, Izz~3616 kg*m^2), i.e. roll < pitch < yaw.
	inertia = Vector3(2475.0, 3616.0, 1742.0)
	continuous_cd = true
	can_sleep = false
	# Full manual integration: we compute every force/torque (including gravity)
	# in _integrate_forces and advance the velocities ourselves. This is fully
	# deterministic and side-steps ambiguity about how applied forces interact
	# with the built-in integrator inside _integrate_forces.
	custom_integrator = true
	gravity_scale = 1.0
	_spawn_transform = global_transform
	_spawn_velocity = Vector3.ZERO


func set_spawn(xform: Transform3D, vel: Vector3) -> void:
	_spawn_transform = xform
	_spawn_velocity = vel


func reset() -> void:
	global_transform = _spawn_transform
	linear_velocity = _spawn_velocity
	angular_velocity = Vector3.ZERO
	engine.rpm = C172Engine.IDLE_RPM
	engine.throttle = 0.0
	elevator = 0.0
	aileron = 0.0
	rudder = 0.0
	brakes_on = false
	FlightData.reset_state()


func _process(_delta: float) -> void:
	_read_input()


func _read_input() -> void:
	# Axis inputs (-1..1). Keyboard is digital; analog sticks map naturally.
	input_pitch = Input.get_axis("pitch_down", "pitch_up")
	input_roll = Input.get_axis("roll_left", "roll_right")
	input_yaw = Input.get_axis("yaw_left", "yaw_right")

	if Input.is_action_pressed("throttle_up"):
		engine.throttle = clampf(engine.throttle + 0.6 * get_process_delta_time(), 0.0, 1.0)
	if Input.is_action_pressed("throttle_down"):
		engine.throttle = clampf(engine.throttle - 0.6 * get_process_delta_time(), 0.0, 1.0)

	if Input.is_action_pressed("trim_up"):
		elevator_trim = clampf(elevator_trim + TRIM_RATE * get_process_delta_time(), -0.3, 0.3)
	if Input.is_action_pressed("trim_down"):
		elevator_trim = clampf(elevator_trim - TRIM_RATE * get_process_delta_time(), -0.3, 0.3)

	if Input.is_action_just_pressed("flaps_down"):
		FlightData.flaps_setting = clampi(FlightData.flaps_setting + 1, 0, 3)
	if Input.is_action_just_pressed("flaps_up"):
		FlightData.flaps_setting = clampi(FlightData.flaps_setting - 1, 0, 3)

	if Input.is_action_just_pressed("toggle_brakes"):
		FlightData.parking_brake = not FlightData.parking_brake
	brakes_on = FlightData.parking_brake

	if Input.is_action_just_pressed("reset_aircraft"):
		reset()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt := state.step
	var xform := state.transform
	var basis := xform.basis

	# Smoothly drive control surfaces toward commanded positions.
	elevator = move_toward(elevator, input_pitch * MAX_ELEVATOR, CONTROL_RATE * dt)
	aileron = move_toward(aileron, input_roll * MAX_AILERON, CONTROL_RATE * dt)
	rudder = move_toward(rudder, input_yaw * MAX_RUDDER, CONTROL_RATE * dt)

	# --- Air data ---------------------------------------------------------
	var alt_m: float = maxf(xform.origin.y, 0.0)
	var rho := Atmosphere.density(alt_m)
	var vel_world := state.linear_velocity
	var wind := Vector3.ZERO  # (hook for future wind/turbulence)
	var v_rel := vel_world - wind
	var v_body := basis.inverse() * v_rel

	var u := -v_body.z            # forward speed [m/s]
	var airspeed := v_rel.length()
	var qbar := 0.5 * rho * airspeed * airspeed   # dynamic pressure

	# Angle of attack and sideslip (guard against divide-by-zero at rest).
	var alpha := 0.0
	var beta := 0.0
	if airspeed > 1.0:
		alpha = atan2(-v_body.y, maxf(u, 0.1))
		beta = asin(clampf(v_body.x / airspeed, -1.0, 1.0))

	# --- Configuration: flaps --------------------------------------------
	var flap_target := FlightData.flaps_setting * 10.0
	FlightData.flaps_deg = move_toward(FlightData.flaps_deg, flap_target, 8.0 * dt)
	var flap_frac := FlightData.flaps_deg / 30.0
	var dCL_flap := 0.55 * flap_frac      # extra lift from flaps
	var dCD_flap := 0.045 * flap_frac     # extra drag from flaps
	var dCM_flap := -0.06 * flap_frac     # nose-down pitch from flaps

	# --- Lift coefficient with stall --------------------------------------
	var cl_max_eff := CL_MAX + 0.4 * flap_frac
	var cl_linear := CL0 + CL_ALPHA * alpha + dCL_flap
	var cl := _apply_stall(cl_linear, alpha, cl_max_eff)

	# --- Drag: parasite + induced + flaps --------------------------------
	var k := 1.0 / (PI * OSWALD_E * ASPECT_RATIO)
	var cd := CD0 + dCD_flap + k * cl * cl

	# --- Aerodynamic forces (wind axes -> world) -------------------------
	var lift_force := Vector3.ZERO
	var drag_force := Vector3.ZERO
	var side_force := Vector3.ZERO
	if airspeed > 0.5:
		var vel_dir := v_rel / airspeed
		var right_axis := basis.x
		# Lift is perpendicular to relative wind, in the plane of symmetry.
		var lift_dir := right_axis.cross(vel_dir).normalized()
		lift_force = lift_dir * (qbar * WING_AREA * cl)
		drag_force = -vel_dir * (qbar * WING_AREA * cd)
		# Side force opposing sideslip (fuselage + fin).
		var cy := -0.8 * beta
		side_force = right_axis * (qbar * WING_AREA * cy)

	var thrust_mag := engine.update(dt, airspeed, alt_m)
	var thrust_force := -basis.z * thrust_mag  # along nose

	var total_force := lift_force + drag_force + side_force + thrust_force
	total_force += Vector3.DOWN * (mass * Atmosphere.G0)  # gravity (manual integrator)

	# --- Aerodynamic moments ---------------------------------------------
	# Non-dimensional body rates.
	# In Godot's body frame the roll axis is z (longitudinal), the pitch axis
	# is x (lateral) and the yaw axis is y (vertical).
	var omega := basis.inverse() * state.angular_velocity
	var p := omega.z   # roll rate
	var q := omega.x   # pitch rate
	var r := omega.y   # yaw rate
	var two_v := maxf(2.0 * airspeed, 1.0)
	var phat := p * WING_SPAN / two_v
	var qhat := q * MEAN_CHORD / two_v
	var rhat := r * WING_SPAN / two_v

	var cm := CM0 + dCM_flap + CM_ALPHA * alpha + CM_Q * qhat \
		+ CM_ELEVATOR * (elevator + elevator_trim)
	var cl_roll := CL_BETA * beta + CL_P * phat + CL_AILERON * aileron
	var cn := CN_BETA * beta + CN_R * rhat + CN_RUDDER * rudder

	var pitch_moment := qbar * WING_AREA * MEAN_CHORD * cm   # about body x
	var roll_moment := qbar * WING_AREA * WING_SPAN * cl_roll # about body z(fwd)
	var yaw_moment := qbar * WING_AREA * WING_SPAN * cn       # about body y

	var torque_body := Vector3(pitch_moment, yaw_moment, roll_moment)
	var torque_world := basis * torque_body

	# --- Ground contact ---------------------------------------------------
	var on_ground := false
	if xform.origin.y < GEAR_HEIGHT + 0.05:
		on_ground = true
		var penetration := (GEAR_HEIGHT - xform.origin.y)
		# Spring-damper normal force (only pushes up).
		var normal_force := maxf(0.0, GEAR_STIFFNESS * penetration - GEAR_DAMPING * vel_world.y)
		total_force += Vector3.UP * normal_force
		# Tyre friction: rolling + braking resists ground-track velocity.
		var horiz_vel := Vector3(vel_world.x, 0.0, vel_world.z)
		if horiz_vel.length() > 0.05:
			var mu := BRAKE_FRICTION if brakes_on else ROLLING_FRICTION
			total_force += -horiz_vel.normalized() * (normal_force * mu)
		# Keep the aircraft tracking roughly level on the ground.
		torque_world += _ground_leveling_torque(basis, state.angular_velocity)

	# --- Integrate (manual) ----------------------------------------------
	state.linear_velocity += (total_force / mass) * dt
	# Angular: convert world torque to body frame, divide by the body inertia
	# tensor, then rotate the resulting angular acceleration back to world.
	var torque_b := basis.inverse() * torque_world
	var ang_accel_body := Vector3(
		torque_b.x / inertia.x,
		torque_b.y / inertia.y,
		torque_b.z / inertia.z)
	state.angular_velocity += basis * ang_accel_body * dt
	# Light angular damping for numerical stability of the rotational solver.
	state.angular_velocity *= (1.0 - 0.03 * dt)

	_publish_flight_data(state, airspeed, alpha, beta, alt_m, cl, cl_max_eff, on_ground)


## Smoothly limit CL past the stall angle so lift collapses instead of
## growing without bound. Uses a soft blend around ALPHA_STALL.
func _apply_stall(cl_linear: float, alpha: float, cl_max: float) -> float:
	var a := absf(alpha)
	if a <= ALPHA_STALL:
		return clampf(cl_linear, -cl_max, cl_max)
	# Past stall: fade lift down toward a low post-stall plateau.
	# (a > ALPHA_STALL here, so alpha is non-zero and its sign is well-defined.)
	var over := clampf((a - ALPHA_STALL) / 0.25, 0.0, 1.0)
	var stalled_cl := lerpf(cl_max, 0.7, over)
	return signf(alpha) * stalled_cl


func _ground_leveling_torque(basis: Basis, ang_vel: Vector3) -> Vector3:
	# Keeps the aircraft sitting upright on its gear (we model the ground as a
	# single contact, so without this the body could tip over). We correct
	# ROLL only — pitch stays free so the pilot can rotate for takeoff, and
	# yaw is only lightly damped so the aircraft tracks straight on rollout.
	var omega := basis.inverse() * ang_vel
	# Roll error: positive when the right wing has dropped (see roll_deg).
	var roll_err := asin(clampf(-basis.x.y, -1.0, 1.0))
	var roll_correct := 30000.0 * roll_err - 6000.0 * omega.z  # about +z (roll)
	var yaw_damp := -1500.0 * omega.y                          # about +y (yaw)
	var torque_body := Vector3(0.0, yaw_damp, roll_correct)
	return basis * torque_body


func _publish_flight_data(state: PhysicsDirectBodyState3D, airspeed: float,
		alpha: float, beta: float, alt_m: float, cl: float, cl_max: float,
		on_ground: bool) -> void:
	var basis := state.transform.basis
	var tas_kt := airspeed * FlightData.MS_TO_KNOTS
	FlightData.true_airspeed_kt = tas_kt
	FlightData.indicated_airspeed_kt = Atmosphere.tas_to_ias(airspeed, alt_m) * FlightData.MS_TO_KNOTS
	var horiz := Vector3(state.linear_velocity.x, 0.0, state.linear_velocity.z)
	FlightData.ground_speed_kt = horiz.length() * FlightData.MS_TO_KNOTS
	FlightData.altitude_ft = alt_m * FlightData.M_TO_FEET
	FlightData.altitude_agl_ft = maxf(0.0, state.transform.origin.y - GEAR_HEIGHT) * FlightData.M_TO_FEET
	FlightData.vertical_speed_fpm = state.linear_velocity.y * FlightData.MS_TO_FPM

	# Attitude from the basis. Forward = -z.
	var fwd := -basis.z
	FlightData.pitch_deg = rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))
	# Heading: project forward onto the horizontal plane, 0 = -Z (north).
	FlightData.heading_deg = fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)
	# Roll: how far the right wing has dropped below horizontal.
	var right := basis.x
	FlightData.roll_deg = rad_to_deg(asin(clampf(-right.y, -1.0, 1.0)))

	FlightData.angle_of_attack_deg = rad_to_deg(alpha)
	# Slip/skid from lateral acceleration component (inclinometer ball).
	FlightData.slip_skid = clampf(beta * 2.5, -1.0, 1.0)
	FlightData.load_factor = 1.0 / maxf(0.1, cos(deg_to_rad(FlightData.roll_deg))) \
		if not on_ground else 1.0

	FlightData.engine_rpm = engine.rpm
	FlightData.throttle_pct = engine.throttle * 100.0
	FlightData.fuel_flow_gph = engine.fuel_flow_gph()
	FlightData.manifold_pressure_inhg = engine.manifold_pressure(alt_m)
	FlightData.oil_temp_c = lerpf(40.0, 95.0, clampf(engine.rpm / C172Engine.MAX_RPM, 0.0, 1.0))
	FlightData.on_ground = on_ground

	# Stall warning fires a few knots above the actual stall (like the reed horn).
	FlightData.stall_warning = absf(alpha) > (ALPHA_STALL - 0.05) and airspeed > 2.0
