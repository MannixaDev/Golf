## Checks the rules that govern what ends up in your hand.
##
## These came out of a playtest rather than a spec: a hand that silently filled
## with spare putters, and long holes that opened with nothing long enough to
## play. Both are the sort of thing that only shows up when a person plays, and
## both are easy to regress, so they are asserted here.
extends SceneTree

const HAND_SIZE := 5
const OPENING_HANDS := 200

var failures := 0
var screen: HoleScreen = null


func _initialize() -> void:
	_trace_piles()
	_check_duplicate_cap()
	_check_club_cap()
	_check_you_cannot_lose_the_short_game()

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


# --- Pile counts ----------------------------------------------------------

func _trace_piles() -> void:
	var list: DeckList = load("res://resources/decks/starting_deck.tres")
	var deck := Deck.new(list.build())
	deck.reset_for_hole()
	print("=== piles, stroke by stroke (%d card bag) ===" % deck.total_cards())

	for stroke in range(1, 7):
		deck.draw_up_to(HAND_SIZE)
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
		deck.draw_up_to(6)
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
			deck.draw_up_to(HAND_SIZE)
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
	deck.draw_up_to(HAND_SIZE)
	var distinct: Dictionary = {}
	for card in deck.cards:
		distinct[card.id] = true
	var expected := mini(HAND_SIZE, distinct.size())
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
