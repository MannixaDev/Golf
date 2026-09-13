## What a hole pays out, and what it offers you afterwards.
##
## Kept in one place so the prize for a birdie is a single number to argue with
## rather than something scattered across three screens.
class_name RewardTable
extends RefCounted

## Winnings by score against par, best first. Index 0 is eagle or better.
const BY_SCORE := [46, 34, 24, 15, 9, 5]
## Harder stops pay more, so taking the difficult route is worth something.
const DIFFICULTY_BONUS := 0.28

## Cards offered after a hole.
const CARD_CHOICES := 3
## Chance an offered card is uncommon rather than common, before difficulty.
const UNCOMMON_CHANCE := 0.34


static func winnings_for(strokes: int, par: int, difficulty: int) -> int:
	var over := strokes - par
	var index := clampi(over + 2, 0, BY_SCORE.size() - 1)
	var base: int = BY_SCORE[index]
	return int(round(base * (1.0 + DIFFICULTY_BONUS * maxi(difficulty - 1, 0))))


## Distinct cards to choose between after a hole. Never offers the same card
## twice in one set, because picking between two identical cards is not a choice.
static func card_offer(rng: RandomNumberGenerator, difficulty: int,
		count: int = CARD_CHOICES) -> Array[CardData]:
	var common := _pool(CardData.Rarity.COMMON)
	var uncommon := _pool(CardData.Rarity.UNCOMMON)
	var chance := clampf(UNCOMMON_CHANCE + 0.08 * maxi(difficulty - 1, 0), 0.0, 0.8)

	var offer: Array[CardData] = []
	var taken: Dictionary = {}
	var guard := 0
	while offer.size() < count and guard < 200:
		guard += 1
		var pool := uncommon if (rng.randf() < chance and not uncommon.is_empty()) else common
		if pool.is_empty():
			pool = common if not common.is_empty() else uncommon
		if pool.is_empty():
			break
		var pick: CardData = pool[rng.randi_range(0, pool.size() - 1)]
		if taken.has(pick.id):
			continue
		taken[pick.id] = true
		# A fresh instance: the player owns this copy and may upgrade it alone.
		offer.append(CardLibrary.copy(pick.id))
	return offer


## Starter cards are what you begin with, so they are never offered as a prize.
static func _pool(rarity: int) -> Array[CardData]:
	var pool: Array[CardData] = []
	for id in CardLibrary.all_ids():
		var card := CardLibrary.template(id)
		if card != null and card.rarity == rarity:
			pool.append(card)
	return pool


## Rough guide shown on the results panel, so the payout is not a mystery.
static func describe_payout(strokes: int, par: int) -> String:
	return "%s — %s" % [RunState.score_name(strokes, par),
		"well played" if strokes <= par else "it happens"]
