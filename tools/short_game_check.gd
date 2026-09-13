## Checks the rules that govern the last twenty yards of a hole.
##
## Every one of these came out of a single reported run: a wedge that finished
## visibly inside the cup and did not drop, no putter in the bag when it
## mattered, and a hole that ran to twelve strokes and ended the round on its
## own. None of them are things a simulation with perfect club selection will
## ever find, so they are pinned down here instead.
extends SceneTree

const AIR_SHOTS := 240
const AIM_ATTEMPTS := 400
const TIERS := 5

var failures := 0
var screen: HoleScreen = null

# Signal results, held as members rather than captured in a lambda: GDScript
# lambdas capture locals by value, so a flag set inside one is never seen again.
var _holed := false
var _completed_strokes := -1
var _completed_holed := true


func _initialize() -> void:
	_check_cup_is_honest()

	screen = load("res://scenes/run/hole_screen.tscn").instantiate()
	screen.setup(HoleGenerator.generate(7, 2, 1), Deck.new())
	root.add_child(screen)


func _process(_delta: float) -> bool:
	_check_air_capture()
	_check_short_game_rescue()
	_check_pick_up()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)
	return true


# --- The cup you see is the cup that is there -----------------------------

func _check_cup_is_honest() -> void:
	print("=== the drawn cup and the played cup are one circle ===")

	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var smallest := INF
	var shortest_hole := 0.0
	for tier in TIERS:
		for attempt in 40:
			var hole := HoleGenerator.generate(rng.randi(), tier, 1)
			var pixels := hole.cup_pixels()
			if pixels < smallest:
				smallest = pixels
				shortest_hole = hole.hole_length_yards()
			_expect(pixels >= HoleData.MIN_CUP_PIXELS,
				"a cup smaller than the one drawn on screen")

	print("  smallest cup across 200 holes: %.1f px (floor %.1f)" % [
		smallest, HoleData.MIN_CUP_PIXELS])
	print("  it turned up on a %.0f yard hole" % shortest_hole)


# --- A wedge that lands in the hole goes in -------------------------------

func _check_air_capture() -> void:
	print("")
	print("=== pitching into the cup ===")

	var hole := HoleGenerator.generate(11, 2, 1)
	var ball: Ball = screen.get_node("HoleView/Ball")
	var hole_view: HoleView = screen.get_node("HoleView")
	hole_view.hole = hole
	ball.configure(hole.pin_position, hole.cup_pixels(), hole.bounds)

	# Half a cup off centre, because a shot that finishes at exactly zero
	# distance is not a thing that happens and would pass any test you wrote.
	var inside := hole.cup_pixels() * 0.5
	# Roll-out in yards. A wedge that checks releases a yard or two; a low runner
	# releases twenty and has no business dropping out of the air.
	for roll_yards in [0.0, 1.0, 3.0, 8.0, 20.0]:
		var holed := _pitch_at_pin(ball, hole, roll_yards, inside)
		print("  pitching inside the cup with %4.1f yd of release: %s" % [
			roll_yards, "IN" if holed else "runs through"])
		if roll_yards <= 3.0:
			_expect(holed, "a wedge landing in the cup should drop")
		if roll_yards >= 20.0:
			_expect(not holed, "a low runner should race straight through")

	# And it must still be a shot, not a magnet.
	var offset_holed := _pitch_at_pin(ball, hole, 0.0, hole.cup_pixels() * 1.6)
	print("  landing %.1f px off the flag: %s" % [
		hole.cup_pixels() * 1.6, "IN" if offset_holed else "misses"])
	_expect(not offset_holed, "a miss should not be pulled into the cup")

	_check_wedges_are_not_free(hole, ball)


## The rule this replaced was brutally strict for a reason: make the cup too
## willing and every approach shot drops for an eagle. So fire real resolved
## wedge shots straight at the flag and count how many go in.
func _check_wedges_are_not_free(hole: HoleData, ball: Ball) -> void:
	var card := CardLibrary.copy(&"wedge")
	var profile := ShotProfile.from_card(card)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337

	var from := hole.pin_position - Vector2(80.0 * hole.pixels_per_yard, 0.0)
	var holed := 0
	for attempt in AIM_ATTEMPTS:
		_holed = false
		ball.reset_to(from)
		# Dialled to finish at the flag, aimed straight at it: the best a player
		# could realistically do, every single time.
		var power := clampf(80.0 / maxf(profile.max_reach_yards(), 1.0), 0.0, 1.0)
		var shot := ShotResolver.resolve(profile, power, Vector2.RIGHT, rng,
			hole.wind_vector())
		ball.launch(shot, hole.pixels_per_yard)
		for step in AIR_SHOTS:
			if _holed or not ball.is_moving():
				break
			ball._physics_process(1.0 / 60.0)
		if _holed:
			holed += 1

	var rate := 100.0 * holed / AIM_ATTEMPTS
	print("  perfect 80 yard wedges holed: %d of %d (%.1f%%)" % [
		holed, AIM_ATTEMPTS, rate])
	_expect(rate < 5.0, "wedge shots should not be free eagles")


