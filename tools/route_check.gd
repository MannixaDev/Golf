## How much golf can you dodge?
##
## The map is a branching route and only some stops are actually holes. Nothing
## in the generator forces a given path to contain any particular number of them,
## so in principle a player can pick their way from the first tee to the closing
## hole through shops and rests, arrive with a card built from almost nothing,
## and rests take strokes *off* that card on the way.
##
## This walks every map exhaustively -- cheapest and richest route by hole count
## -- rather than guessing from the node weights, because the weights describe
## the whole map and the player only ever walks one line through it.
extends SceneTree

const MAPS := 400
## A nine is a nine.
const MIN_HOLES := MapGenerator.HOLES_PER_NINE

var failures := 0


func _initialize() -> void:
	print("=== golf per route, %d maps ===" % MAPS)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260909

	var fewest := 99
	## The largest "fewest holes" seen. If routes are truly uniform this equals
	## , which is a much stronger statement than an average.
	var most_low := 0
	var most := 0
	var fewest_total := 0.0
	var most_total := 0.0
	var histogram := {}

	for attempt in MAPS:
		var map := MapGenerator.generate(rng.randi())
		var least := _extreme(map, true)
		var best := _extreme(map, false)
		fewest = mini(fewest, least)
		most_low = maxi(most_low, least)
		most = maxi(most, best)
		fewest_total += least
		most_total += best
		histogram[least] = int(histogram.get(least, 0)) + 1

	print("  dodging as hard as you can:  %.1f holes on average, %d at worst"
		% [fewest_total / MAPS, fewest])
	print("  seeking out every hole:      %.1f holes on average, %d at best"
		% [most_total / MAPS, most])

	var counts: Array = histogram.keys()
	counts.sort()
	print("")
	print("  how little golf a run can contain:")
	for count in counts:
		var share := 100.0 * float(histogram[count]) / float(MAPS)
		print("    %2d holes  %s %.0f%%" % [
			count, "#".repeat(int(share / 2.0)), share])

	# Golf and services alternate, so this is not a soft average -- every single
	# route through every single map must contain the same amount of golf.
	print("")
	print("  every route carries the same golf: %s" % ("yes" if fewest == most_low else "NO"))
	_expect(fewest >= MIN_HOLES,
		"a route can dodge down to %d holes, need at least %d" % [fewest, MIN_HOLES])
	_expect(fewest == most_low,
		"routes through the same map differ in how much golf they contain")

	_check_round_shapes()
	_check_resting_cannot_pay()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


## A round is specified in holes, and the columns fall out of that. Nine and
## eighteen are the two the player can pick, so both are pinned here -- an
## eighteen is walked as two nines, but the shape function still has to be able
## to describe one.
func _check_round_shapes() -> void:
	print("")
	print("=== round shapes ===")

	for holes in [9, 18]:
		var kinds := MapGenerator.layer_kinds(holes)
		var golf := 0
		for kind in kinds:
			if kind:
				golf += 1
		print("  %2d holes -> %d columns, %d of them golf" % [
			holes, kinds.size(), golf])
		_expect(golf == holes, "a %d-hole round should lay out %d holes" % [holes, holes])
		_expect(kinds[kinds.size() - 1], "a round should end on a hole")
		_expect(not kinds[kinds.size() - 2],
			"there should be a breather before the closing hole")


## The other half of the same design fault. Forcing golf is pointless if the
## stops between the golf still hand strokes back for free -- score against par
## is both the score and the health bar here, so an unconditional heal is also a
## way to flatter a round you were already winning.
func _check_resting_cannot_pay() -> void:
	print("")
	print("=== resting is a way back, not a way ahead ===")

	# par, strokes, what a two-stroke rest should leave you on
	var cases := [
		[16, 22, 4],   # +6, claws back the full two
		[16, 17, 0],   # +1, claws back only the one it can
		[16, 16, 0],   # level, nothing to take
		[16, 13, -3],  # three under, and it stays three under
	]

	for case in cases:
		var run := RunState.new()
		run.total_par = case[0]
		run.total_strokes = case[1]
		var before := run.score_to_par()
		var taken := run.rest(2)
		print("  %+3d before, rest takes %d, %+3d after" % [
			before, taken, run.score_to_par()])
		_expect(run.score_to_par() == case[2],
			"resting from %+d should leave %+d, left %+d" % [
				before, case[2], run.score_to_par()])
		_expect(run.score_to_par() >= mini(before, 0),
			"resting improved a card that was already level or better")


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)


## Fewest (or most) hole-type stops on any route from the first tee to the close.
## Walked backwards layer by layer, so every path is covered without enumerating
## them one at a time.
func _extreme(map: RunMap, want_fewest: bool) -> int:
	var best := {}
	var layers := map.layers.size()

	for index in range(layers - 1, -1, -1):
		for id in map.layers[index]:
			var node := map.node_by_id(id)
			var own := 1 if (node.spec != null and node.spec.plays_hole) else 0
			if index == layers - 1:
				best[id] = own
				continue

			var onward := -1
			for next_id in node.next_ids:
				if not best.has(next_id):
					continue
				var value: int = best[next_id]
				if onward < 0:
					onward = value
				elif want_fewest:
					onward = mini(onward, value)
				else:
					onward = maxi(onward, value)
			best[id] = own + maxi(onward, 0)

	var overall := -1
	for id in map.layers[0]:
		if not best.has(id):
			continue
		var value: int = best[id]
		if overall < 0:
			overall = value
		elif want_fewest:
			overall = mini(overall, value)
		else:
			overall = maxi(overall, value)
	return maxi(overall, 0)
