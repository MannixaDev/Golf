## The golf ball.
##
## The ball does not use Godot physics. A shot is executed as a two-phase plan:
##
##   FLIGHT  the ball travels in a straight line to its landing point over a
##           duration proportional to carry, with a purely visual height arc. It
##           does not interact with the ground during this phase.
##   ROLL    from the landing point the ball decelerates at a constant rate,
##           launched at exactly the speed needed to cover the intended roll
##           distance. This is where the cup can catch it.
##
## Splitting carry from roll is what makes golf-shaped design work: Milestone 4's
## hazards test the *landing point* (carry into water) separately from the
## *resting point* (rolled into a bunker), and surface friction becomes a simple
## multiplier on the roll phase.
class_name Ball
extends Node2D

signal came_to_rest(pos: Vector2)
signal holed_out()
signal went_out_of_bounds(pos: Vector2)
## The ball would have been lost, but the stroke was protected.
signal saved_from_trouble()
## The ball finished somewhere it cannot be played from, such as water.
signal caught_by_hazard(pos: Vector2)
## The ball has touched down, before any roll. Where the impact lands.
signal landed(pos: Vector2, speed_fraction: float)
## The ball flew into something growing and dropped out of the air.
signal struck_canopy(pos: Vector2)
## The ball crossed the hole too quickly and was thrown off line by the edge.
signal lipped_out(pos: Vector2)
## The ball stopped overhanging the lip and toppled in.
signal hung_on_the_lip(pos: Vector2)

enum State { IDLE, FLYING, ROLLING, HOLED }

## Rolling deceleration in px/s^2.
const ROLL_DECEL := 520.0
## Putts decelerate far more gently than a ball running out across a fairway.
##
## Roll *distance* is unaffected -- the launch speed is derived from whichever
## deceleration applies, so the ball still finishes where the shot said it would
## -- but the journey takes about three times as long. A putt used to cross ten
## yards in a third of a second, which is quicker than the eye and gave a slope
## no time at all to work on it.
const PUTT_DECEL_SCALE := 0.033
## How hard a full-tilt green pulls a rolling ball, in px/s^2. Tuned by
## measurement rather than by feel -- see tools/green_check.gd, which putts
## across a known slope and reports the break in yards.
##
## Retuned when putts were slowed down: break grows with the square of the time
## the ball spends rolling, so tripling that time multiplied the break by nine.
## The ball now curves visibly across the putt instead of arriving pre-bent.
const SLOPE_ACCEL := 6.5
## Below this speed the ball is considered stopped, at the normal deceleration.
##
## Scaled with whatever deceleration this roll is using, because it is only ever
## meant to stop the ball dithering at walking pace. Left fixed, it was a quarter
## of a slow putt's launch speed and quietly stopped every putt short -- a three
## yard putt was finishing two and a third.
const STOP_SPEED := 16.0
## How much run a ball may still have left in it and drop.
##
## Judged on the roll it has remaining rather than on a raw speed, because a
## speed threshold means nothing once different shots decelerate at different
## rates -- and because "how far past would this have finished" is exactly what
## a golfer means by hitting it too hard. The target shrinks as the ball speeds
## up: dying at the hole gives you the whole cup, running six yards past gives
## you the middle of it, and anything quicker lips out.
const CAPTURE_MAX_RUN_PX := 16.0
## A ball arriving from the air can only drop if it has little run left in it,
## and the target shrinks as that run grows: a shot that checks up dead has the
## whole cup to aim at, one still carrying 30px of release has to find the middle
## of it, and a low runner cannot go in from the air at all. Past this it has to
## take its chances with the rolling test below, once it has slowed down.
##
## This was once a flat 12px cut-off, which no real wedge shot ever met -- you
## could pitch into the middle of the cup and watch it skip out, which is exactly
## the sort of thing that makes a player stop trusting the game.
const AIR_CAPTURE_MAX_ROLL_PX := 60.0
## How hard the edge of the hole throws a putt that was travelling too fast to
## drop into it.
##
## A ball crossing the cup with pace catches the far wall and is spat out
## sideways. It is the most expressive thing that happens in putting and the only
## way the game can say *that was too hard* at the moment it is worth saying --
## before this, a putt hit six yards past sailed over the hole in a dead straight
## line as though the hole were painted on.
##
## It cannot make a putt easier: it only ever fires on a ball the capture test
## has already turned down. What it does do is leave the miss somewhere awkward,
## so hitting it too hard costs you the next putt as well.
const LIP_THROW := 0.55
## How much speed the lip takes out of a ball it throws.
const LIP_DRAG := 0.16
## The ball is not drawn at a size of its own any more.
##
## Every fixed number tried here was wrong, because the eye never judges a ball
## against the screen -- it judges it against the hole. A flat 1.5 pixels was
## *wider than the entire cup* the generator makes, so the ball blotted out the
## target it was aiming at and a putt finishing three ball-widths away looked
## dead in. It is now sized off `cup_radius`, at golf's own ratio, so a ball on
## the lip looks like a ball on the lip on every hole at every zoom.
##
## Only the drawing changed. Nothing here has ever been tested against: what goes
## in is decided by where the ball's centre is, exactly as before.
## A fallback for before a cup has been configured.
const NOMINAL_RADIUS := 1.5
## Never drawn smaller than this on screen, whatever the camera is doing.
##
## Only about keeping sight of your ball from the tee, where it is a third of a
## pixel across otherwise. It is small enough that the ball stays narrower than
## the hole at any zoom close enough to judge a putt from -- below about 2.5x the
## floor does win, but at that distance the cup is a three pixel dot and it is
## the flag you are looking at anyway.
const MIN_SCREEN_RADIUS := 2.4
const MAX_APEX := 190.0
const TRAIL_MAX := 48

