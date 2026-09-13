## Builds a playable HoleData from a seed and a difficulty tier.
##
## Fairness comes from placing everything relative to the line of play rather
## than scattering it at random: the fairway is a band around a spine from tee to
## pin, and hazards are positioned by how far down that spine they sit and how
## far off it. That way a generated hole always has a route, and the trouble is
## always trouble you could have avoided.
##
## **A yard is a yard.** Scale used to be per hole: every hole was squeezed into
## the same screen width, so a 300 yard hole was drawn at 3.7 pixels per yard and
## a 600 yard hole at 1.9. Two consequences, both bad. Fairways are a fixed width
## in yards, so long holes rendered at barely half the width of short ones and
## looked like threads. And a long hole did not *feel* long -- it was the same
## picture with different numbers on it.
##
## Now one scale serves every hole and the hole occupies as much world as it
## deserves. The camera frames it, so a 600 yard par 5 is genuinely twice the
## walk of a 300 yard par 4.
class_name HoleGenerator
extends RefCounted

## World pixels per yard, the same on every hole. Chosen so a mid-length par 4
## still fits a screen comfortably while the longest par 5 needs the camera to
## pull back rather than the hole to shrink.
const PIXELS_PER_YARD := 2.6
## Room beyond the tee and behind the green, and either side of the line of play.
## The side margin has to clear the widest fairway plus the hazards placed off
## it, or generated trouble ends up out of bounds and is silently dropped.
const EDGE_MARGIN := 240.0
const SIDE_MARGIN := 300.0
## How far the pin may sit above or below the tee, in yards. Kept in yards like
## everything else, so the shape of a hole does not change with its length.
const RISE_YARDS := 78.0
const GREEN_RADIUS_YARDS := 22.0
## How far out of bounds sits, as a multiple of the fairway's half width. It
## scales with the fairway on purpose: out of bounds used to be a fixed 115 yards
## either side of the line of play on every hole, which meant a championship hole
## was exactly as forgiving as an opener and there was no real cost to spraying
## one as long as you could find it again.
##
## Wide enough that ordinary rough still exists between the short grass and the
## white stakes -- a boundary that hugs the fairway is not a hard hole, it is a
## hole where every miss is stroke and distance.
## Retuned when the fairways were widened on the architects' advice: the
## boundary is a multiple of the fairway, so widening one silently widened the
## other and out of bounds went from 0.17 shots a hole to 0.02. Measured, not
## guessed -- see run_sim's out of bounds count.
const OB_HALF_WIDTHS := 3.1
## The corridor runs on past the tee and the green, so neither sits on an edge.
const OB_RUN_OFF_YARDS := 45.0
## And it opens out around the putting surface, to hold the greenside trouble.
const OB_GREEN_REACH := 2.8

## Fairway half width by tier, away from the landing zone. Deliberately generous.
##
## These were uniform and narrow, which is the lever real architects say not to
## pull: MacKenzie's "narrow fairways bordered by long grass make bad golfers".
## A hole that is tight everywhere just asks you to hit it straight; a hole that
## is wide and then pinches where you want to land asks you a question.
const FAIRWAY_HALF_WIDTH_BY_TIER := [25.0, 22.0, 20.0, 18.0, 16.0]
## What the fairway shrinks to at the landing zone, as a share of the above.
## Modelled on the 11th at Golf Club of Houston, which runs about 25 yards wide
## and closes to 15 where a long hitter wants to be.
const FAIRWAY_PINCH_BY_TIER := [0.86, 0.78, 0.70, 0.62, 0.55]
## How far either side of the landing zone the pinch is felt, along the hole.
const PINCH_REACH := 0.20
## The fairway necks down to this share of its width as it runs into the green,
## so the short grass becomes an apron rather than stopping dead.
const APRON_TAPER := 0.40
const APRON_REACH := 0.10
## Extra length for its par at the sharp end, so the closer is a genuine haul.
const LENGTH_BONUS_BY_TIER := [-15.0, 0.0, 20.0, 35.0, 50.0]
const CUP_RADIUS_YARDS := 0.55
## How much the greens fall, by tier. One is as steep as a green gets; the
## opening holes are close to flat so the mechanic introduces itself gently.
const GREEN_SLOPE_BY_TIER := [0.28, 0.45, 0.62, 0.78, 0.95]

