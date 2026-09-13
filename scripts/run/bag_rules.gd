## How the bag behaves this hole, before a card is dealt.
##
## Exists so equipment can change the shape of a turn rather than only the
## numbers on a stroke. Hand size and focus were `@export`s read straight off
## HoleView, which meant nothing could ever touch them without the golf scene
## growing a special case for each piece of equipment that wanted to.
##
## HoleView builds one of these at the start of every hole, hands it round the
## bag, and plays by whatever comes back.
class_name BagRules
extends RefCounted

## Cards held. Topped back up to this before every shot.
var hand_size: int = 5
## Focus available each shot. A shot card costs 1; techniques spend the rest.
var focus: int = 3
## Techniques that cost nothing this hole. Spent oldest first, and counted per
## hole rather than per shot: a discount you get every stroke is not a discount,
## it is just more focus.
var free_techniques: int = 0


func _init(base_hand: int = 5, base_focus: int = 3) -> void:
	hand_size = base_hand
	focus = base_focus


## Kept sane whatever the bag asks for. A hand of zero is not a hard mode, it is
## a hole you cannot play.
func clamped() -> BagRules:
	hand_size = clampi(hand_size, 1, 9)
	focus = clampi(focus, 1, 9)
	free_techniques = maxi(free_techniques, 0)
	return self