var state: State = State.IDLE

# Configured by HoleView.
var cup_position: Vector2 = Vector2.ZERO
var cup_radius: float = 3.5
var bounds: Rect2 = Rect2(0, 0, 1600, 900)

var _height: float = 0.0
var _direction: Vector2 = Vector2.RIGHT

# Flight phase.
var _flight_t: float = 0.0
var _flight_duration: float = 1.0
var _flight_from: Vector2 = Vector2.ZERO
var _flight_to: Vector2 = Vector2.ZERO
var _apex: float = 0.0
var _pending_roll_px: float = 0.0
## Sideways bend applied across the carry, in pixels. Positive is right of the
## line of travel.
var _curve_px: float = 0.0
var _perpendicular: Vector2 = Vector2.ZERO
var _protects_ball: bool = false
## The ball is over the hole right now and has not been taken by it.
var _crossing: bool = false
## Viewport scale the ball was last painted at, so a zoom can ask for a redraw.
var _drawn_at_scale: float = 0.0
## How much of the green's fall this stroke shrugs off, set at launch.
var _slope_resistance: float = 0.0
## World-space wind offset applied across the carry, in pixels.
var _wind_px: Vector2 = Vector2.ZERO

## Lets the ball ask about the ground without knowing what a hole is.
var sampler: SurfaceSampler = null
## Kept from the last launch so height can be reported in yards. Heights are
## judged in yards, not pixels, because a hole's pixel scale changes with its
## length and a tree is the same height on every hole.
var _pixels_per_yard: float = 3.0

# Roll phase.
var _velocity: Vector2 = Vector2.ZERO
## Deceleration for this particular roll. Used both to launch the ball and to
## slow it, so the distance is whatever the shot asked for regardless.
var _roll_decel: float = ROLL_DECEL

var _trail: PackedVector2Array = PackedVector2Array()


func configure(cup_pos: Vector2, cup_r: float, play_bounds: Rect2) -> void:
	cup_position = cup_pos
	cup_radius = cup_r
	bounds = play_bounds


