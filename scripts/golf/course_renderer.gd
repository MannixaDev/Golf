## Draws a hole from its HoleData using primitives and generated textures.
##
## No binary art assets by design: every element here is a shape with a named
## colour from Palette and grain from TextureBank, so the whole renderer can be
## swapped for sprites later without any other system noticing.
##
## What makes flat shapes read as ground is not detail, it is **consistency of
## light**. One sun direction, declared once in Palette, and every raised thing
## on the hole -- trees, bunker lips, the flagstick, the ball -- casts its shadow
## the same way. Get that right and a circle becomes a bush; get it wrong and no
## amount of texture rescues it.
##
## How a surface is drawn comes from `SurfaceType.style`, not from what the
## surface does to the ball. A new hazard picks its own treatment as data.
class_name CourseRenderer
extends Node2D

## Mown bands run across the line of play, the way a fairway is actually cut.
const STRIPE_WIDTH := 46.0
## Collar of longer grass around the fairway, so its edge is a transition rather
## than a hard line between two flat colours.
const COLLAR_WIDTH := 13.0
## World pixels covered by one tile of grain. Larger than the texture itself, so
## the noise reads as ground rather than as static.
const GRAIN_SCALE := 270.0
const MOTTLE_SCALE := 940.0

var hole: HoleData = null


func _ready() -> void:
	# Grain is drawn by tiling a small texture over large polygons, which needs
	# UVs outside 0..1 to wrap instead of clamping to the edge pixel.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func set_hole(value: HoleData) -> void:
	hole = value
	queue_redraw()


func _draw() -> void:
	if hole == null:
		return

	# Out of bounds everywhere, then the rough inside the boundary. Drawn as
	# ground rather than as a border, so the edge of the hole is somewhere you
	# can see coming rather than a line you discover by crossing it.
	draw_rect(Rect2(-6000, -6000, 18000, 18000), Palette.SHADE)
	_grain_rect(hole.bounds.grow(200.0), TextureBank.turf_mottle(), MOTTLE_SCALE)

	var play := hole.in_bounds_polygon
	if play.size() < 3:
		play = _rect_points(hole.bounds)
	draw_colored_polygon(play, Palette.ROUGH)

	# Two scales of noise over the rough: fine grain for texture, and a much
	# broader mottle because the rough covers most of the screen and uniform
	# speckle across that much area still reads as flat.
	_grain_polygon(play, TextureBank.turf_mottle(), MOTTLE_SCALE)
	_grain_polygon(play, TextureBank.turf_grain(), GRAIN_SCALE)
	_draw_boundary(play)

	_draw_fairway()
	# Draw order follows height off the ground. Sand, water and scrapes are cut
	# into the ground, so they go down first; the green is the top layer of
	# ground; and foliage is the only thing on a golf course that is genuinely in
	# the air, so it goes over everything.
	#
	# Sand painted over a tree canopy was the giveaway: you are looking down at
	# the top of a tree, and a bunker cannot be on top of that.
	_draw_hazards(false)
	_draw_green()
	_draw_hazards(true)
	_draw_distance_rings()
	_draw_tee_box()
	_draw_pin()
	_draw_vignette()


## The white stakes. A boundary you can only find by crossing it is a boundary
## that feels like a bug, so it is marked the way a real one is: a line of posts,
## with the ground beyond it visibly darker and out of play.
func _draw_boundary(play: PackedVector2Array) -> void:
	var outline := play.duplicate()
	outline.append(play[0])
	draw_polyline(outline, Color(Palette.SHADOW, 0.30), 7.0, true)
	draw_polyline(outline, Color(0.90, 0.92, 0.86, 0.30), 2.0, true)

	# Posts at a steady spacing along the edge rather than one per vertex, so
	# they do not bunch up where the boundary turns.
	var spacing := 26.0 * hole.pixels_per_yard
	var carried := 0.0
	for i in play.size():
		var from: Vector2 = play[i]
		var to: Vector2 = play[(i + 1) % play.size()]
		var length := from.distance_to(to)
		if length < 0.01:
			continue
		var step := (to - from) / length
		var walked := spacing - carried
		while walked < length:
			var at := from + step * walked
			draw_circle(at + Palette.shadow_offset(3.0), 2.4, Color(Palette.SHADOW, 0.5))
			draw_circle(at, 2.4, Color(0.94, 0.95, 0.90))
			walked += spacing
		carried = fmod(length - (walked - spacing), spacing)


