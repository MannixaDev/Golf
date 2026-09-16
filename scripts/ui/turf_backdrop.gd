## Ground to put a menu screen on.
##
## The shop, the picker and the notices all used to sit on a flat near-black
## rectangle, which is what made them read as dialog boxes floating in a void
## rather than as places on a golf course. This is the same turf and grain the
## course itself is drawn with, dimmed right down so it never competes with the
## content laid over it.
##
## Drop it in as the first child of a screen and it fills the parent.
class_name TurfBackdrop
extends Control

## How far towards real turf the ground is pulled. Low, because everything here
## is a backdrop: it should register as ground without ever being looked at.
@export_range(0.0, 1.0) var turf_mix: float = 0.34
@export_range(0.0, 1.0) var grain_strength: float = 0.5
## Darkening around the edges, which is what keeps the eye in the middle where
## the content is.
@export var vignette_depth: float = 110.0

const GRAIN_SCALE := 420.0
const MOTTLE_SCALE := 1250.0
## Width of one mown band. Wide -- four times the course's own stripe -- because
## a menu is a much bigger piece of ground than a fairway and stripes at course
## scale would read as a barcode.
const STRIPE_WIDTH := 184.0
## How far a stripe lifts off the base. The mowing should be something you
## notice about the ground rather than something you read -- but at two per cent
## it was not visible at all, which is a different failure from being subtle.
const STRIPE_LIFT := 0.055
## Lean, so the bands do not line up with the edges of the screen and start
## reading as columns of a layout.
const STRIPE_LEAN := 0.26


func _ready() -> void:
	# Grain tiles across the whole screen, which needs UVs past 0..1 to wrap.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	resized.connect(queue_redraw)


func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	draw_rect(full, Palette.SHADE.lerp(Palette.ROUGH, turf_mix))
	_mown_stripes(full)
	_grain(full, TextureBank.turf_mottle(), MOTTLE_SCALE)
	_grain(full, TextureBank.turf_grain(), GRAIN_SCALE)
	_sunlight(full)

	var bands := 8
	for i in bands:
		var inset := vignette_depth * float(bands - i) / float(bands)
		var edge := vignette_depth - inset
		draw_rect(Rect2(Vector2(edge, edge), size - Vector2(edge, edge) * 2.0),
			Color(Palette.SHADE, 0.05), false, vignette_depth / float(bands) + 1.0)


## Mowing. The one cue that says golf course rather than dark green felt, and
## every screen in the game shares this backdrop, so it is one job for all of
## them.
##
## Drawn as leaning bands whose corners are worked out per stripe rather than
## clipped: a Control does not clip its own draw calls, and turning clipping on
## to fix that is how this project once masked an entire panel away.
func _mown_stripes(rect: Rect2) -> void:
	var lean := rect.size.y * STRIPE_LEAN
	var bright := Palette.FAIRWAY_STRIPE
	var band := 0
	var x := -lean
	while x < rect.size.x + STRIPE_WIDTH:
		if band % 2 == 0:
			# Sheared quad, then each corner pulled back inside the rect, which
			# keeps it on the screen without needing a clip.
			var quad := PackedVector2Array([
				_inside(rect, Vector2(x, rect.size.y)),
				_inside(rect, Vector2(x + STRIPE_WIDTH, rect.size.y)),
				_inside(rect, Vector2(x + STRIPE_WIDTH + lean, 0.0)),
				_inside(rect, Vector2(x + lean, 0.0)),
			])
			draw_colored_polygon(quad, Color(bright, STRIPE_LIFT))
		band += 1
		x += STRIPE_WIDTH


func _inside(rect: Rect2, point: Vector2) -> Vector2:
	return Vector2(clampf(point.x, rect.position.x, rect.end.x),
		clampf(point.y, rect.position.y, rect.end.y))


## A wash of light from the same direction everything else on the course is lit
## from, so the ground is not uniformly bright from corner to corner.
func _sunlight(rect: Rect2) -> void:
	var texture := TextureBank.soft_light()
	if texture == null:
		return
	var reach := maxf(rect.size.x, rect.size.y) * 1.25
	var centre := rect.get_center() - Palette.SUN * rect.size.y * 0.42
	draw_texture_rect(texture,
		Rect2(centre - Vector2(reach, reach) * 0.5, Vector2(reach, reach)),
		false, Color(1.0, 0.97, 0.86, 0.045))


func _grain(rect: Rect2, texture: Texture2D, scale: float) -> void:
	if texture == null or scale <= 0.0:
		return
	var points := PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.end,
		rect.position + Vector2(0.0, rect.size.y),
	])
	var uvs := PackedVector2Array()
	for point in points:
		uvs.append(point / scale)
	draw_colored_polygon(points, Color(1.0, 1.0, 1.0, grain_strength), uvs, texture)
