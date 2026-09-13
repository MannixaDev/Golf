## Measures how much a green breaks a putt.
##
## Slope is the only thing in the game that acts on the ball *while it rolls*,
## which makes it easy to get badly wrong in either direction and hard to notice
## by eye: too little and the read is decoration, too much and putting becomes a
## lottery nobody can learn.
##
## So it is measured in the units a golfer actually thinks in -- how many yards a
## ten yard putt moves sideways, and how much further it runs downhill than up.
extends SceneTree

## Long enough for any putt to finish.
const STEPS := 2000
const PUTT_YARDS := 10.0

## What a full-tilt green should do to a ten yard putt. A foot of break is
## nothing; four yards is a pinball table.
const MIN_BREAK_YARDS := 0.7
const MAX_BREAK_YARDS := 2.6

var failures := 0
var screen: HoleScreen = null
var _holed := false


func _initialize() -> void:
	screen = load("res://scenes/run/hole_screen.tscn").instantiate()
	screen.setup(HoleGenerator.generate(3, 2, 1), Deck.new())
	root.add_child(screen)


func _process(_delta: float) -> bool:
	_check_break()
	_check_uphill_and_down()
	_check_pace()
	_check_lip_out()
	_check_generated_greens()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)
	return true


## A putt struck straight across the fall of the green, and how far the slope
## moves it by the time it stops.
func _check_break() -> void:
	print("=== a ten yard putt across the slope ===")

	var hole: HoleData = screen.get_node("HoleView").hole
	var ball: Ball = screen.get_node("HoleView/Ball")

	for steepness in [0.0, 0.3, 0.6, 1.0]:
		# Falling straight down the screen, putt struck straight across it, so
		# the break is simply how far the ball ends up from the line.
		hole.green_slope = Vector2.DOWN * steepness
		var finish := _putt(hole, ball, Vector2.RIGHT, PUTT_YARDS)
		var break_yards := absf(finish.y - hole.green_center.y) / hole.pixels_per_yard

		print("  slope %.1f -> breaks %.2f yd" % [steepness, break_yards])
		if is_zero_approx(steepness):
			_expect(break_yards < 0.05, "a flat green should not break at all")
		elif is_equal_approx(steepness, 1.0):
			_expect(break_yards >= MIN_BREAK_YARDS,
				"the steepest green barely breaks: %.2f yd, want %.2f"
					% [break_yards, MIN_BREAK_YARDS])
			_expect(break_yards <= MAX_BREAK_YARDS,
				"the steepest green is a pinball table: %.2f yd, cap %.2f"
					% [break_yards, MAX_BREAK_YARDS])


## Pace and line are the same decision in golf, so the slope has to change how
## far a putt runs as well as where it goes.
func _check_uphill_and_down() -> void:
	print("")
	print("=== the same putt uphill and downhill ===")

	var hole: HoleData = screen.get_node("HoleView").hole
	var ball: Ball = screen.get_node("HoleView/Ball")
	hole.green_slope = Vector2.RIGHT * 0.8

	var downhill := _putt(hole, ball, Vector2.RIGHT, PUTT_YARDS)
	var uphill := _putt(hole, ball, Vector2.LEFT, PUTT_YARDS)
	var down_run := hole.green_center.distance_to(downhill) / hole.pixels_per_yard
	var up_run := hole.green_center.distance_to(uphill) / hole.pixels_per_yard

	print("  struck downhill: %.1f yd" % down_run)
	print("  struck uphill:   %.1f yd" % up_run)
	_expect(down_run > up_run * 1.15,
		"the same putt should run further downhill than up")


