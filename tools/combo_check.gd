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
extends SceneTree

var failures := 0


func _initialize() -> void:
	_check_each_combo_fires()
	_check_order_does_not_matter()
	_check_a_combo_cannot_feed_a_combo()
	_check_the_base_effect_always_applies()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


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


## A 5 iron with these techniques folded onto it.
func _profile(ids: Array) -> ShotProfile:
	var profile := ShotProfile.from_card(CardLibrary.template(&"iron_5"))
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
