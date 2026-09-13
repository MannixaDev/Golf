## Is the Driron worth destroying two clubs for, and is it findable at all?
##
## Two things can go wrong with a secret legendary and neither shows up in play
## for a dozen runs. It can be underwhelming -- a card that reads special and
## measures ordinary, which is worse than not having it. Or it can be a ghost:
## gated behind a stop, a bag state and a roll, all of which are individually
## reasonable and together mean nobody ever sees the thing.
##
## So this measures both. What the club actually does against every club it
## could have been made from, and how often a nine that could produce one does.
extends SceneTree

## Routes walked when measuring how often the door turns up.
const ROUTES := 600
## The stops with a workbench out the back. Kept in step with main.gd by hand,
## which is the one seam here a harness cannot check for itself.
const WORKBENCH_STOPS := [&"clubhouse", &"driving_range", &"pro_shop"]

var failures := 0
var _screen: HoleScreen


func _initialize() -> void:
	CardLibrary.ensure_loaded()
	MapGenerator.ensure_specs_loaded()

	_check_families()
	_check_the_rules()
	_check_the_club_is_worth_it()
	_check_it_stays_secret()
	_check_you_can_find_it()

	# The shaping check drives the real hole scene rather than re-implementing
	# the plumbing and proving nothing. A node added during _initialize has not
	# run _ready yet, so that one waits a frame.
	_screen = load("res://scenes/run/hole_screen.tscn").instantiate()
	_screen.setup(HoleGenerator.generate(4242, 2, 1),
		Deck.new([CardLibrary.copy(&"driron"), CardLibrary.copy(&"putter")]))
	root.add_child(_screen)


func _process(_delta: float) -> bool:
	# begin() is what deals the hand, and it needs _ready to have run first.
	_screen.begin()
	_check_shaping_reaches_the_shot()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)
	return true


## The fusion asks what a club is, never what it is called, so a club left on
## the default family would quietly become fusible or stop being so.
func _check_families() -> void:
	print("=== every club knows what it is ===")
	var expected := {
		&"driver": ClubSpec.Family.WOOD,
		&"wood_3": ClubSpec.Family.WOOD,
		&"hybrid": ClubSpec.Family.WOOD,
		&"iron_5": ClubSpec.Family.IRON,
		&"iron_7": ClubSpec.Family.IRON,
		&"iron_9": ClubSpec.Family.IRON,
		&"wedge": ClubSpec.Family.WEDGE,
		&"sand_wedge": ClubSpec.Family.WEDGE,
		&"chipper": ClubSpec.Family.WEDGE,
		&"putter": ClubSpec.Family.PUTTER,
		&"driron": ClubSpec.Family.SPECIAL,
	}
	var seen := 0
	for id in CardLibrary.all_ids():
		var card := CardLibrary.template(id)
		if card == null or card.club == null:
			continue
		var club_id: StringName = card.club.id
		if not expected.has(club_id):
			_fail("club '%s' is not accounted for here" % club_id)
			continue
		seen += 1
		_expect(card.club.family == expected[club_id],
			"%s should be a %s" % [club_id,
				ClubSpec.Family.keys()[expected[club_id]]])
	_expect(seen >= expected.size(), "every known club was checked (%d seen)" % seen)


func _check_the_rules() -> void:
	print("")
	print("=== what may go in the vice ===")

	var wood := CardLibrary.copy(&"driver")
	var iron := CardLibrary.copy(&"iron_5")
	var putter := CardLibrary.copy(&"putter")

	_expect(not ClubFusion.is_available([putter]),
		"a bag of putters cannot fuse anything")
	_expect(not ClubFusion.is_available([wood, putter]),
		"a wood on its own is not enough")
	_expect(not ClubFusion.is_available([iron, putter]),
		"an iron on its own is not enough")
	_expect(ClubFusion.is_available([wood, iron, putter]),
		"one of each opens the door")

	var made := ClubFusion.fuse(wood, iron)
	_expect(made != null and made.id == ClubFusion.RESULT_ID,
		"the vice produces a Driron")
	_expect(not ClubFusion.is_available([made, wood, iron]),
		"a bag that already has one cannot make another")

	# Grooving a club and then melting it down has to keep the groove, or the
	# range and the workshop are quietly at war with each other.
	var grooved := CardLibrary.copy(&"iron_5")
	grooved.upgrade()
	_expect(grooved.upgraded, "the 5 iron can be grooved at all")
	var better := ClubFusion.fuse(CardLibrary.copy(&"driver"), grooved)
	_expect(better.upgraded, "a grooved parent makes a grooved Driron")
	_expect(not ClubFusion.fuse(CardLibrary.copy(&"driver"),
		CardLibrary.copy(&"iron_5")).upgraded,
		"two stock parents make a stock Driron")


