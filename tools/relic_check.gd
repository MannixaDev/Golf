## Asserts that equipment does what its rules text claims, and that the reward
## table pays out sensibly.
##
## Relics are conditional, which is exactly the sort of thing that silently stops
## firing after an unrelated change, so each condition is exercised directly.
extends SceneTree

var failures := 0
## Chosen so the opening hand holds both techniques. Anything that changes how
## a hand is dealt will trip the checks below rather than silently skipping them.
const SHUFFLE_SEED := 1
var _screen: HoleScreen
## Caught out of a signal, so it has to outlive the lambda that sets it.
var _read := Vector2.ZERO
var _note := ""


func _initialize() -> void:
	_check_relics_load()
	_check_conditions()
	_check_lie_resistance()
	_check_rescue()
	_check_rewards()
	_check_scoring()
	_check_every_class_is_used()

	# The bag checks drive the real hole, because what is under test is whether
	# a relic reaches the hand you are actually dealt -- re-deriving that in here
	# would prove only that this file can add one to five.
	_screen = load("res://scenes/run/hole_screen.tscn").instantiate()
	# A bag chosen rather than the starting one. Dealt from the real deck this
	# check kept reading whatever it happened to draw, and a second support card
	# that turns out to be a Mulligan with nothing to undo rejects itself and
	# spends no focus -- which looks exactly like the free allowance never running
	# out. Draw and Fade are plain profile tweaks and cannot refuse.
	var bag: Array[CardData] = [CardLibrary.copy(&"draw"), CardLibrary.copy(&"fade"),
		CardLibrary.copy(&"driver"), CardLibrary.copy(&"iron_5"),
		CardLibrary.copy(&"iron_9"), CardLibrary.copy(&"wedge"),
		CardLibrary.copy(&"wood_3"), CardLibrary.copy(&"putter")]
	var deck := Deck.new(bag)
	# Eight cards so a hand of six is a real deal rather than the whole bag, and a
	# pinned shuffle so which six is not a coin toss.
	deck._rng.seed = SHUFFLE_SEED
	_screen.setup(HoleGenerator.generate(31337, 2, 1), deck)
	_screen.setup_run(_carrying([&"fourteenth_club", &"range_token",
		&"green_book", &"shot_tracer"]), 0)
	root.add_child(_screen)


func _process(_delta: float) -> bool:
	_check_the_bag()
	_check_insight()
	_check_the_shop()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)
	return true


# --- The shop -------------------------------------------------------------

