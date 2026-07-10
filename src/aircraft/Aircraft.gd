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
const CD0: float = 0.0345           # parasite drag (gear down, fixed prop);
                                    # tuned against POH cruise/climb numbers

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

# --- Propulsion coupling (what makes a single truly feel like a single) ----
const PROP_DISC_AREA: float = 2.85      # m^2 (75-inch McCauley)
const TAIL_WASH_FRACTION: float = 0.55  # share of far-wake slipstream q over the tail
const K_SLIPSTREAM_YAW: float = 0.30    # spiral slipstream: nose-left with power
const K_PFACTOR: float = 1.6            # P-factor: nose-left with power at high alpha
const K_TORQUE_ROLL: float = 0.6        # engine reaction torque rolls left

# --- Stall behaviour --------------------------------------------------------
const BUFFET_AMPLITUDE: float = 0.015   # pre-stall airframe buffet strength

# --- Ground handling: three-point gear -------------------------------------
# Each wheel is its own spring/damper contact with tire friction, so ground
# attitude, rotation, braking pitch-down and steering all emerge from the
# geometry instead of being scripted. Mains sit behind the CG (the nosewheel
# carries ~8% of the weight, like the real aircraft).
const GEAR_HEIGHT: float = 1.2      # wheel contact below CG [m]
# Spring rates are matched to the static load split (nose ~15%, mains ~85%)
# so an even-compression transient settles level instead of pitching; the
# mains sit far enough behind the CG that gear forces can't tip it tail-down,
# while the elevator can still rotate at ~55 KIAS once wing lift unloads them.
const WHEELS := [
	Vector3(0.0, -1.2, -2.0),       # nosewheel
	Vector3(-1.05, -1.2, 0.45),     # left main
	Vector3(1.05, -1.2, 0.45),      # right main
	Vector3(0.0, -0.55, 3.3),       # tail tie-down skid (strike protection)
]
const WHEEL_STIFF := [18000.0, 51000.0, 51000.0, 40000.0]
const WHEEL_DAMP := [3000.0, 8000.0, 8000.0, 4000.0]
const ROLLING_FRICTION: float = 0.03
const BRAKE_FRICTION: float = 0.45
const MU_SIDE: float = 0.75         # lateral tire grip (tires resist skidding)
const TIRE_CORNER_STIFF: float = 0.35   # side force per m/s of lateral slip
const NOSE_STEER_ANGLE: float = 0.30    # rad of nosewheel steer at full pedal

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
## When true, keyboard reading is skipped and input_* are driven externally
## (test harness / future autopilot).
var control_override: bool = false
var _buffet_t: float = 0.0
var _load_factor: float = 1.0

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
	Replay.register(self)


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
	Replay.clear()   # a respawn starts a fresh recording


func _process(_delta: float) -> void:
	# During replay the aircraft is frozen and driven by the recorder, so the
	# live controls (and the reset key) are inert.
	if Replay.is_replaying():
		return
	_read_input()


func _read_input() -> void:
	if control_override:
		return
	var dt := get_process_delta_time()
	if JoystickInput.has_stick():
		# Analog stick (e.g. TCA Sidestick): direct, curve-shaped input — no
		# rate ramp, the hand on the stick IS the smoothing.
		input_pitch = JoystickInput.pitch()
		input_roll = JoystickInput.roll()
		input_yaw = JoystickInput.yaw()
	else:
		# Keyboard is digital, so ramp the commanded input toward the key
		# state instead of snapping — the yoke moves like a hand is on it,
		# not a switch — and re-centre a little faster than it deflects.
		# Yoke convention: Up arrow pushes the nose DOWN, Down arrow pulls it UP.
		input_pitch = _shape_axis(input_pitch, Input.get_axis("pitch_up", "pitch_down"), dt)
		input_roll = _shape_axis(input_roll, Input.get_axis("roll_left", "roll_right"), dt)
		input_yaw = _shape_axis(input_yaw, Input.get_axis("yaw_left", "yaw_right"), dt)

	if JoystickInput.has_throttle():
		# Absolute lever (TCA Quadrant, or the sidestick's mini slider).
		engine.throttle = JoystickInput.throttle()
	else:
		if Input.is_action_pressed("throttle_up"):
			engine.throttle = clampf(engine.throttle + 0.6 * dt, 0.0, 1.0)
		if Input.is_action_pressed("throttle_down"):
			engine.throttle = clampf(engine.throttle - 0.6 * dt, 0.0, 1.0)

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
	# Parking brake, plus momentary braking while the quadrant levers are
	# lifted into the reverse range (a 172 has no reversers — repurposed).
	brakes_on = FlightData.parking_brake or JoystickInput.reverse_braking()

	if Input.is_action_just_pressed("reset_aircraft"):
		reset()


