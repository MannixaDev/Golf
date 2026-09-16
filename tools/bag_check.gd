## Is every bag a run can start from actually playable?
##
## A starting bag is the one piece of content nobody can route around. A bad card
## sits in your deck and gets ignored; a bad bag is nine holes you cannot win and
## no way to find out until you have played them.
##
## So each is asked the questions the game will ask it: can it reach a long hole,
## can it get down from twenty yards, does it hold a putter at all, and does it
## fill a hand of four clubs and two techniques without gaps.
extends SceneTree

## What the split hand deals.
const CLUB_HAND := 4
const EXTRA_HAND := 2
## HoleView.min_power_fraction: the floor on how gently a club may be struck.
const MIN_POWER := 0.12
## A long par four. A bag that cannot get near this in two is not a style, it is
## a bag that loses.
const LONG_HOLE_YARDS := 400.0

var failures := 0


func _initialize() -> void:
	var bags := DeckLibrary.all()
	print("=== %d bags ===" % bags.size())
	_expect(bags.size() >= 2,
		"only %d bag, so the picker is a menu of one" % bags.size())

	for bag in bags:
		_check_bag(bag)
	_check_they_are_actually_different(bags)

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


func _check_bag(bag: DeckList) -> void:
	print("")
	print("--- %s ---" % bag.display_name)
	var cards := bag.build()
	var clubs := 0
	var extras := 0
	var putters := 0
	var shortest := INF
	for card in cards:
		if card.is_shot():
			clubs += 1
			shortest = minf(shortest,
				ShotProfile.from_card(card).max_reach_yards() * MIN_POWER)
			if card.club != null and card.club.is_ground_shot:
				putters += 1
		else:
			extras += 1

	print("  %d cards: %d clubs (%d putters), %d techniques" % [
		cards.size(), clubs, putters, extras])
	print("  longest %d yd, gentlest shot %.1f yd" % [
		int(bag.longest_yards()), shortest])

	_expect(bag.display_name.strip_edges() != "", "a bag with no name")
	_expect(bag.blurb.strip_edges() != "",
		"%s says nothing about itself on the picker" % bag.display_name)
	_expect(putters >= 1,
		"%s cannot putt, and nothing in the shop sells one" % bag.display_name)
	_expect(bag.longest_yards() * 2.0 >= LONG_HOLE_YARDS,
		"%s cannot reach a %d yard hole in two: %d yards is its best"
			% [bag.display_name, int(LONG_HOLE_YARDS), int(bag.longest_yards())])
	_expect(shortest <= 6.0,
		"%s has nothing to chip with: its gentlest shot is %.1f yards"
			% [bag.display_name, shortest])
	_expect(extras >= 1,
		"%s holds no techniques, so half its hand is always empty"
			% bag.display_name)

	# The hand has to fill. A bag with three distinct clubs leaves a slot blank
	# every single deal, which reads as a bug rather than as a style.
	var deck := Deck.new(bag.build())
	deck.shuffle_from(4242)
	var worst_clubs := 99
	var worst_extras := 99
	for attempt in 40:
		deck.reset_for_hole()
		deck.deal_up_to(CLUB_HAND, EXTRA_HAND)
		worst_clubs = mini(worst_clubs, deck.clubs_in_hand())
		worst_extras = mini(worst_extras, deck.extras_in_hand())
	print("  worst deal: %d clubs, %d techniques" % [worst_clubs, worst_extras])
	_expect(worst_clubs >= CLUB_HAND,
		"%s deals only %d clubs into a hand of %d"
			% [bag.display_name, worst_clubs, CLUB_HAND])
	_expect(worst_extras >= 1,
		"%s can deal a hand with no technique in it at all" % bag.display_name)


## They have to be different from each other, or it is one bag with four names.
func _check_they_are_actually_different(bags: Array) -> void:
	print("")
	print("=== and they are different bags ===")
	var longest: Array[float] = []
	var shapes: Array[String] = []
	for bag in bags:
		longest.append(bag.longest_yards())
		var clubs := 0
		for id in bag.card_ids:
			var card := CardLibrary.template(StringName(id))
			if card != null and card.is_shot():
				clubs += 1
		var mix := "%d/%d" % [clubs, bag.card_ids.size() - clubs]
		shapes.append(mix)
		print("  %-20s longest %3d yd, clubs to techniques %s" % [
			bag.display_name, int(bag.longest_yards()), mix])

	var spread: float = longest.max() - longest.min()
	_expect(spread >= 40.0,
		"every bag hits it the same distance (%d yards between longest and "
			% int(spread) + "shortest), so they are not really different runs")
	var distinct: Dictionary = {}
	for mix in shapes:
		distinct[mix] = true
	_expect(distinct.size() >= 3,
		"only %d different club-to-technique mixes across %d bags"
			% [distinct.size(), bags.size()])


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)
