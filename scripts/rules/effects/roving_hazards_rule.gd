## Somebody keeps moving things. Hazards drift between strokes, so the line you
## picked from the tee is not necessarily the line you have on your second.
##
## Deliberately a nudge rather than a teleport: trouble that jumps across the
## hole reads as a bug, trouble that creeps reads as a groundskeeper.
class_name RovingHazardsRule
extends CourseRule

@export_multiline var summary: String = "The hazards do not stay where you left them."
## How far a hazard may drift each stroke, in pixels.
@export var drift: float = 46.0
@export var announcement: String = "The groundskeeper has been busy."


func describe() -> String:
	return summary


func before_stroke(hole: HoleData, ctx: CourseRuleContext) -> void:
	if ctx.stroke_number <= 1:
		return

	for region in hole.hazards:
		if region == null:
			continue
		var shift := Vector2.RIGHT.rotated(ctx.rng.randf_range(0.0, TAU)) \
			* ctx.rng.randf_range(drift * 0.4, drift)
		_move(region, shift)
		_keep_clear_of_green(region, hole)
		_keep_in_bounds(region, hole)

	ctx.course_changed = true
	ctx.announce(announcement)


func _move(region: HazardRegion, shift: Vector2) -> void:
	region.centre += shift
	if region.shape == HazardRegion.Shape.POLYGON:
		var moved := PackedVector2Array()
		for point in region.polygon:
			moved.append(point + shift)
		region.polygon = moved


## The same promise the generator makes: nothing may creep onto the putting
## surface, however much the groundskeeper would like it to.
func _keep_clear_of_green(region: HazardRegion, hole: HoleData) -> void:
	var away := region.centre - hole.green_center
	var minimum := hole.green_keep_out(away) + region.radius
	if away.length() < 0.001:
		away = Vector2.RIGHT * 0.001
	if away.length() >= minimum:
		return
	_move(region, away.normalized() * minimum - away)


func _keep_in_bounds(region: HazardRegion, hole: HoleData) -> void:
	var clamped := Vector2(
		clampf(region.centre.x, hole.bounds.position.x + region.radius,
			hole.bounds.end.x - region.radius),
		clampf(region.centre.y, hole.bounds.position.y + region.radius,
			hole.bounds.end.y - region.radius))
	if not clamped.is_equal_approx(region.centre):
		_move(region, clamped - region.centre)
