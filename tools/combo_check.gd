## Cards that pay off depending on what else is on the stroke.
##
## A combo is exactly the sort of thing that silently stops firing: the condition
## reads a profile that something else quietly changed, and a card that no longer
## combines still looks like a card. So every one is exercised twice here, once
## with its condition met and once without, and the difference is printed rather
## than assumed.
##
## The order pair at the end is the point of the two-pass fold in
## ShotProfile.apply_effects: play a combination either way round and you should
## get the same shot. Folded in one pass a combo would only see the cards played
## before it, which makes a pair a sequencing puzzle rather than a combination.
## The situation cards at the end are the other half: they read the hole rather
## than the stroke, and everything they read is put on the profile by whoever
## builds it. A caller that forgets leaves every one of them silently inert and
## nothing about the game looks wrong, so the last check drives the real
## HoleView instead of trusting arithmetic.
extends SceneTree

var failures := 0
var screen: HoleScreen = null


func _initialize() -> void:
	_check_each_combo_fires()
	_check_the_payoffs_are_shots_not_percentages()
	_check_every_combination_has_a_name()
	_check_order_does_not_matter()
	_check_a_combo_cannot_feed_a_combo()
	_check_the_base_effect_always_applies()
	_check_each_situation_fires()
	_check_trouble_pays_and_cruising_does_not()

	# The real scene, for the one thing arithmetic here cannot prove.
	screen = load("res://scenes/run/hole_screen.tscn").instantiate()
	screen.setup(HoleGenerator.generate(7, 2, 1),
		Deck.new(load("res://resources/decks/starting_deck.tres").build()))
	root.add_child(screen)


func _process(_delta: float) -> bool:
	_check_the_game_tells_a_card_where_it_is()
	_check_the_player_can_see_it_coming()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)
	return true


## Every situation card, in and out of its situation.
func _check_each_situation_fires() -> void:
	print("")
	print("=== every situation card reads the hole ===")
	var cases := [
		{"card": &"up_and_down", "stroke": 1, "par": 4, "trouble": true, "club": &""},
		{"card": &"grinder", "stroke": 3, "par": 4, "trouble": false, "club": &""},
		{"card": &"damage_limitation", "stroke": 4, "par": 4, "trouble": false, "club": &""},
		{"card": &"in_the_groove", "stroke": 2, "par": 4, "trouble": false, "club": &"iron_5"},
	]
	for case in cases:
		var cruising := _situated([case["card"]], 1, 4, false, &"")
		var in_it := _situated([case["card"]], int(case["stroke"]),
			int(case["par"]), bool(case["trouble"]), case["club"])
		if cruising == null or in_it == null:
			_expect(false, "%s is missing" % case["card"])
			continue
		print("  %-18s cruising spread %.2f   in the situation %.2f" % [
			case["card"], cruising.dispersion_deg, in_it.dispersion_deg])
		_expect(in_it.dispersion_deg < cruising.dispersion_deg - 0.001,
			"%s does the same thing in its situation as out of it"
				% case["card"])


## The whole point of biasing these towards trouble: a hole that is going well
## must not also pay a bonus, or good rounds run away from everybody.
func _check_trouble_pays_and_cruising_does_not() -> void:
	print("")
	print("=== a good hole does not also pay a bonus ===")
	for id in [&"up_and_down", &"grinder", &"damage_limitation"]:
		var bare := ShotProfile.from_card(CardLibrary.template(&"iron_5"))
		var cruising := _situated([id], 1, 4, false, &"")
		if cruising == null:
			_expect(false, "%s is missing" % id)
			continue
		# Its base half still applies -- it is never a dead card -- but the
		# situation half must not.
		var payout := bare.dispersion_deg * 0.90
		print("  %-18s on a tee shot from the fairway: spread %.2f (floor %.2f)"
			% [id, cruising.dispersion_deg, payout])
		_expect(cruising.dispersion_deg > payout,
			"%s pays out on a hole that is going perfectly well" % id)


