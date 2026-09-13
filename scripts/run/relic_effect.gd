## Base class for what a piece of equipment actually does.
##
## Deliberately the same shape as CardEffect: parameterised subclasses authored
## as .tres, so a new relic is data rather than a new special case somewhere in
## the golf code.
class_name RelicEffect
extends Resource

## One line of rules text.
func describe() -> String:
	return ""


## Bend the stroke about to be played. Called after the card, the techniques and
## the lie have all had their say.
func modify_profile(_profile: ShotProfile, _ctx: RelicContext) -> void:
	pass


## Return true to cancel a lost ball: no penalty stroke, ball dropped where it
## went in. Used by equipment that saves you once a hole.
func try_rescue_ball(_ctx: RelicContext) -> bool:
	return false


## Change the shape of a turn before the hole is dealt -- hand size, focus, what
## techniques cost. Called once per hole.
func modify_bag(_bag: BagRules, _ctx: RelicContext) -> void:
	pass


## Change what a finished hole is worth, once the score is known.
func on_hole_scored(_reward: HoleReward, _ctx: RelicContext) -> void:
	pass


## Whether this grants a particular piece of information the player would not
## otherwise have. Asked by name so adding a new one is a constant and a branch
## at the place that shows it, rather than a new hook here.
func grants(_insight: StringName) -> bool:
	return false
