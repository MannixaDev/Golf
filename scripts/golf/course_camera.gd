## Follows the ball down the hole, and eases into a close view near the green so
## that chipping and putting stay precise.
##
## This used to frame the entire hole at once. That is why fairways looked like
## threads, and why the first attempt at fixing it -- giving long holes more
## world and zooming out to fit -- changed nothing at all: **fitting a hole on
## screen is arithmetically the same as squeezing it**. The screen is the
## constraint either way, and the fairway ends up exactly as thin.
##
## So the camera shows a fixed slice of golf course instead: `view_yards` of it,
## the same amount on every hole, and it walks along. A fairway is now the same
## fraction of the screen however long the hole is, and a 600 yard par 5 takes
## genuinely longer to walk than a 300 yard par 4.
##
## The cost of that is you cannot see the green from the tee on a long hole, so
## the player can look around before committing: the wheel pulls back as far as
## the whole hole, and dragging with the middle button walks the view up and down
## it. Both snap back the instant the ball is struck -- a free look is for
## planning a shot, not for watching one.
class_name CourseCamera
extends Camera2D

## How much of the hole is on screen at the wide setting, measured across. Sized
## so a tee shot and the ground it lands on are visible together.
@export var view_yards: float = 340.0
## How far ahead of the ball the camera sits, towards the pin. The interesting
## ground is in front of you, so the ball sits back in frame rather than centred.
@export var lead_yards: float = 85.0
## Beyond this distance to the pin, use the wide view.
@export var far_yards: float = 130.0
## At or inside this distance, use max_zoom.
@export var near_yards: float = 12.0
## Close view, for chipping and putting. Absolute rather than relative, and
## meaningful now that every hole shares one scale: a putt looks the same size on
## the shortest par 3 and the longest par 5.
## Closed right in for putting. The cup and the ball are much smaller than they
## were, so the close view has to do the work of making them readable.
@export var max_zoom: float = 5.2
@export var follow_speed: float = 3.5
## How much one notch of the wheel changes the view.
@export var look_step: float = 0.82
## Closest a free look may push in, as a multiple of the walking view.
@export var look_max_in: float = 1.6

var ball: Node2D = null
var pin_position: Vector2 = Vector2.ZERO
var bounds: Rect2 = Rect2(0, 0, 1600, 900)
var pixels_per_yard: float = 3.0
## Zoom at which `view_yards` of hole is on screen.
var wide_zoom: float = 1.0

## A look down the hole before the first shot, so you arrive knowing where the
## green is rather than having to go and find it. Counts down to zero, and while
## it is running the camera walks from the green back to the tee.
var _flyover: float = 0.0
var _flyover_length: float = 0.0

## Free look, cleared on every strike. Kept apart from the framing so the camera
## has one answer for "where should I be" and the player's browsing is an offset
## on top of it, rather than two systems fighting over the same variable.
var _look_scale: float = 1.0
var _look_offset: Vector2 = Vector2.ZERO
var _dragging: bool = false

## Decaying kick applied on top of the framing, so a driver lands with some
## weight behind it and a putt does not.
var _shake: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO
var _rng := RandomNumberGenerator.new()


func setup(ball_node: Node2D, hole: HoleData) -> void:
	ball = ball_node
	pin_position = hole.pin_position
	bounds = hole.bounds
	pixels_per_yard = hole.pixels_per_yard
	wide_zoom = _zoom_for_view()
	reset_look()
	zoom = Vector2.ONE * wide_zoom
	position = _framed(ball_node.global_position, wide_zoom)


## Walk the hole from the green back to the tee. Returns how long it takes, so
## the caller can hold play until it is done.
func flyover(seconds: float) -> float:
	_flyover_length = seconds
	_flyover = seconds
	# Start looking at the green: the camera walks backwards to the ball, which
	# reads as "here is where you are going, and here is where you are".
	position = _clamped(pin_position, wide_zoom)
	zoom = Vector2.ONE * wide_zoom
	return seconds


func is_flying_over() -> bool:
	return _flyover > 0.0