## The measurement that matters. Two clubs are destroyed to make this, and a
## hand is five cards, so it has to be better than either parent at the thing
## that parent was for -- not merely a nice average of the two.
func _check_the_club_is_worth_it() -> void:
	print("")
	print("=== is it worth two clubs ===")

	var driron := ShotProfile.from_card(CardLibrary.copy(&"driron"))
	var woods: Array[String] = []
	var irons: Array[String] = []
	var longest_iron := 0.0
	var straightest := 999.0
	var driver := ShotProfile.from_card(CardLibrary.copy(&"driver"))

	for id in CardLibrary.all_ids():
		var card := CardLibrary.template(id)
		if card == null or card.club == null or card.id == &"driron":
			continue
		var profile := ShotProfile.from_card(CardLibrary.copy(card.id))
		if card.club.family == ClubSpec.Family.WOOD:
			woods.append(card.display_name)
			_expect(profile.dispersion_deg > driron.dispersion_deg,
				"the Driron is straighter than the %s" % card.display_name)
		elif card.club.family == ClubSpec.Family.IRON:
			irons.append(card.display_name)
			longest_iron = maxf(longest_iron, profile.max_reach_yards())
			_expect(profile.max_reach_yards() < driron.max_reach_yards(),
				"the Driron outruns the %s" % card.display_name)
		if card.club.family in [ClubSpec.Family.WOOD, ClubSpec.Family.IRON]:
			straightest = minf(straightest, profile.dispersion_deg)

	_expect(driron.dispersion_deg < straightest,
		"the Driron is the straightest club in the bag (%.1f deg against %.1f)"
			% [driron.dispersion_deg, straightest])
	# But not simply a better driver, or the driver stops being a decision.
	_expect(driver.max_reach_yards() > driron.max_reach_yards(),
		"the driver still hits it furthest (%.0f against %.0f yards)"
			% [driver.max_reach_yards(), driron.max_reach_yards()])
	_expect(driron.sweet_spot_multiplier > 1.0,
		"the Driron is kinder to a mistimed swing")
	_expect(driron.lie_resistance > 0.0,
		"the Driron shrugs off a bad lie")
	_expect(driron.shape_deg > 0.0,
		"the Driron can be worked either way (%.0f deg)" % driron.shape_deg)
	_expect(not driron.conceal_shape,
		"and the bend is shown, unlike a Draw or a Fade")
	# Nothing else in the bag offers the choice, or it stops being the reason to
	# make one.
	for id in CardLibrary.all_ids():
		var other := CardLibrary.template(id)
		if other == null or other.club == null or other.id == &"driron":
			continue
		_expect(ShotProfile.from_card(CardLibrary.copy(other.id)).shape_deg <= 0.0,
			"the %s cannot be shaped to order" % other.display_name)
	# Worth as much as a Draw card, which is what it replaces the need for.
	var drawn := ShotProfile.from_card(CardLibrary.copy(&"driver"))
	drawn.apply_effects(CardLibrary.template(&"draw").shot_modifiers())
	_expect(driron.shape_deg >= absf(drawn.curve_deg),
		"shaping it bends as far as a Draw does (%.0f against %.0f deg)"
			% [driron.shape_deg, absf(drawn.curve_deg)])

	print("  it beats %d irons for distance and %d woods for line"
		% [irons.size(), woods.size()])
	print("  %.0f yards (driver %.0f, best iron %.0f), %.1f deg (driver %.1f)"
		% [driron.max_reach_yards(), driver.max_reach_yards(), longest_iron,
			driron.dispersion_deg, driver.dispersion_deg])
	# What the numbers mean where it is actually used: a 200-yard approach.
	print("  worst miss on a 200 yard shot: Driron %.0f yards offline, driver %.0f"
		% [_miss(driron, 200.0), _miss(driver, 200.0)])


## The profile knowing it can be shaped is not the same as the shot bending.
## This walks the seam the player actually uses: pick a shape, and the staged
## profile the aiming overlay draws from has to come back curved.
func _check_shaping_reaches_the_shot() -> void:
	print("")
	print("=== does asking for a shape do anything ===")

	var view: HoleView = _screen.get_node("HoleView")
	var driron_slot := _slot(view, ClubFusion.RESULT_ID)
	if driron_slot < 0:
		_fail("the Driron never reached the hand")
		return
	_expect(true, "the Driron reaches the hand")

	view.select_card(driron_slot)
	var straight: float = view._aim.shot_profile.curve_deg
	view.set_shot_shape(-1)
	var drawn: float = view._aim.shot_profile.curve_deg
	view.set_shot_shape(1)
	var faded: float = view._aim.shot_profile.curve_deg

	_expect(absf(straight) < 0.01, "left alone it goes straight")
	_expect(drawn < -1.0, "asking for a draw bends it left (%.0f deg)" % drawn)
	_expect(faded > 1.0, "asking for a fade bends it right (%.0f deg)" % faded)
	_expect(absf(drawn) == absf(faded), "both ways bend the same amount")

	# And a club that cannot be shaped ignores the request entirely, rather than
	# quietly carrying a bend over from the last stroke.
	var putter_slot := _slot(view, &"putter")
	if putter_slot >= 0:
		view.select_card(putter_slot)
		_expect(absf(view._aim.shot_profile.curve_deg) < 0.01,
			"a club that cannot be worked is not bent by the request")


