## Checks the rules that govern what ends up in your hand.
##
## These came out of a playtest rather than a spec: a hand that silently filled
## with spare putters, and long holes that opened with nothing long enough to
## play. Both are the sort of thing that only shows up when a person plays, and
## both are easy to regress, so they are asserted here.
extends SceneTree

const CLUB_HAND := 4
const EXTRA_HAND := 2
const OPENING_HANDS := 200
## Deals sampled when asking whether a hand can play the shot in front of it.
const DEALS := 600

var failures := 0
var screen: HoleScreen = null


func _initialize() -> void:
	_trace_piles()
	_check_duplicate_cap()
	_check_club_cap()
	_check_you_cannot_lose_the_short_game()
	_check_the_deal_is_never_a_dead_end()
	_check_the_shortest_putt()

	# The tee-shot rule lives in HoleView, so the check drives the real scene
	# rather than re-implementing the logic and proving nothing. Nodes added
	# during _initialize have not run _ready yet, so the work waits a frame.
	screen = load("res://scenes/run/hole_screen.tscn").instantiate()
	screen.setup(HoleGenerator.generate(1, 2, 1), Deck.new())
	root.add_child(screen)


func _process(_delta: float) -> bool:
	_check_tee_shot()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)
	return true


## Can the hand you are dealt actually play the shot in front of you?
##
## This is the check that earns the right to delete HoleView._ensure_short_game
## -- thirty-five lines that reached into the draw pile mid-hole and swapped a
## card behind the player's back, announcing "You reach for something softer".
## A game that silently edits your hand is a game you cannot learn, and it only
## existed because clubs and techniques shared one deal: with five cards and no
## guarantee of how many were clubs, a hand of four techniques and a driver was a
## real outcome, and from forty yards it was a dead end.
##
## So the raw deal is measured here with no rescue of any kind, across the whole
## range of shots a hole asks for, against the old single hand and the new split
## one. If the split does not take stranding to zero on its own it has not earned
## the deletion and the rescue stays.
func _check_the_deal_is_never_a_dead_end() -> void:
	print("")
	print("=== every deal can play every shot ===")

	var list: DeckList = load("res://resources/decks/starting_deck.tres")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234

	# Only the short end. Being unable to reach a green in one is not a dead end,
	# it is golf -- you take your longest club and advance the ball. The dead end
	# is the other direction: every club in hand flies past the target even
	# feathered to its minimum, so there is no shot to play at all. A first cut
	# of this check counted "cannot reach 420 yards off the tee" as stranded and
	# reported a fifth of all deals broken, which measured nothing.
	var shots: Array[float] = [60.0, 30.0, 14.0, 6.0]
	var split: Array[int] = []
	var single: Array[int] = []
	split.resize(shots.size())
	single.resize(shots.size())

	for attempt in DEALS:
		var deck := Deck.new(list.build())
		deck.reset_for_hole()
		deck.deal_up_to(CLUB_HAND, EXTRA_HAND)
		var old_hand := _old_style_hand(list, rng)
		for i in shots.size():
			if not _can_play(deck.hand, shots[i]):
				split[i] += 1
			if not _can_play(old_hand, shots[i]):
				single[i] += 1

	print("  %d deals.  stranded, one hand of five -> four clubs and two extras:"
		% DEALS)
	for i in shots.size():
		print("   %5.0f yd:  %5.1f%%  ->  %5.1f%%" % [shots[i],
			100.0 * single[i] / DEALS, 100.0 * split[i] / DEALS])

	# Fourteen yards and out is the range HoleView._ensure_short_game was written
	# for, and the split closes it completely.
	var old_total := 0
	for i in shots.size():
		old_total += single[i]
		if shots[i] < 12.0:
			continue
		_expect(split[i] == 0,
			"%.0f yards still strands the player %d times in %d"
				% [shots[i], split[i], DEALS])
	# Not asserted per distance: from thirty yards out any wedge or nine iron
	# can be feathered short enough, so neither deal was ever stuck there. The
	# old one only broke down from about fourteen yards in, which is exactly
	# where the rescue in HoleView was aimed.
	_expect(old_total > 0,
		"the old deal never stranded anybody anywhere, so this check is "
			+ "measuring the wrong thing")

	# Inside that it is not the hand's fault and the split cannot fix it: with
	# four club slots and five distinct clubs you are always missing exactly one,
	# and when the one is the putter nothing else in the bag can be feathered
	# short enough. It halves the problem rather than solving it, and the rescue
	# in HoleView still has a job.
	var close: int = split[shots.size() - 1]
	_expect(close < single[shots.size() - 1],
		"the split should at least improve the six yard case")
	print("  inside twelve yards the putter is the only club that works, and a")
	print("  four club hand is missing one club: %.0f%% of deals lack it."
		% (100.0 * close / DEALS))