## `amount` is roughly pixels of displacement at its peak.
func kick(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Back to following the ball. Called the moment a shot is struck, because a
## camera left parked over the green while the ball is in the air is worse than
## no free look at all.
func reset_look() -> void:
	_look_scale = 1.0
	_look_offset = Vector2.ZERO
	_dragging = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if not event.pressed:
			if event.button_index == MOUSE_BUTTON_MIDDLE:
				_dragging = false
			return
		match event.button_index:
			MOUSE_BUTTON_WHEEL_DOWN:
				# Never further out than the whole hole: past that you are looking
				# at the void around it, which tells you nothing.
				_look_scale = maxf(_look_scale * look_step,
					_fit_zoom() / maxf(wide_zoom, 0.001))
			MOUSE_BUTTON_WHEEL_UP:
				_look_scale = minf(_look_scale / look_step, look_max_in)
			MOUSE_BUTTON_MIDDLE:
				_dragging = true
	elif event is InputEventMouseMotion and _dragging:
		# Divided by zoom so a drag moves the ground under the cursor by the
		# distance the cursor moved, whatever the view is set to.
		_look_offset -= event.relative / maxf(zoom.x, 0.001)


## The zoom that just fits this whole hole on screen, which is as far out as a
## free look is allowed to go.
func _fit_zoom() -> float:
	var view := _view_size()
	return minf(view.x / maxf(bounds.size.x, 1.0),
		view.y / maxf(bounds.size.y, 1.0))


func _process(delta: float) -> void:
	if ball == null:
		return

	if _shake > 0.01:
		_shake = maxf(0.0, _shake - delta * 42.0)
		_shake_offset = Vector2(
			_rng.randf_range(-_shake, _shake), _rng.randf_range(-_shake, _shake))
	else:
		_shake_offset = Vector2.ZERO

	if _flyover > 0.0:
		_flyover = maxf(0.0, _flyover - delta)
		var t := 1.0 - _flyover / maxf(_flyover_length, 0.001)
		# Eased at both ends, so it sets off and arrives rather than snapping.
		var eased_walk := t * t * (3.0 - 2.0 * t)
		zoom = Vector2.ONE * wide_zoom
		position = _clamped(
			pin_position.lerp(_framed(ball.global_position, wide_zoom), eased_walk),
			wide_zoom)
		return

	var distance_yards := ball.global_position.distance_to(pin_position) / pixels_per_yard
	var t := clampf(inverse_lerp(far_yards, near_yards, distance_yards), 0.0, 1.0)
	# Squared so the zoom stays out of the way until you are genuinely close.
	var eased := t * t

	var target_zoom := lerpf(wide_zoom, max_zoom, eased) * _look_scale
	# Close in the pin is what matters; far out it is the ground ahead of the ball.
	var focus := ball.global_position.lerp(pin_position, eased)
	var target := _clamped(_framed(focus, target_zoom) + _look_offset, target_zoom)

	# A free look should arrive as fast as you asked for it; following the ball
	# should still be a glide.
	var looking := not is_equal_approx(_look_scale, 1.0) or _look_offset != Vector2.ZERO
	var weight := clampf(follow_speed * (2.2 if looking else 1.0) * delta, 0.0, 1.0)
	position = position.lerp(target, weight) + _shake_offset
	zoom = zoom.lerp(Vector2.ONE * target_zoom, weight)


## Where to point the camera to frame a shot from here: ahead of the ball,
## towards the pin, but never so far ahead that the ball leaves the screen.
func _framed(from: Vector2, at_zoom: float) -> Vector2:
	var to_pin := pin_position - from
	if to_pin.length() > 1.0:
		var lead := minf(lead_yards * pixels_per_yard, to_pin.length() * 0.5)
		from += to_pin.normalized() * lead
	return _clamped(from, at_zoom)


## Keep the view inside the hole, so the player never looks at the void beyond
## it. A hole smaller than the view on an axis is centred on that axis rather
## than shoved against an edge.
func _clamped(target: Vector2, at_zoom: float) -> Vector2:
	var half := _view_size() / (2.0 * maxf(at_zoom, 0.01))
	var result := target

	if bounds.size.x <= half.x * 2.0:
		result.x = bounds.get_center().x
	else:
		result.x = clampf(result.x, bounds.position.x + half.x, bounds.end.x - half.x)

	if bounds.size.y <= half.y * 2.0:
		result.y = bounds.get_center().y
	else:
		result.y = clampf(result.y, bounds.position.y + half.y, bounds.end.y - half.y)
	return result


func _zoom_for_view() -> float:
	var across := view_yards * pixels_per_yard
	return maxf(_view_size().x / maxf(across, 1.0), 0.05)


func _view_size() -> Vector2:
	var viewport := get_viewport()
	if viewport != null:
		var size := viewport.get_visible_rect().size
		if size.x > 1.0 and size.y > 1.0:
			return size
	return Vector2(1600.0, 900.0)