func reset_to(pos: Vector2) -> void:
	position = pos
	state = State.IDLE
	_height = 0.0
	_velocity = Vector2.ZERO
	_pending_roll_px = 0.0
	_curve_px = 0.0
	_wind_px = Vector2.ZERO
	_protects_ball = false
	_slope_resistance = 0.0
	_crossing = false
	_trail.clear()
	queue_redraw()


func is_moving() -> bool:
	return state == State.FLYING or state == State.ROLLING


## How high the ball is right now, in yards.
func height_yards() -> float:
	return _height / maxf(_pixels_per_yard, 0.001)


## Execute a resolved shot.
func launch(shot: ShotResult, pixels_per_yard: float) -> void:
	_direction = shot.direction.normalized()
	_pixels_per_yard = maxf(pixels_per_yard, 0.001)
	_crossing = false
	_trail.clear()
	_trail.append(position)

	var carry_px := shot.carry_yards * pixels_per_yard
	_pending_roll_px = shot.roll_yards * pixels_per_yard
	_protects_ball = shot.protects_ball
	_slope_resistance = clampf(shot.slope_resistance, 0.0, 1.0)
	# A putt never leaves the ground, and rolls to a stop far more gently.
	_roll_decel = ROLL_DECEL * (PUTT_DECEL_SCALE if carry_px < 1.0 else 1.0)
	_curve_px = shot.curve_offset_yards * pixels_per_yard
	_wind_px = shot.wind_drift_yards * pixels_per_yard
	# Right of the line of travel, with screen y pointing down.
	_perpendicular = Vector2(-_direction.y, _direction.x)

	if carry_px < 1.0:
		# A putt stays on the deck, so neither shape nor weather touches it.
		_curve_px = 0.0
		_wind_px = Vector2.ZERO
		_begin_roll()
		return

	_flight_from = position
	_flight_to = position + _direction * carry_px
	_flight_duration = clampf(carry_px / 620.0, 0.45, 2.0)
	# The shot itself knows how high it goes, so the height the ball flies and
	# the height the HUD promised are the same number by construction.
	_apex = minf(shot.apex_yards() * pixels_per_yard, MAX_APEX)
	_flight_t = 0.0
	state = State.FLYING


func _physics_process(delta: float) -> void:
	match state:
		State.FLYING:
			_process_flight(delta)
		State.ROLLING:
			_process_roll(delta)


func _process(_delta: float) -> void:
	# Also when the camera zooms, because the ball has a screen-space floor on
	# its size and a ball sitting still while the camera closes in would keep the
	# width it was drawn at from forty yards away.
	var on_screen := get_viewport_transform().get_scale().x
	if is_moving() or not is_equal_approx(on_screen, _drawn_at_scale):
		_drawn_at_scale = on_screen
		queue_redraw()


# --- Phases ---------------------------------------------------------------

func _process_flight(delta: float) -> void:
	_flight_t += delta / _flight_duration
	var t := clampf(_flight_t, 0.0, 1.0)
	# Squared, so a worked shot holds its line early and turns over late, the way
	# a real one does. The full offset has been applied by the time it lands.
	var bend_now := (_perpendicular * _curve_px + _wind_px) * t * t
	position = _flight_from.lerp(_flight_to, t) + bend_now
	_height = _apex * sin(PI * t)
	_push_trail()

	# Checked before the landing test, because a ball that hits a tree never
	# reaches the end of its carry.
	if sampler != null and sampler.blocks_flight_at(position, height_yards()):
		_into_the_canopy()
		return

	if t >= 1.0:
		_height = 0.0
		# Run out along the tangent of the curved path, not the original line.
		var bend := _perpendicular * _curve_px + _wind_px
		if not bend.is_zero_approx():
			var tangent := (_flight_to - _flight_from) + bend * 2.0
			if tangent.length() > 0.001:
				_direction = tangent.normalized()
		_on_landed()