func _rect_points(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.end,
		rect.position + Vector2(0.0, rect.size.y),
	])


# --- Turf -----------------------------------------------------------------

func _draw_fairway() -> void:
	if hole.fairway_polygon.size() < 3:
		return

	# The collar goes down first and the fairway covers its middle, leaving a
	# band of first cut all the way round.
	for piece in Geometry2D.offset_polygon(hole.fairway_polygon, COLLAR_WIDTH):
		draw_colored_polygon(piece, Palette.FIRST_CUT)

	draw_colored_polygon(hole.fairway_polygon, Palette.FAIRWAY)
	_draw_mowing_stripes()
	_grain_polygon(hole.fairway_polygon, TextureBank.turf_grain(), GRAIN_SCALE)


## Alternate bands of slightly lighter grass, clipped to the fairway itself.
## Intersecting each band with the fairway polygon is exact and costs nothing
## worth worrying about: this only redraws when the hole actually changes.
##
## The bands follow the line of play rather than the straight line from tee to
## pin. That distinction did not exist while holes ran straight and became
## obvious the moment they curved: parallel stripes across a bending fairway
## drift out of square with it and end up cutting the short grass at an angle,
## which is not how anything has ever been mown.
func _draw_mowing_stripes() -> void:
	var walk := _resample(hole.spine, STRIPE_WIDTH)
	if walk.size() < 2:
		return

	# Far enough either side to cover the widest fairway at any angle.
	var reach := 1400.0
	for i in walk.size() - 1:
		# Every other band, so the pattern reads as stripes rather than a wash.
		if i % 2 == 1:
			continue
		var near: Vector2 = walk[i]
		var far: Vector2 = walk[i + 1]
		var along := (far - near).normalized()
		var across := Vector2(-along.y, along.x) * reach
		# Stretched a little past each end so consecutive bands butt together
		# on a bend instead of leaving a wedge of unmown grass.
		var overlap := along * STRIPE_WIDTH * 0.12
		var quad := PackedVector2Array([
			near - across - overlap, far - across + overlap,
			far + across + overlap, near + across - overlap,
		])
		for piece in Geometry2D.intersect_polygons(quad, hole.fairway_polygon):
			draw_colored_polygon(piece, Palette.FAIRWAY_STRIPE)


## Points at even spacing along a path, so a curve can be walked in equal steps
## rather than in whatever lengths its own points happen to be.
func _resample(path: PackedVector2Array, step: float) -> PackedVector2Array:
	if path.size() < 2 or step <= 0.0:
		return path

	var out := PackedVector2Array([path[0]])
	var carried := 0.0
	for i in path.size() - 1:
		var from: Vector2 = path[i]
		var to: Vector2 = path[i + 1]
		var length := from.distance_to(to)
		if length < 0.001:
			continue
		var direction := (to - from) / length
		var walked := step - carried
		while walked < length:
			out.append(from + direction * walked)
			walked += step
		carried = length - (walked - step)
	out.append(path[path.size() - 1])
	return out