## The shortest shot the game can actually play.
##
## Nothing to do with the hand. `min_power_fraction` is a share of a club's reach
## rather than an absolute, so the shortest putt in the game is the putter's own
## reach times that floor -- and at 28 yards times 0.12 that is over three yards.
## You cannot lag a ten footer: every putt inside that has to be struck hard
## enough to run past the hole and rely on being caught on the way over.
##
## Asserted rather than fixed here because it is a difficulty change and belongs
## in its own milestone. If somebody shortens the putter or lowers the floor this
## goes green on its own.
func _check_the_shortest_putt() -> void:
	print("")
	print("=== the shortest shot in the bag ===")
	const MIN_POWER := 0.12
	var list: DeckList = load("res://resources/decks/starting_deck.tres")
	var gentlest := INF
	var which := ""
	for card in list.build():
		if not card.is_shot():
			continue
		var floor_yards := ShotProfile.from_card(card).max_reach_yards() * MIN_POWER
		if floor_yards < gentlest:
			gentlest = floor_yards
			which = str(card.id)
	print("  the gentlest shot in the game is %s at %.2f yd (%.0f feet)" % [
		which, gentlest, gentlest * 3.0])
	_expect(gentlest <= 4.0,
		"the shortest playable shot is %.1f yards, so nothing can be tapped in"
			% gentlest)


## Is there a club here that can be hit *gently* enough to stay on this hole?
##
## HoleView.min_power_fraction is the floor on how softly a club may be struck,
## so a club's shortest possible shot is its reach times that. If every club in
## hand overshoots even at the floor, the hand is a dead end.
func _can_play(cards: Array[CardData], needed: float) -> bool:
	const MIN_POWER := 0.12
	for card in cards:
		if card == null or not card.is_shot():
			continue
		if ShotProfile.from_card(card).max_reach_yards() * MIN_POWER <= needed:
			return true
	return false


