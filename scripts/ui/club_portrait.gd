## The club, photographed.
##
## Drawn rather than imported, like everything else here: a chrome head against
## a course thrown out of focus behind it. Chrome is the reason this is worth
## doing properly -- what makes metal look like metal is not shine but the hard
## dark band where it reflects the horizon, sky above it and ground bouncing
## back underneath. Get that band right and three greys do the rest.
##
## The shape is nine control points and a corner-cutting pass. The accents are
## polygons clipped against the head, so nothing can spill over its edge however
## the outline is later nudged.
class_name ClubPortrait
extends Control

## Rounds of corner cutting. Two keeps the trailing edge as an edge; three
## rounds it off and the whole thing reads as a metal egg.
const SMOOTHING := 2
## Fraction of the shorter side left as air around the head.
const MARGIN := 0.16

## Where each of the palette's chrome stops falls between crown and sole. The
## colours themselves live in the palette, like every other colour in the game.
const CHROME := [
	[0.00, Palette.CHROME_SKY],
	[0.16, Palette.CHROME_HIGH],
	[0.34, Palette.CHROME_MID],
	[0.44, Palette.CHROME_TURN],
	[0.50, Palette.CHROME_HORIZON],
	[0.58, Palette.CHROME_UNDER],
	[0.78, Palette.CHROME_GROUND],
	[0.93, Palette.CHROME_BOUNCE],
	[1.00, Palette.CHROME_SOLE],
]

## Head outline before smoothing. Face to the left, trailing edge to the right.
##
## A driver is not symmetrical and drawing it symmetrically is what makes it
## look like a stone: it is tallest just behind the face, sweeps back and down
## to a trailing edge that is nearly a point, and sits on a long flat sole.
const OUTLINE := [
	Vector2(-1.00, -0.28),
	Vector2(-0.88, -0.50),
	Vector2(-0.46, -0.60),
	Vector2(0.16, -0.55),
	Vector2(0.74, -0.34),
	Vector2(1.08, -0.04),
	Vector2(0.86, 0.24),
	Vector2(0.16, 0.42),
	Vector2(-0.56, 0.42),
	Vector2(-0.97, 0.20),
]
const TOP := -0.60
const BOTTOM := 0.42

var _centre := Vector2.ZERO
var _scale := 1.0


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	if size.x <= 4.0 or size.y <= 4.0:
		return
	# Fitted on its own terms, so the picture never stretches when the screen it
	# sits on changes shape.
	_scale = minf(size.x / 2.6, size.y / 1.9) * (1.0 - MARGIN)
	_centre = Vector2(size.x * 0.5, size.y * 0.56)

	_draw_background()
	var head := _head()
	_draw_shadow()
	_draw_shaft()
	_draw_chrome(head)
	_draw_face(head)
	_draw_accents(head)
	_draw_specular(head)
	_draw_rim(head)


# --- The course, out of focus ---------------------------------------------

func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.SHADE)

	# One continuous ramp down the whole frame rather than three bands. Bands
	# leave a seam at every join, and a seam is the one thing a photograph taken
	# on a long lens does not have.
	_ramp_down([
		[0.00, Palette.SCRUB_SHADOW],
		[0.30, Palette.SCRUB],
		[0.44, Palette.SCRUB_CROWN],
		[0.54, Palette.ROUGH],
		[0.66, Palette.FIRST_CUT],
		[0.82, Palette.FAIRWAY],
		[1.00, Palette.shaded(Palette.FAIRWAY, 0.26)],
	])

	# Blown-out highlights where light comes through the trees. Big, soft and
	# few: bokeh is what tells the eye the background is far away.
	var light := TextureBank.soft_light()
	for spot in [Vector2(0.16, 0.20), Vector2(0.78, 0.14),
			Vector2(0.90, 0.38), Vector2(0.34, 0.33)]:
		var r: float = size.x * (0.10 + 0.06 * spot.y)
		draw_texture_rect(light,
			Rect2(Vector2(size.x * spot.x - r, size.y * spot.y - r),
				Vector2(r, r) * 2.0),
			false, Color(0.86, 0.95, 0.72, 0.20))

	# Light pooled behind the club, so it reads as the subject.
	var glow := _scale * 2.2
	draw_texture_rect(light,
		Rect2(_centre - Vector2(glow, glow), Vector2(glow, glow) * 2.0),
		false, Color(1.0, 0.98, 0.82, 0.16))

	var shade := TextureBank.soft_shadow()
	var edge := size.x * 0.55
	for corner in [Vector2(0.0, 0.0), Vector2(size.x, 0.0),
			Vector2(0.0, size.y), Vector2(size.x, size.y)]:
		draw_texture_rect(shade,
			Rect2(corner - Vector2(edge, edge), Vector2(edge, edge) * 2.0),
			false, Color(0.03, 0.06, 0.03, 0.55))