func _shape_axis(current: float, target: float, dt: float) -> float:
	var rate := 2.2 if absf(target) > 0.01 else 4.5
	return move_toward(current, target, rate * dt)


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
	var wind := Wind.sample(xform.origin)
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
	var cl := _apply_stall(cl_linear, alpha, cl_max_eff, CL0 + dCL_flap)

	# --- Drag: parasite + induced (with ground effect) + flaps + stall ----
	# Ground effect: near the runway the wing's induced drag collapses
	# (McCormick h/b model). This is what makes the aircraft float in the
	# flare instead of dropping on.
	var h_over_b := clampf((xform.origin.y + 0.5) / WING_SPAN, 0.05, 1.1)
	var ge := pow(16.0 * h_over_b, 2.0)
	ge = ge / (1.0 + ge)
	var k := 1.0 / (PI * OSWALD_E * ASPECT_RATIO)
	var cd := CD0 + dCD_flap + k * cl * cl * ge
	# Post-stall separation drag rises sharply.
	if absf(alpha) > ALPHA_STALL:
		cd += 0.9 * (absf(alpha) - ALPHA_STALL)

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

	# --- Propwash over the tail -------------------------------------------
	# Momentum theory: the far-wake slipstream raises dynamic pressure behind
	# the prop, so the elevator and rudder keep authority at low airspeed —
	# this is why a real 172 can rotate at 55 KIAS and hold the nose in a
	# full-power climb.
	var wash_sq := airspeed * airspeed \
		+ TAIL_WASH_FRACTION * 2.0 * thrust_mag / (rho * PROP_DISC_AREA)
	var q_tail := 0.5 * rho * wash_sq

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

	# Ailerons lose bite as the wing approaches the stall (separated flow).
	var stall_margin := absf(alpha) - (ALPHA_STALL - 0.035)
	var ail_eff := 1.0
	if stall_margin > 0.0:
		ail_eff = clampf(1.0 - stall_margin / 0.12, 0.35, 1.0)

	# Wing-borne moments scale with freestream q; tail-borne moments (elevator,
	# rudder, fin, pitch/yaw damping) scale with slipstream-washed q_tail.
	var cm_wing := CM0 + dCM_flap + CM_ALPHA * alpha
	var cm_tail := CM_Q * qhat + CM_ELEVATOR * (elevator + elevator_trim)
	var cl_roll := CL_BETA * beta + CL_P * phat + CL_AILERON * aileron * ail_eff
	var cn_tail := CN_BETA * beta + CN_R * rhat + CN_RUDDER * rudder

	var pitch_moment := (qbar * cm_wing + q_tail * cm_tail) * WING_AREA * MEAN_CHORD
	var roll_moment := qbar * WING_AREA * WING_SPAN * cl_roll   # about body z(fwd)
	var yaw_moment := q_tail * WING_AREA * WING_SPAN * cn_tail  # about body y

	# --- Left-turning tendencies (single-engine character) ----------------
	# Spiral slipstream strikes the fin from the left (strongest slow + high
	# power), P-factor at high alpha, and engine torque reaction. Positive
	# yaw moment = nose LEFT, positive roll moment = roll LEFT in this frame.
	var slip_w := clampf(1.0 - airspeed / 75.0, 0.15, 1.0)
	yaw_moment += K_SLIPSTREAM_YAW * thrust_mag * slip_w
	yaw_moment += K_PFACTOR * thrust_mag * maxf(alpha, 0.0)
	roll_moment += K_TORQUE_ROLL * engine.torque_nm

	# --- Turbulence gradients ----------------------------------------------
	# Sample the gust field at the wingtips and tail: a stronger updraft on
	# one wing rolls the aircraft, a different gust at the tail pitches/yaws
	# it — bumps come from the air, not from injected random torques.
	if Wind.turbulence() > 0.01 and airspeed > 6.0:
		var w_l := Wind.sample(xform.origin - basis.x * 4.5)
		var w_r := Wind.sample(xform.origin + basis.x * 4.5)
		var w_t := Wind.sample(xform.origin + basis.z * 4.0)
		# Signs: an updraft on a wingtip RAISES that wing (+roll = roll left,
		# so a right-tip updraft is positive); an updraft at the tail pushes
		# the nose DOWN; a rightward gust on the fin pushes the tail right,
		# i.e. the nose LEFT (+yaw).
		roll_moment += 0.12 * rho * airspeed * WING_AREA * WING_SPAN \
			* (w_r - w_l).dot(basis.y)
		pitch_moment += 0.6 * rho * airspeed * WING_AREA * MEAN_CHORD \
			* (wind - w_t).dot(basis.y)
		yaw_moment += 0.05 * rho * airspeed * WING_AREA * WING_SPAN \
			* (w_t - wind).dot(basis.x)

	# --- Pre-stall buffet ---------------------------------------------------
	# Separated flow shakes the airframe just before and through the stall —
	# the tactile warning a real wing gives.
	if stall_margin > -0.01 and airspeed > 12.0:
		_buffet_t += dt
		var amp := BUFFET_AMPLITUDE * qbar * WING_AREA * MEAN_CHORD
		pitch_moment += amp * sin(_buffet_t * 47.0)
		roll_moment += amp * 1.6 * sin(_buffet_t * 31.0)

	var torque_body := Vector3(pitch_moment, yaw_moment, roll_moment)
	var torque_world := basis * torque_body

	# --- Ground contact: per-wheel springs + tire friction -----------------
	var on_ground := false
	if xform.origin.y < GEAR_HEIGHT + 1.0:
		var steer := (rudder / MAX_RUDDER) * NOSE_STEER_ANGLE
		for i in range(WHEELS.size()):
			var wp: Vector3 = xform * WHEELS[i]
			if wp.y >= 0.0:
				continue
			on_ground = true
			var arm := wp - xform.origin
			var wheel_vel := state.linear_velocity + state.angular_velocity.cross(arm)
			# Spring-damper normal force (only pushes up).
			var n := maxf(0.0, WHEEL_STIFF[i] * (-wp.y) - WHEEL_DAMP[i] * wheel_vel.y)
			var f := Vector3.UP * n
			# Tire friction in the body frame: free-rolling fore-aft (brakes on
			# the mains only), strong cornering grip sideways. The nosewheel's
			# slip includes its steer angle, so rudder pedals steer at taxi
			# speed and wash out naturally as the tail becomes effective.
			var wb := basis.inverse() * Vector3(wheel_vel.x, 0.0, wheel_vel.z)
			var v_fwd := -wb.z
			var v_side := wb.x
			if i == 0:
				v_side -= v_fwd * steer
			var f_long := 0.0
			if absf(v_fwd) > 0.05:
				var braking := brakes_on and (i == 1 or i == 2)  # mains only
				var mu := BRAKE_FRICTION if braking else ROLLING_FRICTION
				f_long = -signf(v_fwd) * mu * n
			var f_side := -clampf(v_side * TIRE_CORNER_STIFF, -MU_SIDE, MU_SIDE) * n
			f += basis * Vector3(f_side, 0.0, -f_long)
			total_force += f
			torque_world += arm.cross(f)
		if on_ground:
			# Mild scrub/shimmy damping in yaw.
			torque_world += basis * Vector3(0.0, -1200.0 * r, 0.0)

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

	# True load factor: lift component along the body-up axis over weight.
	if on_ground:
		_load_factor = 1.0
	else:
		_load_factor = lift_force.dot(basis.y) / (mass * Atmosphere.G0)

	_publish_flight_data(state, airspeed, alpha, beta, alt_m, cl, cl_max_eff, on_ground)


