## Does the card add up?
##
## A scorecard is the one screen in the game a player can check by hand, which
## makes it the one screen that must never be approximately right. Two numbers
## describing the same round are allowed to disagree never -- the same rule that
## caught resting leaving the leaderboard behind, applied to the artefact the
## round actually produces.
extends SceneTree

const HOLES := 9

var failures := 0
var _screen: ScorecardScreen


func _initialize() -> void:
	_check_the_card_matches_the_round()
	_check_clawed_back_strokes_are_declared()
	_check_an_eighteen_folds_into_two_nines()

	# Drawing it is the other half: a card that computes correctly and paints
	# nothing is still a blank screen at the end of somebody's round.
	_screen = load("res://scenes/ui/scorecard_screen.tscn").instantiate()
	root.add_child(_screen)


func _process(_delta: float) -> bool:
	_check_it_draws()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)
	return true


func _check_the_card_matches_the_round() -> void:
	print("=== the card matches the round ===")
	var run := _round([4, 5, 3, 4, 6, 4, 3, 5, 4], [4, 4, 3, 5, 4, 4, 3, 4, 4])
	print("  %d holes, %d strokes against par %d, %s" % [
		run.holes_played, run.total_strokes, run.total_par, run.score_text()])
	_expect(run.card.size() == HOLES, "every hole played is on the card")
	_expect(run.card_strokes() == run.total_strokes,
		"the card adds up to the round's strokes (%d against %d)"
			% [run.card_strokes(), run.total_strokes])
	_expect(run.card_par() == run.total_par,
		"and to its par (%d against %d)" % [run.card_par(), run.total_par])

	# A place is stamped on every line, so the card can show where each hole
	# left you rather than only what you scored.
	for line in run.card:
		_expect(int(line["place"]) > 0, "every hole records where it left you")


## Resting takes strokes off the total but cannot un-play a hole. The card has
## to stay truthful about what was actually scored and declare the difference.
func _check_clawed_back_strokes_are_declared() -> void:
	print("")
	print("=== strokes taken back off the card ===")
	var run := _round([6, 6, 6, 6], [4, 4, 4, 4])
	var scored := run.total_strokes
	var taken := run.rest(2)
	print("  scored %d, clawed back %d, total now %d" % [
		scored, taken, run.total_strokes])
	_expect(taken == 2, "there were strokes to claw back")
	_expect(run.strokes_clawed_back == taken, "and the card knows how many")
	_expect(run.card_strokes() == run.total_strokes,
		"the card still agrees with the total (%d against %d)"
			% [run.card_strokes(), run.total_strokes])

	var written := 0
	for line in run.card:
		written += int(line["strokes"])
	_expect(written == scored,
		"the holes themselves are untouched -- you cannot un-play one")


## An eighteen is two nines, and a card shows it that way: OUT, IN, and a total.
func _check_an_eighteen_folds_into_two_nines() -> void:
	print("")
	print("=== an eighteen folds ===")
	var pars: Array[int] = []
	var strokes: Array[int] = []
	for i in 18:
		pars.append(4)
		strokes.append(4 if i % 3 else 5)
	var run := _round(strokes, pars)
	var view := ScorecardView.new()
	view.set_card(run.card, "test", 0)
	var slots: Array = view._total_slots()
	var names: PackedStringArray = PackedStringArray()
	for slot in slots:
		names.append(slot["name"])
	print("  columns: %s" % ", ".join(names))
	_expect(slots.size() == 3, "eighteen holes give OUT, IN and a total")
	_expect(names[0] == "OUT" and names[1] == "IN" and names[2] == "TOT",
		"and in that order")
	_expect(int(slots[2]["strokes"]) == run.total_strokes,
		"the total column is the round")
	_expect(int(slots[0]["strokes"]) + int(slots[1]["strokes"])
			== int(slots[2]["strokes"]),
		"and the two nines add up to it")
	view.free()

	var nine := _round([4, 4, 4, 4, 4, 4, 4, 4, 4], [4, 4, 4, 4, 4, 4, 4, 4, 4])
	var short_view := ScorecardView.new()
	short_view.set_card(nine.card, "test", 0)
	_expect(short_view._total_slots().size() == 1,
		"a nine gets one total column, not three")
	short_view.free()


func _check_it_draws() -> void:
	print("")
	print("=== it actually draws ===")
	var run := _round([4, 5, 3, 4, 6, 4, 3, 5, 4], [4, 4, 3, 5, 4, 4, 3, 4, 4])
	_screen.show_card(run, TourLibrary.opening(), true, null)
	var view: ScorecardView = _screen.get_node("CardPanel/Card")
	_expect(view.lines.size() == HOLES, "the view was handed the card")
	_expect(view.size.x > 100.0,
		"and has somewhere to draw it (%.0f wide)" % view.size.x)
	# The marks are what make it readable, so the round above is chosen to
	# contain one of each: a birdie, a par, a bogey and a double.
	var shapes := {"birdie": 0, "par": 0, "bogey": 0, "worse": 0}
	for line in run.card:
		var over: int = int(line["strokes"]) - int(line["par"])
		if over < 0:
			shapes["birdie"] += 1
		elif over == 0:
			shapes["par"] += 1
		elif over == 1:
			shapes["bogey"] += 1
		else:
			shapes["worse"] += 1
	print("  %d birdies, %d pars, %d bogeys, %d worse"
		% [shapes["birdie"], shapes["par"], shapes["bogey"], shapes["worse"]])
	for kind in shapes:
		_expect(shapes[kind] > 0,
			"the drawing check should exercise a %s and does not" % kind)


func _round(strokes: Array, pars: Array) -> RunState:
	var run := RunState.new()
	run.round_holes = strokes.size()
	run.leaderboard = Leaderboard.new(99)
	for i in strokes.size():
		run.record_hole(int(strokes[i]), int(pars[i]))
	return run


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)
