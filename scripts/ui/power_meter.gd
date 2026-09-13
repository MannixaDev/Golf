## The swing meter: power first, then timing.
##
## This is the one control the player reads under time pressure, so it is drawn
## to be legible at a glance rather than to be pretty. It has two jobs and shows
## a visibly different thing for each, because a meter that looks the same in
## both stages would be a meter you have to remember the state of.
##
##   POWER   a bar filling green through amber to red, with the greedy end
##           marked out before you reach it rather than explained afterwards.
##   TIMING  the bar dims to what you locked in, a bright marker falls back
##           down it, and a band at the bottom shows where a pure strike is.
class_name PowerMeter
extends Control

## Past this the shot starts costing you accuracy, so it is marked out.
const DANGER_FROM := 0.90

var value: float = 0.0
var phase: int = AimController.Phase.IDLE
var marker: float = 0.0
## Half-width of the pure-strike band, in meter units. Already scaled by how
## hard the swing was, so the meter can draw it without knowing any of that.
var band: float = 0.06

var _track: StyleBoxFlat = null
var _fill: StyleBoxFlat = null


func _ready() -> void:
	_track = StyleBoxFlat.new()
	_track.bg_color = Color(0.02, 0.05, 0.03, 0.85)
	_track.set_corner_radius_all(5)
	_track.border_color = Color(1.0, 1.0, 1.0, 0.10)
	_track.set_border_width_all(1)

	_fill = StyleBoxFlat.new()
	_fill.set_corner_radius_all(4)


func set_power(power_pct: float) -> void:
	value = clampf(power_pct, 0.0, 1.0)
	queue_redraw()


## Everything the meter needs, from the one signal that owns all of it.
func set_swing(new_phase: int, power: float, new_marker: float,
		new_band: float) -> void:
	phase = new_phase
	value = clampf(power, 0.0, 1.0)
	marker = clampf(new_marker, 0.0, 1.0)
	band = new_band
	queue_redraw()


func _draw() -> void:
	if _track == null:
		return
	var full := Rect2(Vector2.ZERO, size)
	draw_style_box(_track, full)

	var timing := phase == AimController.Phase.TIMING
	if timing:
		_draw_sweet_spot()
	else:
		# The greedy end of the meter, marked before you get there.
		draw_rect(Rect2(size.x * DANGER_FROM, 2.0,
			size.x * (1.0 - DANGER_FROM), size.y - 4.0),
			Color(Palette.DANGER, 0.16))

	if value > 0.001:
		var colour := _fill_colour()
		# Once power is locked the bar is history, so it steps back and lets the
		# marker be the thing your eye follows.
		_fill.bg_color = Color(colour, 0.32) if timing else colour
		draw_style_box(_fill, Rect2(2.0, 2.0,
			maxf((size.x - 4.0) * value, 4.0), size.y - 4.0))

		if not timing:
			# A bright leading edge, so the eye can track the head of the bar as
			# it sweeps rather than having to judge the width of a block.
			var head := 2.0 + (size.x - 4.0) * value
			draw_line(Vector2(head, 3.0), Vector2(head, size.y - 3.0),
				Color(1.0, 1.0, 0.94, 0.9), 2.0)

	if timing:
		_draw_marker()

	for i in range(1, 10):
		var x := size.x * i / 10.0
		var tall := i == 5
		var height := size.y * (0.5 if tall else 0.28)
		draw_line(Vector2(x, size.y - height), Vector2(x, size.y),
			Color(Palette.INK, 0.20 if tall else 0.11), 1.0)


## Green through amber to red: the bar tells you what the swing is going to cost
## without you having to read a number.
func _fill_colour() -> Color:
	if value > DANGER_FROM:
		return Palette.WARN.lerp(Palette.DANGER,
			(value - DANGER_FROM) / (1.0 - DANGER_FROM))
	return Palette.GOOD.lerp(Palette.WARN, clampf(value / DANGER_FROM, 0.0, 1.0))


## Where a pure strike lives. Drawn from the very left edge, so the instruction
## reads as "stop it at the end" without needing a word of explanation.
func _draw_sweet_spot() -> void:
	var width := maxf(size.x * band, 3.0)
	draw_rect(Rect2(2.0, 2.0, width, size.y - 4.0), Color(Palette.GOOD, 0.30))
	draw_line(Vector2(2.0 + width, 1.0), Vector2(2.0 + width, size.y - 1.0),
		Color(Palette.GOOD, 0.65), 1.5)


func _draw_marker() -> void:
	var x := 2.0 + (size.x - 4.0) * marker
	# Green while it is still inside the band, white once it has passed through:
	# the colour is the feedback, and it arrives before the shot does.
	var inside := marker <= band
	var colour := Palette.GOOD if inside else Color(1.0, 1.0, 0.94)
	draw_line(Vector2(x, 0.0), Vector2(x, size.y), colour, 3.0)
	draw_line(Vector2(x, 0.0), Vector2(x, size.y), Color(colour, 0.25), 7.0)
