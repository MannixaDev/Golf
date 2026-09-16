## A deck as a flat list of card ids, with repeats.
##
## Authored as a .tres so starting decks (and later, boss-specific or event decks)
## are content rather than code.
class_name DeckList
extends Resource

@export var display_name: String = "Deck"
## One line on the picker, in the golfer's own terms rather than the game's.
## "Never been past two-fifty" says more about how a bag plays than a list of
## clubs does, and the list is right underneath it anyway.
@export_multiline var blurb: String = ""
## Order on the picker. The bag somebody should take first comes first.
@export var billing: int = 0
## One entry per physical card. Repeat an id to include several copies.
@export var card_ids: PackedStringArray = PackedStringArray()


## Clubs in this bag, longest first. The picker shows these because what a bag
## can and cannot reach is most of what makes it a different run.
func clubs() -> Array[CardData]:
	var found: Array[CardData] = []
	var seen: Dictionary = {}
	for id in card_ids:
		var card := CardLibrary.template(StringName(id))
		if card == null or not card.is_shot() or seen.has(card.id):
			continue
		seen[card.id] = true
		found.append(card)
	found.sort_custom(func(a: CardData, b: CardData) -> bool:
		return ShotProfile.from_card(a).max_reach_yards() 			> ShotProfile.from_card(b).max_reach_yards())
	return found


## Furthest this bag can hit a ball, before anything is bought.
func longest_yards() -> float:
	var best := 0.0
	for card in clubs():
		best = maxf(best, ShotProfile.from_card(card).max_reach_yards())
	return best


## Fresh, independent CardData instances. Each copy can be upgraded separately.
func build() -> Array[CardData]:
	var cards: Array[CardData] = []
	for id in card_ids:
		var card := CardLibrary.copy(StringName(id))
		if card != null:
			cards.append(card)
	return cards
