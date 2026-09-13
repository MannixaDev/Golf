## One thing that happens to you on the way round.
##
## The brief asks for events that are ridiculous as often as they are dangerous,
## so these are written as short scenes with two or three ways out, each with a
## real consequence.
class_name EventSpec
extends Resource

@export_group("Identity")
@export var id: StringName = &"event"
@export var title: String = "Something Happens"
@export_multiline var body: String = ""
@export var colour: Color = Color("#d9c966")

@export_group("Placement")
@export var weight: float = 10.0
## Never before this many holes have been played, so the opening is not silly.
@export var min_holes_played: int = 0

@export_group("Choices")
@export var outcomes: Array[EventOutcome] = []


## Only the options the player could actually take.
func available_outcomes(winnings: int) -> Array[EventOutcome]:
	var usable: Array[EventOutcome] = []
	for outcome in outcomes:
		if outcome != null and outcome.is_affordable(winnings):
			usable.append(outcome)
	return usable
