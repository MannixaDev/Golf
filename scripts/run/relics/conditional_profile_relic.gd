## Equipment that quietly improves a stroke when some condition holds.
##
## One parameterised class covers most of the equipment in the game: a glove that
## helps every third swing, a rangefinder that helps every swing, a caddie who
## only speaks up when you are in trouble, and a handicap that only helps once
## you are behind. Adding another is a .tres file.
class_name ConditionalProfileRelic
extends RelicEffect

enum Condition {
	ALWAYS,
	EVERY_NTH_STROKE,   ## Fires on stroke N, 2N, 3N of each hole.
	WHEN_LIE_IS_TROUBLE, ## Rough, sand, a divot: anything that hurts the shot.
	WHEN_OVER_PAR,       ## Only once the run is going badly.
}

@export_multiline var summary: String = ""
@export var condition: Condition = Condition.ALWAYS
## Used by EVERY_NTH_STROKE.
@export var every: int = 3

@export_group("Effect")
@export var distance_multiplier: float = 1.0
@export var dispersion_multiplier: float = 1.0
@export var roll_multiplier: float = 1.0
## Softens what your lie does to the shot. 1.0 ignores the lie entirely.
@export var lie_resistance: float = 0.0


func describe() -> String:
	return summary


func modify_profile(profile: ShotProfile, ctx: RelicContext) -> void:
	if not _applies(ctx):
		return
	profile.carry_yards_max *= distance_multiplier
	profile.dispersion_deg *= dispersion_multiplier
	profile.roll_ratio *= roll_multiplier
	profile.lie_resistance = maxf(profile.lie_resistance, lie_resistance)


func _applies(ctx: RelicContext) -> bool:
	match condition:
		Condition.ALWAYS:
			return true
		Condition.EVERY_NTH_STROKE:
			return every > 0 and ctx.stroke_number % every == 0
		Condition.WHEN_LIE_IS_TROUBLE:
			return ctx.lie_is_trouble()
		Condition.WHEN_OVER_PAR:
			return ctx.is_over_par()
	return false
