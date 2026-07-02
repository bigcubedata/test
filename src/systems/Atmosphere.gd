extends Node
## International Standard Atmosphere (ISA) model.
##
## Provides air density, pressure, temperature and speed of sound as a
## function of geometric altitude. Valid through the troposphere and lower
## stratosphere (0 - 20 km), which comfortably covers the C172S envelope
## (service ceiling ~14,000 ft). Registered as an autoload singleton so any
## system (aerodynamics, engine, instruments) can query the air mass.

# --- ISA sea-level reference values (SI units) ---
const T0: float = 288.15          # Sea-level standard temperature [K]
const P0: float = 101325.0        # Sea-level standard pressure [Pa]
const RHO0: float = 1.225         # Sea-level standard density [kg/m^3]
const L: float = 0.0065           # Troposphere temperature lapse rate [K/m]
const G0: float = 9.80665         # Standard gravity [m/s^2]
const R: float = 287.05287        # Specific gas constant for dry air [J/(kg*K)]
const GAMMA: float = 1.4          # Ratio of specific heats for air
const TROPOPAUSE_ALT: float = 11000.0  # Top of the troposphere [m]

## Temperature [K] at the given geometric altitude [m].
func temperature(alt_m: float) -> float:
	if alt_m <= TROPOPAUSE_ALT:
		return T0 - L * alt_m
	# Isothermal lower stratosphere.
	return T0 - L * TROPOPAUSE_ALT

## Static pressure [Pa] at the given altitude [m].
func pressure(alt_m: float) -> float:
	if alt_m <= TROPOPAUSE_ALT:
		var t := temperature(alt_m)
		return P0 * pow(t / T0, G0 / (L * R))
	var t_trop := temperature(TROPOPAUSE_ALT)
	var p_trop := P0 * pow(t_trop / T0, G0 / (L * R))
	return p_trop * exp(-G0 * (alt_m - TROPOPAUSE_ALT) / (R * t_trop))

## Air density [kg/m^3] at the given altitude [m].
func density(alt_m: float) -> float:
	var t := temperature(alt_m)
	var p := pressure(alt_m)
	return p / (R * t)
## Density ratio sigma = rho / rho0. Useful for converting true airspeed to
## indicated/equivalent airspeed and for de-rating engine power with altitude.
func density_ratio(alt_m: float) -> float:
	return density(alt_m) / RHO0

## Convert true airspeed [m/s] to calibrated/indicated airspeed [m/s].
## At the speeds and altitudes a C172 flies, IAS ~= EAS = TAS * sqrt(sigma).
func tas_to_ias(tas_ms: float, alt_m: float) -> float:
	return tas_ms * sqrt(density_ratio(alt_m))