## Fires one shot that touches down at (or beside) the flag and reports whether
## the cup took it. Driving the real Ball, so the test cannot drift from the game.
func _pitch_at_pin(ball: Ball, hole: HoleData, roll_yards: float,
		offset_px: float = 0.0) -> bool:
	_holed = false
	if not ball.holed_out.is_connected(_on_holed):
		ball.holed_out.connect(_on_holed)

	var target := hole.pin_position + Vector2(0.0, offset_px)
	var carry_px := 300.0
	ball.reset_to(target - Vector2(carry_px, 0.0))

	var shot := ShotResult.new()
	shot.direction = Vector2.RIGHT
	shot.carry_yards = hole.to_yards(carry_px)
	shot.roll_yards = roll_yards
	ball.launch(shot, hole.pixels_per_yard)

	# Fly it out by hand: the flight is time-based, so a fixed step is enough.
	for step in AIR_SHOTS:
		if _holed or not ball.is_moving():
			break
		ball._physics_process(1.0 / 60.0)
	return _holed


func _on_holed() -> void:
	_holed = true


# --- Something you can actually hit softly --------------------------------

func _check_short_game_rescue() -> void:
	print("")
	print("=== stuck by the green with nothing short ===")

	var hole := HoleGenerator.generate(13, 2, 1)
	var hole_view: HoleView = screen.get_node("HoleView")
	var ball: Ball = screen.get_node("HoleView/Ball")

	# A bag with one putter buried in it and a hand of nothing but drivers: the
	# exact position that produced a twelve.
	var cards: Array[CardData] = []
	for i in 6:
		cards.append(CardLibrary.copy(&"driver"))
	cards.append(CardLibrary.copy(&"putter"))

	hole_view.hole = hole
	hole_view.deck = Deck.new(cards)
	hole_view.start_hole()

	# Three yards from the cup, which no driver can be feathered down to.
	ball.reset_to(hole.pin_position - Vector2(3.0 * hole.pixels_per_yard, 0.0))
	hole_view.strokes = 2
	hole_view._begin_shot_turn()

	var gentlest := INF
	for card in hole_view.deck.hand:
		if card.is_shot():
			gentlest = minf(gentlest, ShotProfile.from_card(card).max_reach_yards())

	# The promise is the gentlest club you own, not a club you do not have.
	var gentlest_owned := INF
	for card in hole_view.deck.cards:
		if card.is_shot():
			gentlest_owned = minf(gentlest_owned,
				ShotProfile.from_card(card).max_reach_yards())

	print("  three yards out, gentlest club in hand reaches %.0f yd" % gentlest)
	print("  gentlest club anywhere in the bag reaches %.0f yd" % gentlest_owned)
	_expect(gentlest <= gentlest_owned + 0.01,
		"a hand by the green should hold the softest club in the bag")
	_expect(gentlest < 100.0,
		"a hand of nothing but drivers should not survive contact with a green")

	# From the tee the same rule must do nothing at all: it rescues you, it does
	# not caddie for you. Drawing a putter is fine; being stripped of the driver
	# you need to reach the green is not.
	hole_view.deck = Deck.new(cards)
	hole_view.start_hole()
	var longest := 0.0
	for card in hole_view.deck.hand:
		if card.is_shot():
			longest = maxf(longest, ShotProfile.from_card(card).max_reach_yards())
	print("  longest club left in hand on the tee: %.0f yd" % longest)
	_expect(longest > gentlest_owned,
		"the short-game rule should stay quiet off the tee")


# --- One hole cannot end the round ----------------------------------------

func _check_pick_up() -> void:
	print("")
	print("=== picking up ===")

	var hole := HoleGenerator.generate(17, 2, 1)
	var hole_view: HoleView = screen.get_node("HoleView")
	hole_view.hole = hole
	var bag: Array[CardData] = []
	for id in [&"driver", &"putter", &"wedge"]:
		bag.append(CardLibrary.copy(id))
	hole_view.deck = Deck.new(bag)
	hole_view.start_hole()

	_completed_strokes = -1
	_completed_holed = true
	if not hole_view.hole_completed.is_connected(_on_completed):
		hole_view.hole_completed.connect(_on_completed)

	# One stroke short of the maximum: play on.
	hole_view.strokes = hole.par + hole_view.max_over_par - 1
	hole_view._begin_shot_turn()
	print("  at %d on a par %d: still playing" % [hole_view.strokes, hole.par])
	_expect(_completed_strokes < 0, "the hole should not end early")

	hole_view.strokes = hole.par + hole_view.max_over_par
	hole_view._begin_shot_turn()
	print("  at par + %d: %s" % [
		hole_view.max_over_par,
		"picked up for %d" % _completed_strokes if _completed_strokes >= 0
			else "STILL PLAYING"])
	_expect(_completed_strokes == hole.par + hole_view.max_over_par,
		"the hole should cap at par + %d" % hole_view.max_over_par)
	_expect(not _completed_holed, "picking up is not holing out")

	# The cut is +8, so the cap has to leave room for more than one bad hole.
	var worst := hole_view.max_over_par
	print("  worst hole possible: +%d, cut at +%d, so it takes %d of them" % [
		worst, RunState.DEFAULT_CUT, RunState.DEFAULT_CUT / worst + 1])
	_expect(worst < RunState.DEFAULT_CUT,
		"one hole should never be able to end a run on its own")


func _on_completed(strokes: int, _par: int, holed: bool) -> void:
	_completed_strokes = strokes
	_completed_holed = holed


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)
