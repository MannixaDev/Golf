## Asserts what trees do to a shot in the air.
##
## Trees are the only thing on the course that occupies the *sky*. Everything
## else -- sand, water, rough -- is judged where the ball comes down. That makes
## this the one mechanic the two-phase shot model has never had to express, and
## the one place a bug is completely invisible: a tree that quietly does nothing
## looks exactly like a tree you happened to fly over.
##
## The rule under test, in three bands:
##
##   over the canopy      clears, nothing happens
##   into the branches    drops straight down, no run
##   under the trunks     passes through, which is why a punch exists
extends SceneTree

const STEPS := 400

var failures := 0
var screen: HoleScreen = null

var _struck := false


func _initialize() -> void:
	_check_only_trees_stand_up()
	_check_the_bands()
	_check_the_hitbox_matches_the_picture()
	_check_the_avenue_stays_open()

	screen = load("res://scenes/run/hole_screen.tscn").instantiate()
	screen.setup(HoleGenerator.generate(5, 1, 1), Deck.new())
	root.add_child(screen)


func _process(_delta: float) -> bool:
	_check_shots_through_a_wood()
	_check_the_warning_matches_the_shot()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)
	return true


# --- Data -----------------------------------------------------------------

func _check_only_trees_stand_up() -> void:
	print("=== what stands up out of the ground ===")

	for id in SurfaceLibrary.all_ids():
		var surface := SurfaceLibrary.by_id(id)
		if not surface.has_canopy():
			continue
		print("  %-11s trunks to %.0f yd, canopy to %.0f yd" % [
			id, surface.trunk_clear_yards, surface.canopy_top_yards])
		_expect(surface.trunk_clear_yards < surface.canopy_top_yards,
			"%s has a canopy that starts above where it ends" % id)

	var trees := SurfaceLibrary.by_id(&"deep_rough")
	_expect(trees != null and trees.has_canopy(), "deep rough should have a canopy")

	# Everything you can play a shot *over* must not also be in the air.
	for id in [&"fairway", &"green", &"rough", &"bunker", &"water", &"tee"]:
		var surface := SurfaceLibrary.by_id(id)
		_expect(surface == null or not surface.has_canopy(),
			"%s should not be standing in the air" % id)


func _check_the_bands() -> void:
	print("")
	print("=== the three bands ===")

	var trees := SurfaceLibrary.by_id(&"deep_rough")
	if trees == null:
		_expect(false, "no deep rough to test")
		return

	var under := trees.trunk_clear_yards * 0.5
	var into := (trees.trunk_clear_yards + trees.canopy_top_yards) * 0.5
	var over := trees.canopy_top_yards + 4.0

	print("  %.0f yd (under the trunks): %s" % [
		under, "blocked" if trees.blocks_at_height(under) else "through"])
	print("  %.0f yd (into the branches): %s" % [
		into, "blocked" if trees.blocks_at_height(into) else "through"])
	print("  %.0f yd (over the top): %s" % [
		over, "blocked" if trees.blocks_at_height(over) else "through"])

	_expect(not trees.blocks_at_height(under), "a low shot should go under")
	_expect(trees.blocks_at_height(into), "a shot at branch height should be stopped")
	_expect(not trees.blocks_at_height(over), "a high shot should clear")
	_expect(not trees.blocks_at_height(0.0), "a putt should not hit a tree")


# --- The real ball --------------------------------------------------------

## Everything above is arithmetic. This drives the actual Ball down an actual
## hole with an actual tree on it, because the arithmetic being right is no use
## if nothing ever asks it the question.
func _check_shots_through_a_wood() -> void:
	print("")
	print("=== shots at a tree ===")

	var hole := screen.get_node("HoleView").hole as HoleData
	var ball: Ball = screen.get_node("HoleView/Ball")
	if not ball.struck_canopy.is_connected(_on_struck):
		ball.struck_canopy.connect(_on_struck)

	var start := hole.tee_position

	# A 9 iron peaks around 30 yards up, so it is inside the branch band briefly
	# after take-off and again on the way down, and clear of it in between. That
	# is the whole shape of the mechanic: the dangerous trees are the ones just
	# in front of you and the ones just short of your target.
	for distance in [18.0, 65.0, 112.0]:
		var blocked := _fire(hole, ball, start, &"iron_9", 1.0, distance)
		print("  9 iron over a tree at %3.0f yd: %s" % [
			distance, "stopped" if blocked else "cleared"])
		if distance == 65.0:
			_expect(not blocked, "a mid-flight tree should be flown over")

	var near_blocked := _fire(hole, ball, start, &"iron_9", 1.0, 18.0)
	_expect(near_blocked, "a tree just in front of you should stop a full shot")

	# The answer to a tree in your face. A punch never gets above the trunks.
	var punched := _fire(hole, ball, start, &"iron_9", 1.0, 18.0, &"punch")
	print("  punched 9 iron at the same tree: %s" % [
		"stopped" if punched else "went under"])
	_expect(not punched, "a punch should go under the branches")

	# And the answer for anyone without a punch card: hit it softly. Apex scales
	# with carry, so a quarter swing stays under the trunks too. Nobody is ever
	# stranded under a tree with no way out, which is the trap this mechanic
	# would otherwise be.
	var feathered := _fire(hole, ball, start, &"iron_9", 0.25, 18.0)
	print("  quarter-swing 9 iron at the same tree: %s" % [
		"stopped" if feathered else "went under"])
	_expect(not feathered, "a soft shot should stay under the branches")