func _draw_green() -> void:
	var centre := hole.green_center
	var radius := hole.green_radius
	var green := hole.green_polygon
	if green.size() < 3:
		green = _circle_points(centre, radius, 30)

	# A soft shadow around the outside, so the green reads as sitting slightly
	# down in the ground rather than pasted on top of it.
	for piece in Geometry2D.offset_polygon(green, HoleData.GREEN_FRINGE_PIXELS + 6.0):
		draw_colored_polygon(piece, Color(Palette.SHADOW, 0.16))
	# Fringe under, green over the top of it: the same trick as the fairway
	# collar, and the reason nothing is allowed within the fringe's width.
	for piece in Geometry2D.offset_polygon(green, HoleData.GREEN_FRINGE_PIXELS):
		draw_colored_polygon(piece, Palette.GREEN_FRINGE)

	draw_colored_polygon(green, Palette.GREEN)
	_draw_green_check(centre, radius, green)

	# A brighter crown so the surface reads as domed rather than as a flat disc,
	# offset towards the sun rather than sitting dead centre.
	for piece in Geometry2D.offset_polygon(green, -radius * 0.30):
		var lifted := PackedVector2Array()
		for point in piece:
			lifted.append(point - Palette.SUN * radius * 0.10)
		draw_colored_polygon(lifted, Color(1.0, 0.98, 0.86, 0.05))

	_draw_green_fall(green)
	_grain_polygon(green, TextureBank.turf_grain(), GRAIN_SCALE * 0.5)

	var outline := green.duplicate()
	outline.append(green[0])
	draw_polyline(outline, Palette.GREEN_FRINGE, 2.0, true)


## The fall of the green, shaded across it.
##
## A slope you cannot see is not a read, it is a trap -- so the high side is lit
## and the low side is in shadow, the way ground actually looks, with a few
## contour lines across the fall for anyone who wants to measure it rather than
## feel it. Deliberately not drawn as arrows: arrows tell you the answer, and
## the whole point of a green is that reading it is the skill.
func _draw_green_fall(green: PackedVector2Array) -> void:
	var fall := hole.green_slope
	if fall.length() < 0.05 or green.size() < 3:
		return

	var down := fall.normalized()
	var across := Vector2(-down.y, down.x)
	var centre := hole.green_center
	var reach := hole.green_radius * 1.6
	var bands := 14
	var strength := clampf(fall.length(), 0.0, 1.0)

	for i in bands:
		var t := float(i) / float(bands - 1)
		# Light at the top of the slope, dark at the bottom.
		var shade := lerpf(0.055, -0.075, t) * strength
		var near := -reach + 2.0 * reach * t
		var far := near + 2.0 * reach / float(bands) + 1.0
		var quad := PackedVector2Array([
			centre + down * near - across * reach,
			centre + down * far - across * reach,
			centre + down * far + across * reach,
			centre + down * near + across * reach,
		])
		var tint := Color(1.0, 0.98, 0.86, shade) if shade > 0.0 			else Color(Palette.SHADOW, -shade)
		for piece in Geometry2D.intersect_polygons(quad, green):
			draw_colored_polygon(piece, tint)

	# Contour lines, thin and few, running across the fall.
	for i in 3:
		var offset := lerpf(-reach * 0.5, reach * 0.5, float(i) / 2.0)
		var line := PackedVector2Array([
			centre + down * offset - across * reach,
			centre + down * offset + across * reach,
		])
		var band := PackedVector2Array([
			line[0], line[1],
			line[1] + down * 1.5, line[0] + down * 1.5,
		])
		for piece in Geometry2D.intersect_polygons(band, green):
			draw_colored_polygon(piece, Color(Palette.SHADOW, 0.13 * strength))


## Fine bands both ways across the putting surface. Kept very low contrast: the
## point is that you notice the green is mown, not that you notice stripes.
##
## Clipped against the green's own outline rather than drawn as chords of a
## circle, because the green stopped being a circle.
func _draw_green_check(centre: Vector2, radius: float,
		green: PackedVector2Array) -> void:
	var band := maxf(radius * 0.24, 9.0)
	var tint := Color(1.0, 1.0, 1.0, 0.05)
	var reach := radius * 2.0
	var steps := int(reach * 2.0 / band) + 1

	for horizontal in [true, false]:
		for i in steps:
			if i % 2 == 1:
				continue
			var offset := -reach + i * band
			var quad := _band_quad(centre, offset, band, reach, horizontal)
			for piece in Geometry2D.intersect_polygons(quad, green):
				draw_colored_polygon(piece, tint)


