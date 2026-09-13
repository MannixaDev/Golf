## One rung of the ladder you are climbing.
##
## The game had no reason to start a second run. Every round was the same round
## against the same field for the same stakes, so finishing one was the end of
## the story rather than the start of the next. A tour is the standing answer to
## "why again": the same game, played against better players, for a tighter cut
## and a bigger cheque.
##
## Every lever here already existed as a seam. The field's quality is the
## leaderboard's, the cut is the run's, the difficulty is the hole generator's
## and the purse is the reward's -- so a rung is a .tres, not a mode.
class_name TourSpec
extends Resource

@export_group("Identity")
@export var id: StringName = &"tour"
@export var display_name: String = "Tour"
## One line, shown while you are deciding.
@export_multiline var blurb: String = ""
## Where this sits on the ladder. Rung 0 is always unlocked.
@export var rung: int = 0
@export var colour: Color = Color("#8fcc6b")

@export_group("The field")
## Shifted onto every rival's expected score. Negative is a better field, and
## this is the sharpest lever on the ladder: the leaderboard is where the
## pressure in this game actually lives.
@export var field_skill_delta: float = 0.0

@export_group("The cut")
## Share of the field that goes home at halfway.
@export var cut_share: float = 0.34

@export_group("The course")
## Added to the difficulty of every hole on the route.
@export var difficulty_delta: int = 0

@export_group("The purse")
@export var winnings_multiplier: float = 1.0


## How much harder than the rung below, roughly, for the ladder readout.
func summary() -> String:
	var parts: PackedStringArray = PackedStringArray()
	if not is_zero_approx(field_skill_delta):
		# Stated over a round rather than per hole. The stored number is a shift
		# on a rival's expected score for one hole, which is the right shape for
		# the simulation and a meaningless one to read: "field 1.2 shots better"
		# is a sentence, "field +0.1" is not.
		parts.append("field %.1f shots better"
			% (-field_skill_delta * MapGenerator.HOLES_PER_NINE))
	if not is_equal_approx(cut_share, 0.34):
		parts.append("%d%% cut" % roundi(cut_share * 100.0))
	if difficulty_delta != 0:
		parts.append("harder holes")
	if not is_equal_approx(winnings_multiplier, 1.0):
		parts.append("purse x%.2f" % winnings_multiplier)
	return "  ·  ".join(parts) if not parts.is_empty() else "where everyone starts"