const HOLE_NAMES_SHORT := [
	"The Postage Stamp", "Short Measure", "The Pulpit", "Sunday Pin", "The Ledge"]
const HOLE_NAMES_MID := [
	"Opening Drive", "The Dogleg", "Church Pews", "The Narrows", "Long Meadow",
	"Keeper's Corner", "The Elbow", "Blind Second"]
const HOLE_NAMES_LONG := [
	"The Long Way Round", "Three Shots Home", "The Haul", "Mill Stream"]


## `rules` may reshape the hole before anything is placed -- forcing a par, a
## length, a tighter fairway or extra greenside trouble. A boss should be a hole
## built differently, not just an ordinary hole with a rule bolted on.
static func generate(hole_seed: int, difficulty: int, hole_number: int = 1,
		rules: CourseRuleSet = null) -> HoleData:
	var rng := RandomNumberGenerator.new()
	rng.seed = hole_seed

	var hole := HoleData.new()
	hole.hole_number = hole_number

	# --- Length and par --------------------------------------------------
	var tier := clampi(difficulty, 0, 4)
	var par := _pick_par(tier, rng)
	if rules != null and rules.force_par > 0:
		par = rules.force_par
	hole.par = par

	var length: float = _pick_length(par, rng) + LENGTH_BONUS_BY_TIER[tier]
	if rules != null and rules.force_length_yards > 0.0:
		length = rules.force_length_yards

	hole.pixels_per_yard = PIXELS_PER_YARD
	hole.cup_radius = CUP_RADIUS_YARDS * hole.pixels_per_yard
	hole.green_radius = GREEN_RADIUS_YARDS * hole.pixels_per_yard

	# --- Spine from tee to pin -------------------------------------------
	# Always left to right, with the pin higher or lower than the tee, so the
	# hole reads the same way every time and the camera work stays predictable.
	# The world is then sized around that line rather than the line being
	# squeezed to fit a fixed world.
	var spine_pixels := length * PIXELS_PER_YARD
	var rise := rng.randf_range(-RISE_YARDS, RISE_YARDS) * PIXELS_PER_YARD
	var tee := Vector2(EDGE_MARGIN, SIDE_MARGIN + maxf(0.0, -rise))
	var pin := tee + Vector2(spine_pixels, rise)

	hole.bounds = Rect2(0.0, 0.0,
		spine_pixels + EDGE_MARGIN * 2.0,
		SIDE_MARGIN * 2.0 + absf(rise))
	hole.tee_position = tee
	hole.pin_position = pin
	hole.green_center = pin + Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0))
	hole.green_polygon = _green_shape(hole.green_center, hole.green_radius, rng)
	hole.green_slope = _green_slope(hole, tier, rng)

	var spine := _build_spine(tee, pin, par, rng)
	hole.spine = spine
	var half_width: float = FAIRWAY_HALF_WIDTH_BY_TIER[tier] * hole.pixels_per_yard
	if rules != null:
		half_width *= maxf(rules.fairway_scale, 0.25)

	# The fairway is widest away from where you want to land and tightest right
	# where you do, which is what makes taking on the corner a decision rather
	# than a formality.
	var pinch: float = FAIRWAY_PINCH_BY_TIER[tier]
	var landing := _landing_fraction(par)
	hole.fairway_polygon = _band_around(spine,
		_width_profile(spine.size(), half_width, pinch, landing))

	# Out of bounds follows the hole's full width, not the pinched one, or the
	# boundary would wander in and out with the fairway.
	var ob_half := half_width * OB_HALF_WIDTHS
	hole.in_bounds_polygon = _in_bounds_shape(hole, spine, ob_half)
	# The world is the corridor plus a strip of out of bounds to see beyond it.
	var margin := 34.0 * hole.pixels_per_yard
	hole.bounds = _shape_bounds(hole.in_bounds_polygon).grow(margin)

	# --- Weather ---------------------------------------------------------
	# Calm openers; genuinely difficult weather only once the run is under way.
	var wind_strength: float = [0.0, 3.5, 6.0, 8.5, 11.0][tier]
	if wind_strength > 0.0:
		wind_strength *= rng.randf_range(0.75, 1.25)
		hole.wind_direction = Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		hole.wind_yards_per_100 = wind_strength

	# --- Trouble ---------------------------------------------------------
	var extra_greenside := rules.extra_greenside_hazards if rules != null else 0
	hole.hazards = _build_hazards(hole, spine, par, tier, half_width, rng,
		extra_greenside, ob_half)

	hole.hole_name = _pick_name(par, rng)
	hole.strategy_hint = _describe(hole, par, tier)
	return hole


