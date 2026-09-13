## Put the ball back where the last stroke was played from and refund the stroke.
##
## Mulligan. Refuses on the tee, and refuses twice in a row -- HoleView clears the
## rewind flag once a shot has been taken back, so you cannot chain them.
class_name RewindShotEffect
extends CardEffect

@export_multiline var summary: String = "Replay your last stroke. It does not count."
@export var refund_strokes: int = 1
@export var success_message: String = "Mulligan. Nobody saw that."
@export var refusal_message: String = "There is no stroke to take back."


func describe() -> String:
	return summary


func on_play(ctx: EffectContext) -> void:
	if not ctx.can_rewind:
		ctx.reject(refusal_message)
		return
	ctx.move_ball_to = ctx.last_shot_origin
	ctx.stroke_delta = -refund_strokes
	ctx.consume_rewind = true
	ctx.message = success_message
