## What goes in the hole, and what it looks like when it does not.
##
## The green suite already measures break and pace. This one is about the last
## inch, which turned out to be where the game was lying to the player: the ball
## was drawn at a flat 1.5 pixels against a cup the generator makes 1.43 wide, so
## it was wider than the entire hole and blotted out the target it was aiming at.
## A putt resting three ball-widths short of the cup covered it completely and
## looked stone dead. Nothing was wrong with what went in. Everything was wrong
## with what it looked like, and no harness here was watching the picture.
##
## So the first check is a drawing check with teeth, and the rest measure the
## price of the two mechanics added alongside it -- the lip-out, and the ball
## that hangs over the edge -- because neither is allowed to quietly make putting
## easier.
extends SceneTree

const STEPS := 3000
## What the camera is doing when you are actually putting.
const PUTTING_ZOOM := 5.2

var failures := 0
var screen: HoleScreen = null
var _holed := false
var _topples := 0


func _initialize() -> void:
	screen = load("res://scenes/run/hole_screen.tscn").instantiate()
	screen.setup(HoleGenerator.generate(3, 2, 1), Deck.new())
	root.add_child(screen)


func _process(_delta: float) -> bool:
	_check_the_ball_does_not_hide_the_hole()
	_check_a_lip_out_is_thrown_off_line()
	_check_hanging_on_the_lip()
	_check_the_make_rate()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)
	return true


## The actual bug: a ball you cannot see past is a ball that looks holed.
func _check_the_ball_does_not_hide_the_hole() -> void:
	print("=== the ball against the hole it is aiming at ===")
	var hole: HoleData = screen.get_node("HoleView").hole
	var cup := hole.cup_pixels()

	# Checked across the range of zooms, because the floor that keeps sight of
	# the ball from the tee is exactly the sort of thing that restores the bug at
	# one end while the other end looks fine.
	#
	# The cup is painted at its true size at every zoom and is never floored: the
	# course is drawn once when the hole is set and never again, so a cup that
	# depended on the camera would freeze at the flyover's zoom and stay that
	# size all round. That was tried, and did.
	for zoom in [1.0, 2.5, 3.5, PUTTING_ZOOM, 8.0]:
		var ball: float = maxf(cup * HoleData.BALL_TO_CUP, 2.4 / zoom)
		var outer := ball * 1.42
		print("  at %.1fx: cup %.2f px, ball %.2f px (%.2f with its rim), %.1f balls across the hole"
			% [zoom, cup, ball, outer, cup / ball])
		# Anywhere close enough to judge a putt from, the hole must be the wider
		# of the two. Further out than that the floor wins and the flag is what
		# marks the hole.
		if zoom >= 2.5:
			_expect(outer < cup,
				"at %.1fx the ball is drawn wider than the hole, so it hides it"
					% zoom)

	# What is painted is what is tested. No flattering version of the cup, ever.
	_expect(is_equal_approx(hole.cup_pixels(), cup),
		"the drawn cup is not the tested cup")

	# The case in the bug report: a ball at rest a hole's width from the middle
	# of the cup is a clear miss and has to look like one.
	var ball_r := cup * HoleData.BALL_TO_CUP
	print("  a ball resting one hole-width out covers the cup centre: %s"
		% ("YES -- looks holed" if cup < ball_r * 1.42 else "no"))
	_expect(cup >= ball_r * 1.42,
		"a ball a hole's width out still covers the middle of the hole")


## Hit too hard, the edge should throw it -- and it must leave the ball somewhere
## other than straight on, or nothing has actually happened.
func _check_a_lip_out_is_thrown_off_line() -> void:
	print("")
	print("=== hit too hard ===")
	var hole: HoleData = screen.get_node("HoleView").hole
	var ball: Ball = screen.get_node("HoleView/Ball")
	hole.green_slope = Vector2.ZERO

	# Straight at the cup but a touch off centre, which is every putt a human
	# ever hits, at paces from dying to racing.
	for run in [10.3, 12.0, 15.0, 20.0]:
		var rest := _putt(hole, ball, 10.0, run, 0.6)
		var thrown := absf(rest.y - hole.green_center.y - 0.6)
		print("  would finish %4.1f yd past: %-9s and ends up %.2f px off its line"
			% [run - 10.0, "drops" if _holed else "lips out", thrown])
		if run >= 15.0:
			_expect(not _holed,
				"a putt %.0f yards too strong should not drop" % (run - 10.0))
			_expect(thrown > 1.0,
				"it passed straight over the hole as though it were painted on")

	# Dead centre and racing: it rattles the back of the cup rather than being
	# thrown, and still stays out.
	var rest := _putt(hole, ball, 10.0, 20.0, 0.0)
	print("  dead centre and racing: %s, finishes %.1f yd past" % [
		"drops" if _holed else "rattles and stays out",
		(rest.x - hole.green_center.x) / hole.pixels_per_yard])
	_expect(not _holed, "a putt ten yards too strong should never drop")


