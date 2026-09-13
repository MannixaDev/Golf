## A deck as a flat list of card ids, with repeats.
##
## Authored as a .tres so starting decks (and later, boss-specific or event decks)
## are content rather than code.
class_name DeckList
extends Resource

@export var display_name: String = "Deck"
## One entry per physical card. Repeat an id to include several copies.
@export var card_ids: PackedStringArray = PackedStringArray()


## Fresh, independent CardData instances. Each copy can be upgraded separately.
func build() -> Array[CardData]:
	var cards: Array[CardData] = []
	for id in card_ids:
		var card := CardLibrary.copy(StringName(id))
		if card != null:
			cards.append(card)
	return cards
