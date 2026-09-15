## Equipment that changes the shape of a turn rather than the flight of a ball.
##
## The most valuable thing a relic can do in a game where a hand is five cards
## and focus is three. An extra club in hand is felt on every stroke of every
## hole; a free technique each hole is what turns a bag full of modifiers from a
## pile of nice-to-haves into a plan.
class_name BagRelic
extends RelicEffect

## Rules text for the equipment bar and the shop.
@export_multiline var summary: String = ""

@export_group("The hands")
## Extra clubs held. One is a lot: it is a whole extra option every stroke.
##
## Split from the techniques when the hands were, so a relic has to say which it
## widens. That is more design space rather than less -- "one more club" and "one
## more technique" want quite different bags built around them.
@export var club_hand_delta: int = 0
## Extra techniques held. Worth pairing with focus: holding a third technique
## you cannot afford to play is a card you can only look at.
@export var extra_hand_delta: int = 0

@export_group("Focus")
@export var focus_delta: int = 0
## Techniques that cost nothing, per hole. Counted per hole rather than per
## stroke on purpose -- a discount on every stroke is not a discount, it is
## simply more focus, and there is already a field for that.
@export var free_techniques: int = 0


func describe() -> String:
	return summary


func modify_bag(bag: BagRules, _ctx: RelicContext) -> void:
	bag.club_hand += club_hand_delta
	bag.extra_hand += extra_hand_delta
	bag.focus += focus_delta
	bag.free_techniques += free_techniques