## The ball that stops overhanging the edge. This one adds makes, so the cost is
## the point of the check.
func _check_hanging_on_the_lip() -> void:
	print("")
	print("=== hanging over the edge ===")
	var hole: HoleData = screen.get_node("HoleView").hole
	var ball: Ball = screen.get_node("HoleView/Ball")
	var cup := hole.cup_pixels()
	var ball_r := cup * HoleData.BALL_TO_CUP
	print("  the overhang is %.2f px wide, on a %.2f px hole" % [ball_r, cup])

	# Above the hole and below it, on the same green, from the same distance.
	# The read is the whole mechanic: it has to matter which side you miss on.
	hole.green_slope = Vector2.DOWN * 0.8
	var above := 0
	var below := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 400:
		# Set down just outside the hole on one side or the other, dead weight.
		# The green falls towards +y, so -1 sets the ball above the hole.
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var gap: float = cup + rng.randf_range(0.05, 0.95) * ball_r
		ball.sampler = SurfaceSampler.new(hole)
		ball.configure(hole.green_center, cup, hole.bounds)
		ball.reset_to(hole.green_center + Vector2(0.0, side * gap))
		_holed = false
		if not ball.holed_out.is_connected(_on_holed):
			ball.holed_out.connect(_on_holed)
		ball._come_to_rest()
		if _holed:
			if side < 0.0:
				above += 1
			else:
				below += 1
	# Uphill of the cup, where the green falls away towards it, and downhill of
	# it, where the slope holds the ball out. Which side you miss on is the whole
	# mechanic, so the two numbers have to be opposites rather than merely
	# different.
	print("  hung on the high side: %d of 200 toppled in" % above)
	print("  hung on the low side:  %d of 200 toppled in" % below)
	_expect(below == 0, "a ball hanging below the hole should stay out there")
	_expect(above > 150,
		"a ball hanging on the high side should topple in, and only %d of 200 did"
			% above)

	# Flat greens have nothing to topple it with, so the overhang pays nothing.
	hole.green_slope = Vector2.ZERO
	ball.reset_to(hole.green_center + Vector2(0.0, cup + ball_r * 0.5))
	_holed = false
	ball._come_to_rest()
	print("  on a dead flat green it stays hung: %s" % ("no" if _holed else "yes"))
	_expect(not _holed, "a flat green should not topple a ball into the hole")


## The number that says whether any of this made putting easier.
func _check_the_make_rate() -> void:
	print("")
	print("=== six footers, 400 of them ===")
	var hole: HoleData = screen.get_node("HoleView").hole
	var ball: Ball = screen.get_node("HoleView/Ball")
	var cup := hole.cup_pixels()
	var ball_outer: float = cup * HoleData.BALL_TO_CUP * 1.42

	for slope in [0.0, 0.7]:
		hole.green_slope = Vector2.DOWN * slope
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		var holed := 0
		var hidden := 0
		_topples = 0
		if not ball.hung_on_the_lip.is_connected(_on_hung):
			ball.hung_on_the_lip.connect(_on_hung)
		for i in 400:
			var rest := _putt(hole, ball, 2.0, rng.randfn(2.1, 0.35),
				rng.randfn(0.0, 1.6))
			if _holed:
				holed += 1
			elif rest.distance_to(hole.green_center) < ball_outer:
				hidden += 1
		print("  slope %.1f: holed %d of 400 (%.0f%%), of which %d toppled off the lip; sat hiding the hole %d"
			% [slope, holed, holed * 0.25, _topples, hidden])
		# The overhang is the only thing here that can add a make, so this is the
		# whole of the difficulty it costs -- named as a number rather than left
		# to feel, because "not too easy" is the entire brief.
		_expect(_topples * 0.25 < 5.0,
			"the lip overhang alone adds %.1f points of make rate, which is a gift"
				% (_topples * 0.25))
		_expect(hidden == 0,
			"%d putts came to rest covering the hole they had missed" % hidden)
		_expect(holed < 280,
			"%.0f%% of six footers drop, which is a gimme" % (holed * 0.25))
		_expect(holed > 120,
			"only %.0f%% of six footers drop" % (holed * 0.25))


func _putt(hole: HoleData, ball: Ball, from_yards: float, roll_yards: float,
		offset_px: float) -> Vector2:
	var start: Vector2 = hole.green_center - Vector2(
		from_yards * hole.pixels_per_yard, 0.0)
	start.y += offset_px
	ball.sampler = SurfaceSampler.new(hole)
	ball.configure(hole.green_center, hole.cup_pixels(), hole.bounds)
	ball.reset_to(start)
	_holed = false
	if not ball.holed_out.is_connected(_on_holed):
		ball.holed_out.connect(_on_holed)
	var shot := ShotResult.new()
	shot.direction = Vector2.RIGHT
	shot.carry_yards = 0.0
	shot.roll_yards = roll_yards
	ball.launch(shot, hole.pixels_per_yard)
	for step in STEPS:
		if _holed or not ball.is_moving():
			break
		ball._physics_process(1.0 / 60.0)
	return ball.position


func _on_holed() -> void:
	_holed = true


func _on_hung(_pos: Vector2) -> void:
	_topples += 1


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)
