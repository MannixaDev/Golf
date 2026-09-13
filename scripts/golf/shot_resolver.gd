## Turns a player's intent (shot profile + aim + power) into a concrete ShotResult.
##
## Deliberately a pure static function with no scene dependencies: it is trivial
## to unit test, and it never needs to know whether the shot came from a club, a
## card, or a card modified by three techniques and a hazard. Everything upstream
## expresses itself by mutating the ShotProfile.
class_name ShotResolver
extends RefCounted

## Below this power the shot is a duff and barely moves.
const MIN_EFFECTIVE_POWER := 0.02


## `offline_deg` is the player's own timing miss, in degrees, signed. It is kept
## separate from dispersion on purpose: dispersion is the club being a club, and
## this is the swing being yours. Reporting them separately is what lets the game
## tell you whether you were unlucky or bad.
static func resolve(profile: ShotProfile, power_pct: float, aim_dir: Vector2,
		rng: RandomNumberGenerator, wind: Vector2 = Vector2.ZERO,
		offline_deg: float = 0.0) -> ShotResult:
	var result := ShotResult.new()
	result.profile = profile
	result.arc_factor = profile.arc_factor

	var power := clampf(power_pct, 0.0, 1.0)

	# --- Distance -------------------------------------------------------
	var distance := profile.carry_yards_max * maxf(power, MIN_EFFECTIVE_POWER)
	distance *= 1.0 + _triangular(rng) * profile.distance_variance
	distance = maxf(distance, 0.0)

	if profile.is_ground_shot:
		# Putts and other along-the-deck shots: no carry at all.
		result.carry_yards = 0.0
		result.roll_yards = distance
	else:
		result.carry_yards = distance
		result.roll_yards = distance * profile.roll_ratio

	# --- Direction ------------------------------------------------------
	# Dispersion grows with power, so a full-send driver is genuinely risky
	# while a controlled half swing is comparatively safe.
	var power_factor := 0.35 + 0.65 * power
	var error_deg := _triangular(rng) * profile.dispersion_deg * power_factor
	result.aim_error_deg = error_deg
	result.timing_error_deg = offline_deg
	result.direction = aim_dir.normalized().rotated(
		deg_to_rad(error_deg + offline_deg))

	# --- Shape ----------------------------------------------------------
	# A worked shot bends across the flight rather than simply starting on a
	# different line, so it can be used to get around things.
	result.curve_offset_yards = tan(deg_to_rad(profile.curve_deg)) * result.carry_yards
	result.protects_ball = profile.protects_ball
	result.slope_resistance = profile.slope_resistance

	# --- Weather --------------------------------------------------------
	# Drift scales with how long the ball is in the air and how high it goes,
	# so a punched shot bores through weather that ruins a lofted one. That is
	# the whole reason to hold a Punch card.
	result.wind_drift_yards = ShotResolver.wind_drift(wind, result.carry_yards, profile.arc_factor)

	return result


## Shared with the aim overlay so the preview and the shot agree exactly.
static func wind_drift(wind: Vector2, carry_yards: float, arc_factor: float) -> Vector2:
	if wind == Vector2.ZERO or carry_yards <= 0.0:
		return Vector2.ZERO
	return wind * (carry_yards / 100.0) * arc_factor


## Triangular distribution over [-1, 1], centre-weighted. Cheaper than a proper
## gaussian and it never produces absurd outliers.
static func _triangular(rng: RandomNumberGenerator) -> float:
	return rng.randf() + rng.randf() - 1.0
