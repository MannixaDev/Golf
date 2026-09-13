## Equipment that changes what a hole is worth, rather than how it is played.
##
## This is the class that lets equipment change your appetite for risk. A relic
## paying double for birdies makes going at a tucked pin worth the bunker behind
## it; one paying for bogeys makes laying up a living. Neither touches the ball.
class_name ScoringRelic
extends RelicEffect

@export_multiline var summary: String = ""

@export_group("Winnings")
## Applied to the whole payout.
@export var winnings_multiplier: float = 1.0
## Flat bonus when the hole came in at or under par.
@export var bonus_at_or_under_par: int = 0
## Flat bonus for a birdie or better, on top of the above.
@export var bonus_for_birdie: int = 0
## Flat bonus when the hole went badly. Consolation equipment: it makes a bad
## round survivable rather than making a good one better.
@export var bonus_over_par: int = 0

@export_group("The card")
## Strokes taken back off the card for a birdie or better. Capped at level by
## HoleReward, like resting is: a way back into a run, never a way to gild one
## that is already going well.
@export var strokes_back_for_birdie: int = 0


func describe() -> String:
	return summary


func on_hole_scored(reward: HoleReward, _ctx: RelicContext) -> void:
	var before := reward.winnings
	if not is_equal_approx(winnings_multiplier, 1.0):
		reward.winnings = roundi(float(reward.winnings) * winnings_multiplier)
	if reward.to_par() <= 0:
		reward.winnings += bonus_at_or_under_par
	if reward.is_birdie_or_better():
		reward.winnings += bonus_for_birdie
		reward.strokes_back += strokes_back_for_birdie
	if reward.to_par() > 0:
		reward.winnings += bonus_over_par

	var gained := reward.winnings - before
	if gained != 0:
		reward.note("%s %d" % ["+" if gained > 0 else "", gained])
