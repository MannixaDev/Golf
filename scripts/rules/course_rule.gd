## Base class for a special rule a hole plays under.
##
## The brief is explicit that a boss should not simply be a hole with more sand
## in it, so this is deliberately a behaviour hook rather than another hazard
## knob: rules get to change the weather between strokes, rearrange the course,
## and lean on the swing itself.
class_name CourseRule
extends Resource

## One line of rules text, shown before the hole starts.
func describe() -> String:
	return ""


## Once, as the hole begins.
func on_hole_start(_hole: HoleData, _ctx: CourseRuleContext) -> void:
	pass


## Before every stroke, including the first. This is where the weather turns and
## the groundskeeper moves things.
func before_stroke(_hole: HoleData, _ctx: CourseRuleContext) -> void:
	pass


## Fold into the stroke about to be played, after the card, techniques, equipment
## and lie have all had their say.
func modify_profile(_profile: ShotProfile, _ctx: CourseRuleContext) -> void:
	pass
