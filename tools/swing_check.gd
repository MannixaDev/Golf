## Asserts the two-stage swing.
##
## Timing is now the difference between a good shot and a bad one on every
## stroke in the game, which makes it the single most load-bearing piece of
## arithmetic in the project. It is also the easiest to get subtly wrong in a way
## nobody notices until the game feels unfair: a sweet spot that is off-centre,
## a miss that punishes in only one direction, or a "pure" strike that still
## sprays.
extends SceneTree

var failures := 0
var aim: AimController = null

var _fired := false
var _fired_power := 0.0
var _fired_offline := 0.0


func _initialize() -> void:
	Settings.ensure_loaded()

	aim = AimController.new()
	root.add_child(aim)
	aim.shot_requested.connect(_on_fired)

	_check_pure_strike_is_pure()
	_check_misses_go_both_ways()
	_check_clubs_differ()
	_check_a_bad_lie_is_harder_to_swing()
	_check_flinching_is_the_worst_outcome()
	_check_reaches_the_ball()
	_check_can_be_turned_off()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


# --- The band -------------------------------------------------------------

func _check_pure_strike_is_pure() -> void:
	print("=== a good strike is a good strike ===")

	aim.shot_profile = _profile(&"iron_9")
	aim._power = 1.0
	var slack := aim.band()
	print("  9 iron band at a full swing: %.3f of the meter" % slack)

	# Anywhere inside the band must be exactly zero, not merely small. A window
	# that quietly tapers would mean there is no such thing as catching it, only
	# degrees of failing to, which is the sort of thing players can feel and
	# cannot name.
	for at in [0.0, slack * 0.5, slack * 0.99]:
		aim._marker = at
		aim._marker_dir = -1.0
		var offline := aim.timing_error_deg()
		print("    marker at %.3f -> %+.2f deg" % [at, offline])
		_expect(is_zero_approx(offline),
			"a strike inside the window should be dead straight")

	aim._marker = slack * 1.6
	_expect(not is_zero_approx(aim.timing_error_deg()),
		"a strike outside the window should not be straight")


func _check_misses_go_both_ways() -> void:
	print("")
	print("=== early pushes, late pulls ===")

	aim.shot_profile = _profile(&"driver")
	aim._power = 1.0
	var worst := aim.shot_profile.offline_deg()

	aim._marker = 0.6
	aim._marker_dir = -1.0
	var early := aim.timing_error_deg()
	aim._marker_dir = 1.0
	var late := aim.timing_error_deg()

	print("  driver, marker at 0.6 falling: %+.1f deg" % early)
	print("  driver, marker at 0.6 rising:  %+.1f deg" % late)
	print("  worst this club can do: %.1f deg" % worst)

	_expect(early < 0.0 and late > 0.0,
		"missing on the way down and the way up should go opposite ways")
	_expect(is_equal_approx(absf(early), absf(late)),
		"the two directions should punish equally")
	_expect(absf(early) <= worst + 0.01,
		"a miss should never exceed the club's own worst")


func _check_clubs_differ() -> void:
	print("")
	print("=== forgiving clubs are forgiving ===")

	# Reported in milliseconds, because that is the unit the player's thumb works
	# in and the meter units are meaningless without the sweep speed beside them.
	var windows := {}
	for id in [&"putter", &"wedge", &"iron_9", &"iron_5", &"driver"]:
		aim.shot_profile = _profile(id)
		var window_ms := 2.0 * aim.tolerance() * AimController.TIMING_TIME * 1000.0
		windows[id] = aim.tolerance()
		print("  %-8s window %3.0f ms, worst miss %.1f deg" % [
			id, window_ms, aim.shot_profile.offline_deg()])
		_expect(window_ms > 60.0,
			"%s gives only %.0f ms to react, which is not a test but a coin toss"
				% [id, window_ms])

	_expect(windows[&"putter"] > windows[&"driver"] * 1.5,
		"a putter should be far easier to time than a driver")
	_expect(windows[&"iron_9"] > windows[&"iron_5"],
		"a shorter iron should be the more forgiving of the two")