func _on_landed() -> void:
	# How hard it arrived, for the impact effect and its sound.
	var impact := clampf(_flight_from.distance_to(_flight_to) / 900.0, 0.15, 1.0)
	landed.emit(position, impact)

	# A shot that pitches straight into the cup is holed. Rare and spectacular.
	var checked_up := clampf(1.0 - _pending_roll_px / AIR_CAPTURE_MAX_ROLL_PX, 0.0, 1.0)
	if position.distance_to(cup_position) <= cup_radius * checked_up:
		_hole_out()
		return
	if _out_of_bounds_here():
		_go_out_of_bounds()
		return
	if _caught_here():
		return
	_begin_roll()


## Straight down out of the branches. No run-out: a ball that hits a tree drops
## like it has been shot, which is the entire reason trees are frightening.
func _into_the_canopy() -> void:
	_height = 0.0
	_pending_roll_px = 0.0
	_velocity = Vector2.ZERO
	struck_canopy.emit(position)
	if _out_of_bounds_here():
		_go_out_of_bounds()
		return
	if _caught_here():
		return
	_come_to_rest()


func _begin_roll() -> void:
	if _pending_roll_px <= 1.0:
		_come_to_rest()
		return
	# v0 covers exactly _pending_roll_px on neutral ground, and surface friction
	# can then only ever take energy away. Scaling v0 by the launch surface was
	# tried and was badly wrong: a ball pitching into a bunker got launched at
	# five times the speed, left the small sand circle within a few frames and
	# coasted hundreds of yards across the fairway. Sand has to stop the ball,
	# never start it, so every friction value is >= 1 and the ball can only ever
	# fall short of its intended run.
	_velocity = _direction * sqrt(2.0 * _roll_decel * _pending_roll_px)
	state = State.ROLLING


func _process_roll(delta: float) -> void:
	position += _velocity * delta
	_height = 0.0
	_push_trail()

	if _drops_here():
		_hole_out()
		return

	# Crossing the hole. Every frame spent over it is another chance to be taken,
	# and the edge only gets involved once the ball has made it the whole way
	# across untaken -- which is the real shape of a lip-out: the ball runs over
	# the hole, catches the far edge on its way out and is thrown sideways.
	#
	# Fired on the way in instead, it stole the chance to drop from the very
	# putts that had earned it and *every* putt lipped out, dying ones included.
	# A putt can also lip out, be gathered up by the slope and come back at the
	# hole from the other side; that second pass is a real chance rather than a
	# formality, which falls out of this for free.
	if _is_over_cup():
		_crossing = true
	elif _crossing:
		_crossing = false
		_lip_out()

	if _out_of_bounds_here():
		_go_out_of_bounds()
		return
	if _caught_here():
		return

	# The green pulls the ball downhill while it rolls. Applied as acceleration
	# rather than as a bend on the aim, so it does what gravity does: a putt hit
	# hard holds its line and one dying at the hole falls away, which is the
	# whole reason pace and line are the same decision in golf.
	if sampler != null:
		var fall := sampler.slope_at(position)
		if fall != Vector2.ZERO:
			_velocity += fall * SLOPE_ACCEL * (1.0 - _slope_resistance) * delta

	# Friction is sampled every frame, so a ball running off the fairway into
	# rough pulls up short exactly where the ground changes.
	var decel := _roll_decel
	if sampler != null:
		decel *= sampler.friction_at(position)
	var speed := _velocity.length() - decel * delta
	if speed <= _stop_speed():
		_velocity = Vector2.ZERO
		_come_to_rest()
	else:
		_velocity = _velocity.normalized() * speed


# --- Outcomes -------------------------------------------------------------

func _come_to_rest() -> void:
	if _topples_in():
		hung_on_the_lip.emit(position)
		_hole_out()
		return
	state = State.IDLE
	_velocity = Vector2.ZERO
	queue_redraw()
	came_to_rest.emit(position)


func _hole_out() -> void:
	state = State.HOLED
	_velocity = Vector2.ZERO
	position = cup_position
	_height = 0.0
	queue_redraw()
	holed_out.emit()


