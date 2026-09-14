## Static description of a single golf hole.
##
## Everything about a hole's geometry and difficulty lives here so that holes can
## be authored as .tres files (or later, generated procedurally) without touching
## gameplay code. All positions are in world pixels; distances the player sees are
## converted to yards via `pixels_per_yard`.
class_name HoleData
extends Resource

@export_group("Identity")
@export var hole_number: int = 1
@export var hole_name: String = "Untitled Hole"
@export var par: int = 4
@export_multiline var strategy_hint: String = ""

@export_group("Geometry")
## Where the ball starts.
@export var tee_position: Vector2 = Vector2(170, 640)
## The cup.
@export var pin_position: Vector2 = Vector2(1290, 320)
@export var green_center: Vector2 = Vector2(1300, 330)
## Nominal size, used for laying things out around the green. The green's actual
## edge is `green_polygon`; this is the circle it was grown from.
@export var green_radius: float = 92.0
## The putting surface itself. Every green used to be a circle, which made every
## hole finish the same way -- a green's shape is most of what makes an approach
## a decision. Falls back to the circle when empty, so hand-authored holes and
## old saves still work.
@export var green_polygon: PackedVector2Array = PackedVector2Array()

## Band of fringe drawn around the putting surface. Nothing may sit inside it:
## the clearance rule and the renderer both read this, because they used to
## disagree by exactly this much and bunkers visibly bit into the green.
const GREEN_FRINGE_PIXELS := 7.0
## The line of play, tee to pin, as a curve. The fairway is a band around it and
## the hole is read along it, so anything that needs to know "which way is
## forward from here" -- a caddie, a robot, a mowing pattern -- can ask.
@export var spine: PackedVector2Array = PackedVector2Array()
## Closed polygon describing the fairway band. Purely visual in Milestone 1;
## Milestone 4 will use it to determine the ball's lie.
@export var fairway_polygon: PackedVector2Array = PackedVector2Array()
## The world this hole occupies. Everything the camera may look at, and the last
## resort for anything that escapes the corridor below.
@export var bounds: Rect2 = Rect2(30, 30, 1540, 840)
## In play: a corridor along the line of play, widening around the green.
##
## Out of bounds used to be the world rectangle, which was a fixed 115 yards
## either side of the line whatever the hole. That made spraying it off the tee
## almost free -- there was an enormous field of rough to land in and no boundary
## you could realistically reach. The corridor narrows with the fairway, so a
## championship hole is genuinely tighter than an opener.
@export var in_bounds_polygon: PackedVector2Array = PackedVector2Array()


## Is this a legal place for the ball to be?
func is_in_bounds(point: Vector2) -> bool:
	if in_bounds_polygon.size() >= 3:
		return Geometry2D.is_point_in_polygon(point, in_bounds_polygon)
	return bounds.has_point(point)

@export_group("Hazards")
## Patches of trouble, in draw order: later regions sit on top of earlier ones.
@export var hazards: Array[HazardRegion] = []
## Surfaces used where no hazard region applies.
@export var fairway_surface_id: StringName = &"fairway"
@export var green_surface_id: StringName = &"green"
@export var rough_surface_id: StringName = &"rough"
@export var tee_surface_id: StringName = &"tee"

@export_group("Weather")
## Direction the wind pushes the ball. Zero for a calm day.
@export var wind_direction: Vector2 = Vector2.ZERO
## Yards of drift per 100 yards of carry, on a normally lofted shot.
@export var wind_yards_per_100: float = 0.0

@export_group("Scale")
@export var pixels_per_yard: float = 3.0
## Gameplay cup radius. Deliberately far larger than a real 4.25" cup would be at
## this scale, because a realistic cup would be sub-pixel and unputtable.
@export var cup_radius: float = 2.5
## A floor on the cup, for hand-authored holes at odd scales. It used to be 5px,
## which at the game's fixed scale is 1.9 yards -- **three and a half times the
## 0.55 yard cup it was supposed to be protecting**, and about thirty times a
## real one. That is why the green looked small: the green was right and the
## hole sitting in it was enormous.
##
## It was set that high so the cup stayed visible from the tee. It does not need
## to be: the flag marks the hole at distance, and the camera closes right in
## once you are putting.
const MIN_CUP_PIXELS := 1.4