## An emergent property worth pinning down before somebody tunes it away.
##
## The timing window comes from dispersion, and a lie multiplies dispersion, so
## playing out of trouble is not only shorter and wilder -- it is genuinely
## harder to strike. Nothing was written to make that true; it falls out of the
## two systems meeting, which is exactly the sort of thing that quietly breaks.
func _check_a_bad_lie_is_harder_to_swing() -> void:
	print("")
	print("=== a bad lie is harder to time ===")

	for id in [&"fairway", &"rough", &"deep_rough", &"bunker"]:
		var surface := SurfaceLibrary.by_id(id)
		if surface == null:
			continue
		var profile := _profile(&"iron_9")
		surface.apply_to(profile)
		aim.shot_profile = profile
		var window := 2.0 * aim.tolerance() * AimController.TIMING_TIME * 1000.0
		print("  9 iron from %-11s spread %.1f deg, window %3.0f ms" % [
			id, profile.dispersion_deg, window])

	var clean := _profile(&"iron_9")
	SurfaceLibrary.by_id(&"fairway").apply_to(clean)
	aim.shot_profile = clean
	var from_fairway := aim.tolerance()

	var nasty := _profile(&"iron_9")
	SurfaceLibrary.by_id(&"rough").apply_to(nasty)
	aim.shot_profile = nasty
	var from_rough := aim.tolerance()

	_expect(from_rough < from_fairway * 0.9,
		"the rough should be meaningfully harder to time than the fairway")


func _check_flinching_is_the_worst_outcome() -> void:
	print("")
	print("=== not swinging at all ===")

	aim.shot_profile = _profile(&"iron_5")
	aim._phase = AimController.Phase.TIMING
	aim._power = 0.9
	aim._marker = 0.9
	aim._marker_dir = 1.0

	_fired = false
	# One step past the top: the marker has come all the way back without you.
	aim._process_timing(1.0)
	print("  marker ran back to the top: fired %s, %+.1f deg offline" % [
		_fired, _fired_offline])
	_expect(_fired, "letting the marker run out should still play the shot")
	_expect(absf(_fired_offline) > aim.shot_profile.offline_deg() * 0.5,
		"letting it run out should be a genuinely bad miss")


# --- End to end -----------------------------------------------------------

func _check_reaches_the_ball() -> void:
	print("")
	print("=== the miss reaches the ball ===")

	var profile := _profile(&"driver")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11

	# Dispersion is random, so the honest comparison is the same seed twice with
	# only the timing changed.
	rng.seed = 11
	var pure := ShotResolver.resolve(profile, 1.0, Vector2.RIGHT, rng, Vector2.ZERO, 0.0)
	rng.seed = 11
	var missed := ShotResolver.resolve(profile, 1.0, Vector2.RIGHT, rng, Vector2.ZERO, 9.0)

	var swing := rad_to_deg(pure.direction.angle_to(missed.direction))
	print("  same shot, 9 degrees of mistiming: %.1f degrees apart" % swing)
	_expect(is_equal_approx(snappedf(swing, 0.01), 9.0),
		"the timing miss should reach the ball intact")
	_expect(is_zero_approx(pure.timing_error_deg),
		"a pure strike should record no timing error")
	_expect(is_equal_approx(missed.timing_error_deg, 9.0),
		"the shot should remember whose fault it was")


func _check_can_be_turned_off() -> void:
	print("")
	print("=== the timing stage can be switched off ===")

	var was := Settings.swing_accuracy
	Settings.swing_accuracy = false

	aim.shot_profile = _profile(&"driver")
	aim._phase = AimController.Phase.POWER
	aim._power = 0.7
	_fired = false
	aim._lock_power()

	print("  with timing off, releasing power fired at %.2f, %+.1f deg" % [
		_fired_power, _fired_offline])
	_expect(_fired, "releasing should play the shot outright")
	_expect(is_zero_approx(_fired_offline), "and it should be a pure strike")
	_expect(aim._phase == AimController.Phase.IDLE, "and the swing should be over")

	Settings.swing_accuracy = was


func _profile(card_id: StringName) -> ShotProfile:
	return ShotProfile.from_card(CardLibrary.copy(card_id))


func _on_fired(_direction: Vector2, power: float, offline: float) -> void:
	_fired = true
	_fired_power = power
	_fired_offline = offline


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)
