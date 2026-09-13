## Equipment that saves a lost ball, a limited number of times per hole.
##
## The count lives on the context rather than on the relic, so the relic itself
## stays stateless and two of them could not quietly share a counter.
class_name FreeRecoveryRelic
extends RelicEffect

@export_multiline var summary: String = ""
@export var uses_per_hole: int = 1


func describe() -> String:
	return summary


func try_rescue_ball(ctx: RelicContext) -> bool:
	return ctx.recoveries_used < uses_per_hole