## Put one tree at `distance` yards down the line, hit one shot at it, and say
## whether the tree stopped it. The hole is left as it was found.
func _fire(hole: HoleData, ball: Ball, from: Vector2,
		card_id: StringName, power: float, distance: float,
		technique: StringName = &"") -> bool:
	var kept := hole.hazards.duplicate()

	var tree := HazardRegion.new()
	tree.surface_id = &"deep_rough"
	tree.shape = HazardRegion.Shape.CIRCLE
	tree.centre = from + Vector2.RIGHT * distance * hole.pixels_per_yard
	tree.radius = 7.0 * hole.pixels_per_yard
	hole.hazards.append(tree)

	var card := CardLibrary.copy(card_id)
	var profile := ShotProfile.from_card(card)
	if technique != &"":
		# Folded in the way HoleView folds it, so the test cannot drift from a
		# card whose numbers somebody changes later.
		var modifiers: Array[CardEffect] = []
		for effect in CardLibrary.copy(technique).effects:
			if effect != null and effect.is_shot_modifier():
				modifiers.append(effect)
		profile.apply_effects(modifiers)
		if modifiers.is_empty():
			_expect(false, "%s carries no shot modifier to test with" % technique)

	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var shot := ShotResolver.resolve(profile, power, Vector2.RIGHT, rng,
		Vector2.ZERO)
	# Straight, so the only thing being tested is height.
	shot.direction = Vector2.RIGHT
	shot.curve_offset_yards = 0.0
	shot.wind_drift_yards = Vector2.ZERO

	_struck = false
	ball.reset_to(from)
	ball.launch(shot, hole.pixels_per_yard)
	for step in STEPS:
		if _struck or not ball.is_moving():
			break
		ball._physics_process(1.0 / 60.0)

	hole.hazards = kept
	return _struck


func _on_struck(_pos: Vector2) -> void:
	_struck = true


## The canopy that catches the ball has to be the canopy you can see.
##
## It was not: the hit test was the bounding circle while the picture was a main
## blob at four fifths of it plus a couple of satellites, so a gap you could see
## was not a gap you could hit through.
func _check_the_hitbox_matches_the_picture() -> void:
	print("")
	print("=== the canopy you can see is the one that stops you ===")

	var tree := HazardRegion.new()
	tree.surface_id = &"deep_rough"
	tree.shape = HazardRegion.Shape.CIRCLE
	tree.centre = Vector2.ZERO
	tree.radius = 40.0

	# Sampled on a grid: what fraction of the bounding circle is actually solid,
	# and is every solid point inside one of the drawn blobs?
	var inside := 0
	var tested := 0
	var outside_a_blob := 0
	for x in range(-40, 41, 2):
		for y in range(-40, 41, 2):
			var point := Vector2(float(x), float(y))
			if point.length() > tree.radius:
				continue
			tested += 1
			if not tree.contains(point):
				continue
			inside += 1
			var covered := false
			for blob in tree.blobs():
				if point.distance_to(blob.position) <= blob.size.x:
					covered = true
					break
			if not covered:
				outside_a_blob += 1

	var solid := float(inside) / float(maxi(tested, 1))
	print("  %.0f%% of the bounding circle is solid (was 100%%)" % (solid * 100.0))
	_expect(outside_a_blob == 0,
		"every point that stops a ball is inside a blob that is drawn")
	_expect(solid < 0.92,
		"the hitbox should be smaller than the circle it used to be")
	_expect(solid > 0.45,
		"but a tree should still be mostly tree")

	# And the middle of a clump is always solid, or trees would be full of holes.
	_expect(tree.contains(tree.centre), "the middle of a tree is a tree")
	_expect(not tree.contains(Vector2(tree.radius * 1.4, 0.0)),
		"and well outside it is not")