## How long a putt takes. Reported because it is the thing a player feels first
## and the thing that decides whether a slope can act at all -- break grows with
## the square of the time the ball is rolling, so a putt that crosses the green
## in a third of a second cannot bend no matter how steep the green is.
func _check_pace() -> void:
	print("")
	print("=== how long a putt takes ===")

	var hole: HoleData = screen.get_node("HoleView").hole
	var ball: Ball = screen.get_node("HoleView/Ball")
	hole.green_slope = Vector2.ZERO

	for yards in [3.0, 10.0, 20.0]:
		var seconds := _putt_seconds(hole, ball, Vector2.RIGHT, yards)
		var finish := _putt(hole, ball, Vector2.RIGHT, yards)
		var ran := hole.green_center.distance_to(finish) / hole.pixels_per_yard
		print("  %4.0f yd putt rolls for %.2f s and finishes at %.1f yd" % [
			yards, seconds, ran])
		_expect(absf(ran - yards) < yards * 0.08,
			"a %.0f yard putt finished at %.1f yd" % [yards, ran])
		if is_equal_approx(yards, 10.0):
			_expect(seconds > 1.1,
				"a ten yard putt is over in %.2f s, which is quicker than the eye"
					% seconds)
			_expect(seconds < 3.2,
				"a ten yard putt takes %.2f s, which is a wait rather than a shot"
					% seconds)


## Hit it too hard and it should spin out of the side of the hole.
func _check_lip_out() -> void:
	print("")
	print("=== pace at the hole ===")

	var hole: HoleData = screen.get_node("HoleView").hole
	var ball: Ball = screen.get_node("HoleView/Ball")
	hole.green_slope = Vector2.ZERO

	# Struck from ten yards, dead straight at the cup, with more and more pace.
	# The first dies in the hole; the last is racing.
	for run in [10.5, 13.0, 17.0, 26.0]:
		var holed := _putt_at_cup(hole, ball, 10.0, run)
		print("  a putt that would finish %4.1f yd past: %s" % [
			run - 10.0, "drops" if holed else "lips out"])
		if run <= 10.5:
			_expect(holed, "a putt dying at the hole should drop")
		if run >= 17.0:
			_expect(not holed,
				"a putt that would finish %.0f yards past should lip out"
					% (run - 10.0))


## Fire one putt straight at the cup and say whether it went in.
func _putt_at_cup(hole: HoleData, ball: Ball, from_yards: float,
		roll_yards: float) -> bool:
	var start := hole.green_center - Vector2(from_yards * hole.pixels_per_yard, 0.0)
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
	return _holed


func _on_holed() -> void:
	_holed = true


## Seconds of rolling for a putt of this length.
func _putt_seconds(hole: HoleData, ball: Ball, direction: Vector2,
		yards: float) -> float:
	ball.sampler = SurfaceSampler.new(hole)
	ball.configure(hole.green_center + Vector2(0.0, -99999.0),
		hole.cup_pixels(), hole.bounds)
	ball.reset_to(hole.green_center)

	var shot := ShotResult.new()
	shot.direction = direction
	shot.carry_yards = 0.0
	shot.roll_yards = yards
	ball.launch(shot, hole.pixels_per_yard)

	var steps := 0
	while steps < STEPS and ball.is_moving():
		ball._physics_process(1.0 / 60.0)
		steps += 1
	return float(steps) / 60.0


## And the greens the generator actually makes have to sit inside that range,
## not just the hand-set values above.
func _check_generated_greens() -> void:
	print("")
	print("=== what the generator builds ===")

	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	for tier in 5:
		var total := 0.0
		var steepest := 0.0
		for attempt in 40:
			var hole := HoleGenerator.generate(rng.randi(), tier, 1)
			var fall := hole.green_slope.length()
			total += fall
			steepest = maxf(steepest, fall)
		print("  tier %d: average fall %.2f, steepest %.2f" % [
			tier, total / 40.0, steepest])
		_expect(steepest <= 1.0,
			"tier %d builds greens steeper than the model allows" % tier)


## Roll one putt from the middle of the green and return where it stops.
func _putt(hole: HoleData, ball: Ball, direction: Vector2,
		yards: float) -> Vector2:
	ball.sampler = SurfaceSampler.new(hole)
	# Far from the cup, so a putt that happens to run over it is not swallowed
	# and reported as no break at all.
	ball.configure(hole.green_center + Vector2(0.0, -99999.0),
		hole.cup_pixels(), hole.bounds)
	ball.reset_to(hole.green_center)

	var shot := ShotResult.new()
	shot.direction = direction
	shot.carry_yards = 0.0
	shot.roll_yards = yards
	ball.launch(shot, hole.pixels_per_yard)

	for step in STEPS:
		if not ball.is_moving():
			break
		ball._physics_process(1.0 / 60.0)
	return ball.position


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)
