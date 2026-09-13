## One fully resolved shot, ready to be executed by the Ball.
##
## This is the hand-off point between "what the player intended" and "what
## actually happens". Hazards, relics and card effects will all eventually act by
## mutating a ShotResult before it reaches the ball.
class_name ShotResult
extends RefCounted

## Actual travel direction, after dispersion has been applied.
var direction: Vector2 = Vector2.RIGHT
## Distance through the air, in yards.
var carry_yards: float = 0.0
## Distance rolled after landing, in yards.
var roll_yards: float = 0.0
## Visual flight height multiplier.
var arc_factor: float = 0.8
## The profile this shot was resolved from, for logging and UI.
var profile: ShotProfile = null
## Sideways bend at the end of the carry, in yards. Positive is right.
var curve_offset_yards: float = 0.0
## The ball cannot be lost on this stroke.
var protects_ball: bool = false
## Share of the green's break this stroke ignores, 0 to 1.
var slope_resistance: float = 0.0
## World-space drift from wind over the carry, in yards.
var wind_drift_yards: Vector2 = Vector2.ZERO
## How far off the intended line the shot ended up, in degrees. Useful for
## feedback ("pushed it right") and for relics that react to bad shots.
var aim_error_deg: float = 0.0
## The share of that which was the player mistiming the swing, rather than the
## club's own dispersion. Zero on a pure strike.
var timing_error_deg: float = 0.0


## Peak height as a share of carry, for a neutral shot. The one place this is
## written down: the ball flies by it, the HUD reports it, and the trees are
## judged against it, so they cannot disagree.
const APEX_RATIO := 0.24


func total_yards() -> float:
	return carry_yards + roll_yards


## How high this shot gets, in yards. What decides whether it clears a tree.
func apex_yards() -> float:
	return carry_yards * APEX_RATIO * arc_factor
