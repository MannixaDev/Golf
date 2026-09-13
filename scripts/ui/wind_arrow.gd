## A small compass arrow showing which way the wind is pushing the ball.
class_name WindArrow
extends Control

const CALM_COLOUR := Color(Palette.INK, 0.25)
const LIGHT_COLOUR := Color(Palette.WATER_FOAM, 0.95)
const STRONG_COLOUR := Color(Palette.WARN, 0.95)

var direction: Vector2 = Vector2.ZERO
## Yards of drift per 100 yards of carry.
var strength: float = 0.0


func set_wind(new_direction: Vector2, new_strength: float) -> void:
	direction = new_direction
	strength = new_strength
	queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.46
	draw_arc(centre, radius, 0.0, TAU, 32, Color(Palette.INK, 0.16), 1.5, true)

	if direction == Vector2.ZERO or strength <= 0.01:
		draw_circle(centre, 3.0, CALM_COLOUR)
		return

	# Colour carries the strength, so the arrow reads at a glance.
	var heat := clampf(strength / 12.0, 0.0, 1.0)
	var colour := LIGHT_COLOUR.lerp(STRONG_COLOUR, heat)

	var forward := direction.normalized()
	var side := Vector2(-forward.y, forward.x)
	var tip := centre + forward * radius
	var tail := centre - forward * radius * 0.85

	draw_line(tail, tip - forward * 6.0, colour, 2.5, true)
	draw_colored_polygon(PackedVector2Array([
		tip,
		tip - forward * 9.0 + side * 5.5,
		tip - forward * 9.0 - side * 5.5,
	]), colour)
