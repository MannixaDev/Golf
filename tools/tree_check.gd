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

	screen = load("res://scenes/run/hole_screen.tscn").instantiate()
	screen.setup(HoleGenerator.generate(5, 1, 1), Deck.new())
	root.add_child(screen)


func _process(_delta: float) -> bool:
	_check_shots_through_a_wood()

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


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)
