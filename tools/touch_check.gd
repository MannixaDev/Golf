## Can the game be played with a finger?
##
## The web build runs on a phone and was unplayable there for one reason: aim
## followed the pointer every frame, and a touchscreen has no pointer until you
## touch something. Tapping a club moved it to the bottom of the screen, so every
## shot aimed at the card you had just chosen.
##
## That bug was invisible on a desktop and invisible in every existing harness,
## because both have a mouse. This one drives the real hole with the touch path
## switched on and asks the questions a thumb would.
extends SceneTree

var failures := 0
var _screen: HoleScreen
var _aim: AimController


func _initialize() -> void:
	_screen = load("res://scenes/run/hole_screen.tscn").instantiate()
	_screen.setup(HoleGenerator.generate(31337, 2, 1),
		Deck.new(load("res://resources/decks/starting_deck.tres").build()))
	root.add_child(_screen)


func _process(_delta: float) -> bool:
	_screen.begin()
	_aim = _screen.get_node("HoleView/AimController")

	_check_a_tap_aims()
	_check_the_card_does_not_aim()
	_check_the_swing_button_swings()
	_check_a_mouse_is_left_alone()

	print("")
	if failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)
	return true


## The replacement for hovering: a tap on the course points the line at it.
func _check_a_tap_aims() -> void:
	print("=== a tap aims ===")
	_aim.set_touch_ui(true)
	_aim.enabled = true

	var ball: Vector2 = _aim.global_position
	var targets: Array[Vector2] = [ball + Vector2(400.0, 0.0),
		ball + Vector2(0.0, -400.0), ball + Vector2(-300.0, 200.0)]
	for target in targets:
		_tap(target)
		var wanted := (target - ball).normalized()
		var off := rad_to_deg(_aim.aim_direction.angle_to(wanted))
		print("  tapped %s, aim is %.1f deg off it" % [target, off])
		_expect(absf(off) < 1.0, "a tap should point the line where it landed")

	# Too close to the ball is not an instruction, it is a fumble.
	var before := _aim.aim_direction
	_tap(ball + Vector2(2.0, 2.0))
	_expect(_aim.aim_direction == before,
		"a tap on the ball itself should not spin the aim")


## The actual bug. A card is a Control, so it swallows the event -- but aim used
## to be polled from the pointer rather than read from events, and polling does
## not care what swallowed anything.
func _check_the_card_does_not_aim() -> void:
	print("")
	print("=== choosing a club does not aim at it ===")
	_aim.set_touch_ui(true)
	_tap(_aim.global_position + Vector2(500.0, -60.0))
	var aimed := _aim.aim_direction

	# Whatever the pointer is doing, an event the course never saw must not move
	# the line. Left pointing where it was told, which is the whole fix.
	_aim._process(0.016)
	print("  aim after a frame with the pointer elsewhere: %.2f, %.2f"
		% [_aim.aim_direction.x, _aim.aim_direction.y])
	_expect(_aim.aim_direction.is_equal_approx(aimed),
		"aim should stay where it was put")
	_expect(_aim.aim_direction.x > 0.0,
		"and should still be pointing down the hole, not at the hand")


## The swing has to be drivable without a mouse button to hold.
func _check_the_swing_button_swings() -> void:
	print("")
	print("=== the swing button swings ===")
	_aim.set_touch_ui(true)
	_aim.swing_pressed()
	_expect(_aim._phase == AimController.Phase.POWER,
		"holding the button starts the meter")

	# Charging must survive frames, which is what caught the desktop path
	# needing a held-button poll in the first place.
	for frame in 8:
		_aim._process_power(0.016)
	_expect(_aim._phase == AimController.Phase.POWER,
		"and keeps charging while it is held")
	var power: float = _aim._power
	print("  charged to %.0f%% over eight frames" % (power * 100.0))
	_expect(power > 0.0, "the meter actually moves")

	_aim.swing_released()
	_expect(_aim._phase == AimController.Phase.TIMING,
		"releasing locks the power and starts the timing")
	_aim.swing_pressed()
	_expect(_aim._phase == AimController.Phase.IDLE,
		"and tapping again plays the shot")


## The desktop path must be exactly as it was. A mouse hovers, and the line
## should still follow it across the course.
func _check_a_mouse_is_left_alone() -> void:
	print("")
	print("=== a mouse still works ===")
	_aim.set_touch_ui(false)
	_aim.enabled = true
	var ball: Vector2 = _aim.global_position

	var motion := InputEventMouseMotion.new()
	motion.global_position = ball + Vector2(0.0, 350.0)
	_aim._unhandled_input(motion)
	_aim._process(0.016)
	var off := rad_to_deg(_aim.aim_direction.angle_to(Vector2.DOWN))
	print("  moved the pointer below the ball, aim is %.1f deg off it" % off)
	_expect(absf(off) < 1.0, "the line should follow a moving pointer")

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = ball + Vector2(0.0, 350.0)
	_aim._unhandled_input(press)
	_expect(_aim._phase == AimController.Phase.POWER,
		"and a press should still start the swing rather than only aiming")
	_aim._cancel_charge()


func _tap(at: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = at
	_aim._unhandled_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.global_position = at
	_aim._unhandled_input(release)


func _expect(condition: bool, what: String) -> void:
	if not condition:
		failures += 1
		print("  FAIL: %s" % what)
