## Asserts that special rules actually change the hole, and that events can be
## resolved without leaving the run in a broken state.
##
## Rules mutate the hole between strokes, which is exactly the sort of thing that
## breaks quietly, so each one is driven through a real hole and the change is
## measured rather than assumed.
extends SceneTree

var failures := 0


func _initialize() -> void:
	_check_rule_sets()
	_check_shifting_wind()
	_check_roving_hazards()
	_check_distraction()
	_check_generation_overrides()
	_check_assignment()
	_check_events()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


func _context(stroke: int, rng: RandomNumberGenerator) -> CourseRuleContext:
	var ctx := CourseRuleContext.new()
	ctx.stroke_number = stroke
	ctx.strokes_taken = stroke - 1
	ctx.rng = rng
	return ctx


func _rng(value: int = 99) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = value
	return rng


# --- Loading --------------------------------------------------------------

func _check_rule_sets() -> void:
	var sets := CourseRuleLibrary.all()
	print("=== local rules (%d) ===" % sets.size())
	for rule_set in sets:
		print("  %-22s min tier %d  %s" % [
			rule_set.display_name, rule_set.min_difficulty, rule_set.rules_text()])
		for rule in rule_set.rules:
			_expect(rule != null, "%s has a null rule" % rule_set.display_name)
	_expect(sets.size() >= 5, "there should be a spread of special rules")


# --- Behaviour ------------------------------------------------------------

func _check_shifting_wind() -> void:
	print("")
	print("=== the wind will not settle ===")
	var hole := HoleGenerator.generate(11, 4, 1)
	var rule := ShiftingWindRule.new()
	var rng := _rng(3)

	rule.on_hole_start(hole, _context(1, rng))
	_expect(hole.has_wind(), "a shifting wind hole should never be calm")

	# The tee shot plays the wind as shown, so nothing moves on stroke 1.
	var opening := hole.wind_direction
	rule.before_stroke(hole, _context(1, rng))
	_expect(hole.wind_direction.is_equal_approx(opening),
		"the wind should hold for the tee shot")

	var turns := 0
	var previous := hole.wind_direction
	for stroke in range(2, 7):
		var ctx := _context(stroke, rng)
		rule.before_stroke(hole, ctx)
		if not hole.wind_direction.is_equal_approx(previous):
			turns += 1
		_expect(ctx.conditions_changed, "a turning wind should refresh the readout")
		_expect(not ctx.messages.is_empty(), "a turning wind should announce itself")
		previous = hole.wind_direction
	print("  wind turned on %d of 5 strokes after the tee" % turns)
	_expect(turns == 5, "the wind should turn on every stroke after the tee")


func _check_roving_hazards() -> void:
	print("")
	print("=== the groundskeeper moves things ===")
	var hole := HoleGenerator.generate(22, 4, 1)
	var rule := RovingHazardsRule.new()
	var rng := _rng(5)

	var before: Array[Vector2] = []
	for region in hole.hazards:
		before.append(region.centre)

	for stroke in range(2, 6):
		rule.before_stroke(hole, _context(stroke, rng))

	var moved := 0
	for i in hole.hazards.size():
		if not hole.hazards[i].centre.is_equal_approx(before[i]):
			moved += 1
	print("  %d of %d hazards moved over four strokes" % [moved, hole.hazards.size()])
	_expect(moved == hole.hazards.size(), "every hazard should drift")

	# The promise the generator makes has to survive the groundskeeper.
	for step in 24:
		var angle := TAU * float(step) / 24.0
		var probe: Vector2 = hole.pin_position \
			+ Vector2.RIGHT.rotated(angle) * hole.green_radius * 0.7
		var surface := hole.surface_at(probe)
		if surface.catches_ball or surface.blocks_ground_shots:
			_expect(false, "%s ended up on the green" % surface.display_name)
			break
	for region in hole.hazards:
		_expect(hole.bounds.has_point(region.centre),
			"a hazard drifted out of bounds")
	print("  green still clear, everything still in bounds")