# --- Shape ----------------------------------------------------------------

static func _pick_par(tier: int, rng: RandomNumberGenerator) -> int:
	# Short holes read as a breather, long ones as a slog, so weight by tier.
	var roll := rng.randf()
	match tier:
		0: return 4 if roll < 0.75 else 3
		1: return 3 if roll < 0.2 else (4 if roll < 0.85 else 5)
		2: return 3 if roll < 0.15 else (4 if roll < 0.7 else 5)
		3: return 4 if roll < 0.5 else 5
	return 4 if roll < 0.45 else 5


static func _pick_length(par: int, rng: RandomNumberGenerator) -> float:
	match par:
		3: return rng.randf_range(135.0, 205.0)
		5: return rng.randf_range(480.0, 570.0)
	return rng.randf_range(330.0, 435.0)


## Tee to pin, with a kink in the middle for a dogleg on longer holes.
## The line of play, as a smooth curve.
##
## The control points are the same as they ever were -- a tee, a dogleg or two,
## a pin -- but they used to be joined with straight segments, so every hole had
## a visible kink at the corner and the fairway read as a zigzag. A dogleg on a
## real course is a bend, so the control points are now a skeleton and the hole
## is the curve through them.
static func _build_spine(tee: Vector2, pin: Vector2, par: int,
		rng: RandomNumberGenerator) -> PackedVector2Array:
	var control := PackedVector2Array([tee])
	var run := pin - tee
	var across := Vector2(-run.y, run.x).normalized()

	if par >= 4:
		var bend_count := 1 if par == 4 else 2
		# A single bend leans one way; a par 5 may swing back the other.
		var lean := 1.0 if rng.randf() < 0.5 else -1.0
		for i in bend_count:
			var along := float(i + 1) / float(bend_count + 1)
			var amount := rng.randf_range(40.0, 140.0) * lean
			if bend_count == 2 and i == 1 and rng.randf() < 0.5:
				amount = -amount
			control.append(tee + run * along + across * amount)

	control.append(pin)
	return _smooth(control, 10)


## Catmull-Rom through the control points. It passes through every one of them,
## which matters: the dogleg is where the generator decided it should be, not
## wherever a smoothing pass happened to drag it.
static func _smooth(control: PackedVector2Array,
		per_segment: int) -> PackedVector2Array:
	if control.size() < 3:
		return control

	var out := PackedVector2Array()
	var last := control.size() - 1
	for i in last:
		var p0: Vector2 = control[maxi(i - 1, 0)]
		var p1: Vector2 = control[i]
		var p2: Vector2 = control[i + 1]
		var p3: Vector2 = control[mini(i + 2, last)]
		for step in per_segment:
			var t := float(step) / float(per_segment)
			out.append(_catmull(p0, p1, p2, p3, t))
	out.append(control[last])
	return out


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Half width at every point along the hole: full width, closing to `pinch` of it
## around the landing zone and opening out again by the green.
static func _width_profile(count: int, base: float, pinch: float,
		landing: float) -> PackedFloat32Array:
	var widths := PackedFloat32Array()
	for i in count:
		var t := float(i) / float(maxi(count - 1, 1))
		var near := clampf(1.0 - absf(t - landing) / PINCH_REACH, 0.0, 1.0)
		# Smoothstep, so the fairway necks in rather than stepping in.
		var squeeze := near * near * (3.0 - 2.0 * near)
		var width := base * lerpf(1.0, pinch, squeeze)

		# Taper into the green apron, and off the back of the tee. Without this
		# the band ends square, and a straight edge of fairway sticking out from
		# behind the green is the sort of thing you cannot stop seeing.
		width *= lerpf(APRON_TAPER, 1.0, clampf((1.0 - t) / APRON_REACH, 0.0, 1.0))
		width *= lerpf(0.62, 1.0, clampf(t / 0.06, 0.0, 1.0))
		widths.append(width)
	return widths