## Smoothly limit CL past the stall angle so lift collapses instead of
## growing without bound. The post-stall blend starts from the ACTUAL CL at
## the stall boundary (camber/flaps shift the curve, so the negative-alpha
## boundary CL is much smaller in magnitude than +cl_max) — this keeps the
## lift curve continuous through both stall boundaries.
func _apply_stall(cl_linear: float, alpha: float, cl_max: float, cl_camber: float) -> float:
	var a := absf(alpha)
	if a <= ALPHA_STALL:
		return clampf(cl_linear, -cl_max, cl_max)
	# Past stall: lift breaks down toward a low post-stall plateau — quickly,
	# so the break is a definite event rather than a mush.
	# (a > ALPHA_STALL here, so alpha is non-zero and its sign is well-defined.)
	var s := signf(alpha)
	var boundary := clampf(cl_camber + CL_ALPHA * ALPHA_STALL * s, -cl_max, cl_max)
	var over := clampf((a - ALPHA_STALL) / 0.18, 0.0, 1.0)
	return lerpf(boundary, 0.55 * s, over)


func _publish_flight_data(state: PhysicsDirectBodyState3D, airspeed: float,
		alpha: float, beta: float, alt_m: float, cl: float, cl_max: float,
		on_ground: bool) -> void:
	var basis := state.transform.basis
	var tas_kt := airspeed * FlightData.MS_TO_KNOTS
	FlightData.true_airspeed_kt = tas_kt
	FlightData.indicated_airspeed_kt = Atmosphere.tas_to_ias(airspeed, alt_m) * FlightData.MS_TO_KNOTS
	var horiz := Vector3(state.linear_velocity.x, 0.0, state.linear_velocity.z)
	FlightData.ground_speed_kt = horiz.length() * FlightData.MS_TO_KNOTS
	# Ground track from the velocity vector (crab makes it differ from heading).
	if FlightData.ground_speed_kt > 2.0:
		FlightData.track_deg = fposmod(rad_to_deg(atan2(horiz.x, -horiz.z)), 360.0)
	else:
		FlightData.track_deg = FlightData.heading_deg
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
	# Real load factor from the integrated lift (smoothed for the readout).
	FlightData.load_factor = lerpf(FlightData.load_factor, _load_factor, 0.2)

	FlightData.engine_rpm = engine.rpm
	FlightData.throttle_pct = engine.throttle * 100.0
	FlightData.fuel_flow_gph = engine.fuel_flow_gph()
	FlightData.manifold_pressure_inhg = engine.manifold_pressure(alt_m)
	FlightData.oil_temp_c = lerpf(40.0, 95.0, clampf(engine.rpm / C172Engine.MAX_RPM, 0.0, 1.0))
	FlightData.on_ground = on_ground
	FlightData.pos_x = state.transform.origin.x
	FlightData.pos_z = state.transform.origin.z

	# Stall warning fires a few knots above the actual stall (like the reed horn).
	FlightData.stall_warning = absf(alpha) > (ALPHA_STALL - 0.05) and airspeed > 2.0

	# Feed the flight recorder (no-op unless we're in LIVE mode).
	Replay.capture(state.transform)
