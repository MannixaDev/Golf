## The workshop out the back of the clubhouse.
##
## Clamp a wood and an iron in the vice, take a grinder to both, and walk out
## with one club that has no business existing. Both parents are destroyed, so
## the trade is two ordinary swings for one very good one -- and a bag one card
## thinner, which matters more than it sounds when a hand is five cards.
##
## The rules live here rather than in the run layer so a harness can argue with
## them without booting a screen, and so nothing has to branch on a card's name:
## what may be fused is decided by the club's family, which is data.
class_name ClubFusion
extends RefCounted

const RESULT_ID := &"driron"
## Chance the door is unlocked the first time you walk into a stop that keeps a
## workbench, and how much that improves every time you find it locked.
##
## A flat roll was wrong and a playtest proved it. The route already makes this
## rare: only about three nines in four put *any* workbench stop in front of
## you, so a die on top of that was charging rarity twice and the thing showed
## up in one run in four. Nobody discovers a feature at that rate.
##
## Rarity now comes from the route, which is the part the player can read and
## route towards. The die only decides whether it is this bench or the next one,
## and it gives up if you keep turning up.
## Measured, not picked: past 0.60 the extra chance buys almost nothing, because
## by then the limit is the 78% of nines that contain a workbench stop at all.
const FIRST_CHANCE := 0.60
const CHANCE_STEP := 0.35


## How likely the door is, given how many workbenches have already been locked
## against you this run.
static func chance(misses: int) -> float:
	return clampf(FIRST_CHANCE + CHANCE_STEP * float(maxi(misses, 0)), 0.0, 1.0)


## Everything in the bag that could go in the vice as the long half.
static func woods(cards: Array) -> Array[CardData]:
	return _family(cards, ClubSpec.Family.WOOD)


## ...and the honest half.
static func irons(cards: Array) -> Array[CardData]:
	return _family(cards, ClubSpec.Family.IRON)


## True when the bag has both halves and nothing fused in it yet. One Driron is
## the whole point of a Driron.
static func is_available(cards: Array) -> bool:
	if already_fused(cards):
		return false
	return not woods(cards).is_empty() and not irons(cards).is_empty()


static func already_fused(cards: Array) -> bool:
	for card in cards:
		if card is CardData and card.id == RESULT_ID:
			return true
	return false


## The club itself. Grooving either parent carries across the weld, because
## melting down a club you had worked on and getting a stock one back would make
## the range and the workshop fight each other.
static func fuse(wood: CardData, iron: CardData) -> CardData:
	var made := CardLibrary.copy(RESULT_ID)
	if made == null:
		return null
	if wood != null and wood.upgraded:
		made.upgraded = true
	if iron != null and iron.upgraded:
		made.upgraded = true
	return made


## What the reveal screen says under the picture.
static func lineage(wood: CardData, iron: CardData) -> String:
	return "%s  +  %s" % [wood.title(), iron.title()]


static func _family(cards: Array, family: int) -> Array[CardData]:
	var found: Array[CardData] = []
	for card in cards:
		if card is CardData and card.club != null and card.club.family == family:
			found.append(card)
	return found
