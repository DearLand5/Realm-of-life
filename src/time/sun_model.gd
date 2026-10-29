class_name SunModel
extends RefCounted
## Simple solar geometry. World axes: north = −Z, east = +X, up = +Y.
## year_phase 0 = start of spring (equinox), 0.25 = summer solstice.

const AXIAL_TILT := 23.44


## Solar declination in degrees for a year phase.
static func declination(year_phase: float) -> float:
	return AXIAL_TILT * sin(year_phase * TAU)


## Unit vector pointing from the ground TOWARDS the sun.
static func direction(hour: float, year_phase: float, latitude_deg: float) -> Vector3:
	var lat := deg_to_rad(latitude_deg)
	var dec := deg_to_rad(declination(year_phase))
	var ha := (hour - 12.0) / 24.0 * TAU   # hour angle, 0 at solar noon
	# Equatorial → horizon frame (east, up, north).
	var east := -cos(dec) * sin(ha)
	var north := sin(dec) * cos(lat) - cos(dec) * cos(ha) * sin(lat)
	var up := sin(dec) * sin(lat) + cos(dec) * cos(ha) * cos(lat)
	return Vector3(east, up, -north).normalized()


static func elevation(hour: float, year_phase: float, latitude_deg: float) -> float:
	return rad_to_deg(asin(clampf(direction(hour, year_phase, latitude_deg).y, -1.0, 1.0)))


## 0 at night → 1 in full day; civil twilight ramps between −6° and +8°.
static func daylight(elevation_deg: float) -> float:
	return smoothstep(-6.0, 8.0, elevation_deg)


## Moon roughly opposite the sun, lifted so moonlight comes from the sky.
static func moon_direction(sun_dir: Vector3, year_phase: float) -> Vector3:
	var m := -sun_dir
	m = m.rotated(Vector3.UP, 0.5 + year_phase * TAU * 0.3)
	m.y = maxf(absf(m.y), 0.35)
	return m.normalized()
