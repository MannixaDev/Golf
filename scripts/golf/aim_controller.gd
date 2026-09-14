## Turns player input into a shot intent, and draws the aiming overlay.
##
## A swing is two decisions, not one.
##
##   AIM     the mouse sets the line while idle. Pressing LOCKS it: you commit
##           to a line before you swing, as in real golf.
##   POWER   the meter ping-pongs 0 -> 100 -> 0 while you hold. Releasing locks
##           whatever it reads.
##   TIMING  the marker then falls back towards zero and bounces. Pressing at
##           the bottom is a pure strike; pressing early pushes the ball one way,
##           late pulls it the other, and never pressing at all is the worst
##           miss available.
##
## The timing stage is the whole reason the game has any execution risk. Before
## it, aiming was a pointing exercise: you got a full trajectory preview with an
## exact landing ring, so a shot only ever missed because the dice said so.
## Missing now is something you did, which is the difference between a hard game
## and an unfair one.
##
## Players who do not want that can turn it off in the settings, and the swing
## falls back to power alone.
##
## Milestone 1 reads raw keys rather than named input actions so the project has
## no hand-authored InputMap to go stale. A proper InputMap / rebinding pass
## belongs in the polish milestone.
class_name AimController
extends Node2D

signal shot_requested(direction: Vector2, power_pct: float, offline_deg: float)
signal power_changed(power_pct: float)
signal charge_started()
## Everything the meter needs to draw itself, in one signal: the meter is a
## single control and splitting this across three would only let them disagree.
signal swing_changed(phase: int, power: float, marker: float, band: float)

enum Phase { IDLE, POWER, TIMING }

## Seconds for the meter to travel from 0 to 100.
const CHARGE_TIME := 0.85
## Seconds for the timing marker to fall from wherever power was locked down to
## the bottom -- the same however hard you swung, because a tap-in should not be
## given a tenth of the warning a full drive gets.
const TIMING_TIME := 0.95
## Half-width of the pure-strike band, as a share of the swing. A share rather
## than a fixed slice of the meter, so that scaling the travel with power scales
## the band with it and every shot gets the same window measured in seconds --
## which is the only unit a player's thumb actually works in.
const BASE_TOLERANCE := 0.060
## Degrees per second when nudging aim with the arrow keys.
const NUDGE_SPEED := 22.0

var enabled: bool = false:
	set(value):
		enabled = value
		if not value:
			_cancel_charge()
		visible = value
		queue_redraw()

var shot_profile: ShotProfile = null
var pixels_per_yard: float = 3.0
## Wind in yards of drift per 100 yards of carry, world space.
var wind: Vector2 = Vector2.ZERO

var aim_direction: Vector2 = Vector2.RIGHT
## Where the pointer was last seen *on the course*. Motion over a card or a
## panel is swallowed by that Control and never reaches _unhandled_input, which
## is exactly the filter this wants: the aim line stops following the cursor the
## moment it leaves the course.
var _pointer: Vector2 = Vector2.ZERO
var _pointer_seen: bool = false
## Driven by the on-screen swing control rather than by a raw press, where a
## finger is the only pointer.
var _touch_ui: bool = false
## Whether the on-screen swing control is being held. The desktop path watches
## the real button state as a safety net against a swallowed release; touch has
## no such state to poll, so it is tracked.
var _touch_swing_held: bool = false

var _phase: int = Phase.IDLE
var _power: float = 0.0
var _charge_dir: float = 1.0
var _charge_frames: int = 0
## Timing marker, and which way it is travelling. Falling is a push, rising
## after the bounce is a pull.
var _marker: float = 0.0
var _marker_dir: float = -1.0


func _process(delta: float) -> void:
	if not enabled:
		return

	match _phase:
		Phase.POWER:
			_process_power(delta)
		Phase.TIMING:
			_process_timing(delta)
		_:
			# Aim follows the pointer only where it has actually been seen moving
			# over the course. Polling get_global_mouse_position() every frame
			# instead meant the line chased the cursor wherever it was, including
			# while it sat on a card at the bottom of the screen -- which on a
			# touchscreen is every single tap, so every shot aimed at the club
			# you had just chosen.
			if _pointer_seen:
				var to_pointer := _pointer - global_position
				if to_pointer.length() > 8.0:
					aim_direction = to_pointer.normalized()

	# Fine aim adjustment works during the swing too, which is forgiving without
	# removing the commitment of locking your line.
	var nudge := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		nudge -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		nudge += 1.0
	if not is_zero_approx(nudge):
		aim_direction = aim_direction.rotated(deg_to_rad(nudge * NUDGE_SPEED * delta))

	queue_redraw()