## Equipment that acts on the run rather than on a stroke.
##
## None of this is visible to any other check: the shop is assembled in main.gd
## from a ShopStock, and a relic that quietly stopped changing it would look
## exactly like a relic that was working.
func _check_the_shop() -> void:
	print("")
	print("=== equipment that changes the shop ===")

	var base := _stock_with([])
	print("  with nothing: %d cards, %d kit, prices x%.2f, %d free removals"
		% [base.card_slots, base.relic_slots, base.price_scale, base.free_removals])
	_expect(base.price_of(100) == 100, "an empty bag should not move a price")
	_expect(base.removal_price(45, 0) == 45, "nor make a removal free")

	var cheap := _stock_with([&"members_card"])
	print("  members card: prices x%.2f, a 100 club costs %d"
		% [cheap.price_scale, cheap.price_of(100)])
	_expect(cheap.price_of(100) == 75, "the members card takes a quarter off")

	var key := _stock_with([&"locker_key"])
	print("  locker key: removals cost %d, %d, then %d"
		% [key.removal_price(45, 0), key.removal_price(45, 1),
			key.removal_price(45, 2)])
	_expect(key.removal_price(45, 0) == 0 and key.removal_price(45, 1) == 0,
		"the first two removals are free")
	_expect(key.removal_price(45, 2) == 45,
		"and the third is not -- a free removal every visit is not two of them")

	var trade := _stock_with([&"trade_account"])
	print("  trade account: %d cards, %d kit, a 100 club costs %d"
		% [trade.card_slots, trade.relic_slots, trade.price_of(100)])
	_expect(trade.card_slots == base.card_slots + 1
		and trade.relic_slots == base.relic_slots + 1,
		"the trade account widens the shelf")
	_expect(trade.price_of(100) > 100,
		"and charges for it, or it is simply better than carrying nothing")

	# The point of putting this in a ShopStock rather than in main.gd: two
	# relics that both touch the price have to compose, not fight.
	var both := _stock_with([&"members_card", &"trade_account"])
	print("  both together: %d cards, a 100 club costs %d (0.75 x 1.2)"
		% [both.card_slots, both.price_of(100)])
	_expect(both.card_slots == base.card_slots + 1,
		"the wider shelf survives the second relic")
	_expect(both.price_of(100) == 90,
		"the two price effects should multiply, and gave %d" % both.price_of(100))

	# A promised uncommon has to actually arrive, which is the one part of this
	# that goes through the card pools rather than through arithmetic.
	var nod := _stock_with([&"pros_nod"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var promised := 0
	var plain := 0
	for i in 60:
		promised += _uncommons(RewardTable.card_offer(rng, 2, nod.card_slots,
			nod.guaranteed_uncommons))
		plain += _uncommons(RewardTable.card_offer(rng, 2, base.card_slots, 0))
	print("  pro's nod: %.2f uncommons a shelf, against %.2f with nothing"
		% [promised / 60.0, plain / 60.0])
	_expect(promised >= 60 * nod.guaranteed_uncommons,
		"the shelf did not always hold what it promised")
	_expect(promised > plain, "and it should beat an ordinary shelf")

	# Nothing may make the shop free or empty, however much is stacked up.
	var piled := _stock_with([&"members_card", &"members_card", &"members_card",
		&"members_card", &"members_card"])
	print("  five members cards: prices x%.2f, a 100 club still costs %d"
		% [piled.price_scale, piled.price_of(100)])
	_expect(piled.price_of(100) >= 50,
		"stacked discounts got through the clamp: %d" % piled.price_of(100))


## The stock a bag of equipment would produce, built the same way main.gd does.
func _stock_with(ids: Array) -> ShopStock:
	var stock := ShopStock.new(3, 2)
	var ctx := RelicContext.new()
	for relic in _carrying(ids):
		for effect in relic.effects:
			if effect != null:
				effect.modify_shop(stock, ctx)
	return stock.clamped()


func _uncommons(cards: Array[CardData]) -> int:
	var count := 0
	for card in cards:
		if card.rarity == CardData.Rarity.UNCOMMON:
			count += 1
	return count


func _carrying(ids: Array) -> Array[RelicSpec]:
	var carried: Array[RelicSpec] = []
	for id in ids:
		var relic := RelicLibrary.by_id(id)
		if relic == null:
			_fail("no such equipment: %s" % id)
			continue
		carried.append(relic)
	return carried


# --- The bag --------------------------------------------------------------

## An extra club in hand is the most-felt thing a relic can do, and it only
## counts if it reaches the deal.
func _check_the_bag() -> void:
	print("")
	print("=== equipment that changes the turn ===")

	var view: HoleView = _screen.get_node("HoleView")
	_screen.begin()
	print("  dealt %d clubs and %d extras, %d focus (base %d, %d and %d)" % [
		view.deck.clubs_in_hand(), view.deck.extras_in_hand(), view.focus,
		view.club_hand, view.extra_hand, view.focus_max])
	_expect(view.deck.clubs_in_hand() == view.club_hand + 1,
		"the fourteenth slot deals one more club")
	_expect(view.deck.extras_in_hand() == view.extra_hand,
		"and leaves the techniques alone -- it is a club relic")
	_expect(view.focus == view.focus_max,
		"and leaves focus alone")

	# The free technique: played for nothing, and only the first one.
	var first := _slot(view, &"draw")
	var second := _slot(view, &"fade")
	if first < 0 or second < 0:
		_fail("the chosen bag did not reach the hand")
		return

	var cost: int = view.deck.hand[first].effective_cost()
	var before: int = view.focus
	view.activate_card(first)
	print("  Draw costs %d focus, spent %d" % [cost, before - view.focus])
	_expect(cost > 0, "the technique is not free to begin with")
	_expect(view.focus == before, "the range token pays for the first one")

	second = _slot(view, &"fade")
	var again: int = view.focus
	view.activate_card(second)
	print("  Fade then costs %d" % (again - view.focus))
	_expect(view.focus < again, "and only the first one")

	# The hand has to grey out on the price the stroke will really charge. A
	# technique the token is about to pay for must not be refused for focus it
	# was never going to spend.
	view.focus = 1
	for card in view.deck.hand:
		if card.is_shot():
			continue
		_expect(view.can_play(card) == (view._price_of(card) <= 0),
			"%s is offered on what it will actually cost" % card.title())
		break


func _slot(view: HoleView, id: StringName) -> int:
	for i in view.deck.hand.size():
		if view.deck.hand[i].id == id:
			return i
	return -1


# --- Insight --------------------------------------------------------------

func _check_insight() -> void:
	print("")
	print("=== equipment that tells you something ===")

	var view: HoleView = _screen.get_node("HoleView")
	_expect(view.has_insight(InsightRelic.GREEN_READ),
		"the green book is recognised")
	_expect(view.has_insight(InsightRelic.SHOT_SHAPE),
		"the shot tracer is recognised")

	# The ball is on the tee, so there is no slope under it at all. The book has
	# to produce the green's own fall, or it does nothing until you are putting
	# -- which is exactly when you no longer need it.
	# A member, not a local: GDScript lambdas capture locals by value, so a
	# result assigned inside one is never seen outside it and the check reads
	# zero however well the game is working.
	_read = Vector2.ZERO
	view.slope_changed.connect(func(fall: Vector2, note: String) -> void:
		_read = fall
		_note = note)
	view._emit_slope()
	print("  read from the tee: %.2f, %.2f  \"%s\"" % [_read.x, _read.y, _note])
	_expect(view.hole.slope_at(view._ball.position) == Vector2.ZERO,
		"there is genuinely no slope under the tee")
	_expect(_read != Vector2.ZERO,
		"the green book reads the green from back down the fairway")
	# The words and the arrow have to agree. They did not: the note was taken
	# from the pin to itself, which has no direction in it, so it read "Dead
	# flat" underneath an arrow pointing correctly downhill.
	_expect(not _note.begins_with("Dead flat"),
		"and says something other than dead flat while the arrow disagrees")


## Every effect class earns its keep, or it is a class nobody authored anything
## with. This is the check that would have caught six relics sharing two.
func _check_every_class_is_used() -> void:
	print("")
	print("=== effect classes in play ===")
	var seen: Dictionary = {}
	for relic in RelicLibrary.all():
		for effect in relic.effects:
			if effect == null:
				continue
			var kind: String = effect.get_script().resource_path.get_file()
			seen[kind] = int(seen.get(kind, 0)) + 1
	for kind in seen:
		print("  %-30s %d" % [kind, seen[kind]])
	_expect(seen.size() >= 5,
		"equipment should do more than a couple of different kinds of thing")


# --- Scoring --------------------------------------------------------------

func _check_scoring() -> void:
	print("")
	print("=== equipment that changes what a hole is worth ===")

	var sponsor := _reward_with(&"sponsors_bonus", 3, 4, 34)
	var plain := HoleReward.new(3, 4, 34)
	print("  birdie pays %d, %d with the sponsor" % [plain.winnings, sponsor.winnings])
	_expect(sponsor.winnings > plain.winnings, "a birdie pays more with the sponsor")
	_expect(_reward_with(&"sponsors_bonus", 5, 4, 15).winnings == 15,
		"and a bogey pays exactly as it always did")

	var ledger := _reward_with(&"sandbaggers_ledger", 6, 4, 9)
	print("  double bogey pays %d with the ledger (was 9)" % ledger.winnings)
	_expect(ledger.winnings > 9, "the ledger pays for dropped shots")
	_expect(_reward_with(&"sandbaggers_ledger", 3, 4, 34).strokes_back == 1,
		"and a birdie takes one back off the card")
	_expect(ledger.strokes_back == 0, "but a bad hole takes nothing back")


func _reward_with(relic_id: StringName, strokes: int, par: int,
		paid: int) -> HoleReward:
	var reward := HoleReward.new(strokes, par, paid)
	var ctx := RelicContext.new()
	ctx.strokes_taken = strokes
	ctx.par = par
	for effect in RelicLibrary.by_id(relic_id).effects:
		if effect != null:
			effect.on_hole_scored(reward, ctx)
	return reward


func _check_relics_load() -> void:
	var relics := RelicLibrary.all()
	print("=== equipment (%d) ===" % relics.size())
	for relic in relics:
		print("  %-22s %3d  %s" % [relic.display_name, relic.price, relic.effect_text()])
		_expect(not relic.effects.is_empty(), "%s should do something" % relic.display_name)
		for effect in relic.effects:
			_expect(effect != null, "%s has a null effect" % relic.display_name)
	_expect(relics.size() >= 5, "there should be a reasonable spread of equipment")


# --- Conditions -----------------------------------------------------------

func _base_profile() -> ShotProfile:
	return ShotProfile.from_card(CardLibrary.template(&"iron_5"))


func _spread_with(relic_id: StringName, ctx: RelicContext) -> float:
	var profile := _base_profile()
	for effect in RelicLibrary.by_id(relic_id).effects:
		effect.modify_profile(profile, ctx)
	return profile.dispersion_deg


func _context(stroke: int, over_par: int, lie_id: StringName) -> RelicContext:
	var ctx := RelicContext.new()
	ctx.stroke_number = stroke
	ctx.run_score_to_par = over_par
	ctx.lie = SurfaceLibrary.by_id(lie_id)
	return ctx


func _check_conditions() -> void:
	print("")
	print("=== conditions fire only when they should ===")
	var base := _base_profile().dispersion_deg

	# Lucky Glove: every third stroke.
	var third := _spread_with(&"lucky_glove", _context(3, 0, &"fairway"))
	var second := _spread_with(&"lucky_glove", _context(2, 0, &"fairway"))
	print("  lucky glove   stroke 2 %.2f, stroke 3 %.2f (base %.2f)" % [second, third, base])
	_expect(is_equal_approx(second, base), "the glove should do nothing on stroke 2")
	_expect(third < base, "the glove should help on stroke 3")

	# Rangefinder: unconditional.
	var always := _spread_with(&"rangefinder", _context(1, 0, &"fairway"))
	print("  rangefinder   %.2f (base %.2f)" % [always, base])
	_expect(always < base, "the rangefinder should always help")

	# Angry Caddie: only from a bad lie.
	var clean := _spread_with(&"angry_caddie", _context(1, 0, &"fairway"))
	var nasty := _spread_with(&"angry_caddie", _context(1, 0, &"deep_rough"))
	print("  angry caddie  fairway %.2f, deep rough %.2f" % [clean, nasty])
	_expect(is_equal_approx(clean, base), "the caddie should stay quiet from a good lie")
	_expect(nasty < base, "the caddie should help from a bad lie")

	# Dodgy Handicap: only when behind.
	var level := _spread_with(&"dodgy_handicap", _context(1, 0, &"fairway"))
	var behind := _spread_with(&"dodgy_handicap", _context(1, 4, &"fairway"))
	print("  dodgy handicap level %.2f, +4 %.2f" % [level, behind])
	_expect(is_equal_approx(level, base), "the handicap should do nothing while level")
	_expect(behind < base, "the handicap should help while over par")


# --- Lie resistance -------------------------------------------------------

func _check_lie_resistance() -> void:
	print("")
	print("=== resisting the ground ===")
	var rough := SurfaceLibrary.by_id(&"deep_rough")

	var plain := _base_profile()
	rough.apply_to(plain)

	var resisted := _base_profile()
	for effect in RelicLibrary.by_id(&"angry_caddie").effects:
		effect.modify_profile(resisted, _context(1, 0, &"deep_rough"))
	rough.apply_to(resisted)

	var sand_wedge := ShotProfile.from_card(CardLibrary.template(&"sand_wedge"))
	var sand_plain := ShotProfile.from_card(CardLibrary.template(&"sand_wedge"))
	sand_plain.lie_resistance = 0.0
	SurfaceLibrary.by_id(&"bunker").apply_to(sand_plain)
	SurfaceLibrary.by_id(&"bunker").apply_to(sand_wedge)

	print("  5 iron from deep rough: plain %.1f yd / spread %.2f" % [
		plain.carry_yards_max, plain.dispersion_deg])
	print("  ... with angry caddie:  %.1f yd / spread %.2f" % [
		resisted.carry_yards_max, resisted.dispersion_deg])
	_expect(resisted.carry_yards_max > plain.carry_yards_max,
		"resisting the lie should recover distance")

	print("  sand wedge from sand:   %.1f yd (no resistance %.1f yd)" % [
		sand_wedge.carry_yards_max, sand_plain.carry_yards_max])
	_expect(sand_wedge.carry_yards_max > sand_plain.carry_yards_max,
		"the sand wedge should barely notice sand")


# --- Rescue ---------------------------------------------------------------

func _check_rescue() -> void:
	print("")
	print("=== sleeve of new balls ===")
	var relic := RelicLibrary.by_id(&"new_balls")

	var first := RelicContext.new()
	first.recoveries_used = 0
	var second := RelicContext.new()
	second.recoveries_used = 1

	var saved_first := false
	var saved_second := false
	for effect in relic.effects:
		saved_first = saved_first or effect.try_rescue_ball(first)
		saved_second = saved_second or effect.try_rescue_ball(second)

	print("  first ball lost: saved %s, second: saved %s" % [saved_first, saved_second])
	_expect(saved_first, "the first lost ball should be free")
	_expect(not saved_second, "the second should cost you")


# --- Rewards --------------------------------------------------------------

func _check_rewards() -> void:
	print("")
	print("=== payouts ===")
	var previous := 9999
	for over in range(-2, 4):
		var paid := RewardTable.winnings_for(4 + over, 4, 1)
		print("  %-14s %3d" % [RunState.score_name(4 + over, 4), paid])
		_expect(paid < previous, "a worse score should never pay more")
		previous = paid

	var easy := RewardTable.winnings_for(4, 4, 1)
	var hard := RewardTable.winnings_for(4, 4, 3)
	print("  par on an ordinary hole %d, on a championship hole %d" % [easy, hard])
	_expect(hard > easy, "harder stops should pay more")

	print("")
	print("=== card offers ===")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var starters := 0
	for i in 40:
		var offer := RewardTable.card_offer(rng, 2)
		_expect(offer.size() == RewardTable.CARD_CHOICES,
			"an offer should always have %d cards" % RewardTable.CARD_CHOICES)
		var seen: Dictionary = {}
		for card in offer:
			_expect(not seen.has(card.id), "an offer should not repeat a card")
			seen[card.id] = true
			if card.rarity == CardData.Rarity.STARTER:
				starters += 1
		if i == 0:
			var names: PackedStringArray = PackedStringArray()
			for card in offer:
				names.append(card.title())
			print("  example offer: " + ", ".join(names))
	_expect(starters == 0, "starter cards should never be offered as a prize")
	print("  40 offers, no duplicates within an offer, no starter cards")


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)


func _fail(what: String) -> void:
	failures += 1
	print("  FAIL: %s" % what)