func _check_distraction() -> void:
	print("")
	print("=== somebody is putting you off ===")
	var rule := DistractionRule.new()
	rule.chance = 1.0
	rule.dispersion_multiplier = 2.0
	var rng := _rng(7)
	var hole := HoleGenerator.generate(33, 4, 1)

	var base := ShotProfile.from_card(CardLibrary.template(&"iron_5")).dispersion_deg

	# Nothing until the rule has actually rolled for this stroke.
	var quiet := ShotProfile.from_card(CardLibrary.template(&"iron_5"))
	rule.on_hole_start(hole, _context(1, rng))
	rule.modify_profile(quiet, _context(1, rng))
	_expect(is_equal_approx(quiet.dispersion_deg, base),
		"a distraction should do nothing before it fires")

	var ctx := _context(2, rng)
	rule.before_stroke(hole, ctx)
	var spoiled := ShotProfile.from_card(CardLibrary.template(&"iron_5"))
	rule.modify_profile(spoiled, ctx)
	print("  base spread %.2f, distracted %.2f" % [base, spoiled.dispersion_deg])
	_expect(spoiled.dispersion_deg > base, "a distraction should widen the shot")
	_expect(not ctx.messages.is_empty(), "a distraction should say what happened")

	# It must be announced before the swing, not sprung afterwards.
	rule.chance = 0.0
	var calm_ctx := _context(3, rng)
	rule.before_stroke(hole, calm_ctx)
	var calm := ShotProfile.from_card(CardLibrary.template(&"iron_5"))
	rule.modify_profile(calm, calm_ctx)
	_expect(is_equal_approx(calm.dispersion_deg, base),
		"a quiet stroke should be left alone")


# --- Generation -----------------------------------------------------------

func _check_generation_overrides() -> void:
	print("")
	print("=== rules that reshape the hole ===")
	var short_rules := CourseRuleLibrary.by_id(&"impossible_par_3")
	_expect(short_rules != null, "the impossible par 3 should exist")
	if short_rules == null:
		return

	var plain := HoleGenerator.generate(44, 4, 1)
	var forced := HoleGenerator.generate(44, 4, 1, short_rules)
	print("  ordinary closer: par %d, %.0f yd, %d hazards, %d ringing the green" % [
		plain.par, plain.hole_length_yards(), plain.hazards.size(),
		_ringing_the_green(plain)])
	print("  impossible par 3: par %d, %.0f yd, %d hazards, %d ringing the green" % [
		forced.par, forced.hole_length_yards(), forced.hazards.size(),
		_ringing_the_green(forced)])
	_expect(forced.par == 3, "it should force a par 3")
	_expect(forced.hole_length_yards() < 200.0, "it should be genuinely short")
	# Raw counts are the wrong measure: a short hole loses the fairway bunkers a
	# long one gets, and its clearance guards are larger in pixels. What the brief
	# actually asks for is a hole ringed with trouble.
	_expect(_ringing_the_green(forced) > _ringing_the_green(plain),
		"it should be ringed with more trouble than an ordinary closer")

	# Fairness survives the overrides.
	_expect(not forced.surface_at(forced.tee_position).catches_ball,
		"the tee should still be playable")
	for step in 16:
		var angle := TAU * float(step) / 16.0
		var probe: Vector2 = forced.pin_position \
			+ Vector2.RIGHT.rotated(angle) * forced.green_radius * 0.7
		if forced.surface_at(probe).catches_ball:
			_expect(false, "the forced hole put water on its green")
			break


## Hazards close enough to the green to be guarding it.
func _ringing_the_green(hole: HoleData) -> int:
	var count := 0
	for region in hole.hazards:
		if region.centre.distance_to(hole.pin_position) <= hole.green_radius * 2.6:
			count += 1
	return count


func _check_assignment() -> void:
	print("")
	print("=== who gets special rules ===")
	var ordinary := 0
	var elite := 0
	var closer := 0
	for i in 200:
		if CourseRuleLibrary.pick(1, 1000 + i) != null:
			ordinary += 1
		var elite_rules := CourseRuleLibrary.pick(3, 2000 + i)
		if elite_rules != null:
			elite += 1
			_expect(elite_rules.min_difficulty <= 3, "an elite drew a closer's rules")
		var boss_rules := CourseRuleLibrary.pick(4, 3000 + i)
		if boss_rules != null:
			closer += 1
			_expect(boss_rules.min_difficulty >= 4,
				"the closing hole drew a lighter rule set")

	print("  ordinary holes with rules: %d / 200" % ordinary)
	print("  elite holes with rules:    %d / 200" % elite)
	print("  closing holes with rules:  %d / 200" % closer)
	_expect(ordinary == 0, "ordinary holes should never have special rules")
	_expect(elite == 200, "every elite hole should have a twist")
	_expect(closer == 200, "every closing hole should have its own rules")

	# The same hole must read the same way every time it is looked at.
	var first := CourseRuleLibrary.pick(4, 12345)
	var again := CourseRuleLibrary.pick(4, 12345)
	_expect(first == again, "a hole's rules should be stable for its seed")