## The one true cup size, in pixels. Both the renderer and the ball ask for this,
## so what you can see and what you can hole into are the same circle. They were
## once allowed to differ, and a 400 yard hole ended up drawing a cup three times
## wider than the one the ball was actually tested against -- a wedge could
## visibly finish inside the hole and not drop.
func cup_pixels() -> float:
	return maxf(cup_radius, MIN_CUP_PIXELS)


## Is this point on the putting surface?
func on_green(point: Vector2) -> bool:
	if green_polygon.size() >= 3:
		return Geometry2D.is_point_in_polygon(point, green_polygon)
	return point.distance_to(green_center) <= green_radius


## How far the green reaches from its middle in a given direction.
##
## Cast as a ray against the green's own edge rather than assumed, because the
## whole point of an irregular green is that "how big is it" has a different
## answer depending on which way you ask.
func green_reach(direction: Vector2) -> float:
	if green_polygon.size() < 3 or direction.length() < 0.0001:
		return green_radius

	var ray := green_center + direction.normalized() * 100000.0
	var furthest := 0.0
	for i in green_polygon.size():
		var a: Vector2 = green_polygon[i]
		var b: Vector2 = green_polygon[(i + 1) % green_polygon.size()]
		var hit = Geometry2D.segment_intersects_segment(green_center, ray, a, b)
		if hit != null:
			furthest = maxf(furthest, green_center.distance_to(hit))
	# A ray that somehow missed every edge falls back to the nominal circle
	# rather than reporting a green of size zero and letting a bunker sit on it.
	return furthest if furthest > 0.0 else green_radius


## Which way the green falls, and how hard.
##
## Putting was the one part of golf this game did not model at all: the putter
## is the most forgiving club in the bag, the surface was dead flat, and roughly
## a third of all strokes are played from here. Aim at the hole, hit it, done.
##
## A green that falls one way turns every putt into a read. The direction is
## world space, pointing downhill; the length is how steep, where 1 is the most
## a green gets. Deliberately one dominant fall rather than a heightfield --
## a green you can read at a glance is a decision, and one you cannot is noise.
@export var green_slope: Vector2 = Vector2.ZERO
## True where this hole is cut through trees rather than laid out in the open.
## Read by the generator when it plants them, and by anything that wants to say
## so -- it changes how a hole is played, so it should not be a surprise.
@export var woodland: bool = false


## Downhill direction and steepness at a point, zero anywhere but the green.
##
## The fall eases off towards the edge, so a putt does not hit a wall of break
## the instant it touches the surface.
func slope_at(point: Vector2) -> Vector2:
	if green_slope == Vector2.ZERO or not on_green(point):
		return Vector2.ZERO
	var away := point.distance_to(green_center)
	var reach := maxf(green_reach(point - green_center), 1.0)
	var edge := clampf(1.0 - away / reach, 0.0, 1.0)
	# Full tilt across the middle, easing over the last quarter.
	return green_slope * clampf(edge / 0.25, 0.0, 1.0)


## The read, in the words a golfer would use: which way it breaks across the
## line to the hole, and whether it is up or down.
##
## Said relative to the putt rather than to the screen, because "falls south" is
## not a thing anybody has ever thought standing over a four footer.
func slope_note(from: Vector2, to: Vector2) -> String:
	return slope_note_of(slope_at(from), from, to)


## The same read, for a fall measured somewhere other than where you stand.
##
## A green read taken from back down the fairway has to describe the green's own
## tilt along the line you are playing, not the line from the pin to itself --
## which has no direction in it, and so came out as "Dead flat" underneath an
## arrow that was pointing perfectly correctly.
func slope_note_of(fall: Vector2, from: Vector2, to: Vector2) -> String:
	if fall.length() < 0.06:
		return "Dead flat."

	var line := (to - from)
	if line.length() < 0.001:
		return "Dead flat."
	line = line.normalized()
	var across := Vector2(-line.y, line.x)

	var down := fall.dot(line)
	var sideways := fall.dot(across)
	var words: PackedStringArray = PackedStringArray()

	if absf(sideways) > fall.length() * 0.25:
		words.append("Breaks right" if sideways > 0.0 else "Breaks left")
	if absf(down) > fall.length() * 0.25:
		words.append("downhill" if down > 0.0 else "uphill")
	if words.is_empty():
		return "Barely moves."
	return "  ·  ".join(words) + "."


