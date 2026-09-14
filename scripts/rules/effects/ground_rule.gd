## The turf itself, playing differently today.
##
## Not another hazard and not a wobble on the swing: the whole course is running
## or the whole course is sodden, and every club in the bag has to be re-judged
## because the number on its face is no longer the number it does. A 175 yard
## iron on baked ground is a 210 yard iron, and that is a more interesting
## problem than a bunker.
class_name GroundRule
extends CourseRule

@export_multiline var summary: String = "The ground is running."
## Said once, as the hole begins, so the player re-reads their bag before
## choosing rather than discovering it on the second bounce.
@export var announcement: String = ""

@export_group("The ground")
## Applied to roll. Above one and everything releases; near zero and the ball
## sits down where it lands.
@export var roll_multiplier: float = 1.0
## How much of a bad lie this shrugs off. Winter rules, in effect.
@export var lie_resistance: float = 0.0
## Carry, for conditions heavy enough to take distance out of the air.
@export var distance_multiplier: float = 1.0


func describe() -> String:
	return summary


func on_hole_start(_hole: HoleData, ctx: CourseRuleContext) -> void:
	if announcement != "":
		ctx.announce(announcement)


func modify_profile(profile: ShotProfile, _ctx: CourseRuleContext) -> void:
	profile.roll_ratio *= maxf(roll_multiplier, 0.0)
	profile.carry_yards_max *= distance_multiplier
	profile.lie_resistance = maxf(profile.lie_resistance, lie_resistance)
