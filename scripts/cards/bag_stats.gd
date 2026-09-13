## What the bag looks like, counted.
##
## Exists so a card can care about the company it keeps. Until now every card in
## the game was worth exactly the same whatever else you were carrying, which is
## the difference between a pile of good cards and a build: nothing rewarded you
## for going in a direction, so there was no direction to go in.
##
## Counted fresh for each stroke rather than cached. A bag changes at a shop, a
## clubhouse and a workshop, and a stale count is a card that lies about itself.
class_name BagStats
extends RefCounted

var cards: int = 0
var clubs: int = 0
var techniques: int = 0
var upgraded: int = 0
## Clubs by ClubSpec.Family, so a card can ask for irons without knowing names.
var families: Dictionary = {}


static func of(bag: Array) -> BagStats:
	var stats := BagStats.new()
	for card in bag:
		if card == null or not (card is CardData):
			continue
		stats.cards += 1
		if card.upgraded:
			stats.upgraded += 1
		if card.is_shot():
			stats.clubs += 1
			if card.club != null:
				var family: int = card.club.family
				stats.families[family] = int(stats.families.get(family, 0)) + 1
		else:
			stats.techniques += 1
	return stats


func of_family(family: int) -> int:
	return int(families.get(family, 0))
