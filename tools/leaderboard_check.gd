## Is the field a tournament or a dice roll?
##
## The whole value of playing against a leaderboard rather than a cut line is
## that the names on it mean something. If the man at the top is whoever the die
## favoured this week, the board is decoration and beating it is luck. So this
## plays a great many tournaments and asks the only questions that matter:
##
##   does the best player finish near the top nearly every week?
##   is the field spread out enough that positions actually move?
##   does par put you in the middle of it, and does winning need a real round?
extends SceneTree

const TOURNAMENTS := 400
const HOLES := 9

var failures := 0


func _initialize() -> void:
	_check_the_ringer_is_always_there()
	_check_the_field_spreads()
	_check_what_a_round_is_worth()
	_check_nerve()
	_check_the_card_and_the_board_agree()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


## The point of a fixed skill rather than a die: the best player in the field is
## up there every single week, so you can plan a round that beats him instead of
## hoping he has a bad one.
func _check_the_ringer_is_always_there() -> void:
	print("=== is the best player always near the top ===")

	var places := {}
	var totals := {}
	for tournament in TOURNAMENTS:
		var board := _play(tournament, 0)
		for entry in board.entries:
			if entry.is_player:
				continue
			places[entry.name] = places.get(entry.name, 0.0) + entry.place
			totals[entry.name] = totals.get(entry.name, 0) + 1

	var ranked: Array = places.keys()
	ranked.sort_custom(func(a, b) -> bool:
		return places[a] / totals[a] < places[b] / totals[b])

	for name in ranked:
		print("  %-26s average finish %.1f  (%d starts)" % [
			name, places[name] / totals[name], totals[name]])

	var best: String = ranked[0]
	_expect(best.contains("Woodlouse"),
		"the best player in the field should finish top on average, not %s" % best)
	_expect(places[best] / totals[best] < 3.0,
		"the ringer averages %.1f, which is not a ringer"
			% (places[best] / totals[best]))

	# And he must not be *unbeatable* -- a rival who always wins is a wall.
	var wins := 0
	for tournament in TOURNAMENTS:
		var board := _play(tournament, 0)
		if board.entries[0].name.contains("Woodlouse"):
			wins += 1
	var share := 100.0 * wins / TOURNAMENTS
	print("  he wins %.0f%% of them outright against a field playing level" % share)
	_expect(share < 70.0, "the best player wins too often to be worth chasing")


func _check_the_field_spreads() -> void:
	print("")
	print("=== is the field spread out ===")

	var top := 0.0
	var bottom := 0.0
	var middle := 0.0
	for tournament in TOURNAMENTS:
		var board := _play(tournament, 0)
		var scores: Array[int] = []
		for entry in board.entries:
			if not entry.is_player:
				scores.append(entry.to_par)
		scores.sort()
		top += scores[0]
		middle += scores[scores.size() / 2]
		bottom += scores[scores.size() - 1]

	top /= TOURNAMENTS
	middle /= TOURNAMENTS
	bottom /= TOURNAMENTS
	print("  over %d holes the winner shoots %+.1f" % [HOLES, top])
	print("  the middle of the field shoots      %+.1f" % middle)
	print("  the back marker shoots              %+.1f" % bottom)

	_expect(top < -4.0, "winning only takes %+.1f, which is not a tournament" % top)
	_expect(bottom - top > 6.0,
		"the whole field finishes within %.1f strokes of each other"
			% (bottom - top))


## What the player has to shoot to place. The benchmark asked for was par or a
## little over sitting mid-table, and winning needing a real round.
func _check_what_a_round_is_worth() -> void:
	print("")
	print("=== what your round is worth ===")

	var placings := {}
	for score in [4, 2, 0, -2, -4, -6, -8, -10]:
		var total := 0.0
		for tournament in TOURNAMENTS:
			total += _play(tournament, score).player_place()
		placings[score] = total / TOURNAMENTS
		print("  %+3d over the round finishes %4.1f of %d" % [
			score, placings[score], Leaderboard.FIELD_SIZE + 1])

	var field: int = Leaderboard.FIELD_SIZE + 1
	_expect(placings[0] > field * 0.35 and placings[0] < field * 0.75,
		"level par finishes %.1f, which is not mid-table" % placings[0])
	_expect(placings[2] > placings[0],
		"playing worse should cost you places")
	_expect(placings[-6] < 3.5,
		"six under only gets you %.1f, so the board is unbeatable"
			% placings[-6])
	_expect(placings[-2] > 3.0,
		"two under already finishes %.1f, so there is nothing to chase"
			% placings[-2])


## Some of them tighten up in front. It should show, without deciding everything.
func _check_nerve() -> void:
	print("")
	print("=== the ones who feel it ===")

	for id in [&"normal", &"foldover", &"woodlouse"]:
		var spec: RivalSpec = null
		for candidate in Leaderboard.roster():
			if candidate.id == id:
				spec = candidate
		if spec == null:
			continue
		var relaxed := 0.0
		var leading := 0.0
		for i in 600:
			relaxed += spec.score_for_hole(i, 0.0)
			leading += spec.score_for_hole(i, 1.0)
		print("  %-22s %+.2f a hole normally, %+.2f in front" % [
			spec.display_name, relaxed / 600.0, leading / 600.0])
		if spec.nerve > 0.2:
			_expect(leading > relaxed,
				"%s is supposed to feel it and does not" % spec.display_name)


## Anything that edits the card after the fact has to move you on the board too.
##
## It did not. Resting at the halfway house took strokes off your score and left
## your position untouched -- so the one stop sold as a way back into a run moved
## you precisely nowhere, on a cut that is decided by position. Two numbers
## describing the same round are allowed to disagree never.
func _check_the_card_and_the_board_agree() -> void:
	print("")
	print("=== the card and the board agree ===")

	var run := RunState.new()
	run.round_holes = HOLES
	run.leaderboard = Leaderboard.new(7)
	for hole in 4:
		run.record_hole(6, 4)
	var before := run.leaderboard.player_place()
	_expect(run.score_to_par() == run.leaderboard.player().to_par,
		"the card and the board start out saying the same thing")

	var taken := run.rest(2)
	print("  +8 at %s, rested %d strokes, now %s at %s" % [
		Leaderboard.ordinal(before), taken, run.score_text(),
		Leaderboard.ordinal(run.leaderboard.player_place())])
	_expect(taken == 2, "there were strokes there to claw back")
	_expect(run.score_to_par() == run.leaderboard.player().to_par,
		"and they still say the same thing afterwards")
	_expect(run.leaderboard.player_place() < before,
		"resting should actually move you up the board")

	# And the other half of the rule: resting at level does nothing at all, to
	# the card or to the board.
	var level := RunState.new()
	level.round_holes = HOLES
	level.leaderboard = Leaderboard.new(7)
	for hole in 4:
		level.record_hole(4, 4)
	var held := level.leaderboard.player_place()
	_expect(level.rest(2) == 0, "there is nothing to claw back at level")
	_expect(level.leaderboard.player_place() == held,
		"so the board does not move either")


## One tournament, with the player shooting `player_total` spread over the round.
func _play(tournament: int, player_total: int) -> Leaderboard:
	var board := Leaderboard.new(tournament * 7717 + 13)
	for hole in HOLES:
		# Spread as evenly as it divides, so the player's running position is
		# sensible on the way round rather than arriving all at once.
		var so_far := roundi(float(player_total) * hole / HOLES)
		var next := roundi(float(player_total) * (hole + 1) / HOLES)
		board.record_hole(next - so_far)
	return board


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)