## The check that arithmetic cannot do: does the real game tell a card where the
## ball is? Everything above would pass with set_situation deleted from HoleView.
func _check_the_game_tells_a_card_where_it_is() -> void:
	print("")
	print("=== the real hole tells a card where it is ===")
	var view: HoleView = screen.get_node("HoleView")
	view.start_hole()

	var trouble := _somewhere_awful(view.hole)
	if trouble == Vector2.ZERO:
		_expect(false, "no trouble anywhere on this hole to stand in")
		return
	view._ball.reset_to(trouble)
	print("  stood in %s" % view.hole.surface_at(trouble).display_name)

	var card := CardLibrary.template(&"iron_5")
	var profile: ShotProfile = view._build_profile(card)
	print("  the profile says lie_is_trouble = %s, stroke %d of a par %d" % [
		profile.lie_is_trouble, profile.stroke_number, profile.hole_par])
	_expect(profile.lie_is_trouble,
		"HoleView built a profile that does not know the ball is in trouble, so "
			+ "every situation card is inert in the actual game")
	_expect(profile.hole_par == view.hole.par,
		"the profile was not told the par")


## The half that was missing when the conditional cards first shipped: the game
## worked and the player had no way of knowing.
##
## A combination you can only find by spending the focus and comparing numbers
## afterwards is not a decision, and the decision is the whole of what separates
## a combo from a bonus. So the hand has to advertise the pair *before* it is
## played, and the heads-up display has to name it once it is.
func _check_the_player_can_see_it_coming() -> void:
	print("")
	print("=== the player can see a combination coming ===")
	var view: HoleView = screen.get_node("HoleView")
	view.start_hole()

	# A shaping technique on the stroke, and two techniques in hand: one that
	# answers it and one that does not.
	var draw := CardLibrary.copy(&"draw")
	view.deck.hand.append(draw)
	view.activate_card(view.deck.hand.find(draw))

	var answers := CardLibrary.copy(&"double_cross")
	var does_not := CardLibrary.copy(&"punch")
	view.deck.hand.append(answers)
	view.deck.hand.append(does_not)
	print("  double cross would combine: %s" % view.would_combine(answers))
	print("  punch would combine:        %s" % view.would_combine(does_not))
	_expect(view.would_combine(answers),
		"the hand does not advertise a card that would combine, so the pair is "
			+ "invisible until the focus has already been spent")
	_expect(not view.would_combine(does_not),
		"a technique that combines with nothing is being advertised as if it did")

	# And once it is played, the display has to say so.
	view.activate_card(view.deck.hand.find(answers))
	var live := view.live_combinations()
	print("  after playing it, the display reads: %s" % str(live))
	_expect(not live.is_empty(),
		"nothing is reported as combining after a combination was played")
	_expect(not view.would_combine(answers),
		"a card already played is still being advertised")


## A spot on this hole that hurts a shot. Searched rather than assumed, because
## which hazards a generated hole has is up to the generator.
func _somewhere_awful(hole: HoleData) -> Vector2:
	var rect := hole.bounds
	for step in 4000:
		var at := Vector2(
			rect.position.x + fposmod(float(step) * 97.0, rect.size.x),
			rect.position.y + fposmod(float(step) * 61.0, rect.size.y))
		if hole.is_in_bounds(at) and hole.surface_at(at).modifies_play():
			return at
	return Vector2.ZERO


## A profile with these cards on it, played in a given situation.
func _situated(ids: Array, stroke: int, par: int, trouble: bool,
		last_club: StringName) -> ShotProfile:
	var club := CardLibrary.template(&"iron_5")
	var profile := ShotProfile.from_card(club)
	profile.set_situation(stroke, par, trouble,
		club.id if last_club != &"" else &"")
	var effects: Array[CardEffect] = []
	for id in ids:
		var card := CardLibrary.template(id)
		if card == null:
			return null
		effects.append_array(card.shot_modifiers())
	profile.apply_effects(effects)
	return profile


## Each combo card, with its condition met and unmet.
func _check_each_combo_fires() -> void:
	print("=== every combo actually combines ===")
	# card, the partner that should switch it on, and what to watch.
	var cases := [
		{"card": &"follow_through", "with": &"draw", "field": "carry"},
		{"card": &"double_cross", "with": &"draw", "field": "carry"},
		{"card": &"clean_contact", "with": &"", "field": "spread"},
		{"card": &"wind_it_up", "with": &"full_send", "field": "carry"},
		{"card": &"soft_hands", "with": &"draw", "field": "roll"},
	]
	for case in cases:
		var alone := _profile([case["card"]])
		var paired := _profile([case["card"], case["with"]] if case["with"] != &""
			else [case["card"]])
		# Clean Contact is the odd one out: it wants a stroke with nothing
		# bending it, so its "paired" case is the lone one and its unmet case
		# needs a shaping card alongside.
		if case["card"] == &"clean_contact":
			alone = _profile([case["card"], &"draw"])
		if alone == null or paired == null:
			_expect(false, "%s or its partner is missing" % case["card"])
			continue
		print("  %-15s unmet %s   met %s" % [case["card"],
			_read(alone, case["field"]), _read(paired, case["field"])])
		_expect(_value(alone, case["field"]) != _value(paired, case["field"]),
			"%s does the same thing whether it combines or not"
				% case["card"])