## One mown band, long enough to cross the whole green before it is clipped.
func _band_quad(centre: Vector2, offset: float, width: float, reach: float,
		horizontal: bool) -> PackedVector2Array:
	if horizontal:
		return PackedVector2Array([
			centre + Vector2(-reach, offset),
			centre + Vector2(reach, offset),
			centre + Vector2(reach, offset + width),
			centre + Vector2(-reach, offset + width),
		])
	return PackedVector2Array([
		centre + Vector2(offset, -reach),
		centre + Vector2(offset, reach),
		centre + Vector2(offset + width, reach),
		centre + Vector2(offset + width, -reach),
	])


func _circle_points(centre: Vector2, radius: float,
		steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in steps:
		var angle := TAU * float(i) / float(steps)
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points


# --- Trouble --------------------------------------------------------------

## Hazards paint over the fairway and green in authored order, so a bunker cut
## into the green stays visible.
## `canopy` picks which layer this pass draws: false for everything cut into the
## ground, true for what is standing above it.
func _draw_hazards(canopy: bool) -> void:
	for region in hole.hazards:
		if region == null:
			continue
		var surface := region.surface()
		var overhead := surface.style == SurfaceType.Style.FOLIAGE
		if overhead != canopy:
			continue
		match surface.style:
			SurfaceType.Style.FOLIAGE:
				_draw_foliage(region, surface)
			SurfaceType.Style.SAND:
				_draw_sand(region, surface)
			SurfaceType.Style.WATER:
				_draw_water(region, surface)
			_:
				_draw_plain(region, surface)


## A clump of trees or scrub. Drawn as several overlapping blobs rather than one
## circle, with a shadow on the ground beneath it and light on the crowns: the
## only thing on the hole that is meant to read as being *above* the ground.
func _draw_foliage(region: HazardRegion, surface: SurfaceType) -> void:
	# The region's own clump, not one rolled here. Two copies of this drifted
	# apart and the tree you could see stopped matching the one that caught you.
	var blobs := region.blobs()

	# One shadow for the whole clump, offset along the sun, so it reads as a
	# single object rather than as three bushes each with their own shadow.
	#
	# Thrown long and hard on purpose. Trees are the only thing on the course
	# that will stop a ball in mid-air, so the player has to be able to tell at a
	# glance that this clump stands *up* rather than lying flat like a patch of
	# scrub -- and shadow length is the only height cue a top-down view has.
	_soft_shadow(region.centre + Palette.shadow_offset(region.radius * 0.62),
		region.radius * 1.25, 0.62)

	for blob in blobs:
		draw_circle(blob.position, blob.size.x, Palette.SCRUB_SHADOW)
	for blob in blobs:
		draw_circle(blob.position - Palette.SUN * blob.size.x * 0.13,
			blob.size.x * 0.93, surface.colour)
	# Crowns catch the light on the sun side of each blob.
	for blob in blobs:
		_soft_light(blob.position - Palette.SUN * blob.size.x * 0.42,
			blob.size.x * 0.66, 0.30)


## A bunker. The lip on the sun side is bright where it catches the light, and
## throws a shadow down into the bowl behind it -- which is the whole reason a
## real bunker reads as a hole in the ground from above.
##
## Shaped rather than round now, so this walks the region's own outline instead
## of drawing arcs of a circle.
func _draw_sand(region: HazardRegion, surface: SurfaceType) -> void:
	var sand := region.polygon
	if sand.size() < 3:
		sand = _circle_points(region.centre, region.radius, 26)

	_soft_shadow(region.centre + Palette.shadow_offset(region.radius * 0.16),
		region.radius * 1.10, 0.42)

	# Two faint skirts of the same sand before the bunker proper, so the edge is
	# a transition into the ground rather than a cut-out laid on top of it.
	for piece in Geometry2D.offset_polygon(sand, 6.0):
		draw_colored_polygon(piece, Color(surface.colour, 0.26))
	for piece in Geometry2D.offset_polygon(sand, 2.5):
		draw_colored_polygon(piece, Color(surface.colour, 0.55))

	draw_colored_polygon(sand, surface.colour)
	_grain_polygon(sand, TextureBank.sand_grain(), GRAIN_SCALE * 0.34)

	# Shadow cast down into the bowl by the lip the sun is behind: the whole
	# shape, pulled in a little and slid along the sun.
	for piece in Geometry2D.offset_polygon(sand, -region.radius * 0.10):
		var shifted := PackedVector2Array()
		for point in piece:
			shifted.append(point + Palette.SUN * region.radius * 0.10)
		draw_colored_polygon(shifted, Color(Palette.SAND_SHADOW, 0.30))

	_draw_lit_edge(sand, Color(1.0, 0.98, 0.88, 0.45),
		Color(surface.outline_colour, 0.9))


## Water. Darker towards the middle so it reads as having depth, a paler margin
## where it shallows out, and a ruffled surface.
##
## Blended out over several rings rather than one. A pond with a hard rim looks
## like blue paint; the thing that makes it read as water is the ground getting
## damp before it gets wet.
func _draw_water(region: HazardRegion, surface: SurfaceType) -> void:
	if region.polygon.size() < 3:
		_draw_plain(region, surface)
		return

	# Boggy ground, then the bank dropping in, then the water line.
	for step in [[13.0, Palette.MARSH, 0.22], [8.0, Palette.MARSH, 0.34],
			[4.5, Palette.WATER_SHALLOW, 0.45], [1.5, Palette.WATER_SHALLOW, 0.75]]:
		for piece in Geometry2D.offset_polygon(region.polygon, float(step[0])):
			draw_colored_polygon(piece, Color(step[1], float(step[2])))

	draw_colored_polygon(region.polygon, Palette.WATER_SHALLOW)
	# Stepped inwards so the pond deepens rather than changing colour once.
	var depth := maxf(region.radius * 0.16, 5.0)
	for step in [1.0, 2.0]:
		for piece in Geometry2D.offset_polygon(region.polygon, -depth * step):
			draw_colored_polygon(piece,
				Color(surface.colour, 0.55 if step < 1.5 else 1.0))

	_draw_ripples(region)

	var outline := region.polygon.duplicate()
	outline.append(region.polygon[0])
	draw_polyline(outline, Color(Palette.WATER_FOAM, 0.45), 2.0, true)


func _draw_plain(region: HazardRegion, surface: SurfaceType) -> void:
	match region.shape:
		HazardRegion.Shape.CIRCLE:
			# Scuffs and divots. Drawn as a ragged patch with a soft edge rather
			# than a clean disc: a perfect brown circle on a fairway reads as a
			# sticker somebody put there, which is exactly what it looked like.
			var patch := _ragged_circle(region.centre, region.radius)
			_soft_shadow(region.centre + Palette.shadow_offset(2.0),
				region.radius * 1.05, 0.22)
			for piece in Geometry2D.offset_polygon(patch, 4.0):
				draw_colored_polygon(piece, Color(surface.colour, 0.35))
			draw_colored_polygon(patch, surface.colour)
			_grain_polygon(patch, TextureBank.turf_grain(), GRAIN_SCALE * 0.35)
		HazardRegion.Shape.POLYGON:
			if region.polygon.size() < 3:
				return
			# Scuffed ground gets the same soft edge as everything else, so a
			# patch of divots sits in the turf rather than on it.
			_soft_shadow(region.centre + Palette.shadow_offset(1.5),
				region.radius * 1.1, 0.18)
			for piece in Geometry2D.offset_polygon(region.polygon, 3.0):
				draw_colored_polygon(piece, Color(surface.colour, 0.32))
			draw_colored_polygon(region.polygon, surface.colour)
			_grain_polygon(region.polygon, TextureBank.turf_grain(),
				GRAIN_SCALE * 0.35)


## A few highlights across a pond so it reads as a moving surface rather than a
## flat blue shape.
func _draw_ripples(region: HazardRegion) -> void:
	var top := region.centre.y - region.radius
	var lines := 5
	for i in lines:
		var y := top + region.radius * 2.0 * (float(i) + 0.8) / float(lines + 1)
		var half := region.radius * 0.58 * (1.0 - absf(
			(y - region.centre.y) / maxf(region.radius, 1.0)))
		if half <= 4.0:
			continue
		var wobble := region.radius * 0.10 * (1.0 if i % 2 == 0 else -1.0)
		draw_line(
			Vector2(region.centre.x - half + wobble, y),
			Vector2(region.centre.x + half + wobble, y),
			Color(Palette.WATER_FOAM, 0.30), 2.0, true)


# --- Furniture ------------------------------------------------------------

## Sprinkler-head style yardage rings around the pin, so the player can judge
## club selection without a rangefinder.
func _draw_distance_rings() -> void:
	var font := Typo.SEMIBOLD
	for yards in [100, 150, 200]:
		var radius := hole.to_pixels(float(yards))
		draw_arc(hole.pin_position, radius, 0.0, TAU, 96, Palette.YARDAGE_RING,
			2.0, true)
		if font != null:
			var label_at := hole.pin_position + Vector2(-radius + 8.0, -6.0)
			if hole.bounds.has_point(label_at):
				draw_string(font, label_at, str(yards), HORIZONTAL_ALIGNMENT_LEFT,
					-1, Typo.SMALL, Color(Palette.INK, 0.26))


func _draw_tee_box() -> void:
	var box := hole.tee_polygon()
	if box.size() < 3:
		return

	var shadow := PackedVector2Array()
	for point in box:
		shadow.append(point + Palette.shadow_offset(3.0))
	draw_colored_polygon(shadow, Color(Palette.SHADOW, 0.45))

	draw_colored_polygon(box, Palette.TEE)
	_grain_polygon(box, TextureBank.turf_grain(), GRAIN_SCALE * 0.4)
	var outline := box.duplicate()
	outline.append(box[0])
	draw_polyline(outline, Color(1.0, 0.98, 0.88, 0.22), 2.0, true)

	# Two markers, the way a tee box is actually set out: one at each end of the
	# teeing ground, square to the shot.
	for at in hole.tee_markers():
		draw_circle(at + Palette.shadow_offset(2.0), 3.0, Color(Palette.SHADOW, 0.5))
		draw_circle(at, 3.0, Color(0.94, 0.95, 0.90))


func _draw_pin() -> void:
	var pin := hole.pin_position
	# Exactly the circle the ball is tested against, never a flattering version
	# of it: if it looks like it went in, it went in.
	var visual_radius := hole.cup_pixels()
	draw_circle(pin, visual_radius + 2.5, Color(Palette.SHADOW, 0.45))
	draw_circle(pin, visual_radius, Palette.CUP)

	# Flagstick, with its shadow laid along the sun direction across the green.
	var height := 52.0
	var top := pin + Vector2(0.0, -height)
	draw_line(pin, pin + Palette.shadow_offset(height * 0.62),
		Color(Palette.SHADOW, 0.30), 3.0, true)
	draw_line(pin, top, Color(0.94, 0.95, 0.90), 2.5, true)

	var flag := PackedVector2Array([
		top,
		top + Vector2(26.0, 8.0),
		top + Vector2(0.0, 17.0),
	])
	draw_colored_polygon(flag, Palette.FLAG)
	draw_polyline(PackedVector2Array([flag[0], flag[1], flag[2]]),
		Palette.FLAG.darkened(0.3), 1.5, true)


## Ambient darkening around the edge of the play area, so the hole feels lit in
## the middle and enclosed at the treeline instead of ending at a hard border.
func _draw_vignette() -> void:
	var bands := 7
	var depth := 46.0
	for i in bands:
		var inset := depth * float(bands - i) / float(bands)
		var rect := Rect2(
			hole.bounds.position - Vector2(inset, inset) + Vector2(depth, depth),
			hole.bounds.size + Vector2(inset, inset) * 2.0
				- Vector2(depth, depth) * 2.0)
		draw_rect(rect, Color(Palette.SHADOW, 0.045), false, depth / float(bands) + 1.0)


# --- Drawing helpers ------------------------------------------------------

## Walk a shape's outline and light the edges facing the sun while shading the
## rest. On a circle this is an arc; on a bunker with capes and bays it follows
## every lobe, which is what stops an irregular shape reading as a flat cut-out.
func _draw_lit_edge(shape: PackedVector2Array, lit: Color, shade: Color) -> void:
	for i in shape.size():
		var from: Vector2 = shape[i]
		var to: Vector2 = shape[(i + 1) % shape.size()]
		var along := to - from
		if along.length() < 0.001:
			continue
		# Outward normal, given the outline is wound consistently.
		var outward := Vector2(along.y, -along.x).normalized()
		var facing := outward.dot(-Palette.SUN.normalized())
		if facing > 0.0:
			draw_line(from, to, Color(lit, lit.a * facing), 3.0, true)
		else:
			draw_line(from, to, Color(shade, shade.a * -facing * 0.8), 2.0, true)


## A circle with its edge chewed up, seeded from where it sits so it looks the
## same on every redraw instead of crawling.
func _ragged_circle(centre: Vector2, radius: float) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(centre.x), roundi(centre.y)))
	var steps := 14
	var points := PackedVector2Array()
	for i in steps:
		var angle := TAU * float(i) / float(steps)
		points.append(centre + Vector2(cos(angle), sin(angle))
			* radius * rng.randf_range(0.78, 1.10))
	return points


