extends Node
## Flight-test harness: flies the C172S POH test cards headless and prints the
## achieved numbers, so aero changes can be validated against the book:
##   1. Takeoff ground roll + liftoff speed  (book: ~290 m, rotate 55 KIAS)
##   2. Vy climb rate at ~74 KIAS            (book: ~730 fpm at sea level)
##   3. Full-throttle level cruise at 1500ft (book: ~120-124 KTAS)
##   4. Power-off, wings-level stall speed   (book: ~48 KIAS clean)
##
## Not registered as an autoload in normal play. To run the validation:
##   godot --headless --path .   (with TestPilot temporarily added to autoloads)

var ac: Aircraft
var phase := "init"
var t := 0.0
var spawn_z := 0.0
var liftoff_dist := 0.0
var liftoff_ias := 0.0
var rudder_acc := 0.0
var rudder_n := 0
var climb_t0 := -1.0
var cruise_t0 := -1.0
var tas_acc := 0.0
var tas_n := 0
var stall_t0 := -1.0
var min_ias := 999.0


func _ready() -> void:
	# Run 8x faster than realtime WITHOUT changing the physics step: raising
	# the tick rate together with time_scale keeps each tick at 1/120 s of
	# simulated time (time_scale alone would stretch dt 8x and destabilise the
	# stiff gear/damping terms).
	Engine.physics_ticks_per_second = 960
	Engine.time_scale = 8.0
	Engine.max_physics_steps_per_frame = 64


func _physics_process(dt: float) -> void:
	t += dt
	if ac == null:
		ac = Replay.aircraft
		if ac == null:
			return
		ac.control_override = true
		spawn_z = ac.global_position.z
		phase = "takeoff"
		print("POH: start")
	if t > 700.0:
		print("POH: TIMEOUT in phase ", phase)
		get_tree().quit()

	var ias: float = FlightData.indicated_airspeed_kt
	var alt: float = FlightData.altitude_ft
	var av: Vector3 = ac.angular_velocity
	var omega: Vector3 = ac.global_transform.basis.inverse() * av

	# Lateral: wings level + runway heading everywhere.
	var hdg_err := wrapf(FlightData.heading_deg + 180.0, 0.0, 360.0) - 180.0
	ac.input_roll = clampf(-FlightData.roll_deg * 0.06 + omega.z * 1.5, -1.0, 1.0)
	ac.input_yaw = clampf(-hdg_err * 0.08 + av.y * 1.5, -1.0, 1.0)

	match phase:
		"takeoff":
			ac.engine.throttle = 1.0
			rudder_acc += ac.input_yaw
			rudder_n += 1
			ac.input_pitch = 0.5 if ias >= 55.0 else 0.0
			if not FlightData.on_ground and FlightData.altitude_agl_ft > 3.0:
				liftoff_dist = absf(ac.global_position.z - spawn_z)
				liftoff_ias = ias
				print("POH: takeoff roll %.0f m, liftoff %.1f KIAS, mean rudder %.2f" %
					[liftoff_dist, liftoff_ias, rudder_acc / maxf(rudder_n, 1)])
				phase = "climb"
		"climb":
			ac.engine.throttle = 1.0
			ac.input_pitch = clampf((ias - 74.0) * 0.045 - omega.x * 3.0, -0.7, 0.7)
			if climb_t0 < 0.0 and alt >= 400.0:
				climb_t0 = t
			if climb_t0 >= 0.0 and alt >= 1400.0:
				var fpm := 1000.0 / (t - climb_t0) * 60.0
				print("POH: Vy climb %.0f fpm (74 KIAS target, held %.1f)" % [fpm, ias])
				phase = "cruise"
		"cruise":
			ac.engine.throttle = 1.0
			ac.input_pitch = clampf((1500.0 - alt) * 0.004
				- FlightData.vertical_speed_fpm * 0.0005 - omega.x * 2.0, -0.8, 0.8)
			if cruise_t0 < 0.0:
				cruise_t0 = t
			elif t - cruise_t0 > 100.0:
				tas_acc += FlightData.true_airspeed_kt
				tas_n += 1
				if t - cruise_t0 > 120.0:
					print("POH: cruise %.1f KTAS / %.1f KIAS at %.0f ft" %
						[tas_acc / tas_n, ias, alt])
					phase = "stall"
		"stall":
			ac.engine.throttle = 0.0
			ac.input_pitch = clampf((1500.0 - alt) * 0.004
				- FlightData.vertical_speed_fpm * 0.0005 - omega.x * 2.0, -0.9, 0.9)
			if stall_t0 < 0.0:
				stall_t0 = t
			min_ias = minf(min_ias, ias)
			if FlightData.angle_of_attack_deg > 16.2 and t - stall_t0 > 5.0:
				print("POH: stall break at %.1f KIAS (min seen %.1f)" % [ias, min_ias])
				print("POH: done")
				get_tree().quit()