func _process_power(delta: float) -> void:
	# Safety net. The release event can be swallowed before it reaches us -- by a
	# card under the cursor, or by the window losing focus mid-swing -- which
	# would otherwise leave the meter charging forever. Watch the actual button
	# state instead of trusting the event. The frame guard stops the press frame
	# from immediately releasing itself.
	_charge_frames += 1
	if _charge_frames > 1 and not _swing_input_held():
		_lock_power()
		return

	_power += _charge_dir * delta / CHARGE_TIME
	if _power >= 1.0:
		_power = 1.0
		_charge_dir = -1.0
	elif _power <= 0.0:
		_power = 0.0
		_charge_dir = 1.0
	power_changed.emit(_power)
	_publish()


func _process_timing(delta: float) -> void:
	# Speed scales with the locked power, so the fall always takes TIMING_TIME
	# whether you are hitting a driver or a two foot putt.
	_marker += _marker_dir * delta * _swing_span() / TIMING_TIME
	if _marker <= 0.0:
		_marker = 0.0
		_marker_dir = 1.0
	elif _marker >= _swing_span() and _marker_dir > 0.0:
		# It got all the way back up without you. That is the worst you can do.
		_marker = _swing_span()
		_fire()
		return
	_publish()


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return

	if event is InputEventMouseMotion:
		_pointer = (event as InputEventMouseMotion).global_position
		_pointer_seen = true
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _touch_ui:
			# A finger cannot hover, so a tap on the course is how you aim. The
			# swing is a button of its own: overloading the same tap would mean
			# every aim adjustment also started a swing.
			if event.pressed and _phase == Phase.IDLE:
				aim_at((event as InputEventMouseButton).global_position)
			get_viewport().set_input_as_handled()
			return
		if event.pressed:
			_press()
		else:
			_release()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.keycode == KEY_SPACE and not event.echo:
		if event.pressed:
			_press()
		else:
			_release()
		get_viewport().set_input_as_handled()


## Point the line at somewhere on the course. Public so a tap can drive it.
func aim_at(global_point: Vector2) -> void:
	var to_point := global_point - global_position
	if to_point.length() > 8.0:
		aim_direction = to_point.normalized()
		queue_redraw()


## The swing control, for a device with no mouse button to hold.
func swing_pressed() -> void:
	if enabled:
		_press()


func swing_released() -> void:
	if enabled:
		_release()


## Told by the hole rather than worked out here, so a harness can drive either
## mode without a touchscreen to hand.
func set_touch_ui(on: bool) -> void:
	_touch_ui = on
	if on:
		# Nothing has hovered and nothing will.
		_pointer_seen = false


func _swing_input_held() -> bool:
	if _touch_ui:
		return _touch_swing_held
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_SPACE)


func _press() -> void:
	if _touch_ui:
		_touch_swing_held = true
	match _phase:
		Phase.IDLE:
			_start_charge()
		Phase.TIMING:
			_fire()


func _release() -> void:
	_touch_swing_held = false
	if _phase == Phase.POWER:
		_lock_power()


func _start_charge() -> void:
	_phase = Phase.POWER
	_power = 0.0
	_charge_dir = 1.0
	_charge_frames = 0
	charge_started.emit()
	power_changed.emit(_power)
	_publish()


## Power is settled. Either go on to the timing stage or, if the player has
## turned that off, just hit it.
func _lock_power() -> void:
	if _phase != Phase.POWER:
		return
	Settings.ensure_loaded()
	if not Settings.swing_accuracy:
		_phase = Phase.IDLE
		var power := _power
		_cancel_charge()
		shot_requested.emit(aim_direction, power, 0.0)
		return

	_phase = Phase.TIMING
	_marker = _power
	_marker_dir = -1.0
	Sfx.play(&"select", -8.0, 0.02)
	_publish()


## How far off a pure strike this is, in degrees, signed. Inside the club's
## band it is zero: a good strike is a good strike, not a slightly less bad one,
## or the meter would feel like it was cheating you.
func timing_error_deg() -> float:
	if shot_profile == null:
		return 0.0
	var slack := band()
	if _marker <= slack:
		return 0.0
	var over := (_marker - slack) / maxf(_swing_span() - slack, 0.001)
	# Eased, so being a little late is a small miss rather than a cliff.
	var shaped: float = pow(clampf(over, 0.0, 1.0), 1.4)
	return shaped * shot_profile.offline_deg() * _marker_dir


## Half-width of the pure-strike band for the club in hand, in meter units.
func band() -> float:
	return tolerance() * _swing_span()


