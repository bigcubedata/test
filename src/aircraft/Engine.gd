class_name C172Engine
extends RefCounted
## Simplified Lycoming IO-360-L2A powerplant + fixed-pitch McCauley prop.
##
## The C172S has a fixed-pitch propeller, so the pilot has a single throttle
## lever and RPM rises and falls with throttle and airspeed. We model:
##   * Engine RPM lagging toward a throttle-commanded target.
##   * Rated power de-rated for altitude (density) and partial throttle.
##   * Propeller thrust from shaft power and an airspeed-dependent
##     efficiency curve, with a static-thrust cap so it behaves at V ~ 0.
##
## This is intentionally a performance-matching model rather than a full
## blade-element simulation: it reproduces the book numbers (full-throttle
## static thrust, ~124 KTAS cruise, ~730 fpm climb) while staying cheap.

const RATED_POWER_HP: float = 180.0
const HP_TO_WATTS: float = 745.7
const MAX_RPM: float = 2700.0          # Redline / full-throttle static RPM
const IDLE_RPM: float = 700.0
const PROP_DIAMETER_M: float = 1.905   # 75 inch McCauley

# Propeller efficiency as a function of advance — modelled as a smooth curve
# that climbs from ~0 (static) to a peak near cruise then falls off.
const ETA_PEAK: float = 0.82
const V_ETA_PEAK: float = 62.0         # m/s (~120 kt) where efficiency peaks

var rpm: float = IDLE_RPM
var throttle: float = 0.0              # 0..1
var mixture: float = 1.0               # 0..1 (1 = full rich; hook for leaning)
var torque_nm: float = 0.0             # shaft reaction torque (for roll coupling)

## Advance current engine state. dt seconds, true airspeed v [m/s],
## altitude [m]. Returns thrust [N] available along the thrust axis.
func update(dt: float, v: float, alt_m: float) -> float:
	# Target RPM: idle at closed throttle, redline at full. Real fixed-pitch
	# RPM also rises with airspeed (prop unloads); fold in a small term.
	var airspeed_unload := clampf(v / 70.0, 0.0, 1.0) * 150.0
	var target_rpm := lerpf(IDLE_RPM, MAX_RPM, throttle) + throttle * airspeed_unload
	target_rpm = clampf(target_rpm, IDLE_RPM, MAX_RPM)
	# Engine inertia: RPM lags toward target.
	rpm = move_toward(rpm, target_rpm, 1800.0 * dt)

	# Shaft power: scales with throttle and air density (normally aspirated),
	# and with RPM — a fixed-pitch engine at low RPM cannot make rated power,
	# so power (and reaction torque) build as the prop spools up.
	var sigma := Atmosphere.density_ratio(alt_m)
	var power_fraction := lerpf(0.08, 1.0, throttle) * mixture * (rpm / MAX_RPM)
	var shaft_power_w := RATED_POWER_HP * HP_TO_WATTS * power_fraction * sigma

	# Shaft reaction torque (Q = P / omega) for the airframe roll coupling.
	torque_nm = shaft_power_w / maxf(rpm * TAU / 60.0, 30.0)

	# Propeller efficiency vs airspeed (bell-ish curve, zero at V=0).
	var eta := _prop_efficiency(v)

	# Useful thrust from power: T = eta * P / V. As V -> 0 this diverges, so
	# fade smoothly from the momentum-theory static estimate into the
	# min(static, dynamic) regime over the first few m/s — no step at a gate.
	var static_thrust := _static_thrust(shaft_power_w)
	var dynamic_thrust := eta * shaft_power_w / maxf(v, 0.5)
	var blend := clampf(v / 8.0, 0.0, 1.0)
	var thrust := lerpf(static_thrust, minf(static_thrust, dynamic_thrust), blend)
	return maxf(thrust, 0.0)

## Momentum-theory static thrust estimate from shaft power and disc area.
## T = (2 * rho * A * P^2)^(1/3), scaled by a propeller figure of merit.
## Ideal actuator-disc theory overpredicts; FOM ~ 0.55 brings full-power
## static thrust to ~2500 N (~560 lbf), matching the real C172S.
const PROP_FIGURE_OF_MERIT: float = 0.55

func _static_thrust(power_w: float) -> float:
	var disc_area := PI * pow(PROP_DIAMETER_M * 0.5, 2.0)
	var rho := Atmosphere.RHO0
	return PROP_FIGURE_OF_MERIT * pow(2.0 * rho * disc_area * power_w * power_w, 1.0 / 3.0)

func _prop_efficiency(v: float) -> float:
	# Smooth rise from 0, peak at V_ETA_PEAK, gentle falloff afterwards.
	var x := v / V_ETA_PEAK
	# (1 - exp) ramp from static, multiplied by a falloff past the peak.
	var ramp := 1.0 - exp(-2.2 * x)
	var falloff := 1.0 / (1.0 + 0.35 * maxf(0.0, x - 1.0) * maxf(0.0, x - 1.0))
	return clampf(ETA_PEAK * ramp * falloff, 0.0, ETA_PEAK)

## Estimated fuel flow [gallons per hour] for the instrument cluster.
func fuel_flow_gph() -> float:
	# ~ proportional to power; full power ~ 18 gph, idle ~ 2 gph.
	var frac := (rpm - IDLE_RPM) / (MAX_RPM - IDLE_RPM)
	return lerpf(1.8, 17.5, clampf(frac, 0.0, 1.0)) * mixture

## Manifold pressure proxy [inHg] for the engine display.
func manifold_pressure(alt_m: float) -> float:
	var ambient := Atmosphere.pressure(alt_m) / 3386.39  # Pa -> inHg
	# Throttle plate restricts MP below ambient at part throttle.
	return lerpf(ambient * 0.35, ambient * 0.98, throttle)