## Offset a polyline both ways to make a closed band.
## `half_width` is either one number for the whole band or one per spine point.
static func _band_around(spine: PackedVector2Array, half_width) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()

	for i in spine.size():
		var normal := _normal_at(spine, i)
		var w: float = half_width[i] if half_width is PackedFloat32Array else half_width
		left.append(spine[i] + normal * w)
		right.append(spine[i] - normal * w)

	var band := PackedVector2Array(left)
	for i in range(right.size() - 1, -1, -1):
		band.append(right[i])
	return band


## The in-play corridor: a wide band along the line of play, opened out around
## the green so greenside trouble is inside the boundary rather than beyond it.
static func _in_bounds_shape(hole: HoleData, spine: PackedVector2Array,
		ob_half: float) -> PackedVector2Array:
	var run_off := OB_RUN_OFF_YARDS * hole.pixels_per_yard
	var extended := PackedVector2Array()

	# Run the spine on past both ends before banding it, or the corridor would
	# stop dead on the tee markers and behind the flag.
	var first := (spine[1] - spine[0]).normalized() if spine.size() > 1 else Vector2.RIGHT
	extended.append(spine[0] - first * run_off)
	for point in spine:
		extended.append(point)
	var last := Vector2.RIGHT
	if spine.size() > 1:
		last = (spine[spine.size() - 1] - spine[spine.size() - 2]).normalized()
	extended.append(spine[spine.size() - 1] + last * run_off)

	# Built as a union of overlapping segments rather than as one offset band.
	# A band around a curve folds through itself on a tight dogleg, and a
	# self-intersecting polygon breaks every boolean applied to it afterwards --
	# which is how a green ended up outside its own hole.
	var corridor := _corridor_union(extended, ob_half)
	var around_green := _ring(hole.green_center, hole.green_radius * OB_GREEN_REACH)
	var merged := Geometry2D.merge_polygons(corridor, around_green)
	if merged.is_empty():
		return corridor
	# Whichever piece the hole is actually played on.
	for piece in merged:
		if Geometry2D.is_point_in_polygon(hole.pin_position, piece) 				and Geometry2D.is_point_in_polygon(hole.tee_position, piece):
			return piece
	return merged[0]


## The union of a quad per spine segment, which is a clean shape whatever the
## line of play does.
static func _corridor_union(spine: PackedVector2Array,
		half: float) -> PackedVector2Array:
	var shape := PackedVector2Array()
	for i in spine.size() - 1:
		var from: Vector2 = spine[i]
		var to: Vector2 = spine[i + 1]
		var along := to - from
		if along.length() < 0.001:
			continue
		var across := Vector2(-along.y, along.x).normalized() * half
		# Overlapped end to end, so consecutive quads never leave a gap on a bend.
		var stretch := along.normalized() * half * 0.5
		var quad := PackedVector2Array([
			from - across - stretch, to - across + stretch,
			to + across + stretch, from + across - stretch,
		])
		if shape.is_empty():
			shape = quad
			continue
		var joined := Geometry2D.merge_polygons(shape, quad)
		if not joined.is_empty():
			shape = joined[0]
	return shape