## Blobs making up one clump of scrub. Derived from the region's own position, so
## a given bush looks the same every time the hole is drawn rather than crawling
## around between redraws.
func _soft_shadow(centre: Vector2, radius: float, strength: float) -> void:
	_stamp(TextureBank.soft_shadow(), centre, radius, strength)


func _soft_light(centre: Vector2, radius: float, strength: float) -> void:
	_stamp(TextureBank.soft_light(), centre, radius, strength)


func _stamp(texture: Texture2D, centre: Vector2, radius: float,
		strength: float) -> void:
	if texture == null:
		return
	draw_texture_rect(texture,
		Rect2(centre - Vector2(radius, radius), Vector2(radius, radius) * 2.0),
		false, Color(1.0, 1.0, 1.0, strength))


## Tile a grain texture over a rectangle. The UVs come from world position, so
## the noise is continuous across everything drawn on the hole rather than
## restarting inside each shape.
func _grain_rect(rect: Rect2, texture: Texture2D, scale: float) -> void:
	_grain_polygon(PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.end,
		rect.position + Vector2(0.0, rect.size.y),
	]), texture, scale)


func _grain_circle(centre: Vector2, radius: float, texture: Texture2D,
		scale: float) -> void:
	var points := PackedVector2Array()
	var steps := 40
	for i in steps:
		var angle := TAU * float(i) / float(steps)
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	_grain_polygon(points, texture, scale)


func _grain_polygon(points: PackedVector2Array, texture: Texture2D,
		scale: float) -> void:
	if texture == null or points.size() < 3 or scale <= 0.0:
		return
	var uvs := PackedVector2Array()
	for point in points:
		uvs.append(point / scale)
	draw_colored_polygon(points, Color.WHITE, uvs, texture)