# --- Events ---------------------------------------------------------------

func _check_events() -> void:
	print("")
	print("=== events (%d) ===" % EventLibrary.all().size())
	for event in EventLibrary.all():
		print("  %-22s %d choices" % [event.title, event.outcomes.size()])
		_expect(event.outcomes.size() >= 2,
			"%s should offer a real choice" % event.title)
		for outcome in event.outcomes:
			_expect(outcome != null, "%s has a null outcome" % event.title)
			_expect(outcome.label != "", "%s has an unlabelled option" % event.title)
			# A card handed out by name is the one thing in an event that can be
			# silently wrong: a typo here costs the player their reward and says
			# nothing about it.
			if outcome != null and outcome.add_card_id != &"":
				_expect(CardLibrary.template(outcome.add_card_id) != null,
					"%s promises a card called '%s' that does not exist"
						% [event.title, outcome.add_card_id])
		_check_nothing_is_dominated(event)

	# An option you cannot pay for should not be offered.
	var costly := 0
	for event in EventLibrary.all():
		for outcome in event.outcomes:
			if outcome.requires_winnings > 0:
				costly += 1
				_expect(not outcome.is_affordable(0),
					"a paid option should be hidden when skint")
				_expect(outcome.is_affordable(outcome.requires_winnings),
					"a paid option should appear once affordable")
	print("  %d options gated on winnings, all correctly hidden when skint" % costly)

	# Picking should not repeat within a run until everything has been seen.
	var rng := _rng(11)
	var seen: Array = []
	for i in EventLibrary.all().size():
		var event := EventLibrary.pick(rng, 5, seen)
		_expect(event != null, "there should always be an event to show")
		if event != null:
			_expect(not seen.has(event.id), "an event repeated before the pool ran out")
			seen.append(event.id)
	# Once exhausted it must still return something rather than nothing.
	_expect(EventLibrary.pick(rng, 5, seen) != null,
		"an exhausted pool should still produce an event")
	print("  %d events drawn with no repeats, and the pool recycles" % seen.size())


## No option may be strictly worse than another on every axis.
##
## An option that does nothing is fine -- declining a trade is a real decision.
## An option that is beaten outright by a sibling is not: it is a line of text
## nobody will ever click, and it makes the event look like a choice while
## offering one fewer than it claims.
##
## Only outcomes with identical non-numeric effects are compared. Whether losing
## a random club is a gain or a cost depends on the club, and a check that had to
## guess would be a check that cried wolf.
func _check_nothing_is_dominated(event: EventSpec) -> void:
	for i in event.outcomes.size():
		for j in event.outcomes.size():
			if i == j:
				continue
			var worse: EventOutcome = event.outcomes[i]
			var better: EventOutcome = event.outcomes[j]
			if worse == null or better == null:
				continue
			if not _same_shape(worse, better):
				continue
			if better.requires_winnings > worse.requires_winnings:
				continue
			var no_worse := better.winnings_delta >= worse.winnings_delta 				and better.strokes_delta <= worse.strokes_delta
			var strictly_better := better.winnings_delta > worse.winnings_delta 				or better.strokes_delta < worse.strokes_delta
			_expect(not (no_worse and strictly_better),
				"%s: '%s' is beaten outright by '%s'"
					% [event.title, worse.label, better.label])


func _same_shape(a: EventOutcome, b: EventOutcome) -> bool:
	return a.add_card_id == b.add_card_id 		and a.removes_random_card == b.removes_random_card 		and a.upgrades_random_card == b.upgrades_random_card 		and a.grants_relic == b.grants_relic


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		if failures < 15:
			print("  FAIL: %s" % what)
