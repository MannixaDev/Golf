## What the pro shop has on the shelf today, and what it is asking for it.
##
## The same idea as BagRules, for the same reason. Every relic in the game so far
## changes a stroke: how far it goes, whether it is rescued, what the hole paid.
## Not one of them can touch the run itself -- the route, the shop, the money --
## which is the half of a deckbuilder where builds actually come from. A bag that
## wins because you spent the whole run buying cheap is a different run from one
## that wins on ball striking, and until there was something to write to, there
## was nowhere to express that.
##
## Built once as the shop opens, handed round the equipment, and the shop is
## stocked from whatever comes back. Relics compose rather than fight: two that
## each knock something off the price both apply, and the clamp below is what
## stops the pair of them making everything free.
class_name ShopStock
extends RefCounted

## Cards on the shelf.
var card_slots: int = 3
## Equipment on the shelf.
var relic_slots: int = 2
## Multiplier on every asking price, cards and equipment alike. 0.75 is a quarter
## off. The putter kept under the counter is deliberately exempt -- it is a
## rescue, not a purchase, and a discount on it is meaningless.
var price_scale: float = 1.0
## Clubs you may leave at home for nothing, per visit.
var free_removals: int = 0
## At least this many of the cards on the shelf are uncommon rather than common.
## There is no rare card pool, so this is as good as the shelf gets.
var guaranteed_uncommons: int = 0


func _init(cards: int = 3, relics: int = 2) -> void:
	card_slots = cards
	relic_slots = relics


## Kept sane whatever the bag asks for, the way BagRules is. A shop with nothing
## on the shelf is not a hard mode, and one giving everything away is not a
## decision.
func clamped() -> ShopStock:
	card_slots = clampi(card_slots, 1, 6)
	relic_slots = clampi(relic_slots, 0, 4)
	price_scale = clampf(price_scale, 0.5, 2.0)
	free_removals = maxi(free_removals, 0)
	guaranteed_uncommons = clampi(guaranteed_uncommons, 0, card_slots)
	return self


## An asking price, after whatever the equipment has to say about it. Never free:
## something worth having should always cost something, or the decision the shop
## is there to pose stops being a decision.
func price_of(base: int) -> int:
	return maxi(1, int(round(float(base) * price_scale)))


## What it costs to leave a club at home, given how many have been free already.
func removal_price(base: int, used_this_visit: int) -> int:
	if used_this_visit < free_removals:
		return 0
	return price_of(base)
