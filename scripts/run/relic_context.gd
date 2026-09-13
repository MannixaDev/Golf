## What a relic is allowed to know when it decides whether to fire.
##
## Same idea as EffectContext for cards: relics read a snapshot rather than
## reaching into the hole scene, so each one can be tested on its own and none of
## them grows a dependency on how a hole is put together.
class_name RelicContext
extends RefCounted

## 1 for the tee shot, 2 for the next, and so on.
var stroke_number: int = 1
## Strokes already played on this hole.
var strokes_taken: int = 0
var par: int = 4
## The player's score against par across the whole run so far.
var run_score_to_par: int = 0
## What the ball is sitting on.
var lie: SurfaceType = null
## Balls already rescued on this hole, so a once-a-hole relic can count.
var recoveries_used: int = 0


func lie_is_trouble() -> bool:
	return lie != null and lie.modifies_play()


func is_over_par() -> bool:
	return run_score_to_par > 0