func _slot(view: HoleView, id: StringName) -> int:
	for i in view.deck.hand.size():
		if view.deck.hand[i].id == id:
			return i
	return -1


## Nothing hands you one. If a legendary can be bought or won it is not a
## secret, it is a rare drop, and the workshop stops being the point of it.
func _check_it_stays_secret() -> void:
	print("")
	print("=== nothing gives one away ===")

	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var offered := 0
	for roll in 4000:
		for card in RewardTable.card_offer(rng, 1 + roll % 4):
			if card.id == ClubFusion.RESULT_ID:
				offered += 1
	_expect(offered == 0, "4000 prize offers contained no Driron")

	var driron := CardLibrary.template(ClubFusion.RESULT_ID)
	_expect(driron.rarity == CardData.Rarity.LEGENDARY,
		"the Driron is legendary, which is what keeps it out of the pools")
	for deck_list in ResourceFolder.load_all("res://resources/decks"):
		if deck_list is DeckList:
			_expect(not Array(deck_list.card_ids).has(String(ClubFusion.RESULT_ID)),
				"'%s' does not start you with one" % deck_list.display_name)


## The other failure, and the one this harness caught on its first run: a secret
## nobody finds. The door hung off the clubhouse alone opened on 10% of nines,
## because a random route only walks into a clubhouse 0.4 times -- three gates
## multiplied together, each individually sensible.
##
## So this walks real routes and counts the stops that could show it.
func _check_you_can_find_it() -> void:
	print("")
	print("=== can it actually be found ===")

	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var with_a_door := 0
	var with_a_bench := 0
	var benches := 0
	for route in ROUTES:
		var stops := _walk(MapGenerator.generate(rng.randi()), rng)
		benches += stops
		if stops > 0:
			with_a_bench += 1
		# Rolled the way the run layer rolls it, escalating stop by stop. The
		# old model here was a flat chance compounded, which is not what the
		# game does any more and would have reported a number nobody would see.
		var misses := 0
		for bench in stops:
			if rng.randf() < ClubFusion.chance(misses):
				with_a_door += 1
				break
			misses += 1

	var share := float(with_a_door) / float(ROUTES)
	var reachable := float(with_a_bench) / float(ROUTES)
	print("  %.2f workbench stops per nine; %.0f%% of nines have at least one"
		% [float(benches) / float(ROUTES), reachable * 100.0])
	print("  door opens on %.0f%% of nines, and %.0f%% of eighteens"
		% [share * 100.0, (1.0 - pow(1.0 - share, 2)) * 100.0])
	print("  which is %.0f%% of the nines that could have shown it at all"
		% (share / maxf(reachable, 0.001) * 100.0))
	_expect(share > 0.45,
		"a nine should show the door often enough that people discover it")
	_expect(share < 0.80,
		"finding it should still depend on the route you took")
	# The point of escalating: walking into benches has to be what finds it,
	# rather than the same die refusing you four runs running.
	_expect(share / maxf(reachable, 0.001) > 0.75,
		"most nines that offer a bench should open the door at one of them")


## One player's route through a map, counting the stops that keep a workbench.
func _walk(map: RunMap, rng: RandomNumberGenerator) -> int:
	var stops := 0
	for _guard in 40:
		var options := map.available_ids()
		if options.is_empty():
			break
		var id: int = options[rng.randi_range(0, options.size() - 1)]
		var node := map.node_by_id(id)
		if node.spec != null and node.spec.id in WORKBENCH_STOPS:
			stops += 1
		map.travel_to(id)
	return stops


## Worst-case yards offline at a given distance, which is the number a player
## feels rather than the degrees they never see.
func _miss(profile: ShotProfile, yards: float) -> float:
	return yards * tan(deg_to_rad(profile.dispersion_deg))


func _expect(condition: bool, what: String) -> void:
	if condition:
		print("  ok: %s" % what)
	else:
		_fail(what)


func _fail(what: String) -> void:
	failures += 1
	print("  FAIL: %s" % what)
