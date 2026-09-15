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

## Clubs held. Topped back up to this before every shot.
##
## Split from the techniques because the two are not the same kind of resource: a
## club is mandatory and a technique is optional. See Deck.deal_up_to.
var club_hand: int = 4
## Techniques held.
##
## Worth keeping at focus minus one. A shot card costs one focus, so that is
## exactly how many techniques you can afford to play -- hold more and the extras
## are cards you can only look at, which reads as a bigger hand and plays as a
## smaller one.
var extra_hand: int = 2
## Focus available each shot. A shot card costs 1; techniques spend the rest.
var focus: int = 3
## Techniques that cost nothing this hole. Spent oldest first, and counted per
## hole rather than per shot: a discount you get every stroke is not a discount,
## it is just more focus.
var free_techniques: int = 0


func _init(base_clubs: int = 4, base_focus: int = 3, base_extras: int = 2) -> void:
	club_hand = base_clubs
	focus = base_focus
	extra_hand = base_extras


## Kept sane whatever the bag asks for. A hand of zero is not a hard mode, it is
## a hole you cannot play.
func clamped() -> BagRules:
	# At least one club or the hole cannot be played at all. Techniques may go to
	# zero -- a hole with no shaping is a real restriction rather than a broken
	# one, and course rules use it.
	club_hand = clampi(club_hand, 1, 8)
	extra_hand = clampi(extra_hand, 0, 6)
	focus = clampi(focus, 1, 9)
	free_techniques = maxi(free_techniques, 0)
	return self


## Cards on screen once both hands are dealt. The fan has to fit this many.
func total_cards() -> int:
	return club_hand + extra_hand