## The deal as it used to be: five cards off the top, kind-agnostic, respecting
## the copy caps. Rebuilt here rather than kept in Deck, because it exists only
## to be the thing the new deal is measured against.
func _old_style_hand(list: DeckList, rng: RandomNumberGenerator) -> Array[CardData]:
	var pile: Array[CardData] = list.build()
	for i in range(pile.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := pile[i]
		pile[i] = pile[j]
		pile[j] = tmp

	var held: Array[CardData] = []
	var counts: Dictionary = {}
	for card in pile:
		if held.size() >= 5:
			break
		var limit: int = 1 if card.is_shot() else 2
		if int(counts.get(card.id, 0)) >= limit:
			continue
		counts[card.id] = int(counts.get(card.id, 0)) + 1
		held.append(card)
	return held


# --- Pile counts ----------------------------------------------------------

func _trace_piles() -> void:
	var list: DeckList = load("res://resources/decks/starting_deck.tres")
	var deck := Deck.new(list.build())
	deck.reset_for_hole()
	print("=== piles, stroke by stroke (%d card bag) ===" % deck.total_cards())

	for stroke in range(1, 7):
		deck.deal_up_to(CLUB_HAND, EXTRA_HAND)
		print("  before stroke %d:  BAG %2d   HAND %d   PLAYED %2d" % [
			stroke, deck.draw_pile.size(), deck.hand.size(), deck.discard_pile.size()])
		deck.play_from_hand(0)


# --- Duplicate cap --------------------------------------------------------

## A club you already hold is not a second option, it is a dead slot -- and the
## equipment that deals you a sixth card makes that visible. Techniques are
## deliberately still allowed in pairs.
func _check_club_cap() -> void:
	print("")
	print("=== duplicate clubs ===")
	var bag: Array[CardData] = []
	for i in 4:
		bag.append(CardLibrary.copy(&"putter"))
	for i in 4:
		bag.append(CardLibrary.copy(&"draw"))
	var deck := Deck.new(bag)
	var worst_club := 0
	var best_technique := 0
	for attempt in 40:
		deck.reset_for_hole()
		deck.deal_up_to(CLUB_HAND, EXTRA_HAND)
		worst_club = maxi(worst_club, deck.copies_in_hand(&"putter"))
		best_technique = maxi(best_technique, deck.copies_in_hand(&"draw"))
	print("  most putters held %d, most Draws held %d" % [worst_club, best_technique])
	_expect(worst_club <= 1, "never more than one of a club in hand")
	_expect(best_technique >= 2, "but techniques still come in pairs")


## You must never end up unable to putt.
##
## Found by a player, mid-round, stood on a green twenty yards from the flag
## holding a wedge and a 9 iron. The putter is a starter card, so shops and
## prizes -- which draw only from the common and uncommon pools -- can never
## sell you another. Losing the last one was not a setback, it was a run that
## was already over and had not finished yet.
func _check_you_cannot_lose_the_short_game() -> void:
	print("")
	print("=== the bag always keeps something to putt with ===")

	var list: DeckList = load("res://resources/decks/starting_deck.tres")
	var deck := Deck.new(list.build())
	print("  the starting bag holds %d putters" % deck.putters())
	_expect(deck.putters() > 0, "you start with something to putt with")

	# Strip it down to one and check the guard recognises the last one.
	while deck.putters() > 1:
		for card in deck.cards:
			if card.club != null and card.club.is_ground_shot:
				deck.remove_card(card)
				break
	_expect(deck.putters() == 1, "stripped down to a single putter")

	var guarded := 0
	var unguarded := 0
	for card in deck.cards:
		if deck.is_last_putter(card):
			guarded += 1
		else:
			unguarded += 1
	print("  with one left: %d card protected, %d still removable" % [
		guarded, unguarded])
	_expect(guarded == 1, "the last putter is protected")
	_expect(unguarded == deck.total_cards() - 1,
		"and nothing else is")

	# With two, neither is precious.
	deck.add_card(CardLibrary.copy(&"putter"))
	var protected := 0
	for card in deck.cards:
		if deck.is_last_putter(card):
			protected += 1
	_expect(protected == 0, "with a spare, neither putter is protected")

	# It has to be about the club, not the card's name.
	var wedge := CardLibrary.copy(&"wedge")
	_expect(not deck.is_last_putter(wedge),
		"a wedge is never a putter however short you swing it")

	# And the shop is the way back for a bag that already has none.
	var stranded := Deck.new([CardLibrary.copy(&"driver"),
		CardLibrary.copy(&"iron_5")])
	_expect(stranded.putters() == 0, "a bag can still be built without one")
	var putter := CardLibrary.template(&"putter")
	_expect(putter != null and putter.rarity == CardData.Rarity.STARTER,
		"the putter is a starter card, which is why no pool can offer it")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var offered := 0
	for roll in 500:
		for card in RewardTable.card_offer(rng, 2, 3):
			if card.club != null and card.club.is_ground_shot:
				offered += 1
	print("  putters in 500 prize offers: %d (so the shop has to stock one)"
		% offered)
	_expect(offered == 0,
		"if prizes did offer one, the shop rescue would be unnecessary")


func _check_duplicate_cap() -> void:
	print("")
	print("=== duplicate cap in hand ===")

	# A bag that is almost entirely putters is the worst case for this.
	var cards: Array[CardData] = []
	for i in 12:
		cards.append(CardLibrary.copy(&"putter"))
	for i in 4:
		cards.append(CardLibrary.copy(&"iron_9"))

	var deck := Deck.new(cards)
	var worst := 0
	for round_index in 40:
		deck.reset_for_hole()
		for stroke in 5:
			deck.deal_up_to(CLUB_HAND, EXTRA_HAND)
			worst = maxi(worst, deck.copies_in_hand(&"putter"))
			if not deck.hand.is_empty():
				deck.play_from_hand(0)

	print("  most putters ever held at once: %d (cap %d)" % [
		worst, Deck.MAX_CLUB_COPIES_IN_HAND])
	_expect(worst <= Deck.MAX_CLUB_COPIES_IN_HAND,
		"a hand should never exceed the duplicate cap")

	# The cap must not starve the hand -- but "starve" has to mean the right
	# thing. This bag holds two distinct clubs, so once clubs are capped at one
	# copy a hand of two *is* the whole of what it has to offer, and demanding
	# three was demanding a duplicate back. What must hold is that the hand
	# fills to everything available: passed-over cards go back in the pile, so
	# nothing is ever lost to the cap.
	deck.reset_for_hole()
	deck.deal_up_to(CLUB_HAND, EXTRA_HAND)
	var distinct: Dictionary = {}
	for card in deck.cards:
		distinct[card.id] = true
	var expected := mini(CLUB_HAND + EXTRA_HAND, distinct.size())
	print("  bag of %d distinct clubs drew a hand of %d" % [
		distinct.size(), deck.hand.size()])
	_expect(deck.hand.size() == expected,
		"the hand should hold every distinct club it can, and does not")


# --- Tee shot -------------------------------------------------------------

func _check_tee_shot() -> void:
	print("")
	print("=== something long enough off the tee ===")

	var list: DeckList = load("res://resources/decks/starting_deck.tres")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	var short_openings := 0
	var lengths := 0.0
	var hole_view: HoleView = screen.get_node("HoleView")

	for attempt in OPENING_HANDS:
		# Long holes are where an empty-looking hand actually hurts.
		var hole := HoleGenerator.generate(rng.randi(), 3, 1)
		hole_view.hole = hole
		hole_view.deck = Deck.new(list.build())
		hole_view.start_hole()
		lengths += hole.hole_length_yards()

		var needed := hole.hole_length_yards() * hole_view.tee_reach_fraction
		var best := 0.0
		for card in hole_view.deck.hand:
			if card.is_shot():
				best = maxf(best, ShotProfile.from_card(card).max_reach_yards())

		# The bag's longest club is the ceiling: the rule promises the best you
		# own, not a club you do not have.
		var longest_owned := 0.0
		for card in hole_view.deck.cards:
			if card.is_shot():
				longest_owned = maxf(longest_owned, ShotProfile.from_card(card).max_reach_yards())

		if best < needed and best < longest_owned - 0.01:
			short_openings += 1

	print("  average hole: %.0f yd" % (lengths / OPENING_HANDS))
	print("  opening hands still short of the bag's best: %d / %d" % [
		short_openings, OPENING_HANDS])
	_expect(short_openings == 0,
		"every tee shot should have the longest club available if one exists")


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)