func _ramp_down(stops: Array) -> void:
	var steps := 64
	var slice := size.y / float(steps)
	for i in steps:
		draw_rect(Rect2(0.0, slice * float(i), size.x, slice + 1.0),
			_ramp(stops, float(i) / float(steps - 1)))


# --- The head -------------------------------------------------------------

func _head() -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in OUTLINE:
		points.append(_centre + point * _scale)
	for _pass in SMOOTHING:
		points = _cut_corners(points)
	return points


## Chaikin: replace every corner with the two points a quarter of the way along
## each of its edges. Cheap, closed-loop safe, and it never overshoots the way a
## spline through the same points does on the sharp trailing edge.
func _cut_corners(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := points.size()
	for i in count:
		var a := points[i]
		var b := points[(i + 1) % count]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	return out


## Horizontal slices of the ramp, each cut against the head.
##
## The obvious way is per-vertex colours on one draw_polygon call, and it does
## not work: Godot fans a convex polygon from a single vertex, so the interior
## interpolates towards that one corner and the whole head comes out as a pale
## wash with no horizon in it at all. Slicing costs a few dozen clips on resize
## and gives an exact gradient.
const SLICES := 56


func _draw_chrome(head: PackedVector2Array) -> void:
	var top := _centre.y + TOP * _scale
	var span := (BOTTOM - TOP) * _scale
	var slice := span / float(SLICES)
	for i in SLICES:
		var t := float(i) / float(SLICES - 1)
		var y := top + slice * float(i)
		var band := PackedVector2Array([
			Vector2(_centre.x - 2.0 * _scale, y),
			Vector2(_centre.x + 2.0 * _scale, y),
			Vector2(_centre.x + 2.0 * _scale, y + slice + 1.0),
			Vector2(_centre.x - 2.0 * _scale, y + slice + 1.0),
		])
		var colour := _chrome_at(t)
		for piece in _clip(band, head):
			draw_colored_polygon(piece, colour)


func _chrome_at(t: float) -> Color:
	var colour := _ramp(CHROME, t)
	# Below the horizon band the metal is looking at grass, so let a little in.
	# This is the whole trick for chrome standing on a golf course.
	if t > 0.55:
		colour = colour.lerp(Palette.FAIRWAY, (t - 0.55) * 0.70)
	return colour


func _ramp(stops: Array, t: float) -> Color:
	for i in range(1, stops.size()):
		var lo: Array = stops[i - 1]
		var hi: Array = stops[i]
		if t <= float(hi[0]):
			var span: float = maxf(float(hi[0]) - float(lo[0]), 0.0001)
			return Color(lo[1]).lerp(Color(hi[1]), (t - float(lo[0])) / span)
	return Color(stops[stops.size() - 1][1])


func _draw_shadow() -> void:
	var wide := _scale * 2.4
	var tall := _scale * 0.62
	draw_texture_rect(TextureBank.soft_shadow(),
		Rect2(Vector2(_centre.x - wide * 0.5,
			_centre.y + BOTTOM * _scale - tall * 0.42), Vector2(wide, tall)),
		false, Color(0.04, 0.08, 0.04, 0.5))


## The face, on the heel side: a crescent of brighter metal with score lines.
func _draw_face(head: PackedVector2Array) -> void:
	var at := Vector2(-0.90, -0.03)
	var radius := Vector2(0.28, 0.40)
	var face := _clip(_ellipse(at, radius), head)
	for piece in face:
		draw_colored_polygon(piece, Palette.CHROME_FACE)
	# The crown-to-face edge, and only that edge: outlining the whole crescent
	# draws a line along the silhouette too, which makes the face read as a
	# sticker rather than as a plane the club is pointing with.
	var seam := PackedVector2Array()
	for i in 21:
		var a := lerpf(-PI * 0.5, PI * 0.5, float(i) / 20.0)
		seam.append(_centre + (at + Vector2(cos(a), sin(a)) * radius) * _scale)
	# Thickened and cut against the head, not stroked: an arc drawn straight
	# runs its ends off the silhouette and hangs a hook under the sole.
	for band in Geometry2D.offset_polyline(seam, 0.9):
		for piece in _clip(band, head):
			draw_colored_polygon(piece, Palette.CHROME_SEAM)
	for i in 7:
		var y := _centre.y + lerpf(-0.30, 0.26, float(i) / 6.0) * _scale
		var bar := PackedVector2Array([
			Vector2(_centre.x - 1.10 * _scale, y - 0.011 * _scale),
			Vector2(_centre.x - 0.55 * _scale, y - 0.011 * _scale),
			Vector2(_centre.x - 0.55 * _scale, y + 0.015 * _scale),
			Vector2(_centre.x - 1.10 * _scale, y + 0.015 * _scale),
		])
		for shape in face:
			for piece in _clip(bar, shape):
				draw_colored_polygon(piece, Color(Palette.CHROME_TURN, 0.8))


## The green: a rail around the sole and a mark on the crown.
##
## The rail is the outline shrunk and subtracted from itself, so it hugs the
## edge exactly however the shape is later nudged, then cut off above the
## waist. Freehanding a crescent instead gives you a shape that only fits this
## one silhouette, and looks stuck on the moment the silhouette changes.
func _draw_accents(head: PackedVector2Array) -> void:
	# The rail is the bottom of the outline itself, thickened and then cut back
	# against the head. Subtracting a shrunken copy of the head would have been
	# the obvious way and is wrong: clip_polygons hands back an outer ring and a
	# hole as two ordinary polygons, and filling both paints the whole sole.
	var waist := _centre.y + 0.04 * _scale
	var edge := PackedVector2Array()
	for point in head:
		if point.y > waist:
			edge.append(point)
	if edge.size() > 1:
		for band in Geometry2D.offset_polyline(edge, 0.055 * _scale):
			for piece in _clip(band, head):
				draw_colored_polygon(piece, Palette.ANODISED)
		draw_polyline(edge, Color(Palette.ANODISED_DARK, 0.45), 1.4, true)

	# One alignment stripe on the crown, laid along the way the ball goes and
	# tapering the way a painted one does.
	var stripe := PackedVector2Array()
	var back := PackedVector2Array()
	var count := 12
	for i in count:
		var t := float(i) / float(count - 1)
		var along := _centre + Vector2(lerpf(-0.62, -0.06, t),
			lerpf(-0.40, -0.545, t)) * _scale
		var width := lerpf(0.030, 0.012, t) * _scale
		stripe.append(along - Vector2(0.0, width))
		back.append(along + Vector2(0.0, width))
	for i in range(back.size() - 1, -1, -1):
		stripe.append(back[i])
	for piece in _clip(stripe, head):
		draw_colored_polygon(piece, Color(Palette.ANODISED, 0.95))


## One long highlight across the crown and a short one on the sole. Chrome with
## no hard-edged specular just looks like grey plastic.
func _draw_specular(head: PackedVector2Array) -> void:
	var count := 26
	var streak := PackedVector2Array()
	for i in count:
		var t := float(i) / float(count - 1)
		streak.append(_centre + Vector2(lerpf(-0.72, 0.74, t),
			-0.40 - 0.11 * sin(t * PI)) * _scale)
	for i in range(count - 1, -1, -1):
		var t := float(i) / float(count - 1)
		streak.append(_centre + Vector2(lerpf(-0.72, 0.74, t),
			-0.34 - 0.06 * sin(t * PI)) * _scale)
	for piece in _clip(streak, head):
		draw_colored_polygon(piece, Color(1.0, 1.0, 0.99, 0.55))

	for piece in _clip(_ellipse(Vector2(0.38, 0.24), Vector2(0.30, 0.06)), head):
		draw_colored_polygon(piece, Color(1.0, 1.0, 0.96, 0.30))


func _draw_rim(head: PackedVector2Array) -> void:
	draw_polyline(head, Color(0.05, 0.09, 0.08, 0.55), 2.0, true)
	# Light on the top edge only, which is what lifts the crown off the trees.
	var top := PackedVector2Array()
	for point in head:
		if point.y < _centre.y - 0.24 * _scale:
			top.append(point)
	if top.size() > 1:
		draw_polyline(top, Color(1.0, 1.0, 0.95, 0.45), 2.0, true)


## Steel leaving the hosel, and the ferrule at its foot.
func _draw_shaft() -> void:
	var foot := _centre + Vector2(-0.80, -0.40) * _scale
	var tip := foot + Vector2(0.56, -1.35) * _scale
	var along := (tip - foot).normalized()
	var across := along.orthogonal()
	var wide := 0.055 * _scale
	var thin := 0.036 * _scale
	draw_colored_polygon(PackedVector2Array([
		foot + across * wide, tip + across * thin,
		tip - across * thin, foot - across * wide,
	]), Palette.CHROME_SHAFT)
	draw_line(foot + across * wide * 0.2, tip + across * thin * 0.2,
		Color(1.0, 1.0, 0.95, 0.35), maxf(thin * 0.6, 1.0), true)
	draw_colored_polygon(PackedVector2Array([
		foot + across * wide * 1.25 - along * 0.02 * _scale,
		foot + across * wide * 1.05 + along * 0.20 * _scale,
		foot - across * wide * 1.05 + along * 0.20 * _scale,
		foot - across * wide * 1.25 - along * 0.02 * _scale,
	]), Palette.FERRULE)


# --- Geometry -------------------------------------------------------------

func _ellipse(at: Vector2, radius: Vector2, steps: int = 30) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in steps:
		var a := TAU * float(i) / float(steps)
		points.append(_centre + (at + Vector2(cos(a), sin(a)) * radius) * _scale)
	return points


func _clip(shape: PackedVector2Array, against: PackedVector2Array) -> Array:
	if shape.size() < 3 or against.size() < 3:
		return []
	return Geometry2D.intersect_polygons(shape, against)
