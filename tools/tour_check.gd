## Is the ladder actually a ladder?
##
## A difficulty tier list is the easiest thing in a game to get wrong quietly,
## because every rung *reads* harder in the .tres whatever the numbers do. What
## matters is what a round is worth on each: the same card has to be worth a
## worse finish further up, the cut has to bite harder, and the gap between
## consecutive rungs has to be big enough to notice and small enough to climb.
##
## So this plays several hundred tournaments on every rung and measures.
extends SceneTree

const TOURNAMENTS := 300
const HOLES := 9
## The score a competent round posts, used as the yardstick up the ladder.
const GOOD_ROUND := -3
## Level par should be a respectable week at the bottom and nowhere near it at
## the top, which is the whole point of having rungs.
const PAR_MUST_BEAT_AT_BOTTOM := 0.55

var failures := 0


func _initialize() -> void:
	TourLibrary.ensure_loaded()

	_check_the_rungs_are_ordered()
	_check_each_rung_is_harder()
	_check_the_climb_is_worth_it()
	_check_unlocking()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


func _check_the_rungs_are_ordered() -> void:
	print("=== the ladder ===")
	var tours := TourLibrary.all()
	_expect(tours.size() >= 3, "a ladder needs rungs")
	for i in tours.size():
		var tour: TourSpec = tours[i]
		print("  %d  %-18s %s" % [tour.rung, tour.display_name, tour.summary()])
		_expect(tour.rung == i, "rung %d is numbered %d" % [i, tour.rung])
		if i == 0:
			_expect(is_zero_approx(tour.field_skill_delta),
				"the opening rung should be the plain game")
			continue
		var below: TourSpec = tours[i - 1]
		_expect(tour.field_skill_delta < below.field_skill_delta,
			"%s should have a better field than %s"
				% [tour.display_name, below.display_name])
		_expect(tour.cut_share >= below.cut_share,
			"%s should not cut more gently than %s"
				% [tour.display_name, below.display_name])
		# Harder has to pay, or climbing is punishment.
		_expect(tour.winnings_multiplier > below.winnings_multiplier,
			"%s should pay better than %s"
				% [tour.display_name, below.display_name])


## The measurement: the same round, posted on every rung.
func _check_each_rung_is_harder() -> void:
	print("")
	print("=== what a round is worth up the ladder ===")

	# Sentinels the first rung is not compared against: it has nothing below it,
	# and measuring it against an impossible number failed it every time.
	var previous_par := -1.0
	var previous_good := -1.0
	for tour in TourLibrary.all():
		var at_par := _average_place(tour, 0)
		var at_good := _average_place(tour, GOOD_ROUND)
		var survives := _cut_survival(tour, 0)
		print("  %-18s level par finishes %.1f, %d under finishes %.1f, "
				% [tour.display_name, at_par, -GOOD_ROUND, at_good]
			+ "par makes the cut %.0f%% of weeks" % (survives * 100.0))

		_expect(at_good < at_par,
			"%s: playing well should still beat playing level" % tour.display_name)
		_expect(at_par >= previous_par - 0.01,
			"%s: level par should not finish better than on the rung below"
				% tour.display_name)
		_expect(at_good >= previous_good - 0.01,
			"%s: a good round should not finish better than on the rung below"
				% tour.display_name)
		previous_par = at_par
		previous_good = at_good

	var bottom: TourSpec = TourLibrary.opening()
	var top: TourSpec = TourLibrary.all()[TourLibrary.all().size() - 1]
	_expect(_cut_survival(bottom, 0) >= PAR_MUST_BEAT_AT_BOTTOM,
		"level par should usually survive the opening rung")
	_expect(_cut_survival(top, 0) < _cut_survival(bottom, 0) - 0.15,
		"and should be a far worse week at the top")


## Each step has to be noticeable without being a wall.
func _check_the_climb_is_worth_it() -> void:
	print("")
	print("=== the size of each step ===")
	var tours := TourLibrary.all()
	for i in range(1, tours.size()):
		var below := _average_place(tours[i - 1], GOOD_ROUND)
		var above := _average_place(tours[i], GOOD_ROUND)
		var step := above - below
		print("  %-18s a good round costs you %.1f places against %s"
			% [tours[i].display_name, step, tours[i - 1].display_name])
		_expect(step >= 0.4,
			"%s is not meaningfully harder than the rung below"
				% tours[i].display_name)
		_expect(step <= 4.0,
			"%s is a wall rather than a step" % tours[i].display_name)


func _check_unlocking() -> void:
	print("")
	print("=== earning the next rung ===")
	TourLibrary.reset_career()
	_expect(TourLibrary.unlocked_rung == 0, "a new career starts at the bottom")
	_expect(TourLibrary.is_unlocked(TourLibrary.opening()),
		"and the opening rung is playable")
	_expect(not TourLibrary.is_unlocked(TourLibrary.by_rung(1)),
		"but the one above it is not")

	# Missing the cut teaches you nothing and opens nothing.
	TourLibrary.record_result(TourLibrary.opening(), 9, false)
	_expect(TourLibrary.unlocked_rung == 0,
		"missing the cut should not open the next rung")

	_expect(TourLibrary.record_result(TourLibrary.opening(), 4, true),
		"finishing a round should open the next rung")
	_expect(TourLibrary.is_unlocked(TourLibrary.by_rung(1)),
		"and it should stay open")
	_expect(TourLibrary.best_on(TourLibrary.opening()) == 4,
		"a finish should be remembered")
	TourLibrary.record_result(TourLibrary.opening(), 7, true)
	_expect(TourLibrary.best_on(TourLibrary.opening()) == 4,
		"and a worse one afterwards should not overwrite it")

	# The top of the ladder must not open a rung that does not exist.
	var top: TourSpec = TourLibrary.all()[TourLibrary.all().size() - 1]
	TourLibrary.unlocked_rung = top.rung
	TourLibrary.record_result(top, 1, true)
	_expect(TourLibrary.unlocked_rung == top.rung,
		"winning the last rung should not invent another")
	TourLibrary.reset_career()
	print("  career reset, %d rungs, top is %s"
		% [TourLibrary.all().size(), top.display_name])


# --- Plumbing -------------------------------------------------------------

## Where a player shooting `total` finishes on this rung, averaged over a lot of
## weeks. The player's score is spread evenly across the round so their running
## position makes sense on the way.
func _average_place(tour: TourSpec, total: int) -> float:
	var sum := 0.0
	for tournament in TOURNAMENTS:
		sum += float(_play(tour, tournament, total).player_place())
	return sum / float(TOURNAMENTS)


## How often that card survives the cut on this rung.
func _cut_survival(tour: TourSpec, total: int) -> float:
	var survived := 0
	for tournament in TOURNAMENTS:
		var board := _play(tour, tournament, total, roundi(HOLES * 0.55))
		var through := ceili(board.field_size() * (1.0 - tour.cut_share))
		if board.player_place() <= through:
			survived += 1
	return float(survived) / float(TOURNAMENTS)


func _play(tour: TourSpec, tournament: int, total: int,
		holes: int = HOLES) -> Leaderboard:
	var board := Leaderboard.new(tournament * 7717 + 13, tour.field_skill_delta)
	for hole in holes:
		var so_far := roundi(float(total) * hole / HOLES)
		var next := roundi(float(total) * (hole + 1) / HOLES)
		board.record_hole(next - so_far)
	return board


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)
