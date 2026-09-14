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
## Ball radius in world pixels. It was 5, which at the game's scale is nearly
## two yards -- eighty times a real golf ball, and the other half of why a green
## looked cramped. Small enough now to sit on a green properly; a screen-space
## floor in _draw keeps it visible when the camera is a long way out.
## A real ball is a twentieth of a yard and would be a sixth of a pixel, so this
## is already a generous lie. Pulled in from 2.2 because it was being judged
## against a green rather than against the hole: on a twenty yard green a ball
## drawn at 2.2 is over a yard and a half across, which reads as a football.
const RADIUS := 1.5
## Never drawn smaller than this many pixels on screen, whatever the zoom. Low
## enough to stay honest close up, high enough not to vanish on a wide view.
const MIN_SCREEN_RADIUS := 3.0
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
	if is_moving():
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
	var shadow_at := Palette.shadow_offset(lift * 0.35)
	draw_circle(shadow_at, RADIUS * (1.0 + shadow_fade * 0.5),
		Color(Palette.SHADOW, 0.40 - shadow_fade * 0.22))

	var ball_pos := Vector2(0.0, -lift)
	# Drawn no smaller than MIN_SCREEN_RADIUS however far out the camera is. The
	# ball itself stays small in the world -- this only stops it vanishing when
	# the whole hole is on screen.
	var on_screen := get_viewport_transform().get_scale().x
	var ball_r := maxf(RADIUS, MIN_SCREEN_RADIUS / maxf(on_screen, 0.05))
	ball_r += shadow_fade * 2.0
	# A dark rim, then the ball, then a highlight on the sun side: three circles
	# is all it takes for a flat disc to read as a sphere.
	draw_circle(ball_pos, ball_r + 1.2, Color(0.10, 0.13, 0.10, 0.9))
	draw_circle(ball_pos, ball_r, Palette.BALL_SHADE)
	draw_circle(ball_pos - Palette.SUN * ball_r * 0.30, ball_r * 0.78, Palette.BALL)