func _go_out_of_bounds() -> void:
	if _protects_ball:
		# Protected stroke: pull the ball back inside and play on.
		position = _clamped_into_bounds(position)
		_velocity = Vector2.ZERO
		_come_to_rest()
		saved_from_trouble.emit()
		return

	state = State.IDLE
	_velocity = Vector2.ZERO
	queue_redraw()
	went_out_of_bounds.emit(position)


func _clamped_into_bounds(pos: Vector2) -> Vector2:
	const INSET := 10.0
	return Vector2(
		clampf(pos.x, bounds.position.x + INSET, bounds.end.x - INSET),
		clampf(pos.y, bounds.position.y + INSET, bounds.end.y - INSET))


## Water and the like: the ball is gone the moment it arrives, unless the stroke
## was protected, in which case it is fished out and dropped on the bank.
func _caught_here() -> bool:
	if sampler == null or not sampler.catches_at(position):
		return false

	state = State.IDLE
	_velocity = Vector2.ZERO
	_height = 0.0

	if _protects_ball:
		position = _last_playable_before(position)
		queue_redraw()
		_come_to_rest()
		saved_from_trouble.emit()
		return true

	queue_redraw()
	caught_by_hazard.emit(position)
	return true


## Walk back up the line the ball arrived on until the ground is playable again,
## which is where a retrieved ball would sensibly be dropped.
func _last_playable_before(entry: Vector2) -> Vector2:
	const STEP := 6.0
	const MAX_STEPS := 200
	var probe := entry
	for i in MAX_STEPS:
		probe -= _direction * STEP
		if not bounds.has_point(probe):
			return _clamped_into_bounds(probe)
		if sampler == null or not sampler.catches_at(probe):
			return probe
	return _clamped_into_bounds(entry)


## The boundary is a shape the sampler owns. The rectangle is only a backstop for
## a ball that has left the world entirely, which should not happen but is a
## cheaper thing to check than to debug.
func _out_of_bounds_here() -> bool:
	if sampler != null:
		return sampler.out_of_bounds_at(position)
	return not bounds.has_point(position)


## The speed below which this particular roll is finished.
func _stop_speed() -> float:
	return STOP_SPEED * sqrt(maxf(_roll_decel, 1.0) / ROLL_DECEL)


func _is_over_cup() -> bool:
	return position.distance_to(cup_position) <= cup_radius


## Does the ball fall in from here?
##
## The faster it is going the more of the cup it needs, which is the whole of
## "you hit that too hard" expressed as one number: a ball that would have
## finished stone dead drops from anywhere in the hole, and one still travelling
## has to catch the middle or spin out of the side.
func _drops_here() -> bool:
	var run_left := _velocity.length_squared() / (2.0 * maxf(_roll_decel, 1.0))
	var willing := clampf(1.0 - run_left / CAPTURE_MAX_RUN_PX, 0.0, 1.0)
	return position.distance_to(cup_position) <= cup_radius * willing


## Thrown off line by the edge of the hole.
##
## The ball is deflected away from whichever side of the cup it crossed, hardest
## when it caught the edge and barely at all through the middle -- a putt straight
## over the heart of the hole rattles the back wall and carries on, which is
## exactly how that miss looks.
func _lip_out() -> void:
	if _velocity.length_squared() < 1.0:
		return
	var heading := _velocity.normalized()
	var across := position - cup_position
	# The part of the miss that is sideways to the putt. Along-track offset is
	# just how far through the hole it has got and says nothing about the lip.
	var side := across - heading * across.dot(heading)
	var speed := _velocity.length() * (1.0 - LIP_DRAG)
	if side.length() > 0.001:
		var grazed := clampf(side.length() / maxf(cup_radius, 0.001), 0.0, 1.0)
		_velocity = (heading + side.normalized() * LIP_THROW * grazed).normalized() * speed
	else:
		_velocity = heading * speed
	lipped_out.emit(position)


