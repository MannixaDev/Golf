## The wind will not settle. It turns between every stroke, and the readout turns
## with it, so this is a hole you have to keep re-reading rather than one you can
## solve once off the tee.
class_name ShiftingWindRule
extends CourseRule

@export_multiline var summary: String = "The wind changes between every stroke."
## How far the wind may swing each stroke, in degrees.
@export var max_turn_degrees: float = 150.0
## Floor on strength, so a shifting wind is never quietly calm.
@export var minimum_strength: float = 5.0
@export var maximum_strength: float = 12.0
@export var announcement: String = "The wind swings round again."


func describe() -> String:
	return summary


func on_hole_start(hole: HoleData, ctx: CourseRuleContext) -> void:
	# A calm hole would make this rule invisible, so give it weather to work with.
	if hole.wind_direction == Vector2.ZERO:
		hole.wind_direction = Vector2.RIGHT.rotated(ctx.rng.randf_range(0.0, TAU))
	hole.wind_yards_per_100 = maxf(hole.wind_yards_per_100, minimum_strength)


func before_stroke(hole: HoleData, ctx: CourseRuleContext) -> void:
	# The tee shot plays the wind as shown; it only starts moving after that.
	if ctx.stroke_number <= 1:
		return
	var turn := deg_to_rad(ctx.rng.randf_range(-max_turn_degrees, max_turn_degrees))
	hole.wind_direction = hole.wind_direction.rotated(turn)
	hole.wind_yards_per_100 = ctx.rng.randf_range(minimum_strength, maximum_strength)
	ctx.conditions_changed = true
	ctx.announce(announcement)