static func _ring(centre: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 26:
		var angle := TAU * float(i) / 26.0
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points


static func _shape_bounds(shape: PackedVector2Array) -> Rect2:
	if shape.is_empty():
		return Rect2(0, 0, 1600, 900)
	var rect := Rect2(shape[0], Vector2.ZERO)
	for point in shape:
		rect = rect.expand(point)
	return rect


static func _normal_at(spine: PackedVector2Array, index: int) -> Vector2:
	var forward := Vector2.RIGHT
	if index == 0:
		forward = spine[1] - spine[0]
	elif index == spine.size() - 1:
		forward = spine[index] - spine[index - 1]
	else:
		# Average the two segments so the band does not pinch on a bend.
		forward = (spine[index + 1] - spine[index]).normalized() \
			+ (spine[index] - spine[index - 1]).normalized()
	if forward.length() < 0.001:
		forward = Vector2.RIGHT
	forward = forward.normalized()
	return Vector2(-forward.y, forward.x)


# --- Trouble --------------------------------------------------------------

static func _build_hazards(hole: HoleData, spine: PackedVector2Array, par: int,
		tier: int, half_width: float, rng: RandomNumberGenerator,
		extra_greenside: int = 0, ob_half: float = 0.0) -> Array[HazardRegion]:
	var hazards: Array[HazardRegion] = []
	## Which side the fairway sand ended up on, so the greenside sand can take
	## the other. Neutral until a fairway bunker is actually placed.
	var flank_side := 1.0 if rng.randf() < 0.5 else -1.0

	# Sand flanking the driving zone, so a good drive threads between it.
	if par >= 4:
		var landing := _landing_fraction(par)
		var flank_count := 1 if tier <= 1 else 2
		for i in flank_count:
			var side := 1.0 if i == 0 else -1.0
			if flank_count == 1 and rng.randf() < 0.5:
				side = -1.0
			var along := landing + rng.randf_range(-0.05, 0.05)
			var offset := rng.randf_range(1.25, 1.75) * half_width
			hazards.append(_bunker(
				_point_on(spine, along) + _normal_on(spine, along) * offset * side,
				rng.randf_range(9.0, 13.0) * hole.pixels_per_yard, rng))
			# Remembered so the greenside sand can be put on the other flank:
			# classic strategy is fairway bunker one side, green bunker the
			# other, so flirting with the first opens the angle to the green.
			flank_side = side

	# Chewed-up ground on the line itself: small, nasty, avoidable.
	#
	# Divots used to be one brown disc eight yards across, which reads as a
	# sticker rather than as anything golf has a name for. A divot is a scrape
	# the size of a boot, and they come in patches where everybody lands -- so
	# they are now a scatter of small ones in the driving zone, which is both
	# what they look like and where they would actually be.
	for i in 1 + tier / 2:
		var along := rng.randf_range(0.3, 0.85)
		if rng.randf() < 0.4:
			var offset := rng.randf_range(-0.6, 0.6) * half_width
			hazards.append(_blob(&"wet_patch",
				_point_on(spine, along) + _normal_on(spine, along) * offset,
				rng.randf_range(5.0, 8.0) * hole.pixels_per_yard, rng))
			continue

		var patch_at := _point_on(spine, along)
		var patch_across := _normal_on(spine, along)
		var spread := half_width * 0.55
		for scrape in rng.randi_range(4, 7):
			hazards.append(_blob(&"divot",
				patch_at
					+ patch_across * rng.randf_range(-spread, spread)
					+ Vector2(rng.randf_range(-spread, spread),
						rng.randf_range(-spread, spread)) * 0.5,
				rng.randf_range(1.6, 3.0) * hole.pixels_per_yard, rng))

	# Water guarding the green, from tier 1 up. Kept to one side of the pin so
	# there is always a dry way in.
	if tier >= 1 and rng.randf() < 0.35 + 0.15 * tier:
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var approach := (hole.pin_position - _point_on(spine, 0.85)).normalized()
		var across := Vector2(-approach.y, approach.x) * side
		var centre := hole.pin_position \
			- approach * hole.green_radius * rng.randf_range(0.5, 1.1) \
			+ across * hole.green_radius * rng.randf_range(0.85, 1.35)
		hazards.append(_blob(&"water", centre,
			hole.green_radius * rng.randf_range(0.75, 1.1), rng))

	# Greenside sand, favouring the flank opposite the fairway bunker so the two
	# together make an angle worth thinking about rather than a ring of sand.
	var approach_dir := (hole.pin_position - _point_on(spine, 0.8)).normalized()
	var green_across := Vector2(-approach_dir.y, approach_dir.x)
	var bunker_count := 1 + tier / 2 + extra_greenside
	for i in bunker_count:
		var bearing := green_across * -flank_side
		if i > 0:
			bearing = Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		else:
			bearing = bearing.rotated(rng.randf_range(-0.7, 0.7))
		var distance := hole.green_radius + rng.randf_range(8.0, 16.0) * hole.pixels_per_yard
		hazards.append(_bunker(
			hole.pin_position + bearing.normalized() * distance,
			rng.randf_range(9.0, 14.0) * hole.pixels_per_yard, rng))

	# Settle everything else into its final position before the trees go in.
	# The clearance rule shoves hazards away from the green, so a pond placed
	# beside the flag can end up several yards from where it was rolled -- and a
	# tree checked against the old position had a pond slide into it afterwards.
	for region in hazards:
		_push_clear_of_green(region, hole)

	# Trees go in last, and only where nothing else already is.
	#
	# They line the hole just inside the boundary, which is where trees on a real
	# course are -- but the sand off the driving zone reaches into the same band,
	# so on every tier those two ranges overlapped and a bunker sitting inside a
	# clump of trees was common rather than a freak roll. Placing them last lets
	# a tree stand down rather than grow through a bunker.
	#
	# Pulled in by their own radius as well, so a clump never straddles the white
	# stakes: being stopped by a tree and then told you are out of bounds is two
	# punishments for one mistake.
	var edge := ob_half if ob_half > 0.0 else half_width * OB_HALF_WIDTHS
	for i in 2 + tier / 2:
		var along := rng.randf_range(0.15, 0.9)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var radius := rng.randf_range(0.8, 1.4) * half_width
		var offset := minf(edge * rng.randf_range(0.60, 0.86), edge - radius - 4.0)
		if offset <= half_width * 1.4:
			continue  # no room between the fairway and the fence on this hole
		var centre := _point_on(spine, along) \
			+ _normal_on(spine, along) * offset * side
		if _crowds_anything(hazards, centre, radius):
			continue
		hazards.append(_circle(&"deep_rough", centre, radius))

	return _cleaned(hazards, hole)


## Is anything already close enough to this that the two would grow into each
## other? Measured with a margin, because two shapes merely touching still reads
## as one accident rather than two features.
static func _crowds_anything(hazards: Array[HazardRegion], centre: Vector2,
		radius: float) -> bool:
	for region in hazards:
		if region == null:
			continue
		if centre.distance_to(region.centre) < radius + region.radius + 6.0:
			return true
	return false


## Roughly where a full drive finishes, as a fraction along the spine.
static func _landing_fraction(par: int) -> float:
	return 0.62 if par == 4 else 0.42


## Drop anything that would sit on the tee, and shove everything else clear of
## the putting surface, so a generated hole is never unplayable through bad luck.
static func _cleaned(hazards: Array[HazardRegion], hole: HoleData) -> Array[HazardRegion]:
	var kept: Array[HazardRegion] = []
	var tee_guard := 26.0 * hole.pixels_per_yard

	for region in hazards:
		if region.centre.distance_to(hole.tee_position) < region.radius + tee_guard:
			continue
		# Anything wholly beyond the boundary is scenery nobody will ever stand
		# in, so it is not worth generating or drawing.
		if not hole.is_in_bounds(region.centre):
			continue
		_push_clear_of_green(region, hole)
		if not hole.bounds.has_point(region.centre):
			continue
		kept.append(region)
	return kept


## Nothing may sit on the green. Hazards are pushed outwards rather than deleted,
## so greenside sand still hugs the edge and a pond still guards the approach --
## they simply stop covering the ground you have to putt across. Water on the
## green is not a hard hole, it is a broken one.
static func _push_clear_of_green(region: HazardRegion, hole: HoleData) -> void:
	var away := region.centre - hole.green_center
	# Measured along the line to this hazard, and against the green's drawn edge
	# rather than its nominal radius. Using the radius left bunkers overlapping
	# the fringe by the width of the fringe, every single time.
	var minimum := hole.green_keep_out(away) + region.radius
	if away.length() < 0.001:
		away = Vector2.RIGHT * 0.001
	if away.length() >= minimum:
		return

	var shift := away.normalized() * minimum - away
	region.centre += shift
	if region.shape == HazardRegion.Shape.POLYGON:
		var moved := PackedVector2Array()
		for point in region.polygon:
			moved.append(point + shift)
		region.polygon = moved


static func _circle(surface_id: StringName, centre: Vector2, radius: float) -> HazardRegion:
	var region := HazardRegion.new()
	region.surface_id = surface_id
	region.shape = HazardRegion.Shape.CIRCLE
	region.centre = centre
	region.radius = maxf(radius, 8.0)
	return region


## The putting surface, as a shape rather than a circle.
##
## Two overlaid waves rather than per-vertex randomness: independent jitter on
## every point gives a sea urchin, whereas a couple of slow lobes around the
## circumference gives something that reads as a green somebody built. The
## smaller wave runs at a different rate so the result never looks symmetrical.
static func _green_shape(centre: Vector2, radius: float,
		rng: RandomNumberGenerator) -> PackedVector2Array:
	var steps := 22
	var lobes := rng.randi_range(2, 3)
	var lobe_depth := rng.randf_range(0.10, 0.20)
	var ripple_depth := rng.randf_range(0.03, 0.07)
	var phase := rng.randf_range(0.0, TAU)
	var ripple_phase := rng.randf_range(0.0, TAU)
	# Greens are rarely circular and rarely square-on to the line of play.
	var squash := rng.randf_range(0.80, 1.0)
	var tilt := rng.randf_range(0.0, PI)

	var points := PackedVector2Array()
	for i in steps:
		var angle := TAU * float(i) / float(steps)
		var r := radius * (1.0
			+ lobe_depth * sin(angle * lobes + phase)
			+ ripple_depth * sin(angle * 5.0 + ripple_phase))
		var point := Vector2.RIGHT.rotated(angle) * r
		point.y *= squash
		points.append(centre + point.rotated(tilt))
	return points


## A bunker, shaped like one.
##
## Round bunkers are the single most artificial thing on a drawn golf course.
## Real ones have "lobes, tongues, capes and scribbled edges" -- MacKenzie's own
## description of what he was after at Augusta -- and the signature feature is a
## **cape**: a peninsula of grass reaching into the sand, leaving a **bay** of
## sand either side of it. That one notch does more to make a shape read as a
## bunker than any amount of edge noise.
static func _bunker(centre: Vector2, radius: float,
		rng: RandomNumberGenerator) -> HazardRegion:
	var steps := 26
	var lobes := rng.randi_range(2, 3)
	var lobe_depth := rng.randf_range(0.12, 0.24)
	var scribble := rng.randf_range(0.04, 0.09)
	var phase := rng.randf_range(0.0, TAU)
	var scribble_phase := rng.randf_range(0.0, TAU)

	# One cape on most bunkers, at a random bearing, biting in about halfway.
	var has_cape := rng.randf() < 0.7
	var cape_at := rng.randf_range(0.0, TAU)
	var cape_width := rng.randf_range(0.5, 0.9)
	var cape_depth := rng.randf_range(0.34, 0.55)

	var points := PackedVector2Array()
	var furthest := 0.0
	for i in steps:
		var angle := TAU * float(i) / float(steps)
		var r := radius * (1.0
			+ lobe_depth * sin(angle * lobes + phase)
			+ scribble * sin(angle * 7.0 + scribble_phase))
		if has_cape:
			# Angular distance to the cape, wrapped, as a smooth notch.
			var away := absf(wrapf(angle - cape_at, -PI, PI))
			var bite := clampf(1.0 - away / cape_width, 0.0, 1.0)
			r *= 1.0 - cape_depth * bite * bite * (3.0 - 2.0 * bite)
		furthest = maxf(furthest, r)
		points.append(centre + Vector2.RIGHT.rotated(angle) * r)

	var region := HazardRegion.new()
	region.surface_id = &"bunker"
	region.shape = HazardRegion.Shape.POLYGON
	region.centre = centre
	region.polygon = points
	# The true extent, which the clearance checks trust.
	region.radius = furthest
	return region


## Which way the green falls.
##
## Biased to fall back towards the player rather than in a random direction,
## because that is how greens are actually built -- they are tilted to receive
## a shot and to hold water away from the middle. A green falling away from the
## approach on every hole would just be cruel.
static func _green_slope(hole: HoleData, tier: int,
		rng: RandomNumberGenerator) -> Vector2:
	var toward_player := (hole.tee_position - hole.green_center).normalized()
	# Turned off the line of play by up to a bit over a right angle, so most
	# greens break across the putt rather than straight at you.
	var turn := rng.randf_range(-1.9, 1.9)
	# Clamped at one, because one is defined as the steepest a green gets and
	# the variation above was quietly building tier four greens past it.
	var steepness: float = GREEN_SLOPE_BY_TIER[clampi(tier, 0, 4)]
	steepness = minf(steepness * rng.randf_range(0.7, 1.25), 1.0)
	return toward_player.rotated(turn) * steepness


## An irregular closed shape, so ponds do not all look like coins.
static func _blob(surface_id: StringName, centre: Vector2, radius: float,
		rng: RandomNumberGenerator) -> HazardRegion:
	var region := HazardRegion.new()
	region.surface_id = surface_id
	region.shape = HazardRegion.Shape.POLYGON
	region.centre = centre
	region.radius = radius
	var points := PackedVector2Array()
	var steps := 8
	var furthest := 0.0
	for i in steps:
		var angle := TAU * float(i) / float(steps)
		var r := radius * rng.randf_range(0.78, 1.22)
		furthest = maxf(furthest, r)
		points.append(centre + Vector2.RIGHT.rotated(angle) * r)
	region.polygon = points
	# Report the true extent, not the nominal one: an irregular blob reaches
	# further than its radius, and the clearance checks trust this number.
	region.radius = furthest
	return region


# --- Spine helpers --------------------------------------------------------

## Position a fraction of the way along the spine, following its bends.
static func _point_on(spine: PackedVector2Array, along: float) -> Vector2:
	if spine.size() < 2:
		return spine[0] if spine.size() == 1 else Vector2.ZERO
	var scaled := clampf(along, 0.0, 1.0) * float(spine.size() - 1)
	var index := clampi(int(scaled), 0, spine.size() - 2)
	return spine[index].lerp(spine[index + 1], scaled - float(index))


static func _normal_on(spine: PackedVector2Array, along: float) -> Vector2:
	var scaled := clampf(along, 0.0, 1.0) * float(spine.size() - 1)
	var index := clampi(int(scaled), 0, spine.size() - 2)
	var forward := (spine[index + 1] - spine[index]).normalized()
	return Vector2(-forward.y, forward.x)


# --- Flavour --------------------------------------------------------------

static func _pick_name(par: int, rng: RandomNumberGenerator) -> String:
	var pool: Array = HOLE_NAMES_MID
	if par == 3:
		pool = HOLE_NAMES_SHORT
	elif par == 5:
		pool = HOLE_NAMES_LONG
	return pool[rng.randi_range(0, pool.size() - 1)]


static func _describe(hole: HoleData, par: int, tier: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("A par %d of %d yards." % [par, roundi(hole.hole_length_yards())])

	var sand := 0
	var water := 0
	for region in hole.hazards:
		if region.surface_id == &"bunker":
			sand += 1
		elif region.surface_id == &"water":
			water += 1
	if sand > 0:
		parts.append("%d bunkers." % sand)
	if water > 0:
		parts.append("Water in play.")
	if hole.has_wind():
		parts.append("%s wind." % hole.wind_description())
	if tier >= 3:
		parts.append("This one bites.")
	return " ".join(parts)
