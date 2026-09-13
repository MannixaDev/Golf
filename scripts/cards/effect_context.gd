## What an instant card effect is allowed to see, and what it may ask for.
##
## Effects never touch the hole scene directly. They read the situation from a
## context and write their intent back into it; HoleView is the only thing that
## actually moves the ball or changes the score. That keeps every effect testable
## on its own and stops cards from growing scene dependencies.
class_name EffectContext
extends RefCounted

# --- The situation, read-only as far as effects are concerned -------------

var ball_position: Vector2 = Vector2.ZERO
var pin_position: Vector2 = Vector2.ZERO
## Where the most recent stroke was played from.
var last_shot_origin: Vector2 = Vector2.ZERO
var strokes: int = 0
## False on the tee, or if the last rewind has already been used.
var can_rewind: bool = false
var pixels_per_yard: float = 3.0

# --- What the effect wants to happen --------------------------------------

## Vector2, or null to leave the ball alone.
var move_ball_to: Variant = null
## Added to the stroke count. Negative refunds a stroke.
var stroke_delta: int = 0
## Set when the effect has used up the chance to replay a shot.
var consume_rewind: bool = false
## Shown to the player on success.
var message: String = ""

var _rejected_reason: String = ""


## Refuse the play. The card stays in hand and no focus is spent.
func reject(reason: String) -> void:
	_rejected_reason = reason


func is_rejected() -> bool:
	return _rejected_reason != ""


func rejection_reason() -> String:
	return _rejected_reason


func yards_to_pin() -> float:
	return ball_position.distance_to(pin_position) / pixels_per_yard
