## Equipment that changes the run rather than the round.
##
## Everything else in the bag acts on a stroke. This acts on the shop, which is
## where a run is actually built: what is on the shelf and what it costs decides
## whether a bag can be assembled at all, and a relic that makes cards cheap is
## a different plan from one that makes them plentiful.
##
## Worth saying that none of this touches a golf ball. It is deliberately the
## slowest kind of power in the game -- it pays back over a whole run rather than
## on the next stroke -- which is what stops a cheap early pickup from deciding
## the tournament on its own.
class_name ShopRelic
extends RelicEffect

## Rules text for the equipment bar and the shop.
@export_multiline var summary: String = ""

@export_group("The shelf")
## More to choose between. One extra card is a real widening of the run: the
## shop is the only place you can go looking for a specific thing.
@export var card_slots_delta: int = 0
@export var relic_slots_delta: int = 0
## Cards on the shelf that are guaranteed not to be common. There is no rare card
## pool, so one uncommon is the best a shelf can be promised.
@export var guaranteed_uncommons: int = 0

@export_group("The price")
## Multiplied into every asking price. 0.75 is a quarter off; above one is a
## markup, for equipment that gives with one hand.
@export var price_scale: float = 1.0
## Clubs you may leave at home for nothing on each visit. Removal is how a deck
## gets *better* rather than bigger, and charging for it is the main thing
## standing between a player and a tidy bag.
@export var free_removals: int = 0


func describe() -> String:
	return summary


func modify_shop(stock: ShopStock, _ctx: RelicContext) -> void:
	stock.card_slots += card_slots_delta
	stock.relic_slots += relic_slots_delta
	stock.guaranteed_uncommons += guaranteed_uncommons
	stock.price_scale *= maxf(price_scale, 0.0)
	stock.free_removals += free_removals
