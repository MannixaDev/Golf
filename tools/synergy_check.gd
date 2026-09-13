## Do the bag-aware cards actually reward a direction?
##
## A synergy card has two ways to be pointless and a harness can catch both. It
## can be so flat that building towards it is indistinguishable from ignoring it
## -- a card nobody notices is a card nobody plans around. Or it can be so steep
## that the run is decided the moment you draft it, which is worse: the choice
## stops being a choice.
##
## So this builds the bags a real player would end up with and measures what the
## card is worth in each, rather than asserting the arithmetic works.
extends SceneTree

## Cards the synergy pool is meant to contain. Named rather than discovered, so
## deleting one is a failure here instead of a silently smaller check.
const SYNERGY_CARDS := [&"travel_light", &"matched_set", &"muscle_memory",
	&"big_hitter"]
## A card should be worth at least this much more in the bag it is built for.
const MIN_PAYOFF := 0.12
## And at most this much, or drafting it settles the run.
const MAX_PAYOFF := 0.85

var failures := 0


func _initialize() -> void:
	CardLibrary.ensure_loaded()

	_check_they_all_exist()
	_check_each_one_pays_off()
	_check_the_floor_is_honest()
	_check_the_ceiling_is_reachable()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


func _check_they_all_exist() -> void:
	print("=== the synergy pool ===")
	for id in SYNERGY_CARDS:
		var card := CardLibrary.template(id)
		if card == null:
			_fail("'%s' is gone" % id)
			continue
		var effect := _synergy_in(card)
		if effect == null:
			_fail("'%s' has no synergy effect on it" % id)
			continue
		print("  %-16s pivot %d%s, up to %d steps  %s" % [
			id, effect.pivot, " and down" if effect.fewer_is_better else "",
			effect.max_steps, effect.summary])
		_expect(effect.max_steps > 0 and effect.max_steps <= 6,
			"%s should cap somewhere sensible" % id)


## The measurement that matters: play the same stroke with the same card out of
## a bag that suits it and a bag that does not, and see whether it noticed.
func _check_each_one_pays_off() -> void:
	print("")
	print("=== is building towards one worth doing ===")

	for id in SYNERGY_CARDS:
		var card := CardLibrary.template(id)
		if card == null:
			continue
		var effect := _synergy_in(card)
		if effect == null:
			continue

		var empty := _shot_with(card, BagStats.new())
		var full := _shot_with(card, _bag_suiting(effect))
		var gain := _quality(full) / maxf(_quality(empty), 0.0001) - 1.0
		print("  %-16s %+.0f%% better in the bag it wants (%.0f yd / %.2f deg"
			% [id, gain * 100.0, full.carry_yards_max, full.dispersion_deg]
			+ "  against %.0f / %.2f)" % [empty.carry_yards_max, empty.dispersion_deg])
		_expect(gain >= MIN_PAYOFF,
			"%s barely notices the bag it was built for" % id)
		_expect(gain <= MAX_PAYOFF,
			"%s decides the run on its own" % id)


## A synergy card in a shop has no bag to read, and it must not quietly behave
## as though it had a perfect one. The floor is what it prints on its face.
func _check_the_floor_is_honest() -> void:
	print("")
	print("=== what it is worth with nothing behind it ===")
	for id in SYNERGY_CARDS:
		var card := CardLibrary.template(id)
		if card == null:
			continue
		var effect := _synergy_in(card)
		var bare := ShotProfile.from_card(CardLibrary.copy(&"iron_5"))
		var before := bare.dispersion_deg
		var before_carry := bare.carry_yards_max
		bare.apply_effects([effect])
		_expect(is_equal_approx(bare.dispersion_deg, before)
				and is_equal_approx(bare.carry_yards_max, before_carry),
			"%s should do nothing at all with no bag to read" % id)
	print("  all four sit at their floor with no bag, as the card face claims")


## The top of the ladder has to be somewhere a real run can get to. A card that
## pays out fully only at twelve irons is a card that never pays out.
func _check_the_ceiling_is_reachable() -> void:
	print("")
	print("=== can a real bag reach the top ===")
	var starting: DeckList = load("res://resources/decks/starting_deck.tres")
	var opening := BagStats.of(starting.build())
	print("  you start with %d cards: %d clubs, %d techniques"
		% [opening.cards, opening.clubs, opening.techniques])

	for id in SYNERGY_CARDS:
		var effect := _synergy_in(CardLibrary.template(id))
		if effect == null:
			continue
		var wanted := effect.pivot - effect.max_steps if effect.fewer_is_better \
			else effect.pivot + effect.max_steps
		var from_the_off := effect.steps_for(opening)
		print("  %-16s needs %d to max out, has %d from the first tee"
			% [id, wanted, from_the_off])
		_expect(from_the_off < effect.max_steps,
			"%s is already maxed out before you have played a hole" % id)
		_expect(wanted <= 12,
			"%s asks for a bag nobody will ever assemble" % id)


# --- Plumbing -------------------------------------------------------------

## One number standing for how good a stroke is: reach, and how tightly it is
## held. Crude on purpose -- what is being compared is the same card against
## itself, so the scale does not have to mean anything on its own.
func _quality(profile: ShotProfile) -> float:
	return profile.max_reach_yards() / maxf(profile.dispersion_deg, 0.05) \
		* profile.sweet_spot_multiplier


func _shot_with(card: CardData, bag: BagStats) -> ShotProfile:
	var profile := ShotProfile.from_card(CardLibrary.copy(&"iron_5"), bag)
	profile.apply_effects(card.shot_modifiers())
	return profile


## A bag that gives this card everything it is asking for.
func _bag_suiting(effect: BagSynergyEffect) -> BagStats:
	var bag := BagStats.new()
	var wanted: int = effect.pivot - effect.max_steps if effect.fewer_is_better \
		else effect.pivot + effect.max_steps
	wanted = maxi(wanted, 0)
	# A bag has to look like a bag, or the guard against reading an absent one
	# fires and every card comes back at its floor.
	bag.cards = wanted + 1
	match effect.counts:
		BagSynergyEffect.Counts.CARDS:
			bag.cards = maxi(wanted, 1)
		BagSynergyEffect.Counts.CLUBS:
			bag.clubs = wanted
		BagSynergyEffect.Counts.TECHNIQUES:
			bag.techniques = wanted
		BagSynergyEffect.Counts.WOODS:
			bag.families[ClubSpec.Family.WOOD] = wanted
		BagSynergyEffect.Counts.IRONS:
			bag.families[ClubSpec.Family.IRON] = wanted
		BagSynergyEffect.Counts.WEDGES:
			bag.families[ClubSpec.Family.WEDGE] = wanted
		BagSynergyEffect.Counts.UPGRADED:
			bag.upgraded = wanted
	return bag


func _synergy_in(card: CardData) -> BagSynergyEffect:
	if card == null:
		return null
	for effect in card.active_effects():
		if effect is BagSynergyEffect:
			return effect
	return null


func _expect(condition: bool, what: String) -> void:
	if not condition:
		_fail(what)


func _fail(what: String) -> void:
	failures += 1
	print("  FAIL: %s" % what)