## The warning has to agree with the outcome, every time.
##
## This is the only thing that matters about it. A red line that is right most of
## the time is worse than no line at all: you would start playing around trees
## that were not there, and trusting it exactly when it was wrong.
##
## So: fly the real ball at a real wood from a hundred directions, and check the
## overlay said so beforehand.
func _check_the_warning_matches_the_shot() -> void:
	print("")
	print("=== the warning agrees with the ball ===")

	var view: HoleView = screen.get_node("HoleView")
	var aim: AimController = screen.get_node("HoleView/AimController")
	var hole: HoleData = view.hole
	var profile := ShotProfile.from_card(CardLibrary.template(&"iron_9"))
	aim.shot_profile = profile
	aim.sampler = SurfaceSampler.new(hole)
	aim.pixels_per_yard = hole.pixels_per_yard
	aim.wind = Vector2.ZERO
	# The hole moves the overlay onto the ball every frame; a harness that skips
	# that is aiming from the corner of the world and will never hit anything.
	aim.position = hole.tee_position

	# A tree planted where it is certain to matter, rather than trusting the
	# generator to have put one in range. Near the start of the carry, where the
	# ball is still climbing through the branches -- at half the carry a 9 iron
	# is at its apex and sails over, which is what the first attempt at this
	# measured, twice, while reporting nothing at all.
	var planted := HazardRegion.new()
	planted.surface_id = &"deep_rough"
	planted.shape = HazardRegion.Shape.CIRCLE
	planted.centre = hole.tee_position 		+ Vector2(profile.carry_yards_max * 0.15 * hole.pixels_per_yard, 0.0)
	planted.radius = 46.0
	hole.hazards.append(planted)

	var warned := 0
	var struck := 0
	var disagreed := 0
	var tried := 0
	for i in 120:
		var angle := TAU * float(i) / 120.0
		aim.aim_direction = Vector2.RIGHT.rotated(angle)
		var says := aim.blocked_by_canopy(1.0)

		# Now fly it, exactly as Ball does: the same arc, the same sampler.
		var carry_px: float = profile.carry_yards_max * hole.pixels_per_yard
		var apex := profile.apex_yards(1.0)
		var hits := false
		for step in 400:
			var t := float(step) / 399.0
			var at: Vector2 = aim.global_position 				+ aim.aim_direction * carry_px * t
			if hole.surface_at(at).blocks_at_height(apex * sin(PI * t)):
				hits = true
				break

		tried += 1
		if says:
			warned += 1
		if hits:
			struck += 1
		if says != hits:
			disagreed += 1

	print("  %d directions: warned on %d, hit a tree on %d, disagreed %d times"
		% [tried, warned, struck, disagreed])
	_expect(disagreed == 0,
		"the warning and the ball must never disagree (%d of %d did)"
			% [disagreed, tried])
	# And it has to be discriminating: a warning that never fires, or always
	# fires, is not telling you anything.
	_expect(warned > 0, "the warning never fired on a hole full of trees")
	_expect(warned < tried, "the warning fired in every direction")


## Woodland holes must still be holes.
##
## An avenue of trees is only interesting if the avenue is open: a clump standing
## in the middle of the fairway is not a decision, it is a hole you cannot play
## down. So the line of play is walked on every generated hole and must be clear.
func _check_the_avenue_stays_open() -> void:
	print("")
	print("=== woodland holes are still playable ===")

	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var woodland := 0
	var open := 0
	var wood_trees := 0
	var open_trees := 0
	var blocked := 0

	for i in 240:
		var hole := HoleGenerator.generate(rng.randi(), 1 + i % 4, 1)
		var trees := 0
		for region in hole.hazards:
			if region != null and region.surface().has_canopy():
				trees += 1
		if hole.woodland:
			woodland += 1
			wood_trees += trees
		else:
			open += 1
			open_trees += trees

		# Walk the fairway spine, not a straight line from tee to pin. The
		# straight line cuts the corner of every dogleg and goes through the
		# trees on purpose -- measuring that instead reported 154 of 240 holes
		# blocked, on a generator that was working correctly.
		for point in hole.spine:
			if hole.surface_at(point).has_canopy():
				blocked += 1
				break

	print("  %d woodland holes, %.1f trees each" % [
		woodland, float(wood_trees) / maxf(woodland, 1)])
	print("  %d open holes, %.1f trees each" % [
		open, float(open_trees) / maxf(open, 1)])
	print("  holes with a tree on the line of play: %d" % blocked)

	_expect(woodland > 0, "some holes should be cut through woodland")
	_expect(open > 0, "and some should be out in the open")
	_expect(float(wood_trees) / maxf(woodland, 1)
			> float(open_trees) / maxf(open, 1) * 2.5,
		"a woodland hole should be markedly more wooded than an open one")
	_expect(blocked == 0,
		"%d holes had a tree standing on the line of play" % blocked)


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)