## The half of this that was fair criticism: a combination should change what
## kind of shot you are hitting, not add ten per cent to it.
##
## Each of these is a thing a golfer would name, so each is checked against the
## system it is supposed to change -- the canopy for the high ball, the timing
## window for the flush, the roll for the runner and the spinner. A payoff that
## can only be seen in a decimal is the thing this check exists to refuse.
func _check_the_payoffs_are_shots_not_percentages() -> void:
	print("")
	print("=== a combination changes the shot, not the decimals ===")

	# THE FLIER: a ball out of light rough that comes off with no spin and goes
	# further than it has any right to. Qualitative because the lie stops
	# mattering, which is a fact you can check rather than a percentage.
	#
	# It replaced a high ball that tried to fly the trees. Raising the apex reads
	# like the obvious payoff and measures as a weak one: a full shot already
	# spends 55% of its carry above the sixteen yard canopy, and nearly doubling
	# the arc took that to 77%. Forty per cent more time over the top is not a
	# different shot.
	var rough := SurfaceLibrary.by_id(&"rough")
	var fairway := SurfaceLibrary.by_id(&"fairway")
	var clean := _profile([&"draw"])
	fairway.apply_to(clean)
	var stuck := _profile([&"draw"])
	rough.apply_to(stuck)
	var flier := _profile([&"draw", &"follow_through"])
	rough.apply_to(flier)
	print("  the flier: %.0f yd off the fairway, %.0f from the rough, %.0f as a flier"
		% [clean.carry_yards_max, stuck.carry_yards_max, flier.carry_yards_max])
	_expect(stuck.carry_yards_max < clean.carry_yards_max * 0.95,
		"the rough is not costing anything, so shrugging it off proves nothing")
	_expect(flier.carry_yards_max > clean.carry_yards_max,
		"a flier out of the rough should beat an ordinary shot off the fairway")

	# FLUSHED: the window you have to catch it right in.
	var loose := _profile([&"clean_contact", &"draw"])
	var flush := _profile([&"clean_contact"])
	print("  flushed: timing window x%.2f -> x%.2f"
		% [loose.sweet_spot_scale(), flush.sweet_spot_scale()])
	_expect(flush.sweet_spot_scale() > loose.sweet_spot_scale() * 1.6,
		"flushing it should roughly double the window, not nudge it")

	# THE RUNNER and THE SPINNER: the two ends of what a ball does on landing.
	var runner := _profile([&"full_send", &"wind_it_up"])
	var spinner := _profile([&"draw", &"soft_hands"])
	var ordinary := _profile([])
	print("  the runner: roll %.2f of carry, against %.2f ordinarily"
		% [runner.roll_ratio, ordinary.roll_ratio])
	print("  the spinner: roll %.2f of carry -- it stops where it pitches"
		% spinner.roll_ratio)
	_expect(runner.roll_ratio > ordinary.roll_ratio * 2.5,
		"the runner barely runs further than an ordinary shot")
	_expect(spinner.roll_ratio < ordinary.roll_ratio * 0.25,
		"the spinner does not stop")
	_expect(spinner.slope_resistance >= 0.99,
		"the spinner should hold its line on any slope")


## Every combination has to be called something, or the display reads back a
## sentence of arithmetic at the moment it should be naming a shot.
func _check_every_combination_has_a_name() -> void:
	print("")
	print("=== every combination is called something ===")
	var named := 0
	for id in [&"follow_through", &"double_cross", &"clean_contact",
			&"wind_it_up", &"soft_hands", &"up_and_down", &"grinder",
			&"damage_limitation", &"in_the_groove"]:
		var card := CardLibrary.template(id)
		if card == null:
			_expect(false, "%s is missing" % id)
			continue
		for effect in card.shot_modifiers():
			var name := ""
			if effect is ComboEffect:
				name = (effect as ComboEffect).combination_name
			elif effect is SituationEffect:
				name = (effect as SituationEffect).combination_name
			else:
				continue
			named += 1
			print("  %-18s %s" % [id, name if name != "" else "UNNAMED"])
			_expect(name.strip_edges() != "",
				"%s fires without a name, so the display reads back its rules "
					% id + "text instead")
			_expect(name == name.to_upper(),
				"%s is named '%s'; the readout upper-cases, so author it that way"
					% [id, name])
	_expect(named == 9, "expected nine conditional cards, found %d" % named)


