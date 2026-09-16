## One thing the lesson says, and what has to happen before it says the next.
##
## Authored as data rather than written into the director, because the wording is
## the part that gets rewritten twenty times and the logic is the part that does
## not. A step is a sentence and a condition.
class_name TutorialStep
extends Resource

enum Wait {
	## Advance as soon as it is shown. For a line that only sets the scene.
	NOTHING,
	## The named card is picked up, ready to aim.
	CARD_SELECTED,
	## The named technique is played onto the coming stroke.
	TECHNIQUE_PLAYED,
	## Anything at all is combining.
	COMBINATION_LIVE,
	## This many strokes have been played on the hole.
	STROKES_PLAYED,
	## The ball is on the putting surface.
	ON_THE_GREEN,
	## It is in.
	HOLED,
}

## What the lesson says. Kept to a couple of short sentences: a panel of prose
## over the top of a golf hole is a panel nobody reads.
@export_multiline var text: String = ""
@export var wait: Wait = Wait.NOTHING
## For CARD_SELECTED and TECHNIQUE_PLAYED.
@export var card_id: StringName = &""
## For STROKES_PLAYED.
@export var strokes: int = 1
## Hold the panel for at least this long even once the condition is met, so a
## line the player has not finished reading does not vanish as they act.
@export var linger: float = 0.0