## Share of the swing that counts as a pure strike, before it is scaled by how
## hard the swing actually was.
func tolerance() -> float:
	if shot_profile == null:
		return BASE_TOLERANCE
	return BASE_TOLERANCE * shot_profile.sweet_spot_scale()


## How much meter the marker has to travel. Floored so that releasing at the
## very bottom still produces a swing rather than a marker that cannot move.
func _swing_span() -> float:
	return maxf(_power, 0.08)


func _fire() -> void:
	var power := _power
	var offline := timing_error_deg()
	_phase = Phase.IDLE
	_cancel_charge()
	shot_requested.emit(aim_direction, power, offline)


func _cancel_charge() -> void:
	_phase = Phase.IDLE
	_power = 0.0
	_marker = 0.0
	_charge_frames = 0
	power_changed.emit(0.0)
	_publish()


func _publish() -> void:
	swing_changed.emit(_phase, _power, _marker, band())


# --- Aiming overlay -------------------------------------------------------

func _draw() -> void:
	if not enabled or shot_profile == null:
		return

	var max_px := shot_profile.max_reach_yards() * pixels_per_yard
	var angle := aim_direction.angle()
	# Bend previewed over the carry, which is what actually curves.
	var carry_px := shot_profile.carry_yards_max * pixels_per_yard
	var curve_px := tan(deg_to_rad(shot_profile.curve_deg)) * carry_px
	if shot_profile.conceal_shape:
		# Worked shots are not drawn for you. The narrowed cone still shows the
		# accuracy you bought; where it finishes is yours to judge.
		curve_px = 0.0
	# Same call the resolver makes, so the preview cannot drift from the shot.
	var wind_px := ShotResolver.wind_drift(
		wind, shot_profile.carry_yards_max, shot_profile.arc_factor) * pixels_per_yard

	var swinging := _phase != Phase.IDLE

	# Dispersion cone: how wide this shot can spray at the current power. It does
	# not include the timing miss, on purpose -- the cone is the club's accuracy,
	# and where inside it you end up is now partly your own doing.
	var power_factor := 0.35 + 0.65 * (_power if swinging else 1.0)
	var spread := deg_to_rad(shot_profile.dispersion_deg * power_factor)
	var left := _path_points(angle - spread, max_px, curve_px, wind_px)
	var right := _path_points(angle + spread, max_px, curve_px, wind_px)

	var cone := PackedVector2Array(left)
	for i in range(right.size() - 1, -1, -1):
		cone.append(right[i])
	draw_colored_polygon(cone, Color(Palette.GOLD, 0.05))
	draw_polyline(left, Color(Palette.GOLD, 0.18), 1.5, true)
	draw_polyline(right, Color(Palette.GOLD, 0.18), 1.5, true)

	# Faint reference line along the shot's own shape at full power.
	var full_path := _path_points(angle, max_px, curve_px, wind_px)
	draw_polyline(full_path, Color(Palette.INK, 0.16), 1.5, true)

	if swinging:
		var shot_px := max_px * _power
		var path := _path_points(angle, shot_px, curve_px * _power, wind_px * _power)
		var target: Vector2 = path[path.size() - 1]
		draw_polyline(path, Color(Palette.GOLD, 0.9), 2.5, true)
		draw_arc(target, 11.0, 0.0, TAU, 24, Color(Palette.GOLD, 0.85), 2.0, true)
		draw_arc(target, 4.0, 0.0, TAU, 12, Color(Palette.GOLD, 0.6), 2.0, true)
		_draw_distance_label(target, shot_px)
	else:
		draw_line(Vector2.ZERO, aim_direction * 46.0, Color(Palette.INK, 0.55), 2.0, true)


## The flight path in local space, matching how Ball actually flies it: straight
## down `angle`, bending sideways by `curve_px` with the square of progress.
func _path_points(angle: float, distance_px: float, curve_px: float,
		wind_px: Vector2 = Vector2.ZERO, steps: int = 20) -> PackedVector2Array:
	var dir := Vector2.RIGHT.rotated(angle)
	var perpendicular := Vector2(-dir.y, dir.x)
	var bend := perpendicular * curve_px + wind_px
	var points := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		points.append(dir * distance_px * t + bend * t * t)
	return points


func _draw_distance_label(at: Vector2, distance_px: float) -> void:
	var font := Typo.SEMIBOLD
	if font == null:
		return
	var text := "%d yd" % roundi(distance_px / pixels_per_yard)
	draw_string(font, at + Vector2(16.0, -14.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, Typo.BODY, Palette.GOLD)