## Either order, the same shot.
func _check_order_does_not_matter() -> void:
	print("")
	print("=== a combination is not a sequence puzzle ===")
	var forwards := _profile([&"double_cross", &"draw"])
	var backwards := _profile([&"draw", &"double_cross"])
	if forwards == null or backwards == null:
		_expect(false, "the cards for the order check are missing")
		return
	print("  double cross then draw: %.1f yd, curve %.1f" % [
		forwards.carry_yards_max, forwards.curve_deg])
	print("  draw then double cross: %.1f yd, curve %.1f" % [
		backwards.carry_yards_max, backwards.curve_deg])
	_expect(is_equal_approx(forwards.carry_yards_max, backwards.carry_yards_max)
		and is_equal_approx(forwards.curve_deg, backwards.curve_deg),
		"the same pair played the other way round gives a different shot")


## Two combos on one stroke must not switch each other on. They contribute no
## tags and are not counted as techniques, so each is still waiting on a real
## card -- otherwise a pair of them would be a free payoff for both.
func _check_a_combo_cannot_feed_a_combo() -> void:
	print("")
	print("=== combos do not feed each other ===")
	var alone := _profile([&"follow_through"])
	var doubled := _profile([&"follow_through", &"double_cross"])
	if alone == null or doubled == null:
		_expect(false, "the cards for the feedback check are missing")
		return
	print("  follow through alone: %.1f yd" % alone.carry_yards_max)
	print("  with another combo:   %.1f yd" % doubled.carry_yards_max)
	_expect(is_equal_approx(alone.carry_yards_max, doubled.carry_yards_max),
		"one combo switched another on, so a pair of them pays twice for nothing")


## The half of a combo card that is not conditional has to work regardless, or
## drawing one when it cannot combine is drawing a blank.
func _check_the_base_effect_always_applies() -> void:
	print("")
	print("=== a combo card is never a dead card ===")
	var bare := ShotProfile.from_card(CardLibrary.template(&"iron_5"))
	for id in [&"follow_through", &"double_cross", &"clean_contact",
			&"wind_it_up", &"soft_hands"]:
		var alone := _profile([id])
		if alone == null:
			_expect(false, "%s is missing" % id)
			continue
		var moved := not is_equal_approx(alone.carry_yards_max, bare.carry_yards_max) \
			or not is_equal_approx(alone.dispersion_deg, bare.dispersion_deg) \
			or not is_equal_approx(alone.roll_ratio, bare.roll_ratio) \
			or not is_equal_approx(alone.sweet_spot_multiplier, bare.sweet_spot_multiplier)
		print("  %-15s on its own: %s" % [id,
			"does something" if moved else "DOES NOTHING"])
		_expect(moved,
			"%s does nothing at all unless it combines" % id)


## How much of the carry this shot spends above a given height.
##
## The ball flies as apex * sin(pi * t), so it is over `height` between the two
## points where that crosses it. This is the same question the aiming reticle
## asks when it turns red, in closed form.
func _share_above(profile: ShotProfile, height: float) -> float:
	var apex := profile.apex_yards(1.0)
	if apex <= height:
		return 0.0
	return 1.0 - 2.0 * asin(clampf(height / apex, 0.0, 1.0)) / PI


## A club with these techniques folded onto it.
func _profile(ids: Array, club_id: StringName = &"iron_5") -> ShotProfile:
	var profile := ShotProfile.from_card(CardLibrary.template(club_id))
	var effects: Array[CardEffect] = []
	for id in ids:
		var card := CardLibrary.template(id)
		if card == null:
			return null
		effects.append_array(card.shot_modifiers())
	profile.apply_effects(effects)
	return profile


func _value(profile: ShotProfile, field: String) -> float:
	match field:
		"carry":
			return profile.carry_yards_max
		"spread":
			return profile.dispersion_deg
		"roll":
			return profile.roll_ratio
		"curve":
			return profile.curve_deg
	return 0.0


func _read(profile: ShotProfile, field: String) -> String:
	return "%7.2f" % _value(profile, field)


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)
