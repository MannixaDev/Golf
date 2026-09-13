## Quietly move the ball toward the hole without playing a stroke.
##
## Foot Wedge. Capped so it can never be used to walk the ball in from close
## range -- it improves a lie, it does not hole out for you.
class_name NudgeBallEffect
extends CardEffect

@export_multiline var summary: String = ""
@export var yards: float = 8.0
## Never leave the ball nearer the pin than this.
@export var min_remaining_yards: float = 4.0
@export var success_message: String = "Foot wedge. Purely accidental."
@export var refusal_message: String = "Far too close to get away with that."


func describe() -> String:
	return summary


func on_play(ctx: EffectContext) -> void:
	var to_pin := ctx.pin_position - ctx.ball_position
	var remaining := ctx.yards_to_pin()
	var allowed := minf(yards, remaining - min_remaining_yards)
	if allowed <= 0.1:
		ctx.reject(refusal_message)
		return
	ctx.move_ball_to = ctx.ball_position \
		+ to_pin.normalized() * allowed * ctx.pixels_per_yard
	ctx.message = "%s (%d yards)" % [success_message, roundi(allowed)]