## Nothing may be placed closer to the middle of the green than this, along the
## given direction. The reach plus the fringe drawn around it.
func green_keep_out(direction: Vector2) -> float:
	return green_reach(direction) + GREEN_FRINGE_PIXELS


## What the ball is sitting on at this point.
##
## Hazards win over everything, most recently authored first, then the tee box,
## the green and the fairway. Anything else is rough.
func surface_at(point: Vector2) -> SurfaceType:
	for i in range(hazards.size() - 1, -1, -1):
		var region: HazardRegion = hazards[i]
		if region != null and region.contains(point):
			return region.surface()

	if Geometry2D.is_point_in_polygon(point, tee_polygon()):
		return SurfaceLibrary.by_id(tee_surface_id)
	if on_green(point):
		return SurfaceLibrary.by_id(green_surface_id)
	if fairway_polygon.size() >= 3 and Geometry2D.is_point_in_polygon(point, fairway_polygon):
		return SurfaceLibrary.by_id(fairway_surface_id)
	return SurfaceLibrary.by_id(rough_surface_id)


## Sized in yards like everything else. It was a flat 60x40 pixels, which was
## about right back when the pixel scale was chosen per hole -- at one fixed
## scale it came out a 23 yard wide tee, which is a tennis court.
##
## x is across the line of play, y is along it. A teeing ground is wider than it
## is deep, and it is square to where you are aiming.
const TEE_BOX_YARDS := Vector2(13.0, 8.0)


## Which way this hole is played, from the tee towards the pin.
func line_of_play() -> Vector2:
	var along := pin_position - tee_position
	return along.normalized() if along.length() > 0.001 else Vector2.RIGHT


## The teeing ground, square to the line of play.
##
## It used to be an axis-aligned Rect2, which was invisible while every hole ran
## dead flat across the screen and obviously wrong the moment they did not: a tee
## box sits perpendicular to where you are hitting, with a marker at each end,
## and one that ignores the hole it belongs to reads as a sticker.
func tee_polygon() -> PackedVector2Array:
	var along := line_of_play()
	var across := Vector2(-along.y, along.x)
	var half_across := TEE_BOX_YARDS.x * 0.5 * pixels_per_yard
	var half_along := TEE_BOX_YARDS.y * 0.5 * pixels_per_yard
	return PackedVector2Array([
		tee_position - across * half_across - along * half_along,
		tee_position + across * half_across - along * half_along,
		tee_position + across * half_across + along * half_along,
		tee_position - across * half_across + along * half_along,
	])


## Where the two markers stand: at either end of the teeing ground, level with
## the ball rather than behind it.
func tee_markers() -> Array[Vector2]:
	var along := line_of_play()
	var across := Vector2(-along.y, along.x)
	var reach := (TEE_BOX_YARDS.x * 0.5 - 1.4) * pixels_per_yard
	return [tee_position - across * reach, tee_position + across * reach]


## Wind as a world-space vector in yards of drift per 100 yards of carry.
func wind_vector() -> Vector2:
	if wind_direction == Vector2.ZERO or is_zero_approx(wind_yards_per_100):
		return Vector2.ZERO
	return wind_direction.normalized() * wind_yards_per_100


func has_wind() -> bool:
	return wind_vector() != Vector2.ZERO


## Plain-language wind strength, for the readout.
func wind_description() -> String:
	var strength := wind_yards_per_100
	if strength < 1.0:
		return "Calm"
	if strength < 4.0:
		return "Light breeze"
	if strength < 7.0:
		return "Breezy"
	if strength < 11.0:
		return "Blustery"
	return "Howling"


func to_yards(pixels: float) -> float:
	return pixels / pixels_per_yard


func to_pixels(yards: float) -> float:
	return yards * pixels_per_yard


## Straight-line tee-to-pin distance in yards.
func hole_length_yards() -> float:
	return to_yards(tee_position.distance_to(pin_position))