## The ball has stopped hanging over the edge. Does it fall in?
##
## Its centre is outside the hole, so by the letter of the capture test the putt
## is missed -- but a ball overhanging the lip is balanced on a slope, and which
## way the green falls under it decides what happens next.
##
## Deliberately not a coin toss. Knowing which side of the hole to miss on is the
## whole of green reading, and this is the game paying that out: hang it on the
## high side, where the green falls away towards the cup, and it topples in;
## leave it below the hole and the slope holds it out there and you have a
## tap-in. That plays against pace, which wants you below the hole, so the two
## halves of a green read now pull in different directions.
##
## It widens the target by exactly one ball's width, for a putt that was already
## dead, on greens that actually tilt.
func _topples_in() -> bool:
	if state == State.HOLED or sampler == null:
		return false
	var to_cup := cup_position - position
	var gap := to_cup.length()
	if gap <= cup_radius or gap > cup_radius + world_radius():
		return false
	var fall := sampler.slope_at(position)
	# A green that is all but flat has nothing to topple it with.
	if fall.length() < 0.15:
		return false
	return fall.normalized().dot(to_cup / gap) > 0.35


## The ball's own size in the world, in pixels.
##
## Golf's ratio against the cup, so this is right on any hole at any scale. Kept
## apart from `drawn_radius`, which has a screen floor on it: what the ball does
## must never depend on how far out the camera happens to be.
func world_radius() -> float:
	return maxf(cup_radius, 0.0) * HoleData.BALL_TO_CUP


func _push_trail() -> void:
	if _trail.size() >= TRAIL_MAX:
		_trail.remove_at(0)
	_trail.append(position)


# --- Presentation ---------------------------------------------------------

func _draw() -> void:
	if _trail.size() >= 2:
		var local_trail := PackedVector2Array()
		for p in _trail:
			local_trail.append(p - position)
		draw_polyline(local_trail, Color(Palette.INK, 0.22), 2.0, true)

	var lift := _height * 0.45
	var shadow_fade := clampf(_height / MAX_APEX, 0.0, 1.0)

	# The shadow stays on the ground and only the ball lifts, which is the whole
	# reason a flat top-down shot reads as having height at all. It slides along
	# the sun direction as the ball climbs, so the light agrees with everything
	# else on the course.
	# Sized against the cup it is being played to, through the same call the
	# renderer paints the cup with, so the two can never drift apart. Climbing a
	# little as it flies, because a ball in the air is nearer the eye.
	var ball_r := drawn_radius()
	var shadow_at := Palette.shadow_offset(lift * 0.35)
	draw_circle(shadow_at, ball_r * (1.0 + shadow_fade * 0.5),
		Color(Palette.SHADOW, 0.40 - shadow_fade * 0.22))

	var ball_pos := Vector2(0.0, -lift)
	ball_r *= 1.0 + shadow_fade * 0.7
	# A dark rim, then the ball, then a highlight on the sun side: three circles
	# is all it takes for a flat disc to read as a sphere. The rim is a fraction
	# of the ball rather than a fixed 1.2, which on a small ball was most of its
	# width again and put the drawn edge well outside the hole.
	draw_circle(ball_pos, ball_r * 1.42, Color(0.10, 0.13, 0.10, 0.9))
	draw_circle(ball_pos, ball_r, Palette.BALL_SHADE)
	draw_circle(ball_pos - Palette.SUN * ball_r * 0.30, ball_r * 0.78, Palette.BALL)


## How big the ball is painted right now, in world pixels.
##
## Two and a half of these across is the hole, which is the only proportion a
## golfer reads.
func drawn_radius() -> float:
	if cup_radius <= 0.0:
		return NOMINAL_RADIUS
	var on_screen := get_viewport_transform().get_scale().x
	return maxf(world_radius(), MIN_SCREEN_RADIUS / maxf(on_screen, 0.05))
