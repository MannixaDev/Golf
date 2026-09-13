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

@export_group("The hand")
## Extra cards held. One is a lot: it is a whole extra option every stroke.
@export var hand_size_delta: int = 0

@export_group("Focus")
@export var focus_delta: int = 0
## Techniques that cost nothing, per hole. Counted per hole rather than per
## stroke on purpose -- a discount on every stroke is not a discount, it is
## simply more focus, and there is already a field for that.
@export var free_techniques: int = 0


func describe() -> String:
	return summary


func modify_bag(bag: BagRules, _ctx: RelicContext) -> void:
	bag.hand_size += hand_size_delta
	bag.focus += focus_delta
	bag.free_techniques += free_techniques
