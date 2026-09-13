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


func _ready() -> void:
	# Grain tiles across the whole screen, which needs UVs past 0..1 to wrap.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	resized.connect(queue_redraw)


func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	draw_rect(full, Palette.SHADE.lerp(Palette.ROUGH, turf_mix))
	_grain(full, TextureBank.turf_mottle(), MOTTLE_SCALE)
	_grain(full, TextureBank.turf_grain(), GRAIN_SCALE)

	var bands := 8
	for i in bands:
		var inset := vignette_depth * float(bands - i) / float(bands)
		var edge := vignette_depth - inset
		draw_rect(Rect2(Vector2(edge, edge), size - Vector2(edge, edge) * 2.0),
			Color(Palette.SHADE, 0.05), false, vignette_depth / float(bands) + 1.0)


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
